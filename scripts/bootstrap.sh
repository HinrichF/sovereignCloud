#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — bring the Keycloak stack up on a fresh (or rebuilt) VM.
# Run as root (sudo) from anywhere; it locates the repo relative to itself.
#
#   sudo /opt/sovereign-cloud/scripts/bootstrap.sh
#
# Prerequisite: keycloak/.env exists (cp .env.example .env and fill it in).
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_DIR}/keycloak/.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: ${ENV_FILE} not found. Copy .env.example to .env and fill it in."; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

# --- Prepare the SEPARATE Postgres data volume -------------------------------
# The single most dangerous step in the whole project: on a REBUILD, the volume
# already holds your database. We format ONLY if the device has no filesystem.
prepare_data_volume() {
  local dev="${DATA_DEVICE}" mnt="${DATA_MOUNT}" label="pgdata"

  [ -b "$dev" ] || { echo "ERROR: ${dev} is not a block device. Check DATA_DEVICE (run 'lsblk')."; exit 1; }

  if blkid "$dev" >/dev/null 2>&1; then
    echo "==> Filesystem already present on ${dev}. Mounting, NOT formatting (rebuild case)."
  else
    echo "==> No filesystem on ${dev}. Formatting ext4 (first-ever run)."
    mkfs.ext4 -L "$label" "$dev"
  fi

  mkdir -p "$mnt"
  local uuid; uuid="$(blkid -s UUID -o value "$dev")"
  if ! grep -q "$uuid" /etc/fstab; then
    echo "UUID=${uuid} ${mnt} ext4 defaults,nofail 0 2" >> /etc/fstab
    echo "==> Added ${mnt} to /etc/fstab (mount by UUID)."
  fi
  mountpoint -q "$mnt" || mount "$mnt"
  chown -R 999:999 "$mnt"   # official postgres image runs as uid/gid 999
  echo "==> Data volume ready at ${mnt}."
}

prepare_data_volume

# --- Bring up the stack ------------------------------------------------------
cd "${REPO_DIR}/keycloak"
echo "==> Starting containers..."
docker compose --env-file .env up -d

echo
echo "==> Waiting for Keycloak to report ready (this can take a minute)..."
"${REPO_DIR}/scripts/healthcheck.sh" --wait || {
  echo "Keycloak did not become ready in time. Check: docker compose logs keycloak"
  exit 1
}

echo
echo "============================================================"
echo " Keycloak is up:  https://${PUBLIC_HOSTNAME}"
echo " Admin console:   https://${PUBLIC_HOSTNAME}/admin"
echo " Log in, CREATE A REAL ADMIN USER, then remove the"
echo " KC_BOOTSTRAP_ADMIN_* lines from .env and re-run 'up -d'."
echo "============================================================"
