#!/usr/bin/env bash
# RTCCM customer install bootstrap
# Usage: ./install.sh [--profile aws|azure|gcp] [--profile ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
green(){ printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

# ─── Pre-flight checks ──────────────────────────────────────────────────────
command -v docker >/dev/null || { red "docker is not installed. Install Docker Engine 24+ first."; exit 1; }
docker compose version >/dev/null 2>&1 || { red "docker compose plugin is missing. Install docker-compose-plugin."; exit 1; }

DOCKER_VERSION="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 0.0.0)"
DOCKER_MAJOR="${DOCKER_VERSION%%.*}"
if [ "${DOCKER_MAJOR:-0}" -lt 24 ]; then
  yellow "WARNING: Docker $DOCKER_VERSION detected. Minimum recommended: 24.0"
fi

# ─── Template expansion ─────────────────────────────────────────────────────
if [ ! -f .env ]; then
  cp env-template.txt .env
  yellow "Created .env from template. Edit it before running install.sh again."
  yellow "Edit: \$EDITOR $SCRIPT_DIR/.env"
  exit 0
fi

if [ ! -f .secrets.env ]; then
  cp secrets-template.env .secrets.env
  chmod 600 .secrets.env
  yellow "Created .secrets.env from template. Edit it before running install.sh again."
  yellow "Edit: \$EDITOR $SCRIPT_DIR/.secrets.env"
  exit 0
fi

# ─── Required value sanity check ────────────────────────────────────────────
# Catch the common case of leaving CHANGEME placeholders in the .env files.
if grep -q "CHANGEME_" .env .secrets.env 2>/dev/null; then
  red "One or more CHANGEME_ placeholders remain in .env or .secrets.env."
  red "Edit those files and replace placeholders before running install."
  grep -l "CHANGEME_" .env .secrets.env
  exit 1
fi

# ─── Secrets directory ──────────────────────────────────────────────────────
mkdir -p secrets
umask 077

# Generate grafana admin password if missing
if [ ! -f secrets/grafana_admin_password.txt ]; then
  openssl rand -base64 32 > secrets/grafana_admin_password.txt
  chmod 600 secrets/grafana_admin_password.txt
  green "Generated secrets/grafana_admin_password.txt"
fi

# Mirror postgres password from .secrets.env to secrets/postgres_password.txt
if [ ! -f secrets/postgres_password.txt ] && grep -q "^POSTGRES_PASSWORD=" .secrets.env; then
  grep "^POSTGRES_PASSWORD=" .secrets.env | cut -d= -f2- > secrets/postgres_password.txt
  chmod 600 secrets/postgres_password.txt
  green "Mirrored POSTGRES_PASSWORD to secrets/postgres_password.txt"
fi

# Mirror clickhouse password
if [ ! -f secrets/clickhouse_password.txt ] && grep -q "^CLICKHOUSE_PASSWORD=" .secrets.env; then
  grep "^CLICKHOUSE_PASSWORD=" .secrets.env | cut -d= -f2- > secrets/clickhouse_password.txt
  chmod 600 secrets/clickhouse_password.txt
  green "Mirrored CLICKHOUSE_PASSWORD to secrets/clickhouse_password.txt"
fi

# Mirror encryption key (as raw bytes — the compose expects .bin)
if [ ! -f secrets/clickhouse_encryption_key.bin ] && grep -q "^CLICKHOUSE_ENCRYPTION_KEY=" .secrets.env; then
  grep "^CLICKHOUSE_ENCRYPTION_KEY=" .secrets.env | cut -d= -f2- | xxd -r -p > secrets/clickhouse_encryption_key.bin
  chmod 600 secrets/clickhouse_encryption_key.bin
  green "Mirrored CLICKHOUSE_ENCRYPTION_KEY to secrets/clickhouse_encryption_key.bin"
fi

# License token placeholder (customers receive this from cletrics sales)
if [ ! -f secrets/license_token.txt ]; then
  echo "trial" > secrets/license_token.txt
  chmod 600 secrets/license_token.txt
  yellow "secrets/license_token.txt set to 'trial'. Replace with your licensed token to unlock paid features."
fi

# Cloud credential placeholders (only used if you run the relevant profile)
for f in aws_credentials.json azure_credentials.json gcp_credentials.json; do
  [ -f "secrets/$f" ] || echo '{}' > "secrets/$f"
done
chmod 600 secrets/*.json secrets/*.txt secrets/*.bin 2>/dev/null || true

# ─── Pull and start ─────────────────────────────────────────────────────────
green "Pulling cletrics/rtccm-* images from Docker Hub..."
docker compose "$@" pull

green "Starting the stack..."
docker compose "$@" up -d

green "Install complete."
echo
echo "Next steps:"
echo "  1. Watch containers come healthy:   docker compose ps"
echo "  2. Tail logs for any failures:      docker compose logs -f --tail=50"
echo "  3. Open the web UI:                 http://\${RTCCM_HOST:-localhost}:\${WEB_PORT:-5173}"
echo "  4. First visit prompts for admin account creation."
