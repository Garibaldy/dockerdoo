# Certificación e-CF — guía rápida (rama `doo16-certFE`)

Documento para **levantar el ambiente en un host nuevo** (equipo con acceso SuperOdoo). Réplica detallada y troubleshooting: [CERT-FE-REPLICATE.md](CERT-FE-REPLICATE.md).

## Repositorios

| Componente | URL | Rama | Destino local |
|------------|-----|------|----------------|
| Docker / Odoo | https://github.com/Garibaldy/dockerdoo.git | `doo16-certFE` | (raíz del clone) |
| Addons EP16 | https://github.com/SuperOdoo/addonsEP16.git | `certFE` | `custom/addonsEP16` |
| Enterprise 16 | https://github.com/diegobgl/odoo16ee.git | `main` | `custom/odoo16ee` |

Firma XML (build time): **kvillar93/Dgiisigner** (privado). Necesitas un **PAT** con read en ese repo (`GITHUB_TOKEN` en `.env`). El `.p12` del representante se carga en Odoo, no en git.

## Prerrequisitos

- Linux, Docker Engine + Compose v2, `git`, `python3`
- Puertos **8071** (HTTP Odoo) y **8075** (longpolling / `queue_job`)
- ~8 GB RAM libre (build Playwright + Chromium)
- Acceso GitHub: SuperOdoo, Garibaldy/dockerdoo, odoo16ee, Dgiisigner

## Paso 1 — Red y clones

```bash
docker network create cloudbuild 2>/dev/null || true

git clone -b doo16-certFE https://github.com/Garibaldy/dockerdoo.git doo16-cert
cd doo16-cert
mkdir -p custom

git clone -b certFE https://github.com/SuperOdoo/addonsEP16.git custom/addonsEP16
git clone --depth 1 -b main https://github.com/diegobgl/odoo16ee.git custom/odoo16ee
```

## Paso 2 — Variables de entorno

```bash
cp .env.example .env
```

Editar `.env` (no commitear):

| Variable | Notas |
|----------|--------|
| `POSTGRES_USER`, `POSTGRES_PASSWORD` | Rol app Odoo |
| `POSTGRES_ADMIN_USER`, `POSTGRES_ADMIN_PASSWORD` | Superuser bootstrap Postgres |
| `ADMIN_PASSWORD` | Master password Odoo |
| `DB_ENV_POSTGRES_USER` / `DB_ENV_POSTGRES_PASSWORD` | Igual que `POSTGRES_*` |
| `WORKERS` | **2** mínimo (`queue_job` + certificación) |
| `SERVER_WIDE_MODULES` | `base,web,web_enterprise,queue_job` (+ otros EE si aplica) |
| `PIP_AUTO_INSTALL` | `1` |
| `LIST_DB` | `True` la primera vez (crear DB en UI) |
| `GITHUB_TOKEN` | PAT con read en **kvillar93/Dgiisigner** |
| `DGII_SIGNER_REF` | `main` |

## Paso 3 — Build y arranque

El servicio **playwright-ecf** empaqueta:

- **:8765** — Playwright / portal DGII (Flask)
- **:5000** — DgiiXmlSigner (.NET), clonado en el build con `GITHUB_TOKEN`

```bash
docker compose -p doo16-cert build playwright-ecf
docker compose -p doo16-cert up -d
```

Comprobación:

```bash
curl -sS http://127.0.0.1:8071/web/database/selector
docker compose -p doo16-cert exec playwright-ecf curl -sS http://127.0.0.1:8765/health
docker compose -p doo16-cert exec playwright-ecf curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:5000/
```

## Paso 4 — Base de datos y módulos

1. Crear base en http://127.0.0.1:8071 (país **DO**, sin demo si es solo certificación).
2. Verificar que los addons bajo `custom/` están completos:

   ```bash
   python3 resources/scripts/verify_certfe_module_list.py --repo-root .
   ```

   Debe terminar con `Missing on disk: 0`.
3. Instalar el set de módulos de la instancia referencia (~186 nombres; 15–45 min):

   ```bash
   docker compose -p doo16-cert exec -T odoo odoo shell -d NOMBRE_DB --no-http \
     < resources/scripts/install_certfe_modules.py
   ```

4. Configuración manual en Odoo:

   - Compañía: país DO, dirección, RNC/VAT
   - Instalar / abrir **Certificación ECF**
   - Certificado `.p12`, contraseña, URLs recepción/aprobación, ambiente CerteCF/TesteCF

Odoo firma vía HTTP: `http://playwright-ecf:5000/api/DgiiSigner` (parámetro `certificacion_ecf.dgii_signer_url` al instalar el módulo).

## Actualizar código

```bash
cd custom/addonsEP16 && git pull origin certFE
cd ../.. && git pull origin doo16-certFE
docker compose -p doo16-cert build playwright-ecf   # solo si cambió Dockerfile/signer
docker compose -p doo16-cert up -d
```

## Si falla el build de `playwright-ecf`

1. Revisar `GITHUB_TOKEN` (acceso a Dgiisigner).
2. Alternativa: clonar Dgiisigner en el host:

   ```bash
   git clone -b main https://github.com/kvillar93/Dgiisigner.git \
     custom/addonsEP16/certificacion_ecf/services/dgiisigner
   ```

   y volver a `docker compose build playwright-ecf` (el Dockerfile usa esa carpeta si existe `DgiiXmlSigner.dll`).

## Referencia DGII

[Proceso de certificación Emisor Electrónico (PDF)](https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Documentacin%20sobre%20eCF/Documentaciones%20Proceso%20de%20Certificaci%C3%B3n%20FE/Proceso%20de%20Certificacion%20para%20ser%20Emisor%20Electronico.pdf)