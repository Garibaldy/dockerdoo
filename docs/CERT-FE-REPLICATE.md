# Réplica greenfield — certificación e-CF (doo16-certFE)

**Para compartir con el equipo (paso a paso):** [CERT-FE-QUICKSTART.md](CERT-FE-QUICKSTART.md)

Despliegue en un **host vacío**: sin DB, volúmenes ni sesión DGII de otro servidor. Solo clones + `.env` + bootstrap de módulos.

## 1. Prerrequisitos

- Linux, Docker Engine + Compose v2, `git`, Python 3 (host, para verify).
- Puertos **8071** (HTTP) y **8075** (longpolling / `queue_job`).
- ~8 GB RAM para build del sidecar Playwright + Chromium.
- Acceso a GitHub; `GITHUB_TOKEN` si el build del sidecar clona DgiiSigner privado.

## 2. Clones

```bash
git clone -b doo16-certFE https://github.com/Garibaldy/dockerdoo.git doo16-cert
cd doo16-cert
mkdir -p custom

git clone -b certFE https://github.com/SuperOdoo/addonsEP16.git custom/addonsEP16
git clone --depth 1 -b main https://github.com/diegobgl/odoo16ee.git custom/odoo16ee
```

Enlaces también en [custom/REPOS.md](../custom/REPOS.md).

## 3. Red Docker

```bash
docker network create cloudbuild 2>/dev/null || true
```

Compose usa red externa `cloudbuild` y `odoonet` (`DOCKER_ODONET_SUBNET` en `.env`).

## 4. Configuración

```bash
cp .env.example .env
```

Completar al menos: `POSTGRES_PASSWORD`, `POSTGRES_ADMIN_PASSWORD`, `ADMIN_PASSWORD`, `DB_ENV_POSTGRES_PASSWORD` (igual que `POSTGRES_PASSWORD`).

Certificación FE (valores por defecto del ejemplo):

- `WORKERS=2` (mínimo; `queue_job` + `certificacion_ecf`)
- `SERVER_WIDE_MODULES=base,web,web_enterprise,queue_job`
- `PIP_AUTO_INSTALL=1`
- `GITHUB_TOKEN` / `DGII_SIGNER_REF` para build `playwright-ecf`
- `LIST_DB=True` solo el primer día si creas la DB desde la UI

## 5. Arranque

```bash
docker compose -p doo16-cert build playwright-ecf
docker compose -p doo16-cert up -d
```

Odoo: http://127.0.0.1:8071/

Sidecar (red interna): `http://playwright-ecf:8765` (Playwright), `http://playwright-ecf:5000` (DgiiSigner).

## 6. Base de datos nueva

1. Crear base (ej. `doo16_cert`), país **República Dominicana**, sin datos demo si certificas.
2. Verificar addons en disco (solo módulos que viven bajo `custom/`, ver `resources/certfe-modules-custom-path.txt`):

   ```bash
   python3 resources/scripts/verify_certfe_module_list.py --repo-root .
   ```

   Debe mostrar `Missing on disk: 0`. La instalación completa usa `certfe-modules-installed.txt` (186, incluye core del image Odoo).

3. Instalar el set de módulos de la instancia referencia (**186** nombres):

   ```bash
   docker compose -p doo16-cert exec -T odoo odoo shell -d doo16_cert --no-http \
     < resources/scripts/install_certfe_modules.py
   ```

   Lista: `resources/certfe-modules-installed.txt`. Tiempo típico: 15–45 min con `WORKERS=2`.

4. Configuración manual: compañía (país DO, RNC/VAT), certificado `.p12`, registro `ecf.certification`, URLs recepción/aprobación, ambiente CerteCF/TesteCF.

## 7. Regenerar lista de módulos (mantenimiento)

Desde una DB golden actualizada:

```bash
./resources/scripts/export_installed_modules.sh
```

Variables: `COMPOSE_PROJECT`, `PGUSER`, `DBNAME`.

## 8. Troubleshooting

| Problema | Acción |
|--------|--------|
| `network cloudbuild not found` | `docker network create cloudbuild` |
| DB healthcheck falla | Revisar `POSTGRES_*` en `.env` y logs del servicio `db` |
| Sidecar unhealthy | `docker compose build playwright-ecf` de nuevo; revisar `GITHUB_TOKEN` |
| Verify: missing on disk | Falta `odoo16ee` o `addonsEP16`; o layout EE incorrecto |
| Jobs cert no corren | `WORKERS>=2`, `queue_job` en `SERVER_WIDE_MODULES`, puerto 8075 |

## 9. Referencia DGII

[Proceso de Certificación para ser Emisor Electrónico (PDF)](https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Documentacin%20sobre%20eCF/Documentaciones%20Proceso%20de%20Certificaci%C3%B3n%20FE/Proceso%20de%20Certificacion%20para%20ser%20Emisor%20Electronico.pdf)

## 10. Qué no incluye este repo

- Backup PostgreSQL / filestore de otro servidor
- Secretos (`.p12`, passwords DGII, tokens)
- Árbol vendored `custom/enterprise-16.0` sin git (usa `odoo16ee` en hosts nuevos)