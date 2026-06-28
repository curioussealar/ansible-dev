# ansible-dev — Ansible + Semaphore UI DevOps Lab

Automated infrastructure management with [Semaphore UI](https://semaphoreui.com) running on Docker Compose.
Targets: Linux (SSH), Windows (WinRM/HTTPS), and local Docker containers.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Docker Compose Stack                                    │
│                                                          │
│  ┌─────────────┐    ┌──────────────────────────────┐    │
│  │  PostgreSQL  │◄───│  Semaphore UI :3000          │    │
│  │  (semaphore) │    │  (Git clone → run playbooks) │    │
│  └─────────────┘    └──────────────────────────────┘    │
│                              │                           │
│                    ┌─────────▼────────┐                  │
│                    │  linux-target    │  (profile)       │
│                    │  (SSH test host) │                  │
│                    └──────────────────┘                  │
└──────────────────────────────────────────────────────────┘
         │                          │
    SSH/localhost              WinRM HTTPS
         │                          │
   ┌─────▼──────┐           ┌───────▼───────┐
   │  Linux VPS │           │  Windows Host │
   │  (Ubuntu)  │           │  (WinRM 5986) │
   └────────────┘           └───────────────┘
```

## Quick Start (Local — Windows Docker Desktop)

```powershell
# 1. Clone repo
git clone <repo-url> D:\code\ansible-dev
cd D:\code\ansible-dev

# 2. Generate secrets
.\scripts\generate-secrets.ps1

# 3. Start the stack (with optional Linux test container)
docker compose --profile linux-target up -d

# 4. Open Semaphore UI
Start-Process "http://localhost:3000"

# 5. Validate
.\scripts\validate.sh   # or: bash scripts/validate.sh
```

## Quick Start (VPS — Ubuntu 24.04)

```bash
git clone <repo-url> ~/ansible-dev && cd ~/ansible-dev
./scripts/generate-secrets.sh
docker compose -f compose.yaml -f compose.prod.yaml up -d
```

See [docs/quickstart.md](docs/quickstart.md) for full walkthrough.

## Directory Structure

```
ansible-dev/
├── compose.yaml                  # Core stack (postgres + semaphore)
├── compose.prod.yaml             # Caddy HTTPS overlay
├── compose.observability.yaml    # Prometheus + Grafana overlay
├── ansible.cfg
├── requirements.yml              # Ansible collections
├── requirements.txt              # Python deps (mounted into container)
├── .env.example                  # Public config contract
├── docker/
│   └── linux-target/Dockerfile   # SSH test container
├── inventories/
│   ├── local-docker/
│   ├── internet-lab/
│   └── windows/
├── group_vars/
│   ├── all.yml
│   ├── linux.yml
│   └── windows.yml
├── playbooks/
│   ├── ping_linux.yml
│   ├── linux_baseline.yml
│   ├── install_docker_ubuntu.yml
│   ├── nginx_demo.yml
│   ├── ping_windows.yml
│   ├── windows_facts.yml
│   ├── windows_file_demo.yml
│   ├── windows_iis_demo.yml
│   └── site.yml
├── roles/
│   ├── linux_common/
│   ├── docker_engine_ubuntu/
│   ├── windows_common/
│   └── demo_report/
├── templates/
├── scripts/
│   ├── generate-secrets.sh
│   ├── generate-secrets.ps1
│   ├── validate.sh
│   ├── smoke-test.sh
│   └── windows/Enable-WinRM-For-Ansible.ps1
└── docs/
    ├── quickstart.md
    ├── semaphore-ui-setup.md
    ├── windows-winrm.md
    ├── internet-lab.md
    ├── security-bluebook.md
    └── troubleshooting.md
```

## Semaphore UI Setup

After the stack is running, configure via UI:
1. Create **Project** `ansible-dev-lab`
2. Add **Key Store** credentials (SSH key, WinRM password, Vault password)
3. Add **Inventory** pointing to `inventories/<env>/hosts.yml`
4. Add **Environment** variable groups
5. Create **Task Templates** for each playbook

See [docs/semaphore-ui-setup.md](docs/semaphore-ui-setup.md) for details.

## Documentation

| Doc | Description |
|-----|-------------|
| [docs/quickstart.md](docs/quickstart.md) | First-run walkthrough |
| [docs/semaphore-ui-setup.md](docs/semaphore-ui-setup.md) | Newbie guide for Semaphore project, inventory, key store, and task templates |
| [docs/windows-winrm.md](docs/windows-winrm.md) | WinRM setup for Windows targets |
| [docs/internet-lab.md](docs/internet-lab.md) | VPS + HTTPS production setup |
| [docs/security-bluebook.md](docs/security-bluebook.md) | Security hardening checklist |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Debugging runbook |

## Security

- Secrets live in `secrets/*.txt` or Semaphore Key Store — **never committed**
- See [docs/security-bluebook.md](docs/security-bluebook.md) for the full security checklist
- Run `./scripts/validate.sh` before every commit (includes secret scanning)
