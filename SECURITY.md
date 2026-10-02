# PostgreSQL security (dockerdoo)

## Risk

Default `postgres` image creates `POSTGRES_USER` as **superuser** and appends `host all all all` to `pg_hba.conf`. Attackers use `COPY FROM PROGRAM` after guessing weak credentials (PGMiner / unicorn botnets).

Init scripts in `resources/postgres-init/` run **only on empty** `psql` volume.

## Role model

| Variable | Role |
|----------|------|
| `POSTGRES_ADMIN_USER` / `POSTGRES_ADMIN_PASSWORD` | Bootstrap **superuser** (PostgreSQL container only) |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | **Application** role for Odoo (`NOSUPERUSER`, `NOCREATEROLE`, `CREATEDB`) |
| `DB_ENV_POSTGRES_*` | Must match the application role (15–17 entrypoint) |

Odoo must never connect as the admin superuser.

## New deploy

```bash
cp .env.example .env   # set POSTGRES_PASSWORD, POSTGRES_ADMIN_PASSWORD, ADMIN_PASSWORD
# Keep POSTGRES_* and DB_ENV_POSTGRES_* in sync for the app role
docker compose up -d
```

Verify:

```bash
APP_USER="${POSTGRES_USER:-odoo}"
ADMIN_USER="${POSTGRES_ADMIN_USER:-odoo_admin}"

docker compose exec db psql -U "$ADMIN_USER" -d postgres -c \
  "SELECT rolname, rolsuper, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname IN ('$APP_USER', '$ADMIN_USER') ORDER BY rolname;"

docker compose exec db grep '^host' /var/lib/postgresql/data/pgdata/pg_hba.conf
```

Expected: exactly one superuser (`$ADMIN_USER`); app role with `rolsuper=f`, `rolcreaterole=f`, `rolcreatedb=t`; no `host all all all`; rule for `DOCKER_ODONET_SUBNET` (default `172.28.0.0/16`).

Test `COPY … TO PROGRAM` as the app user (must fail):

```bash
docker compose exec db psql -U "$APP_USER" -d postgres -c "COPY (SELECT 1) TO PROGRAM 'id';"
```

## Existing volume (already has data)

Init does **not** re-run. Prefer **backup and restore into a fresh cluster** (see upstream migration notes). Manual hardening below is for stacks that cannot re-init immediately.

### 0. Backup first

```bash
cd /path/to/your-stack
BACKUP=~/backup_$(date +%Y%m%d_%H%M).sql.gz
# Use your current superuser if you have not migrated roles yet
docker compose exec -T db pg_dumpall -U "$ADMIN_USER" | gzip > "$BACKUP"
gzip -t "$BACKUP" && ls -lh "$BACKUP"
```

### 1. Sync `.env` credentials

Set strong passwords for app, admin, and `ADMIN_PASSWORD`. Application settings:

```env
POSTGRES_USER=odoo
POSTGRES_PASSWORD=<app-password>
POSTGRES_ADMIN_USER=odoo_admin
POSTGRES_ADMIN_PASSWORD=<admin-password>
DB_ENV_POSTGRES_USER=odoo
DB_ENV_POSTGRES_PASSWORD=<app-password>
```

### 2. Recreate DB container (cleans /tmp, /dev/shm)

Does not remove the `psql` volume.

### 3. IoC cleanup (if infection was active)

Inside the `db` container:

- Kill processes: `dns-filter`, `unicorn`, `/tmp/.usr_*`
- Remove: `/tmp/.dl_*`, `/dev/shm/.unicorn`, `/var/lib/postgresql/.claude/`
- Block in `/etc/hosts`: `31.77.227.130`, `xmr.kryptex.network`

### 4. SQL hardening (admin session)

Connect as the **bootstrap superuser** (`POSTGRES_ADMIN_USER` or legacy superuser name).

Create the app role if missing (safe identifiers via psql variables):

```bash
docker compose exec db psql -U "$ADMIN_USER" -d postgres \
  -v app_role_name=odoo -v app_role_password='<app-password>' <<-'EOSQL'
CREATE ROLE :"app_role_name"
    WITH LOGIN CREATEDB PASSWORD :'app_role_password'
    NOSUPERUSER NOCREATEROLE NOREPLICATION NOBYPASSRLS;
EOSQL
```

If Odoo previously used the superuser account, create the app role with a new name, grant access to existing databases, then point Odoo at the app role — do **not** strip superuser from the only admin account on PG16+.

### 5. Restrict `pg_hba.conf`

Edit `/var/lib/postgresql/data/pgdata/pg_hba.conf`. Remove the open rule (auth method varies by cluster age):

```
host all all all md5
host all all all scram-sha-256
```

Replace with (preserve the **same** auth method as the rule you removed; use your stack's `DOCKER_ODONET_SUBNET`):

```
host all all 172.28.0.0/16 md5
host all all 127.0.0.1/32 md5
host all all ::1/128 md5
```

(or `scram-sha-256` instead of `md5` on PG14+ defaults)

Reload as superuser: `SELECT pg_reload_conf();`

Detect subnet: `docker network inspect <project>_odoonet --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'`

### 6. Recreate Odoo

```bash
docker compose up -d --force-recreate odoo
```

Regenerates `/etc/odoo/odoo.conf` from `.env`.

### 7. Verification

| Check | Criterion |
|-------|-----------|
| No miner | `docker top <project>-db-1` without `dns-filter`/`unicorn` |
| CPU DB | idle < 10% |
| One superuser | only admin bootstrap role |
| App role | `rolsuper = f`, `rolcreaterole = f` |
| Odoo connects | logs without `password authentication failed` |
| COPY blocked | `COPY (SELECT 1) TO PROGRAM 'id';` fails for app user |

## Dev

Host `~/.ssh` is **not** mounted by default. Use a local compose override if you need git-over-SSH inside the container.
