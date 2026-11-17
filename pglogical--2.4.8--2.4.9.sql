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

CREATE FUNCTION pglogical.alter_subscription_set_schema_mapping(
    subscription_name name, source_schema name, target_schema name)
RETURNS boolean LANGUAGE plpgsql VOLATILE AS $$
DECLARE subid oid;
BEGIN
    SELECT sub_id INTO STRICT subid FROM pglogical.subscription
      WHERE sub_name = subscription_name;
    DELETE FROM pglogical.subscription_mapping
      WHERE map_subid = subid AND map_source_schema = source_schema
        AND map_source_table IS NULL;
    INSERT INTO pglogical.subscription_mapping
      (map_subid, map_source_schema, map_source_table,
       map_target_schema, map_target_table)
    VALUES (subid, source_schema, NULL, target_schema, NULL);
    RETURN true;
END;
$$;

CREATE FUNCTION pglogical.alter_subscription_remove_schema_mapping(
    subscription_name name, source_schema name)
RETURNS boolean LANGUAGE plpgsql VOLATILE AS $$
DECLARE subid oid;
BEGIN
    SELECT sub_id INTO STRICT subid FROM pglogical.subscription
      WHERE sub_name = subscription_name;
    DELETE FROM pglogical.subscription_mapping
      WHERE map_subid = subid AND map_source_schema = source_schema
        AND map_source_table IS NULL;
    RETURN FOUND;
END;
$$;
