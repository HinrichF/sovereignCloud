#!/usr/bin/env bash
# =============================================================================
# healthcheck.sh — is the stack healthy?
#   ./healthcheck.sh          one-shot check, exits non-zero if unhealthy
#   ./healthcheck.sh --wait   poll until Keycloak is ready (up to ~2 min)
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_DIR}/keycloak/.env"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
cd "${REPO_DIR}/keycloak"

# Keycloak's readiness probe lives on the management port (9000), inside the
# container network. We exec into the caddy container (which shares the network)
# and ask Keycloak directly, avoiding any dependency on tools inside the KC image.
kc_ready() {
  docker compose exec -T keycloak \
    bash -c 'exec 3<>/dev/tcp/localhost/9000 &&
      printf "GET /health/ready HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" >&3 &&
      grep -q "200 OK" <&3' 2>/dev/null
}

if [ "${1:-}" = "--wait" ]; then
  for _ in $(seq 1 60); do
    if kc_ready; then echo "Keycloak ready."; exit 0; fi
    sleep 2
  done
  echo "Timed out waiting for Keycloak."; exit 1
fi

fail=0
echo "== Containers =="
docker compose ps
echo
echo "== Keycloak readiness =="
if kc_ready; then echo "  ready ✓"; else echo "  NOT ready ✗"; fail=1; fi
echo
echo "== Public endpoint =="
if curl -fsS "https://${PUBLIC_HOSTNAME}/realms/master" >/dev/null 2>&1; then
  echo "  https://${PUBLIC_HOSTNAME} reachable ✓"
else
  echo "  https://${PUBLIC_HOSTNAME} NOT reachable ✗ (DNS/cert/firewall?)"; fail=1
fi
exit $fail
