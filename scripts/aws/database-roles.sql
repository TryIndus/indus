\set ON_ERROR_STOP on
\getenv platform_password INDUS_PLATFORM_DB_PASSWORD
\getenv market_password INDUS_MARKET_DB_PASSWORD
\getenv migration_password INDUS_MIGRATION_DB_PASSWORD

CREATE EXTENSION IF NOT EXISTS pgcrypto;

SELECT 'CREATE ROLE indus_platform_owner NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'indus_platform_owner') \gexec
ALTER ROLE indus_platform_owner NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

SELECT 'CREATE ROLE indus_market_owner NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'indus_market_owner') \gexec
ALTER ROLE indus_market_owner NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

SELECT format(
  'CREATE ROLE indus_platform LOGIN PASSWORD %L NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION',
  :'platform_password'
)
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'indus_platform') \gexec
ALTER ROLE indus_platform LOGIN PASSWORD :'platform_password' NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

SELECT format(
  'CREATE ROLE indus_market_writer LOGIN PASSWORD %L NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION',
  :'market_password'
)
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'indus_market_writer') \gexec
ALTER ROLE indus_market_writer LOGIN PASSWORD :'market_password' NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

SELECT format(
  'CREATE ROLE indus_migrator LOGIN PASSWORD %L NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION',
  :'migration_password'
)
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'indus_migrator') \gexec
ALTER ROLE indus_migrator LOGIN PASSWORD :'migration_password' NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

GRANT indus_platform_owner, indus_market_owner TO indus_migrator;

SELECT format('REVOKE CONNECT, TEMPORARY, CREATE ON DATABASE %I FROM PUBLIC', current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO indus_platform, indus_market_writer, indus_migrator', current_database()) \gexec
SELECT format('GRANT CREATE ON DATABASE %I TO indus_platform_owner, indus_market_owner', current_database()) \gexec

ALTER SCHEMA public OWNER TO indus_platform_owner;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO indus_platform;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO indus_platform;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO indus_platform;

CREATE SCHEMA IF NOT EXISTS market_data AUTHORIZATION indus_market_owner;
ALTER SCHEMA market_data OWNER TO indus_market_owner;
REVOKE ALL ON SCHEMA market_data FROM PUBLIC;
GRANT USAGE ON SCHEMA market_data TO indus_market_writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA market_data TO indus_market_writer;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA market_data TO indus_market_writer;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA market_data TO indus_market_writer;

SELECT current_user AS bootstrap_admin \gset
GRANT indus_platform_owner, indus_market_owner TO :"bootstrap_admin";

SET ROLE indus_platform_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO indus_platform;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO indus_platform;
RESET ROLE;

SET ROLE indus_market_owner;
ALTER DEFAULT PRIVILEGES IN SCHEMA market_data
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO indus_market_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA market_data
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO indus_market_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA market_data
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA market_data
  GRANT EXECUTE ON FUNCTIONS TO indus_market_writer;
RESET ROLE;

REVOKE indus_platform_owner, indus_market_owner FROM :"bootstrap_admin";

ALTER ROLE indus_platform SET search_path = public, pg_catalog;
ALTER ROLE indus_market_writer SET search_path = market_data, pg_catalog;
ALTER ROLE indus_migrator SET search_path = public, pg_catalog;
