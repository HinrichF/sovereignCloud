#!/usr/bin/env bash
# =============================================================================
# backup.sh — logical Postgres dump -> restic (encrypted, deduplicated) -> EU S3
#
#   sudo /opt/sovereign-cloud/scripts/backup.sh
#
# The AUTHORITATIVE backup is this logical pg_dump, NOT a block snapshot:
# a dump restores cleanly across Postgres versions; a raw volume does not.
# Schedule via cron/systemd-timer once you're happy it works.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_DIR}/keycloak/.env"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

STAMP="$(date +%Y%m%dT%H%M%SZ)"
STAGING="$(mktemp -d)"
DUMP="${STAGING}/keycloak-${STAMP}.dump"
trap 'rm -rf "$STAGING"' EXIT

cd "${REPO_DIR}/keycloak"

echo "==> Dumping database (custom format)..."
docker compose exec -T postgres \
  pg_dump -U "${POSTGRES_USER}" -Fc "${POSTGRES_DB}" > "$DUMP"
echo "==> Dump written: $(du -h "$DUMP" | cut -f1)"

# restic reads RESTIC_REPOSITORY / RESTIC_PASSWORD / AWS_* from the env we sourced.
echo "==> Ensuring restic repository is initialised..."
restic snapshots >/dev/null 2>&1 || restic init

echo "==> Backing up to ${RESTIC_REPOSITORY} ..."
restic backup --tag keycloak "$DUMP"

echo "==> Applying retention (7 daily / 4 weekly / 12 monthly)..."
# NOTE: --prune deletes data, so it is INCOMPATIBLE with S3 Object-Lock in
# compliance mode. If you enable immutability, drop --prune here and prune from
# a separate privileged path the production host does NOT hold credentials for.
restic forget --tag keycloak \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune

echo "==> Backup complete. REMEMBER: a backup is only real once restore.sh has been tested."
