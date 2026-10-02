#!/bin/bash
# Runs once on first DB init (empty psql volume).
# POSTGRES_USER / POSTGRES_PASSWORD are the bootstrap superuser (POSTGRES_ADMIN_* in .env).
# POSTGRES_APP_* define the unprivileged Odoo application role.
set -euo pipefail

: "${POSTGRES_USER:?POSTGRES_USER must be set (bootstrap admin)}"
: "${POSTGRES_APP_USER:?POSTGRES_APP_USER must be set}"
: "${POSTGRES_APP_PASSWORD:?POSTGRES_APP_PASSWORD must be set}"

psql -v ON_ERROR_STOP=1 \
	-v app_role_name="${POSTGRES_APP_USER}" \
	-v app_role_password="${POSTGRES_APP_PASSWORD}" \
	--username "${POSTGRES_USER}" --dbname "postgres" <<-'EOSQL'
	CREATE ROLE :"app_role_name"
		WITH LOGIN
		CREATEDB
		PASSWORD :'app_role_password'
		NOSUPERUSER
		NOCREATEROLE
		NOREPLICATION
		NOBYPASSRLS;
EOSQL

echo "postgres-init: created application role '${POSTGRES_APP_USER}' (nosuperuser, nocreaterole, createdb)"
