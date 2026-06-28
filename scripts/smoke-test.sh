#!/usr/bin/env bash
# smoke-test.sh - Post-deploy smoke tests:
#   container health, Semaphore HTTP health, Ansible inside Semaphore,
#   and optional local CLI Linux ping.
# Usage: ./scripts/smoke-test.sh [--port 3000]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SEMAPHORE_PORT="${SEMAPHORE_PORT:-3000}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port=*) SEMAPHORE_PORT="${1#*=}" ;;
        --port)
            shift
            SEMAPHORE_PORT="${1:?--port requires a value}"
            ;;
    esac
    shift || true
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((PASS += 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $*"; ((FAIL += 1)); }
skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; ((SKIP += 1)); }
section() { echo -e "\n${BLUE}=== $* ===${NC}"; }

cd "${REPO_ROOT}"

section "Container health"
if command -v docker &>/dev/null && docker compose ps &>/dev/null; then
    for svc in semaphore postgres; do
        cid="$(docker compose ps -q "${svc}" 2>/dev/null || true)"
        if [[ -z "${cid}" ]]; then
            fail "Container ${svc} is not running"
            continue
        fi

        status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${cid}" 2>/dev/null || echo "unknown")"
        if [[ "${status}" == "healthy" ]]; then
            pass "Container ${svc} is healthy"
        else
            fail "Container ${svc} health: ${status}"
        fi
    done
else
    skip "Docker daemon not accessible from this shell"
fi

section "Semaphore HTTP"
SEMAPHORE_URL="http://localhost:${SEMAPHORE_PORT}/api/ping"
MAX_WAIT=60
WAITED=0

until curl -sf "${SEMAPHORE_URL}" &>/dev/null; do
    if [[ ${WAITED} -ge ${MAX_WAIT} ]]; then
        fail "Semaphore did not respond at ${SEMAPHORE_URL} after ${MAX_WAIT}s"
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
done

if curl -sf "${SEMAPHORE_URL}" &>/dev/null; then
    pass "Semaphore API ping at ${SEMAPHORE_URL}"
fi

HTTP_STATUS="$(curl -so /dev/null -w "%{http_code}" "http://localhost:${SEMAPHORE_PORT}" 2>/dev/null || echo "000")"
if [[ "${HTTP_STATUS}" == "200" ]] || [[ "${HTTP_STATUS}" == "302" ]]; then
    pass "Semaphore UI HTTP ${HTTP_STATUS} at http://localhost:${SEMAPHORE_PORT}"
else
    fail "Semaphore UI returned HTTP ${HTTP_STATUS}"
fi

section "Ansible runtime"
if command -v docker &>/dev/null && docker compose ps &>/dev/null && docker compose ps -q semaphore &>/dev/null; then
    if ANSIBLE_VER="$(docker compose exec -T semaphore ansible --version 2>/dev/null | head -1)"; then
        pass "Ansible available inside Semaphore: ${ANSIBLE_VER}"
    else
        fail "ansible not found inside Semaphore container"
    fi
elif command -v ansible &>/dev/null; then
    ANSIBLE_VER="$(ansible --version | head -1)"
    pass "Ansible installed locally: ${ANSIBLE_VER}"
else
    skip "Ansible not found locally and Semaphore container is not running"
fi

section "Linux ping (optional local CLI)"
if command -v ansible-playbook &>/dev/null && [[ -f inventories/local-docker/hosts.yml ]]; then
    if ansible-playbook -i inventories/local-docker/hosts.yml playbooks/ping_linux.yml 2>&1; then
        pass "Linux ping via local Ansible CLI"
    else
        fail "Linux ping playbook failed"
    fi
else
    skip "ansible-playbook not found locally or inventories/local-docker/hosts.yml is missing"
fi

echo ""
echo "------------------------------------------"
echo -e " ${GREEN}PASS${NC}: ${PASS}  ${RED}FAIL${NC}: ${FAIL}  ${YELLOW}SKIP${NC}: ${SKIP}"
echo "------------------------------------------"

if [[ ${FAIL} -gt 0 ]]; then
    echo -e "${RED}Smoke test failed.${NC}"
    exit 1
fi

echo -e "${GREEN}All required smoke tests passed.${NC}"
