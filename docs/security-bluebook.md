# Security Bluebook

Security hardening checklist for the Ansible + Semaphore UI lab.
Organized by risk level. Review before any public deployment.

---

## Secrets Management

| # | Control | Status | Notes |
|---|---------|--------|-------|
| S1 | All secrets stored in `secrets/*.txt` using `_FILE` env vars | Required | Never put secrets directly in compose.yaml or .env |
| S2 | `.env` and `secrets/` in `.gitignore` | Required | Verify with `git status` before every commit |
| S3 | `ansible-vault encrypt` for inventory passwords | Required for WinRM | Run `ansible-vault create group_vars/windows/vault.yml` |
| S4 | Vault password in `secrets/vault_pass.txt` (gitignored) | Required | Add `vault_password_file = secrets/vault_pass.txt` to ansible.cfg |
| S5 | Semaphore Key Store for all SSH/WinRM credentials | Required | Never store keys in environment variables |
| S6 | Rotate secrets at least annually | Recommended | Recreate `secrets/*.txt` and restart stack |
| S7 | Secret scanning in CI with gitleaks | Recommended | Add `gitleaks` job to `.gitlab-ci.yml` |

**Verify locally:**
```bash
git status --short | grep -E '^[AM].*\.(env|txt|key|pem|p12|pfx)$'
# Should return empty
```

---

## Network Security

| # | Control | Status | Notes |
|---|---------|--------|-------|
| N1 | Semaphore bound to `127.0.0.1` (not `0.0.0.0`) | Required | Default in `compose.yaml` — do not change without Caddy |
| N2 | Caddy HTTPS with Let's Encrypt for public access | Required (prod) | See `compose.prod.yaml` |
| N3 | SSH tunnel as alternative to public exposure | Required (no domain) | `ssh -L 3000:localhost:3000 user@vps` |
| N4 | UFW/firewall on VPS — deny all incoming except 22/80/443 | Required (prod) | See `internet-lab.md` |
| N5 | WinRM HTTPS only on port 5986 | Required | Disable HTTP 5985 in production |
| N6 | WinRM restricted to Ansible controller IP | Recommended | Add firewall rule on Windows target |
| N7 | No `--add-host` or host-network in containers | Required | Review before adding new services |

---

## Container Security

| # | Control | Status | Notes |
|---|---------|--------|-------|
| C1 | Named secrets via Docker secrets (not plain env vars) | Required | Uses `_FILE` convention |
| C2 | No privileged containers | Required | Review `docker compose config` |
| C3 | Read-only mounts for configs | Required | `:ro` on all config volume mounts |
| C4 | Pin image tags in production | Recommended | Change `latest` to specific digest |
| C5 | Container image scanning with Trivy | Recommended | Add `trivy` job to CI |
| C6 | Postgres data volume — not exposed externally | Required | Volume-only, no bind mount to host |
| C7 | Docker daemon log rotation configured | Required | See `docker_engine_ubuntu` role `daemon.json` |

**Scan images locally:**
```bash
trivy image semaphoreui/semaphore:latest
trivy image postgres:16-alpine
```

---

## SSH Hardening (Linux targets)

| # | Control | Status | Notes |
|---|---------|--------|-------|
| L1 | PasswordAuthentication no | Required | Applied by `linux_common` role |
| L2 | PermitRootLogin no | Required | Applied by `linux_common` role |
| L3 | PubkeyAuthentication yes | Required | Applied by `linux_common` role |
| L4 | MaxAuthTries 4 | Required | Applied by `linux_common` role |
| L5 | X11Forwarding no | Required | Applied by `linux_common` role |
| L6 | UFW enabled with deny-all-incoming default | Required | Applied by `linux_common` role |
| L7 | Unattended security upgrades enabled | Required | Applied by `linux_common` role |
| L8 | MOTD deployed (legal warning banner) | Recommended | Use `templates/motd.j2` |
| L9 | Separate `ansible` service account (non-root, sudo) | Required | Created in `linux-target` Dockerfile |

---

## WinRM Security (Windows targets)

| # | Control | Status | Notes |
|---|---------|--------|-------|
| W1 | WinRM HTTPS only (port 5986) | Required (prod) | Disable 5985 after testing |
| W2 | Self-signed cert for lab, CA-signed for prod | Required (prod) | See `windows-winrm.md` |
| W3 | NTLM for lab, Kerberos for domain/prod | Required (prod) | Set in `group_vars/windows.yml` |
| W4 | `ansible_winrm_server_cert_validation: validate` in prod | Required (prod) | Change from `ignore` |
| W5 | Dedicated `ansible_svc` service account | Required | Created by `Enable-WinRM-For-Ansible.ps1` |
| W6 | Just Enough Administration (JEA) | Recommended | Replace local admin with constrained JEA endpoint |
| W7 | WinRM access restricted to Ansible controller IP | Recommended | Windows Firewall inbound rule |

---

## CI/CD Security

| # | Control | Status | Notes |
|---|---------|--------|-------|
| I1 | All CI secrets in GitLab CI masked variables | Required | Never hardcode in `.gitlab-ci.yml` |
| I2 | `gitleaks` secret scan in CI | Required | Blocks commits with leaked secrets |
| I3 | `trivy` image scan in CI | Recommended | Catches vulnerable base images |
| I4 | `ansible-lint` with production profile | Required | Enforces Ansible best practices |
| I5 | `yamllint` on all YAML files | Required | Catches syntax errors early |
| I6 | `shellcheck` on all shell scripts | Required | Prevents shell injection |
| I7 | Manual approval for `deploy_lab` job | Required | `when: manual` gate in CI |
| I8 | SSH deploy key (not personal key) in CI | Required | Restrict to read-only repo access |

---

## Ansible Vault

Enable vault for sensitive group variables:

```bash
# Encrypt a file
ansible-vault encrypt group_vars/windows/vault.yml

# Edit encrypted file
ansible-vault edit group_vars/windows/vault.yml

# Run playbook with vault
ansible-playbook playbooks/site.yml --vault-password-file secrets/vault_pass.txt
```

Configure in `ansible.cfg`:
```ini
[defaults]
vault_password_file = secrets/vault_pass.txt
```

---

## Incident Response Checklist

If secrets are suspected compromised:

1. **Rotate** all secrets: `rm -rf secrets/ && ./scripts/generate-secrets.sh`
2. **Change** Semaphore admin password via UI
3. **Revoke** SSH authorized keys on all managed hosts
4. **Reset** WinRM service account password on Windows hosts
5. **Restart** the entire stack: `docker compose down && docker compose up -d`
6. **Audit** Semaphore task history for unauthorized runs
7. **Review** Docker and system logs for suspicious activity
8. **Notify** stakeholders per your incident response plan

---

## References

- [Semaphore Security](https://semaphoreui.com/docs/admin-guide/configuration)
- [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
- [WinRM Security](https://docs.ansible.com/ansible/latest/os_guide/windows_winrm.html)
- [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks)
- [OWASP Docker Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
