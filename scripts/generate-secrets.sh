#!/usr/bin/env bash
# generate-secrets.sh — Generate local secret files and .env from .env.example
# Usage: ./scripts/generate-secrets.sh
# Safe to re-run: only creates missing files, never overwrites existing secrets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_DIR="${REPO_ROOT}/secrets"
ENV_FILE="${REPO_ROOT}/.env"
ENV_EXAMPLE="${REPO_ROOT}/.env.example"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

generate_secret() {
    local file="$1"
    local label="$2"
    if [[ -f "${file}" ]]; then
        warn "${label} already exists — skipping (delete manually to regenerate)"
    else
        openssl rand -base64 32 > "${file}"
        chmod 600 "${file}"
        info "${label} generated → ${file}"
    fi
}

echo ""
echo "=== Ansible-dev secret generator ==="
echo ""

# Create secrets directory
mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"
info "Secrets directory: ${SECRETS_DIR}"

# Generate secret files
generate_secret "${SECRETS_DIR}/postgres_password.txt"       "PostgreSQL password"
generate_secret "${SECRETS_DIR}/access_key_encryption.txt"   "Semaphore access key encryption"
generate_secret "${SECRETS_DIR}/cookie_hash.txt"             "Semaphore cookie hash"
generate_secret "${SECRETS_DIR}/cookie_encryption.txt"       "Semaphore cookie encryption"

# Admin password — use a friendly random password
if [[ -f "${SECRETS_DIR}/admin_password.txt" ]]; then
    warn "Admin password already exists — skipping"
else
    openssl rand -base64 16 | tr -d '/+=' | head -c 20 > "${SECRETS_DIR}/admin_password.txt"
    chmod 600 "${SECRETS_DIR}/admin_password.txt"
    info "Admin password generated → ${SECRETS_DIR}/admin_password.txt"
    echo -e "${YELLOW}  Admin password: $(cat "${SECRETS_DIR}/admin_password.txt")${NC}"
fi

# Copy .env.example → .env if not exists
if [[ -f "${ENV_FILE}" ]]; then
    warn ".env already exists — skipping (edit manually)"
else
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"
    info ".env created from .env.example"
fi

echo ""
info "All secrets ready. Next:"
echo "  1. Edit .env if needed (PUBLIC_HOSTNAME, POSTGRES_USER, etc.)"
echo "  2. docker compose --profile linux-target up -d"
echo "  3. Open http://localhost:3000"
echo "  Admin user: admin"
echo "  Admin pass: $(cat "${SECRETS_DIR}/admin_password.txt")"
echo ""
