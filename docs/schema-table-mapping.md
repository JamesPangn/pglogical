# Per-subscription schema and table mapping

This enhancement lets each subscription apply provider changes to subscriber
tables with different schema and table names. Mapping metadata is stored on the
subscriber in `pglogical.subscription_mapping` and is scoped to a subscription.

## Mapping rules

There are two row forms in the single metadata table:

| Mapping | `source_schema` | `source_table` | `target_schema` | `target_table` |
| --- | --- | --- | --- | --- |
| Schema mapping | Required | `NULL` | Required | `NULL` |
| Table mapping | Required | Required | Required | Required |

When the apply worker receives a provider `RELATION` message, it looks up a
schema mapping first, then an exact table mapping. A table mapping supplies
both target names and takes precedence over the schema mapping. With no
matching mapping, the provider schema and table names are used. The resolved
target names are cached by remote relation ID and used for subsequent
`INSERT`, `UPDATE`, and `DELETE` messages.

## Add or change a mapping

Create the target schemas and tables on the subscriber first. The target table
must have columns and replica identity compatible with the provider table.
Run the mapping functions on the subscriber, using the subscription name.

Schema mapping example:

```sql
SELECT pglogical.alter_subscription_set_mapping(
    'orders_sub', 'sales', NULL::name, 'sales_local', NULL::name);
```

This maps provider relations such as `sales.orders` to `sales_local.orders`.

Table mapping example:

```sql
SELECT pglogical.alter_subscription_set_mapping(
    'orders_sub', 'sales', 'orders', 'archive', 'orders_2026');
```

This maps `sales.orders` to `archive.orders_2026`. If both a schema mapping
and this table mapping exist, the exact table mapping's target schema and table
name are used for `sales.orders`.

Calling `alter_subscription_set_mapping` again for the same subscription and
source schema/table replaces that mapping row.

## Remove a mapping

Remove a schema mapping by passing NULL for the source table:

```sql
SELECT pglogical.alter_subscription_remove_mapping(
    'orders_sub', 'sales', NULL::name);
```

Remove one table mapping by naming its provider table:

```sql
SELECT pglogical.alter_subscription_remove_mapping(
    'orders_sub', 'sales', 'orders');
```

## Operational notes

- The apply worker resolves mappings whenever it handles a `RELATION` message,
  then reuses its cache for row changes. If a mapping changes after a relation
  was cached, the new mapping is applied when the provider next sends that
  relation's metadata. Restart, or disable and re-enable the subscription,
  after changing mappings to force a fresh decoding session and refresh the
  provider and subscriber relation metadata caches.
- Streamed row changes and initial table data copy use the mapping. Initial
  copy reads the provider's source relation and writes to the mapped subscriber
  relation. Create mapped target schemas and tables before starting the
  subscription's data synchronization; `synchronize_data := true` is supported.
- Sequence messages and synchronized DDL are not translated by these mapping
  functions. Do not rely on sequence-name or structure mapping when using this
  enhancement.
- Mappings are local to one subscription. The same provider relation can map
  to different subscriber names for different subscriptions.

## Upgrade

For an existing 2.4.8 installation, install the enhanced 2.4.9 extension files
and run:

```sql
ALTER EXTENSION pglogical UPDATE TO '2.4.9';
```

Fresh installations of 2.4.9 create the mapping table and functions as part of
`CREATE EXTENSION pglogical`.
