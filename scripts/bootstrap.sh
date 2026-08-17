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

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo (this installs packages and mounts volumes)."; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_DIR}/keycloak/.env"

[ -f "$ENV_FILE" ] || { echo "ERROR: ${ENV_FILE} not found. Copy .env.example to .env and fill it in."; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

# --- Install Docker from the official repo (idempotent) ----------------------
# Done here, not in cloud-init: xneelo's user-data filter blocks writes to
# /etc/apt/... in the payload. In this post-boot root shell, no filter applies.
install_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo "==> Docker already installed. Skipping."
    return
  fi
  echo "==> Installing Docker from the official repository..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  local codename; codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  usermod -aG docker admin || true
  echo "==> Docker installed (log out/in for non-sudo 'docker' access)."
}

# --- Full SSH hardening drop-in (idempotent) ---------------------------------
# Also blocked in cloud-init user-data (writes /etc/ssh/...), so applied here.
# cloud-init already set ssh_pwauth:false + disable_root:true natively at boot;
# this reinforces that and adds the remaining directives.
harden_ssh() {
  echo "==> Applying SSH hardening..."
  cat > /etc/ssh/sshd_config.d/10-hardening.conf <<'CONF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
CONF
  chmod 0644 /etc/ssh/sshd_config.d/10-hardening.conf
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  echo "==> SSH hardened (key-only, no root login)."
}

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
  mkdir -p "${mnt}/pgdata"          # Postgres uses this subdir (PGDATA), not the
                                    # volume root, which holds lost+found on ext4
  chown -R 999:999 "$mnt"   # official postgres image runs as uid/gid 999
  echo "==> Data volume ready at ${mnt}."
}

install_docker
harden_ssh
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
