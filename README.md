# Sovereign Collaboration Platform

Self-hosted, open-source collaboration stack. **VMs are disposable; data is not.**
Configuration lives here in Git; secrets never do.

This repository currently implements **Phase 1: Keycloak** (identity/SSO) on
Ubuntu 26.04 LTS + Docker, fronted by Caddy for automatic HTTPS, backed by
PostgreSQL on a **separate block volume**, with encrypted off-site backups via
restic.

## Layout

    infrastructure/   cloud-init.yaml (host baseline), dns.md, firewall.md
    keycloak/         compose.yaml, .env.example, proxy/Caddyfile
    scripts/          bootstrap.sh, backup.sh, restore.sh, healthcheck.sh

## Prerequisites (in xneelo)

- Ubuntu **26.04** instance (1 vCPU / 2 GB is proof-only; size up before real users).
- A **separate block volume** attached for Postgres data (note its device, e.g. `/dev/vdb`).
- A **floating IP** associated with the instance.
- Security group allowing inbound `22/80/443`.
- DNS `A` record for `auth.example.co.za` -> floating IP (see `infrastructure/dns.md`).

## First deploy

1. Edit `infrastructure/cloud-init.yaml`: paste your SSH **public** key and set
   the real repo URL + hostname. Paste the file into xneelo's config-script field
   when creating the instance.
2. SSH in as `admin`. The repo is already at `/opt/sovereign-cloud`.
3. `cd /opt/sovereign-cloud/keycloak && cp .env.example .env` — fill in real
   secrets and confirm `DATA_DEVICE` matches `lsblk`.
4. `sudo /opt/sovereign-cloud/scripts/bootstrap.sh`
5. Log in at `https://auth.example.co.za/admin`. Create a realm + test user.
   Then **create a real admin user**, remove the `KC_BOOTSTRAP_ADMIN_*` lines
   from `.env`, and re-run `docker compose up -d`.
6. `sudo /opt/sovereign-cloud/scripts/backup.sh`

## Milestone #1 — the recovery test (the real goal)

Phase 1 is not "Keycloak works." It is: prove you can rebuild it from Git + a
backup, timed, after deliberately destroying the VM.

    back up Postgres  ->  DELETE the VM  ->  create a new VM (same cloud-init)
      ->  re-associate the floating IP  ->  supply .env  ->  bootstrap.sh
      ->  restore.sh  ->  the same realm/user authenticates

Target: **~10–20 minutes** to rebuild (excluding unavoidable external delays).
Only once that succeeds is Phase 1 done.

## Secrets

`.env` is git-ignored and must never be committed. This repo is **public**:
enable secret scanning / push protection, and ideally a `gitleaks` pre-commit
hook. `.env.example` documents every variable with no real values.
