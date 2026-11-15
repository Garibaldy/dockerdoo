# Custom addons — clones requeridos (certificación FE)

El directorio `custom/` no va completo en el repo **dockerdoo**. En un host **nuevo**, clona:

| Componente | Repositorio | Rama | Ruta local |
|------------|-------------|------|------------|
| Módulos EP16 (equipo) | https://github.com/SuperOdoo/addonsEP16.git | `certFE` | `custom/addonsEP16` |
| Enterprise 16 | https://github.com/diegobgl/odoo16ee.git | `main` | `custom/odoo16ee` |

Módulos EE en `custom/odoo16ee/enterprise-16.0/`.

**Layout alternativo (como algunos despliegues hardened):** copiar o enlazar ese árbol a `custom/enterprise-16.0/` (módulos en la raíz de esa carpeta, sin `.git`).

```bash
mkdir -p custom
git clone -b certFE https://github.com/SuperOdoo/addonsEP16.git custom/addonsEP16
git clone --depth 1 -b main https://github.com/diegobgl/odoo16ee.git custom/odoo16ee
# opcional: rsync -a custom/odoo16ee/enterprise-16.0/ custom/enterprise-16.0/
```

Stack Docker: rama `doo16-certFE` de https://github.com/Garibaldy/dockerdoo.git

**Mantenimiento:** el desarrollo activo puede seguir en `intrepidux/addonsEP16` (privado); `SuperOdoo/addonsEP16` es el espejo para revisión del equipo en rama `certFE`.

**Guía para levantar el ambiente:** [docs/CERT-FE-QUICKSTART.md](../docs/CERT-FE-QUICKSTART.md)  
Réplica / troubleshooting: [docs/CERT-FE-REPLICATE.md](../docs/CERT-FE-REPLICATE.md)