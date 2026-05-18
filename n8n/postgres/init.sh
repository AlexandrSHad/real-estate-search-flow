#!/bin/bash
set -e

# Runs once on first container boot via /docker-entrypoint-initdb.d/.
# POSTGRES_USER / POSTGRES_DB (=N8N_DB) are already set by the Docker image entrypoint.
# All other variables must be passed in the postgres service environment.

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE "$REALESTATE_DB";

    CREATE USER "$N8N_DB_USER" WITH PASSWORD '$N8N_DB_PASSWORD';
    CREATE USER "$REALESTATE_DB_USER" WITH PASSWORD '$REALESTATE_DB_PASSWORD';

    -- Remove default public access so only explicit grants work
    REVOKE CONNECT ON DATABASE "$N8N_DB" FROM PUBLIC;
    REVOKE CONNECT ON DATABASE "$REALESTATE_DB" FROM PUBLIC;

    -- Each user can only reach its own database
    GRANT CONNECT ON DATABASE "$N8N_DB" TO "$N8N_DB_USER";
    GRANT CREATE ON DATABASE "$N8N_DB" TO "$N8N_DB_USER";
    GRANT CONNECT ON DATABASE "$REALESTATE_DB" TO "$REALESTATE_DB_USER";
    GRANT CREATE ON DATABASE "$REALESTATE_DB" TO "$REALESTATE_DB_USER";
EOSQL

# Schema-level grants require a separate connection to each database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$N8N_DB" <<-EOSQL
    GRANT USAGE, CREATE ON SCHEMA public TO "$N8N_DB_USER";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "$N8N_DB_USER";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "$N8N_DB_USER";
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$REALESTATE_DB" <<-EOSQL
    GRANT USAGE, CREATE ON SCHEMA public TO "$REALESTATE_DB_USER";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "$REALESTATE_DB_USER";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "$REALESTATE_DB_USER";
EOSQL
