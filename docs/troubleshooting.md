# Troubleshooting Runbook

## Quick diagnosis

```bash
# Overall stack status
docker compose ps

# Recent logs (all services)
docker compose logs --tail=50

# Semaphore logs only
docker compose logs -f semaphore

# Postgres logs only
docker compose logs -f postgres
```

---

## Semaphore UI issues

### Semaphore won't start

**Symptom**: `docker compose ps` shows semaphore as `unhealthy` or restarting.

```bash
# Check logs
docker compose logs semaphore

# Common causes:
# 1. Secrets files missing
ls -la secrets/
# Expected: postgres_password.txt, access_key_encryption.txt, cookie_hash.txt,
#           cookie_encryption.txt, admin_password.txt

# 2. Postgres not ready yet
docker compose logs postgres | tail -20

# 3. Port 3000 already in use
netstat -an | grep 3000   # Linux
Get-NetTCPConnection -LocalPort 3000  # Windows PowerShell
```

**Fix**: Run `./scripts/generate-secrets.sh` (or `.ps1`), then `docker compose up -d`.

### Cannot log in to Semaphore

```bash
# Read the admin password
cat secrets/admin_password.txt

# Reset admin password via Semaphore CLI
docker compose exec semaphore semaphore user change-by-login \
  --login admin --password NewPassword123
```

### Task failed: "repository not found"

Ensure the Git repository URL in Semaphore is reachable from inside the container:

```bash
# Test Git access from inside container
docker compose exec semaphore git ls-remote <your-repo-url>
```

---

## PostgreSQL issues

### Database connection failed

```bash
# Check Postgres health
docker compose exec postgres pg_isready -U semaphore -d semaphore

# Manual DB connection test
docker compose exec postgres psql -U semaphore -d semaphore -c '\l'

# Check Postgres password matches semaphore config
docker compose exec postgres cat /run/secrets/postgres_password
docker compose exec semaphore cat /run/secrets/SEMAPHORE_DB_PASS
```

### Database reset (destructive!)

```bash
# WARNING: This deletes all Semaphore data
docker compose down
docker volume rm ansible-dev_postgres_data
docker compose up -d
```

---

## Ansible SSH issues

### Permission denied (publickey)

```bash
# Test SSH manually
ssh -i ~/.ssh/ansible_lab_ed25519 -p 22 ansible@HOSTNAME -v

# Check authorized_keys on target
cat ~/.ssh/authorized_keys   # on target host

# From Semaphore container
docker compose exec semaphore ssh -i /path/to/key ansible@linux-target
```

### Connection refused

```bash
# Check SSH service on target
docker compose exec linux-target service ssh status

# Check network connectivity
docker compose exec semaphore ping linux-target

# Verify linux-target is running
docker compose ps linux-target
```

### Host key verification failed

Add `StrictHostKeyChecking=accept-new` to inventory:

```yaml
ansible_ssh_common_args: "-o StrictHostKeyChecking=accept-new"
```

Or clear the known_hosts entry:

```bash
ssh-keygen -R HOSTNAME
```

---

## WinRM issues

### Cannot connect to Windows host

```bash
# Test WinRM HTTPS from Ansible controller
curl -v -k --ntlm --user "ansible_svc:PASSWORD" \
  https://WINDOWS_HOST:5986/wsman

# Check WinRM is running on Windows target (PowerShell as admin)
Get-Service WinRM
winrm enumerate winrm/config/Listener
```

### Authentication error (401)

```powershell
# On Windows target — verify NTLM is enabled
Get-WSManInstance -ResourceURI winrm/config/service/Auth
# NTLM should show True

# Verify user exists and has correct password
Get-LocalUser ansible_svc
```

### SSL certificate error

In `inventories/windows/hosts.yml`:

```yaml
ansible_winrm_server_cert_validation: ignore  # lab only
```

For production, validate the cert and set `validate`.

### Timeout errors

Increase timeouts in `group_vars/windows.yml`:

```yaml
ansible_winrm_operation_timeout_sec: 120
ansible_winrm_read_timeout_sec: 130
```

---

## Docker Desktop (Windows) issues

### Compose config shows "error" on secrets

Ensure all secret files exist:

```powershell
Get-ChildItem secrets\
# Must include: postgres_password.txt, access_key_encryption.txt,
#   cookie_hash.txt, cookie_encryption.txt, admin_password.txt
```

### linux-target container not reachable

Ensure you started with the `linux-target` profile:

```powershell
docker compose --profile linux-target up -d
docker compose ps linux-target
```

### Port 3000 already in use

Change `SEMAPHORE_PORT` in `.env`:

```env
SEMAPHORE_PORT=3001
```

Then restart: `docker compose up -d`

---

## Validation quick-check

```bash
# Run all validation checks
./scripts/validate.sh

# Run smoke tests
./scripts/smoke-test.sh

# Test specific playbook syntax
ansible-playbook --syntax-check \
  -i inventories/local-docker/hosts.yml.example \
  playbooks/ping_linux.yml
```

---

## Log locations

| Component | Log location |
|-----------|-------------|
| Semaphore | `docker compose logs semaphore` |
| Postgres | `docker compose logs postgres` |
| Caddy (prod) | `docker compose logs caddy` |
| Linux target SSH | `docker compose exec linux-target journalctl -u ssh` |
| Windows WinRM | Event Viewer → Windows Logs → Application |
| Ansible CLI | stdout (use `-v` / `-vvv` for verbose) |

## Useful one-liners

```bash
# Restart just semaphore (without touching DB)
docker compose restart semaphore

# Force pull latest images and restart
docker compose pull && docker compose up -d

# Enter semaphore container shell
docker compose exec -it semaphore /bin/sh

# Enter postgres container shell
docker compose exec -it postgres psql -U semaphore -d semaphore

# Check all container resource usage
docker stats $(docker compose ps -q)

# Clean up stopped containers and dangling images
docker system prune -f
```
