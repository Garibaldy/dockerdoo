#!/bin/bash
# Restrict pg_hba to the docker odoonet subnet (+ localhost).
# Requires a fixed subnet in docker-compose.yml (DOCKER_ODONET_SUBNET).
set -euo pipefail

: "${PGDATA:?PGDATA must be set}"

PG_HBA="${PGDATA}/pg_hba.conf"
SUBNET="${DOCKER_ODONET_SUBNET:-172.28.0.0/16}"
MARKER="# dockerdoo secure init"

if [[ ! -f "${PG_HBA}" ]]; then
	echo "postgres-init: ${PG_HBA} not found" >&2
	exit 1
fi

if grep -qF "${MARKER}" "${PG_HBA}"; then
	echo "postgres-init: pg_hba already restricted (${MARKER} present), skipping"
	exit 0
fi

detect_auth_method() {
	local method=""

	method="$(awk '/^host[[:space:]]+all[[:space:]]+all[[:space:]]+all[[:space:]]+/ { print $NF; exit }' "${PG_HBA}" || true)"
	if [[ -n "${method}" ]]; then
		echo "${method}"
		return 0
	fi

	method="$(
		awk -v subnet="${SUBNET}" '
			$1 == "host" && $2 == "all" && $3 == "all" && ($4 == subnet || $4 == "127.0.0.1/32" || $4 == "::1/128") {
				print $NF
				exit
			}
		' "${PG_HBA}" || true
	)"
	if [[ -n "${method}" ]]; then
		echo "${method}"
		return 0
	fi

	if [[ -n "${POSTGRES_USER:-}" ]] && command -v psql >/dev/null 2>&1; then
		local enc=""
		enc="$(psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname postgres -qAtc "SHOW password_encryption" 2>/dev/null || true)"
		case "${enc}" in
		scram-sha-256 | scram)
			echo "scram-sha-256"
			return 0
			;;
		md5)
			echo "md5"
			return 0
			;;
		esac
	fi

	echo "md5"
}

AUTH_METHOD="$(detect_auth_method)"

# Drop wide-open rule: host all all all <auth>
sed -i -E '/^host[[:space:]]+all[[:space:]]+all[[:space:]]+all[[:space:]]+/d' "${PG_HBA}"

{
	echo "${MARKER}"
	echo "host all all ${SUBNET} ${AUTH_METHOD}"
	echo "host all all 127.0.0.1/32 ${AUTH_METHOD}"
	echo "host all all ::1/128 ${AUTH_METHOD}"
} >> "${PG_HBA}"

echo "postgres-init: pg_hba restricted to ${SUBNET} (auth: ${AUTH_METHOD})"
