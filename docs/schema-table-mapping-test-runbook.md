# Schema and table mapping test runbook

This runbook validates the per-subscription mapping enhancement on **RHEL 9
and PostgreSQL 18**. It covers building/installing the extension, fresh
installation, upgrade installation, initial table copy, and streamed DML.

Run this only on a disposable test PostgreSQL instance. The subscription setup
and synchronization steps below create test databases and tables.

## 1. Prepare a complete source tree

The branch is `codex/subscription-schema-table-mapping`. The latest fresh
install fix (`Makefile` plus `pglogical--2.4.9.sql`) may still be local and not
on the remote branch. The server must receive those files along with the branch
source. Either commit and push that fix before cloning, or transfer the full
working tree from the development machine. For example, from Git Bash in the
repository root:

```bash
tar --exclude=.git -czf pglogical-schema-map-test.tar.gz .
scp pglogical-schema-map-test.tar.gz user@test-rhel9:/tmp/
```

On the test server:

```bash
mkdir -p ~/pglogical-schema-map-test
tar -xzf /tmp/pglogical-schema-map-test.tar.gz -C ~/pglogical-schema-map-test
cd ~/pglogical-schema-map-test
```

Before building, confirm these files are present:

```bash
test -f pglogical--2.4.9.sql
test -f pglogical--2.4.8--2.4.9.sql
grep -q 'pglogical--2.4.9.sql' Makefile
```

## 2. Build and install for PostgreSQL 18

Install the compiler and PostgreSQL 18 server development files from the same
package source as the server (normally PGDG on RHEL 9):

```bash
sudo dnf install -y gcc make postgresql18-devel postgresql18-server
```

Build and install using PostgreSQL 18's `pg_config`:

```bash
make clean
make PG_CONFIG=/usr/pgsql-18/bin/pg_config
sudo make PG_CONFIG=/usr/pgsql-18/bin/pg_config install
```

Confirm PostgreSQL sees both extension versions and the update path:

```bash
/usr/pgsql-18/bin/pg_config --version
ls -l /usr/pgsql-18/share/extension/pglogical--2.4.9.sql
ls -l /usr/pgsql-18/share/extension/pglogical--2.4.8--2.4.9.sql
```

If PostgreSQL 18 is not initialized yet, initialize and start it according to
your test server's service configuration. Configure at least these server
settings in `postgresql.conf`, then restart PostgreSQL:

```conf
wal_level = logical
max_worker_processes = 10
max_replication_slots = 10
max_wal_senders = 10
shared_preload_libraries = 'pglogical'
```

Also allow the test role to connect to both databases in `pg_hba.conf`. For a
local-only test, use a loopback rule appropriate to the server's password
method, for example:

```conf
host all pglogical_test 127.0.0.1/32 scram-sha-256
```

Reload or restart after changing `pg_hba.conf`. Check the effective settings:

```sql
SHOW wal_level;
SHOW shared_preload_libraries;
SHOW max_worker_processes;
SHOW max_replication_slots;
SHOW max_wal_senders;
```

## 3. Test fresh extension installation

In a fresh test database, run:

```sql
CREATE EXTENSION pglogical;
SELECT extversion FROM pg_extension WHERE extname = 'pglogical';
SELECT to_regclass('pglogical.subscription_mapping');
```

Expected: extension version `2.4.9` and relation
`pglogical.subscription_mapping`.

Check the mapping API is installed:

```sql
\df pglogical.alter_subscription_*mapping
```

## 4. Test upgrade from 2.4.8

Use a separate disposable database/server state that has the stock 2.4.8
extension installed. Keep a backup before replacing extension files. After
installing this branch's 2.4.9 files, run in that database:

```sql
SELECT extversion FROM pg_extension WHERE extname = 'pglogical';
ALTER EXTENSION pglogical UPDATE TO '2.4.9';
SELECT extversion FROM pg_extension WHERE extname = 'pglogical';
SELECT to_regclass('pglogical.subscription_mapping');
```

Expected: version changes from `2.4.8` to `2.4.9`, and the mapping table and
functions exist. Do not use the fresh-install database for this upgrade test.

## 5. Create provider and subscriber test databases

The examples use two databases on the same PostgreSQL 18 instance. Substitute
your actual host, port, role, and password. Use a test superuser because
pglogical node and subscription administration requires elevated privileges.

Create a login role and databases (as a PostgreSQL administrator):

```sql
CREATE ROLE pglogical_test LOGIN SUPERUSER PASSWORD 'replace-this-password';
CREATE DATABASE pgl_provider OWNER pglogical_test;
CREATE DATABASE pgl_subscriber OWNER pglogical_test;
```

In **both databases**, install the extension and create the local node. Use
each database's own DSN:

```sql
CREATE EXTENSION pglogical;
SELECT pglogical.create_node(
    node_name := 'provider_node',
    dsn := 'host=127.0.0.1 port=5432 dbname=pgl_provider user=pglogical_test password=replace-this-password');
```

In `pgl_subscriber`, use a distinct node name and its database in the DSN:

```sql
SELECT pglogical.create_node(
    node_name := 'subscriber_node',
    dsn := 'host=127.0.0.1 port=5432 dbname=pgl_subscriber user=pglogical_test password=replace-this-password');
```

## 6. Create provider source tables and seed data

Run in `pgl_provider`:

```sql
CREATE SCHEMA sales;

CREATE TABLE sales.orders (
    id bigint PRIMARY KEY,
    payload text NOT NULL
);

CREATE TABLE sales.special_orders (
    id bigint PRIMARY KEY,
    payload text NOT NULL
);

INSERT INTO sales.orders VALUES (1, 'schema mapping initial row');
INSERT INTO sales.special_orders VALUES (1, 'table mapping initial row');

SELECT pglogical.replication_set_add_table('default', 'sales.orders');
SELECT pglogical.replication_set_add_table('default', 'sales.special_orders');
```

The provider replication set must include both source tables before creating
the subscription.

## 7. Create mapped target tables and subscription

Run in `pgl_subscriber`. Create target tables with compatible columns and
replica identity. This test intentionally uses a schema mapping for
`sales.orders` and a table mapping for `sales.special_orders`.

```sql
CREATE SCHEMA sales_local;
CREATE SCHEMA archive;

CREATE TABLE sales_local.orders (
    id bigint PRIMARY KEY,
    payload text NOT NULL
);

CREATE TABLE archive.special_orders_2026 (
    id bigint PRIMARY KEY,
    payload text NOT NULL
);
```

Create the subscription with data sync disabled first. The mapping functions
require an existing subscription row, so this ordering lets you create the
subscription, register mappings, and then explicitly start initial sync:

```sql
SELECT pglogical.create_subscription(
    subscription_name := 'orders_sub',
    provider_dsn := 'host=127.0.0.1 port=5432 dbname=pgl_provider user=pglogical_test password=replace-this-password',
    replication_sets := ARRAY['default'],
    synchronize_structure := false,
    synchronize_data := false);
```

Add the schema mapping and table mapping:

```sql
SELECT pglogical.alter_subscription_set_mapping(
    'orders_sub', 'sales', NULL::name, 'sales_local', NULL::name);

SELECT pglogical.alter_subscription_set_mapping(
    'orders_sub', 'sales', 'special_orders', 'archive', 'special_orders_2026');
```

Check the metadata:

```sql
SELECT s.sub_name, m.map_source_schema, m.map_source_table,
       m.map_target_schema, m.map_target_table
FROM pglogical.subscription_mapping AS m
JOIN pglogical.subscription AS s ON s.sub_id = m.map_subid
WHERE s.sub_name = 'orders_sub'
ORDER BY m.map_source_table NULLS FIRST;
```

Start initial table synchronization and wait for completion:

```sql
SELECT pglogical.alter_subscription_synchronize('orders_sub', false);
SELECT pglogical.wait_for_subscription_sync_complete('orders_sub');
```

Verify initial rows landed at the mapped locations:

```sql
SELECT * FROM sales_local.orders ORDER BY id;
SELECT * FROM archive.special_orders_2026 ORDER BY id;
```

Expected: each target table has its source table's seed row. The subscriber
does not need same-named `sales.orders` or `sales.special_orders` tables.

## 8. Validate streamed INSERT, UPDATE, and DELETE

Run on the provider:

```sql
INSERT INTO sales.orders VALUES (2, 'schema mapped insert');
INSERT INTO sales.special_orders VALUES (2, 'table mapped insert');
UPDATE sales.orders SET payload = 'schema mapped update' WHERE id = 1;
UPDATE sales.special_orders SET payload = 'table mapped update' WHERE id = 1;
DELETE FROM sales.orders WHERE id = 2;
DELETE FROM sales.special_orders WHERE id = 2;
```

Wait briefly for apply, then run on the subscriber:

```sql
TABLE sales_local.orders;
TABLE archive.special_orders_2026;
```

Expected: both `id = 1` rows contain their updated payload, and both `id = 2`
rows are absent. No rows should appear in same-named source relations on the
subscriber.

## 9. Validate mapping refresh after a mapping change

The apply worker looks up mapping metadata on a provider `RELATION` message.
It compares resolved local names with its cache and refreshes the cache if they
differ. To force a fresh provider decoding session after changing a mapping,
restart the subscription by disabling and enabling it.

Create a second target table, disable the subscription, change the table
mapping, then enable it:

```sql
CREATE SCHEMA archive_v2;
CREATE TABLE archive_v2.special_orders_renamed (
    id bigint PRIMARY KEY,
    payload text NOT NULL
);
```

Then:

```sql
SELECT pglogical.alter_subscription_disable('orders_sub', true);
SELECT pglogical.alter_subscription_set_mapping(
    'orders_sub', 'sales', 'special_orders', 'archive_v2', 'special_orders_renamed');
SELECT pglogical.alter_subscription_enable('orders_sub', true);
```

After the worker reconnects, insert a new row into provider
`sales.special_orders` and verify that it arrives in
`archive_v2.special_orders_renamed`. This tests streaming after a mapping
refresh; it does not copy existing rows to the new target table automatically.

## 10. Cleanup

Only on the disposable test instance, drop the test subscription and databases
when finished:

```sql
-- Run in pgl_subscriber
SELECT pglogical.drop_subscription('orders_sub', true);
```

Then, as a PostgreSQL administrator, drop `pgl_subscriber`, `pgl_provider`, and
the `pglogical_test` role if they are no longer needed.

## Expected limitations

- Schema/table mapping applies to streamed table DML and initial table data
  copy. It does not currently translate sequence messages or synchronized
  structure/DDL.
- Mapping changes do not move or copy existing target data. Prepare the new
  target relation and its data as needed before changing the mapping.
- Do not use `synchronize_structure := true` for mapped tables in this test.
