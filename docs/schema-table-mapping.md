# Per-subscription schema mapping

This enhancement lets a subscription apply provider tables from a source
schema into a different subscriber schema. The mapping metadata is stored on
the subscriber in `pglogical.subscription_mapping`, scoped to a subscription.
The metadata table also has nullable table-name columns so a later table
mapping enhancement can use the same table.

## Behavior

This branch supports schema-level mappings only. A schema mapping row has a
source schema and target schema; its source and target table names are NULL.
For example, provider relation `sales.orders` maps to subscriber relation
`sales_local.orders`. With no row for the source schema, the provider schema
name is retained.

The apply worker resolves the mapping when it receives a provider `RELATION`
message, caches the local schema name under the remote relation ID, and uses
that cached name for subsequent `INSERT`, `UPDATE`, and `DELETE` operations.
Initial data copy reads the provider's source relation and writes to the
mapped subscriber schema.

## Add or change a mapping

Create the target schema and tables on the subscriber first. Their table names,
columns, data types, and replica identity must be compatible with the provider
tables. Create the subscription with initial data synchronization disabled so
the mapping can be added before synchronization starts:

```sql
SELECT pglogical.create_subscription(
    subscription_name := 'sales_sub',
    provider_dsn := 'host=provider port=5432 dbname=app',
    replication_sets := ARRAY['default'],
    synchronize_structure := false,
    synchronize_data := false);
```

Then, on the subscriber, add the schema mapping:

```sql
SELECT pglogical.alter_subscription_set_schema_mapping(
    'sales_sub', 'sales', 'sales_local');
```

Start and wait for initial data synchronization:

```sql
SELECT pglogical.alter_subscription_synchronize('sales_sub', false);
SELECT pglogical.wait_for_subscription_sync_complete('sales_sub');
```

Calling `alter_subscription_set_schema_mapping` again for the same
subscription and source schema changes its target schema.

## Remove a mapping

```sql
SELECT pglogical.alter_subscription_remove_schema_mapping(
    'sales_sub', 'sales');
```

Without a schema mapping, future relation metadata resolves to the original
source schema name.

## Operational notes

- A mapping change is applied when the provider next sends a `RELATION`
  message for the source table. Restart, or disable and re-enable, the
  subscription after changing mappings if you need to force a fresh decoding
  session and metadata refresh.
- Sequence messages and synchronized structure/DDL are not mapped by this
  schema-only enhancement.
- Mappings are per subscription, so separate subscriptions can map the same
  provider schema to different subscriber schemas.

## Upgrade

For an existing 2.4.8 installation, install the enhanced 2.4.9 extension files
and run:

```sql
ALTER EXTENSION pglogical UPDATE TO '2.4.9';
```

Fresh installations use the `pglogical--2.4.9.sql` install script.
