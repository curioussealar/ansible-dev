# Quickstart Guide

## Prerequisites

| Tool | Minimum version | Purpose |
|------|----------------|---------|
| Docker Desktop | 4.x | Container runtime (Windows) |
| Docker Compose | v2.x | Stack management |
| Git | 2.x | Clone this repo |
| PowerShell | 5.1+ | Scripts on Windows |

## Step 1 — Clone and generate secrets

```powershell
# Clone
git clone <your-repo-url> D:\code\ansible-dev
cd D:\code\ansible-dev

# Generate secrets (safe to re-run)
.\scripts\generate-secrets.ps1
```

The script creates `secrets/*.txt` files and copies `.env.example` → `.env`.
It prints the auto-generated admin password — save it.

## Step 2 — Review .env

Open `.env` and adjust if needed:

```env
SEMAPHORE_PORT=3000          # Change if 3000 is in use
TZ=Asia/Ho_Chi_Minh          # Your timezone
SEMAPHORE_ADMIN=admin        # Admin username
```

## Step 3 — Start the stack

```powershell
# Core only (Semaphore + Postgres)
docker compose up -d

# With Linux SSH test container
docker compose --profile linux-target up -d

# Watch logs
docker compose logs -f semaphore
```

## Step 4 — Access Semaphore UI

Open [http://localhost:3000](http://localhost:3000) and log in with:
- **Username**: `admin` (or your `SEMAPHORE_ADMIN` value)
- **Password**: printed by `generate-secrets.ps1`, or read from `secrets/admin_password.txt`

## Step 5 — Test Ansible from CLI

If you have Ansible installed locally:

```bash
# Copy inventory from example
cp inventories/local-docker/hosts.yml.example inventories/local-docker/hosts.yml
# Edit hosts.yml — set ansible_ssh_private_key_file to your key

# Ping test
ansible-playbook -i inventories/local-docker/hosts.yml playbooks/ping_linux.yml
```

## Step 6 — Smoke test

```bash
./scripts/smoke-test.sh
```

## Configure Semaphore UI

See [semaphore-ui-setup.md](semaphore-ui-setup.md) to configure:
- Git repository connection
- SSH/WinRM credentials in Key Store
- Inventory files
- Task templates for each playbook

## Next steps

- Set up a Windows WinRM target: [windows-winrm.md](windows-winrm.md)
- Deploy to VPS with HTTPS: [internet-lab.md](internet-lab.md)
- Enable observability: `docker compose -f compose.yaml -f compose.observability.yaml up -d`
- Troubleshooting: [troubleshooting.md](troubleshooting.md)
