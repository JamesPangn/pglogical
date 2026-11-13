CREATE TABLE pglogical.subscription_mapping (
    map_subid oid NOT NULL REFERENCES pglogical.subscription(sub_id) ON DELETE CASCADE,
    map_source_schema name NOT NULL,
    map_source_table name,
    map_target_schema name NOT NULL,
    map_target_table name,
    CHECK ((map_source_table IS NULL) = (map_target_table IS NULL))
);
CREATE UNIQUE INDEX subscription_mapping_schema_idx
    ON pglogical.subscription_mapping (map_subid, map_source_schema)
    WHERE map_source_table IS NULL;
CREATE UNIQUE INDEX subscription_mapping_table_idx
    ON pglogical.subscription_mapping (map_subid, map_source_schema, map_source_table)
    WHERE map_source_table IS NOT NULL;

CREATE FUNCTION pglogical.alter_subscription_set_mapping(
    subscription_name name, source_schema name, source_table name,
    target_schema name, target_table name)
RETURNS boolean LANGUAGE plpgsql VOLATILE AS $$
DECLARE subid oid;
BEGIN
    SELECT sub_id INTO STRICT subid FROM pglogical.subscription
      WHERE sub_name = subscription_name;
    IF (source_table IS NULL) <> (target_table IS NULL) THEN
        RAISE EXCEPTION 'source_table and target_table must both be NULL for schema mappings or both be non-NULL for table mappings';
    END IF;
    DELETE FROM pglogical.subscription_mapping
      WHERE map_subid = subid AND map_source_schema = source_schema
        AND map_source_table IS NOT DISTINCT FROM source_table;
    INSERT INTO pglogical.subscription_mapping VALUES
      (subid, source_schema, source_table, target_schema, target_table);
    RETURN true;
END;
$$;

CREATE FUNCTION pglogical.alter_subscription_remove_mapping(
    subscription_name name, source_schema name, source_table name DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql VOLATILE AS $$
DECLARE subid oid;
BEGIN
    SELECT sub_id INTO STRICT subid FROM pglogical.subscription
      WHERE sub_name = subscription_name;
    DELETE FROM pglogical.subscription_mapping
      WHERE map_subid = subid AND map_source_schema = source_schema
        AND map_source_table IS NOT DISTINCT FROM source_table;
    RETURN FOUND;
END;
$$;
