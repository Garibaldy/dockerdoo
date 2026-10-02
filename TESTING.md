# Manual testing: PostgreSQL hardening (`hardening-test/*`)

Branches: `hardening-test/15.0`, `hardening-test/16.0`, `hardening-test/17.0`, `hardening-test/main` (from fork `18.0`).

## Prerequisites

- Docker Engine + Compose v2
- Check out the branch under test, e.g. `git checkout hardening-test/15.0`

## 1. Fresh volume — default role names

```bash
cp .env.example .env
# Required (compose uses :? — empty values fail fast)
export APP_PW='TestApp-Str0ng!'
export ADMIN_PW='TestAdmin-Str0ng!'
export ODOO_MASTER='TestMaster-Str0ng!'

# Edit .env (or sed) — keep POSTGRES_* and DB_ENV_* in sync on 15–17
# POSTGRES_PASSWORD, POSTGRES_ADMIN_PASSWORD, ADMIN_PASSWORD
# DB_ENV_POSTGRES_PASSWORD = POSTGRES_PASSWORD

docker compose down -v
docker compose up -d db
docker compose logs db | tail -30
```

Wait until Postgres is ready:

```bash
docker compose exec db pg_isready -U odoo_admin
```

### Role privileges

```bash
docker compose exec db psql -U odoo_admin -d postgres -c \
  "SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication FROM pg_roles WHERE rolname IN ('odoo', 'odoo_admin') ORDER BY rolname;"

docker compose exec db psql -U odoo_admin -d postgres -c \
  "SELECT count(*) FILTER (WHERE rolsuper) AS superuser_count FROM pg_roles WHERE rolcanlogin OR rolsuper;"
```

Expect: `odoo_admin` superuser; `odoo` with `rolsuper=f`, `rolcreaterole=f`, `rolcreatedb=t`; one superuser total.

### pg_hba

```bash
docker compose exec db grep '^host' /var/lib/postgresql/data/pgdata/pg_hba.conf
```

Expect: no `host all all all`; lines for `DOCKER_ODONET_SUBNET`, `127.0.0.1/32`, `::1/128`.

### COPY blocked (app role)

```bash
docker compose exec db psql -U odoo -d postgres -c "COPY (SELECT 1) TO PROGRAM 'id';"
```

Expect: permission denied / must be superuser.

### Odoo connects (full stack)

Set passwords in `.env`, then:

```bash
docker compose up -d
docker compose logs odoo 2>&1 | tail -50
```

Expect: no `password authentication failed` for DB; Odoo HTTP on 8069 (may need DB create via UI on first run).

## 2. Hyphen / uppercase role names

Use a **new** project name or `docker compose down -v` first.

In `.env`:

```env
POSTGRES_USER=Odoo-Prod
POSTGRES_ADMIN_USER=Odoo-Admin
# passwords set as above; DB_ENV_POSTGRES_USER=Odoo-Prod on 15–17
```

```bash
docker compose down -v
docker compose up -d db
docker compose exec db psql -U Odoo-Admin -d postgres -c "\du"
```

Init must complete without SQL syntax errors.

## 3. pg_hba script idempotency (simulated re-run)

On a running DB from test 1:

```bash
docker compose exec db bash -c 'grep -E "^host[[:space:]]+all[[:space:]]+all[[:space:]]+all[[:space:]]+" "$PGDATA/pg_hba.conf" || echo "no wide-open rule (ok)"'

# Re-run restrict script manually (init only runs once on empty volume)
docker compose exec db bash /docker-entrypoint-initdb.d/02-restrict-pg_hba.sh
echo exit_code=$?
docker compose exec db bash /docker-entrypoint-initdb.d/02-restrict-pg_hba.sh
echo exit_code=$?
docker compose exec db grep -c '# dockerdoo secure init' /var/lib/postgresql/data/pgdata/pg_hba.conf
```

Expect: both runs exit `0`; marker count stays **1**; no mixed `md5` under `scram-sha-256` on PG14+. Odoo uses `.env` + `entrypoint.sh` for DB credentials (`DB_ENV_POSTGRES_*`).

## 4. Branch-specific notes

| Branch | Default `PSQL_VERSION` | PR |
|--------|------------------------|-----|
| `hardening-test/15.0` | 12 | upstream #178 |
| `hardening-test/16.0` | 12 | #176 |
| `hardening-test/17.0` | 12 | #175 |
| `hardening-test/main` | 16 (see `.env`) | #177 (head: `18.0`) |

**main / 18.0:** also verify `POSTGRES_DB=postgres` in `.env` / `.env.example`, db healthcheck uses app user, no external-only `cloudbuild` network requirement on a clean host (if fixed on that branch).

## 5. Password required

```bash
# With empty POSTGRES_PASSWORD in .env
docker compose config 2>&1 | head -5
```

Expect: compose error referencing `set POSTGRES_PASSWORD` (or admin/app vars).
