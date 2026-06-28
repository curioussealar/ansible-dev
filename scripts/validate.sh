#!/usr/bin/env bash
# validate.sh — Run all pre-commit checks:
#   docker compose config, yamllint, ansible-lint,
#   ansible syntax-check, shellcheck, optional gitleaks.
# Usage: ./scripts/validate.sh [--fast]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FAST_MODE=false

for arg in "$@"; do
    [[ "$arg" == "--fast" ]] && FAST_MODE=true
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0; FAIL=0; SKIP=0

pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((PASS += 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $*"; ((FAIL += 1)); }
skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; ((SKIP += 1)); }
section() { echo -e "\n${BLUE}=== $* ===${NC}"; }

cd "${REPO_ROOT}"

# ── 1. Docker Compose config ────────────────────────────────────────────────
section "Docker Compose config"
if command -v docker &>/dev/null; then
    if docker compose -f compose.yaml config --quiet 2>/dev/null; then
        pass "compose.yaml"
    else
        fail "compose.yaml is invalid"
    fi

    if PUBLIC_HOSTNAME="${PUBLIC_HOSTNAME:-semaphore.example.com}" docker compose -f compose.yaml -f compose.prod.yaml config --quiet 2>/dev/null; then
        pass "compose.prod.yaml overlay"
    else
        fail "compose.prod.yaml overlay is invalid"
    fi

    if docker compose -f compose.yaml -f compose.observability.yaml config --quiet 2>/dev/null; then
        pass "compose.observability.yaml overlay"
    else
        fail "compose.observability.yaml overlay is invalid"
    fi
else
    skip "Docker not found — skipping Compose config check"
fi

# ── 2. YAML lint ─────────────────────────────────────────────────────────────
section "YAML lint"
if command -v yamllint &>/dev/null; then
    if yamllint -c .yamllint.yml . 2>&1; then
        pass "yamllint"
    else
        fail "yamllint found issues"
    fi
else
    skip "yamllint not installed (pip install yamllint)"
fi

# ── 3. Ansible collections ───────────────────────────────────────────────────
section "Ansible collections"
if command -v ansible-galaxy &>/dev/null; then
    if ansible-galaxy collection install -r requirements.yml --force-with-deps 2>/dev/null; then
        pass "ansible-galaxy install"
    else
        fail "ansible-galaxy install failed"
    fi
else
    skip "ansible-galaxy not installed"
fi

# ── 4. Ansible syntax-check ──────────────────────────────────────────────────
section "Ansible syntax-check"
if command -v ansible-playbook &>/dev/null; then
    PLAYBOOKS=(
        playbooks/ping_linux.yml
        playbooks/linux_facts.yml
        playbooks/linux_baseline.yml
        playbooks/install_docker_ubuntu.yml
        playbooks/nginx_demo.yml
        playbooks/ping_windows.yml
        playbooks/windows_facts.yml
        playbooks/windows_file_demo.yml
        playbooks/windows_iis_demo.yml
        playbooks/site.yml
    )
    for pb in "${PLAYBOOKS[@]}"; do
        if ansible-playbook --syntax-check -i inventories/local-docker/hosts.yml.example "$pb" 2>/dev/null; then
            pass "syntax: $pb"
        else
            fail "syntax: $pb"
        fi
    done
else
    skip "ansible-playbook not installed"
fi

# ── 5. Ansible lint ──────────────────────────────────────────────────────────
section "Ansible lint"
if [[ "$FAST_MODE" == "false" ]] && command -v ansible-lint &>/dev/null; then
    if ansible-lint --profile=production 2>&1; then
        pass "ansible-lint"
    else
        fail "ansible-lint found issues"
    fi
else
    skip "ansible-lint (run without --fast to enable)"
fi

# ── 6. Shell check ───────────────────────────────────────────────────────────
section "ShellCheck"
if command -v shellcheck &>/dev/null; then
    SHELL_SCRIPTS=(scripts/generate-secrets.sh scripts/validate.sh scripts/smoke-test.sh)
    for s in "${SHELL_SCRIPTS[@]}"; do
        if shellcheck "$s"; then
            pass "shellcheck: $s"
        else
            fail "shellcheck: $s"
        fi
    done
else
    skip "shellcheck not installed"
fi

# ── 7. Secret scan (gitleaks) ────────────────────────────────────────────────
section "Secret scan"
if command -v gitleaks &>/dev/null; then
    if gitleaks detect --source . --no-git 2>&1; then
        pass "gitleaks — no secrets detected"
    else
        fail "gitleaks — potential secrets found!"
    fi
else
    skip "gitleaks not installed (https://github.com/gitleaks/gitleaks)"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
echo -e " ${GREEN}PASS${NC}: ${PASS}  ${RED}FAIL${NC}: ${FAIL}  ${YELLOW}SKIP${NC}: ${SKIP}"
echo "──────────────────────────────────────────"

if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}Validation failed. Fix issues before committing.${NC}"
    exit 1
fi

echo -e "${GREEN}All checks passed.${NC}"
