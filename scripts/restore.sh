#!/usr/bin/env bash
# =============================================================================
# restore.sh — rebuild path: restore the latest Keycloak dump from restic.
#
#   sudo /opt/sovereign-cloud/scripts/restore.sh
#
# Intended flow on a NEW VM after bootstrap.sh has prepared the volume and
# started the stack: this brings Postgres to a known-empty state, loads the
# newest dump, then (re)starts Keycloak against the restored data.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_DIR}/keycloak/.env"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

RESTORE_DIR="$(mktemp -d)"
trap 'rm -rf "$RESTORE_DIR"' EXIT

cd "${REPO_DIR}/keycloak"

echo "==> Fetching latest dump from restic..."
restic restore latest --tag keycloak --target "$RESTORE_DIR"
DUMP="$(find "$RESTORE_DIR" -name 'keycloak-*.dump' | sort | tail -n1)"
[ -n "$DUMP" ] || { echo "ERROR: no dump found in restic snapshot."; exit 1; }
echo "==> Using ${DUMP}"

echo "==> Ensuring only Postgres is running for a clean restore..."
docker compose up -d postgres
until docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; do
  sleep 2
done
# Stop Keycloak so nothing holds connections / writes schema during restore.
docker compose stop keycloak >/dev/null 2>&1 || true

echo "==> Recreating an empty '${POSTGRES_DB}' database..."
docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d postgres -v ON_ERROR_STOP=1 <<SQL
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${POSTGRES_DB}' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS ${POSTGRES_DB};
CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};
SQL

echo "==> Restoring dump..."
docker compose exec -T postgres \
  pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --no-owner < "$DUMP"

echo "==> Starting Keycloak against the restored database..."
docker compose up -d

echo "==> Waiting for Keycloak to report ready..."
"${REPO_DIR}/scripts/healthcheck.sh" --wait

echo
echo "============================================================"
echo " Restore complete. Log in at https://${PUBLIC_HOSTNAME}/admin"
echo " and confirm your realm + test user authenticate."
echo "============================================================"
