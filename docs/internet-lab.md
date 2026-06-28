# Internet Lab — VPS + HTTPS Setup

Deploy Semaphore UI on a public Ubuntu 24.04 VPS with automatic HTTPS via Caddy.

## Prerequisites

- Ubuntu 24.04 VPS with public IP
- Domain name with DNS A record pointing to VPS IP
- Ports 22, 80, 443 open in firewall/security group
- Docker Engine + Docker Compose v2 installed on VPS

## Step 1 — Install Docker on VPS

```bash
# Run from this repo after SSHing into your VPS
ansible-playbook -i inventories/internet-lab/hosts.yml playbooks/install_docker_ubuntu.yml
```

Or manually:

```bash
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
newgrp docker
```

## Step 2 — Deploy the repo to VPS

```bash
# On VPS
git clone <your-repo-url> ~/ansible-dev
cd ~/ansible-dev

# Generate secrets
./scripts/generate-secrets.sh
```

## Step 3 — Configure .env for production

Edit `.env`:

```env
PUBLIC_HOSTNAME=semaphore.example.com   # Your domain
SEMAPHORE_PORT=3000
TZ=Asia/Ho_Chi_Minh
SEMAPHORE_ADMIN=admin
SEMAPHORE_ADMIN_EMAIL=admin@example.com
POSTGRES_DB=semaphore
POSTGRES_USER=semaphore
```

## Step 4 — Deploy with Caddy HTTPS

```bash
docker compose -f compose.yaml -f compose.prod.yaml up -d
```

Caddy automatically obtains a Let's Encrypt TLS certificate for your domain.

Access Semaphore at: `https://semaphore.example.com`

## Step 5 — Firewall hardening

```bash
# Allow only required ports
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP (Caddy redirects to HTTPS)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

## Alternative: No domain (SSH tunnel)

If you don't have a domain, keep port 3000 bound to 127.0.0.1 (default in `compose.yaml`) and access via SSH tunnel:

```bash
# On local machine
ssh -L 3000:localhost:3000 user@YOUR_VPS_IP

# Then open http://localhost:3000 in local browser
```

## Step 6 — Semaphore Git repository

For Semaphore to clone and run this repo on the VPS:

1. Push this repo to GitHub/GitLab
2. In Semaphore UI → Repositories → Add with your Git URL
3. Semaphore stores the repo in `/tmp/semaphore` inside the container

## Step 7 — Add observability (optional)

```bash
docker compose -f compose.yaml -f compose.prod.yaml -f compose.observability.yaml up -d
```

- Grafana: `http://localhost:3001` (via SSH tunnel or Caddy proxy)
- Prometheus: `http://localhost:9090`

## Updating

```bash
cd ~/ansible-dev
git pull
docker compose -f compose.yaml -f compose.prod.yaml pull
docker compose -f compose.yaml -f compose.prod.yaml up -d
```

## Backup

```bash
# Backup Postgres
docker compose exec postgres pg_dump -U semaphore semaphore > backup-$(date +%Y%m%d).sql

# Backup secrets
tar -czf secrets-backup-$(date +%Y%m%d).tar.gz secrets/
# Store encrypted backups off-server
```

## GitLab CI auto-deploy

The `.gitlab-ci.yml` in this repo includes a `deploy_lab` job that:
1. SSHes to your VPS
2. Runs `git pull && docker compose pull && docker compose up -d`

Configure these CI variables in GitLab:
- `VPS_HOST` — VPS hostname/IP
- `VPS_USER` — SSH user
- `VPS_SSH_KEY` — SSH private key (masked)
