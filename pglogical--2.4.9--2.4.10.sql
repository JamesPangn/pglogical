ALTER TABLE pglogical.subscription
    ADD COLUMN sub_use_existing_slot boolean NOT NULL DEFAULT 'f';

DROP FUNCTION pglogical.create_subscription(name, text, text[], boolean,
                                            boolean, text[], interval, boolean);
CREATE FUNCTION pglogical.create_subscription(subscription_name name, provider_dsn text,
    replication_sets text[] = '{default,default_insert_only,ddl_sql}', synchronize_structure boolean = false,
    synchronize_data boolean = true, forward_origins text[] = '{all}', apply_delay interval DEFAULT '0',
    force_text_transfer boolean = false, slot_name name DEFAULT NULL)
RETURNS oid VOLATILE LANGUAGE c AS 'MODULE_PATHNAME', 'pglogical_create_subscription';
