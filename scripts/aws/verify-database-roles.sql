\set ON_ERROR_STOP on

DO $$
DECLARE
  role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['indus_platform', 'indus_market_writer', 'indus_migrator'] LOOP
    IF NOT EXISTS (
      SELECT FROM pg_roles
      WHERE rolname = role_name
        AND rolcanlogin
        AND NOT rolsuper
        AND NOT rolcreatedb
        AND NOT rolcreaterole
        AND NOT rolreplication
        AND NOT rolinherit
    ) THEN
      RAISE EXCEPTION 'unsafe or missing login role: %', role_name;
    END IF;
  END LOOP;

  IF NOT pg_has_role('indus_migrator', 'indus_platform_owner', 'MEMBER')
     OR NOT pg_has_role('indus_migrator', 'indus_market_owner', 'MEMBER') THEN
    RAISE EXCEPTION 'migration role is missing an owner membership';
  END IF;

  IF NOT has_schema_privilege('indus_platform', 'public', 'USAGE')
     OR has_schema_privilege('indus_platform', 'market_data', 'USAGE') THEN
    RAISE EXCEPTION 'platform runtime schema boundary is invalid';
  END IF;

  IF NOT has_schema_privilege('indus_market_writer', 'market_data', 'USAGE')
     OR has_schema_privilege('indus_market_writer', 'public', 'USAGE') THEN
    RAISE EXCEPTION 'market writer schema boundary is invalid';
  END IF;

  IF EXISTS (
    SELECT FROM pg_tables
    WHERE schemaname = 'public'
      AND (
        has_table_privilege('indus_market_writer', format('%I.%I', schemaname, tablename), 'SELECT')
        OR has_table_privilege('indus_market_writer', format('%I.%I', schemaname, tablename), 'INSERT')
        OR has_table_privilege('indus_market_writer', format('%I.%I', schemaname, tablename), 'UPDATE')
        OR has_table_privilege('indus_market_writer', format('%I.%I', schemaname, tablename), 'DELETE')
      )
  ) THEN
    RAISE EXCEPTION 'market writer can access a platform table';
  END IF;

  IF EXISTS (
    SELECT FROM pg_tables
    WHERE schemaname = 'market_data'
      AND has_table_privilege('indus_platform', format('%I.%I', schemaname, tablename), 'SELECT')
  ) THEN
    RAISE EXCEPTION 'platform runtime can access a market-data table';
  END IF;

  IF EXISTS (
    SELECT FROM pg_tables
    WHERE schemaname = 'market_data'
      AND NOT (
        has_table_privilege('indus_market_writer', format('%I.%I', schemaname, tablename), 'SELECT')
        AND has_table_privilege('indus_market_writer', format('%I.%I', schemaname, tablename), 'INSERT')
        AND has_table_privilege('indus_market_writer', format('%I.%I', schemaname, tablename), 'UPDATE')
        AND has_table_privilege('indus_market_writer', format('%I.%I', schemaname, tablename), 'DELETE')
      )
  ) THEN
    RAISE EXCEPTION 'market writer is missing required DML on a market-data table';
  END IF;

  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'market_data'
        AND p.proname IN ('ensure_monthly_partitions', 'apply_retention')) <> 2
     OR EXISTS (
    SELECT FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'market_data'
      AND p.proname IN ('ensure_monthly_partitions', 'apply_retention')
      AND (
        NOT p.prosecdef
        OR pg_get_userbyid(p.proowner) <> 'indus_market_owner'
        OR EXISTS (
          SELECT FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) acl
          WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
        )
      )
  ) THEN
    RAISE EXCEPTION 'market maintenance functions are not owner-controlled security definers';
  END IF;
END
$$;

SELECT 'database role boundaries verified' AS result;
