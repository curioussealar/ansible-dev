# Huong dan cau hinh va chay Playbook Template tren Semaphore UI

Tai lieu nay danh cho nguoi moi DevOps. Muc tieu la ban hieu Semaphore UI dang lam gi, can dien truong nao trong UI, va nen chay playbook nao truoc de tranh loi kho debug.

## 1. Hieu nhanh kien truc

Semaphore UI khong tu "doc file tren may Windows" cua ban. No chay ben trong container `semaphore`, sau do:

1. Lay code tu Git repository ban khai bao trong UI.
2. Dung Inventory de biet host nao can quan ly.
3. Dung Key Store de lay SSH key hoac WinRM password.
4. Chay lenh tuong duong:

```bash
ansible-playbook -i inventories/local-docker/hosts.yml playbooks/ping_linux.yml
```

Trong repo nay co 3 nhom target:

| Target | Inventory | Ket noi | Dung de |
|---|---|---|---|
| Linux container local | `inventories/local-docker/hosts.yml` | SSH toi `linux-target` | Test nhanh tren Docker Desktop |
| Ubuntu VPS/public lab | `inventories/internet-lab/hosts.yml` | SSH toi IP/hostname | Test that tren internet |
| Windows host | `inventories/windows/hosts.yml` | WinRM HTTPS 5986 | Test Windows playbook |

Trang thai hien tai da kiem tra:

- `compose.yaml` hop le.
- `compose.observability.yaml` hop le.
- `compose.prod.yaml` can `PUBLIC_HOSTNAME`, dung cho VPS co domain.
- Container `semaphore` va `postgres` dang healthy.
- Ben trong Semaphore da co `ansible-playbook`, `git`, `ssh`, `pywinrm`, `pypsrp`, va cac collection Windows/Linux can thiet.

## 2. Review cau truc repo

Repo duoc chia dung huong cho Ansible/Semaphore:

```text
compose.yaml                  # Semaphore UI + PostgreSQL + linux-target optional
compose.prod.yaml             # Caddy HTTPS overlay cho VPS
compose.observability.yaml    # Prometheus/Grafana optional
ansible.cfg                   # Default Ansible config khi chay CLI
requirements.yml              # Ansible collections
requirements.txt              # Python deps duoc Semaphore cai luc start
inventories/                  # Host lists theo moi truong
group_vars/                   # Bien dung chung theo nhom host
playbooks/                    # Entry points de tao Semaphore Task Templates
roles/                        # Logic tai su dung
scripts/                      # Tao secrets, validate, smoke-test
docs/                         # Huong dan van hanh
```

Diem tot:

- Tach `playbooks/`, `roles/`, `inventories/`, `group_vars/` ro rang.
- Compose dung Docker secrets qua bien `_FILE`, khong dua password thang vao `compose.yaml`.
- `requirements.txt` duoc mount vao `/etc/semaphore/requirements.txt`, dung theo co che Semaphore tu cai Python dependencies luc container start.
- Playbook Linux va Windows duoc tach rieng, phu hop cho nguoi moi test tung buoc.

Diem can canh giac:

- `linux_baseline.yml` va role `linux_common` co the doi SSH config, UFW, sysctl. Khong nen chay dau tien tren VPS quan trong.
- `windows_iis_demo.yml` co cai IIS va mo firewall port 8080; chi chay khi ban that su muon test IIS.
- `inventories/*/hosts.yml` la file local bi gitignore; Semaphore chi doc duoc chung neu file ton tai trong Git repository hoac duoc tao/upload trong Semaphore Inventory. Dung `.example` lam mau, nhung khi chay that can co inventory that.
- Docker Desktop Windows khong co san `ansible-playbook` tren host la binh thuong; khi chay qua UI, Ansible nam trong container Semaphore.

## 3. Chuan bi truoc khi vao Semaphore UI

### 3.1 Start stack

Tren Windows PowerShell:

```powershell
cd D:\code\ansible-dev
.\scripts\generate-secrets.ps1
docker compose up -d
docker compose ps
```

Mo UI:

```powershell
Start-Process "http://localhost:3000"
```

Dang nhap:

- Username: gia tri `SEMAPHORE_ADMIN` trong `.env`, mac dinh la `admin`.
- Password: doc tu `secrets/admin_password.txt`.

### 3.2 Neu muon test Linux container local

Tao SSH key neu chua co:

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\ansible_lab_ed25519" -C "ansible-lab"
```

Them public key vao `.env` de Docker build dua key vao user `ansible` trong `linux-target`:

```powershell
$pub = Get-Content "$env:USERPROFILE\.ssh\ansible_lab_ed25519.pub" -Raw
Add-Content .env "ANSIBLE_PUBKEY=`"$($pub.Trim())`""
docker compose build --no-cache linux-target
docker compose --profile linux-target up -d
docker compose --profile linux-target ps
```

Trong Semaphore, target `linux-target` chi truy cap duoc khi container `linux-target` dang chay cung Docker network.

### 3.3 Neu muon test VPS Ubuntu

Tren VPS, can co user `ansible` va public key trong:

```text
/home/ansible/.ssh/authorized_keys
```

Inventory mau nam o `inventories/internet-lab/hosts.yml.example`. Copy thanh `hosts.yml` de test local, nhung khi dung Semaphore qua Git, nen tao inventory trong UI hoac commit mot inventory lab khong chua password.

### 3.4 Neu muon test Windows

Tren Windows target, chay PowerShell as Administrator:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
.\scripts\windows\Enable-WinRM-For-Ansible.ps1
```

Sau do dung inventory `inventories/windows/hosts.yml.example` lam mau. Lab mac dinh dung:

- WinRM HTTPS: port `5986`
- Transport: `ntlm`
- Cert validation: `ignore` cho self-signed lab cert

## 4. Tao Project trong Semaphore UI

Vao `http://localhost:3000`.

1. Click **New Project**.
2. Name: `ansible-dev-lab`.
3. Alert: de trong luc moi hoc.
4. Save/Create.

Tu day, moi cau hinh Repository, Key, Inventory, Environment, Task Template nam trong project nay.

## 5. Tao Key Store

Key Store la noi Semaphore cat credential de task dung luc chay.

### 5.1 SSH key cho Linux

Vao **Key Store** -> **New Key**:

| Field | Gia tri |
|---|---|
| Name | `ansible-ssh-key` |
| Type | `SSH Key` |
| Private key | Noi dung file `C:\Users\HIEU\.ssh\ansible_lab_ed25519` |

Khong paste public key `.pub` vao day. Semaphore can private key de SSH toi target.

### 5.2 Password cho Windows WinRM

Vao **Key Store** -> **New Key**:

| Field | Gia tri |
|---|---|
| Name | `win-lab-credentials` |
| Type | `Login with password` |
| Login | `ansible_svc` |
| Password | Password cua user Windows WinRM |

Neu inventory da co `ansible_user`/`ansible_password`, ban co the de credentials trong Inventory/Environment. Nhung voi nguoi moi, dung Key Store de tranh lo password.

## 6. Tao Repository

Semaphore nen lay playbook tu Git URL. Cach de hoc de nhat:

1. Push repo nay len GitHub/GitLab rieng cua ban.
2. Vao **Repositories** -> **New Repository**.
3. Dien:

| Field | Gia tri |
|---|---|
| Name | `ansible-dev-lab` |
| URL | `https://github.com/YOUR_USER/ansible-dev.git` hoac SSH URL |
| Branch | `main` |
| Access Key | De trong neu repo public HTTPS; chon SSH key neu dung SSH URL |

Kiem tra nhanh: trong container Semaphore phai truy cap duoc repo:

```powershell
docker compose exec -T semaphore git ls-remote https://github.com/YOUR_USER/ansible-dev.git
```

Neu repo private, dung SSH deploy key rieng cho Git repository. Khong dung chung key quan ly server neu khong can.

## 7. Tao Inventory

Inventory noi cho Ansible biet danh sach host.

### 7.1 Local Docker Linux inventory

Vao **Inventory** -> **New Inventory**:

| Field | Gia tri |
|---|---|
| Name | `local-docker` |
| Type | `File` |
| Repository | `ansible-dev-lab` |
| Path | `inventories/local-docker/hosts.yml` |
| SSH Key | `ansible-ssh-key` |

Noi dung file `inventories/local-docker/hosts.yml` nen giong:

```yaml
all:
  children:
    linux:
      hosts:
        linux-target:
          ansible_host: linux-target
          ansible_port: 22
          ansible_user: ansible
```

Neu file `hosts.yml` khong nam trong Git vi bi `.gitignore`, hay tao Inventory dang **Static** trong UI va paste YAML tren vao.

### 7.2 Internet lab inventory

Dung cho VPS Ubuntu:

```yaml
all:
  children:
    linux:
      hosts:
        vps01:
          ansible_host: YOUR_VPS_IP
          ansible_port: 22
          ansible_user: ansible
          ansible_ssh_common_args: "-o StrictHostKeyChecking=accept-new"
```

Khong dua `ansible_password` vao Git. Dung SSH key.

### 7.3 Windows inventory

Dung cho Windows WinRM:

```yaml
all:
  children:
    windows:
      vars:
        ansible_connection: winrm
        ansible_winrm_scheme: https
        ansible_port: 5986
        ansible_winrm_transport: ntlm
        ansible_winrm_server_cert_validation: ignore
      hosts:
        win-lab-01:
          ansible_host: YOUR_WINDOWS_IP
          ansible_user: ansible_svc
```

Gan `win-lab-credentials` trong Inventory/Template neu UI cho chon credential. Neu khong, tao Environment rieng co extra vars password va chi dung cho lab.

## 8. Tao Environment

Environment trong Semaphore la nhom bien cho task.

Vao **Environment** -> **New Environment**.

### 8.1 `lab-defaults`

Name: `lab-defaults`

Extra variables:

```json
{
  "lab_environment": "local-docker",
  "ansible_python_interpreter": "/usr/bin/python3"
}
```

### 8.2 `safe-linux-baseline`

Dung khi test Linux baseline tren container local de giam kha nang loi do container khong co day du quyen nhu VM that:

```json
{
  "linux_common_ufw_enabled": false,
  "linux_common_unattended_upgrades": false,
  "linux_common_sysctl": {}
}
```

Voi VPS Ubuntu that, co the dung `lab-defaults` hoac bien rieng cua ban.

### 8.3 `windows-lab`

Chi dung trong lab neu ban chua dung Key Store/Vault tot:

```json
{
  "ansible_winrm_server_cert_validation": "ignore"
}
```

Khong nen dat password WinRM trong Environment neu project co nhieu nguoi.

## 9. Tao Task Templates

Task Template la "nut bam" de chay playbook.

Thu tu nen tao va chay:

1. Linux Ping
2. Linux Facts
3. Windows Ping
4. Windows Facts
5. Nginx Demo hoac Windows File Demo
6. Baseline/Install Docker/IIS sau khi da hieu tac dong

### 9.1 Linux Ping

| Field | Gia tri |
|---|---|
| Name | `01 - Linux Ping` |
| App | `Ansible` |
| Repository | `ansible-dev-lab` |
| Inventory | `local-docker` hoac `internet-lab` |
| Environment | `lab-defaults` |
| Playbook | `playbooks/ping_linux.yml` |
| CLI args | de trong |

Ket qua dung se co dong gan nhu:

```text
linux-target is reachable - pong: pong
```

### 9.2 Linux Facts

| Field | Gia tri |
|---|---|
| Name | `02 - Linux Facts` |
| App | `Ansible` |
| Repository | `ansible-dev-lab` |
| Inventory | `local-docker` hoac `internet-lab` |
| Environment | `lab-defaults` |
| Playbook | `playbooks/linux_facts.yml` |

Dung de xem OS, kernel, RAM, IPv4, Python.

### 9.3 Nginx Demo

| Field | Gia tri |
|---|---|
| Name | `03 - Nginx Demo` |
| App | `Ansible` |
| Repository | `ansible-dev-lab` |
| Inventory | `internet-lab` |
| Environment | `lab-defaults` |
| Playbook | `playbooks/nginx_demo.yml` |

Khuyen nghi chay tren VPS/VM Ubuntu that. Playbook nay cai `nginx`, tao site demo, va mo port 80 neu UFW bat.

### 9.4 Linux Baseline

| Field | Gia tri |
|---|---|
| Name | `10 - Linux Baseline` |
| App | `Ansible` |
| Repository | `ansible-dev-lab` |
| Inventory | `internet-lab` |
| Environment | `lab-defaults` |
| Playbook | `playbooks/linux_baseline.yml` |

Canh bao cho newbie: playbook nay co the sua SSH hardening va firewall. Truoc khi chay tren VPS:

- Dam bao SSH key login duoc.
- Dam bao port SSH trong `linux_common_ufw_rules` dung voi server.
- Mo console/VNC cua nha cung cap VPS neu co.

### 9.5 Install Docker Ubuntu

| Field | Gia tri |
|---|---|
| Name | `11 - Install Docker Ubuntu` |
| App | `Ansible` |
| Repository | `ansible-dev-lab` |
| Inventory | `internet-lab` |
| Environment | `lab-defaults` |
| Playbook | `playbooks/install_docker_ubuntu.yml` |

Playbook nay yeu cau target la Ubuntu 22.04 tro len.

### 9.6 Windows Ping

| Field | Gia tri |
|---|---|
| Name | `01 - Windows Ping` |
| App | `Ansible` |
| Repository | `ansible-dev-lab` |
| Inventory | `windows-lab` |
| Environment | `windows-lab` |
| Playbook | `playbooks/ping_windows.yml` |

Dung de kiem tra WinRM truoc khi chay bat ky playbook Windows nao.

### 9.7 Windows Facts

| Field | Gia tri |
|---|---|
| Name | `02 - Windows Facts` |
| App | `Ansible` |
| Repository | `ansible-dev-lab` |
| Inventory | `windows-lab` |
| Environment | `windows-lab` |
| Playbook | `playbooks/windows_facts.yml` |

Dung de xem OS, IP, RAM, PowerShell version, hotfix gan day.

### 9.8 Windows File Demo

| Field | Gia tri |
|---|---|
| Name | `03 - Windows File Demo` |
| App | `Ansible` |
| Repository | `ansible-dev-lab` |
| Inventory | `windows-lab` |
| Environment | `windows-lab` |
| Playbook | `playbooks/windows_file_demo.yml` |

Playbook nay tao `C:\ansible-demo`, tao file demo, in noi dung, roi xoa thu muc khi task co tag `cleanup`.

### 9.9 Windows IIS Demo

| Field | Gia tri |
|---|---|
| Name | `10 - Windows IIS Demo` |
| App | `Ansible` |
| Repository | `ansible-dev-lab` |
| Inventory | `windows-lab` |
| Environment | `windows-lab` |
| Playbook | `playbooks/windows_iis_demo.yml` |
| Extra vars | `{"windows_enable_iis": true}` |

Canh bao: playbook nay cai IIS, co the reboot, va mo firewall port 8080.

## 10. Cach chay template va doc ket qua

1. Vao **Task Templates**.
2. Chon template, vi du `01 - Linux Ping`.
3. Click **Run**.
4. Vao tab/log cua task dang chay.
5. Xem cac trang thai:

| Trang thai | Y nghia |
|---|---|
| `starting` | Semaphore dang chuan bi repo/inventory/key |
| `running` | Ansible dang chay |
| `success` | Playbook ket thuc OK |
| `error` | Playbook fail, doc log de xem task nao fail |

Neu fail, doc log tu tren xuong duoi va tim dong:

```text
fatal: [host-name]: FAILED! => ...
```

Dong do moi la loi goc cua Ansible.

## 11. Loi hay gap va cach sua

### Repository not found

Nguyen nhan: URL Git sai, repo private chua co deploy key, hoac container khong ra internet.

Kiem tra:

```powershell
docker compose exec -T semaphore git ls-remote <GIT_URL>
```

### Inventory file not found

Nguyen nhan: ban chon Inventory type `File` nhung file `inventories/.../hosts.yml` khong co trong Git repo.

Cach sua:

- Commit inventory lab khong chua secret vao Git, hoac
- Dung Inventory type `Static` trong UI va paste YAML.

### SSH permission denied

Nguyen nhan: private key trong Key Store khong khop public key tren target.

Kiem tra:

- Public key `.pub` co nam trong `authorized_keys` cua target chua.
- `ansible_user` dung chua.
- Neu la `linux-target`, da build lai sau khi them `ANSIBLE_PUBKEY` chua.

### Host key verification failed

Them vao inventory lab:

```yaml
ansible_ssh_common_args: "-o StrictHostKeyChecking=accept-new"
```

### WinRM 401 Unauthorized

Nguyen nhan: sai user/password hoac transport.

Kiem tra:

- User `ansible_svc` ton tai tren Windows.
- Password dung.
- Inventory dung `ansible_winrm_transport: ntlm`.

### WinRM certificate error

Lab self-signed cert can:

```yaml
ansible_winrm_server_cert_validation: ignore
```

Production nen dung cert CA-signed va doi thanh `validate`.

### Task fail nhung Docker container healthy

Container healthy chi noi Semaphore UI chay duoc. Playbook fail la loi Ansible, inventory, credential, hoac target host.

Xem log Semaphore:

```powershell
docker compose logs --tail=100 semaphore
```

## 12. Checklist cho nguoi moi

Truoc khi chay playbook dau tien:

- `docker compose ps` thay `semaphore` va `postgres` healthy.
- Da login duoc UI.
- Da tao Project.
- Da tao Repository va test Git URL.
- Da tao Key Store phu hop.
- Da tao Inventory dung nhom `linux` hoac `windows`.
- Da tao Environment.
- Da tao Task Template voi playbook dung.
- Chay `Ping` truoc, chua chay baseline/firewall/IIS ngay.

Thu tu hoc de khong bi roi:

1. Chay `01 - Linux Ping`.
2. Chay `02 - Linux Facts`.
3. Doi sang VPS that va lap lai ping/facts.
4. Chay `03 - Nginx Demo`.
5. Setup Windows WinRM.
6. Chay `01 - Windows Ping`.
7. Chay `02 - Windows Facts`.
8. Moi xem toi baseline, Docker install, IIS.

## 13. Mapping playbook trong repo

| Playbook | Nhom host | Muc do rui ro | Ghi chu |
|---|---|---|---|
| `playbooks/ping_linux.yml` | `linux` | Thap | Nen chay dau tien |
| `playbooks/linux_facts.yml` | `linux` | Thap | Chi doc facts |
| `playbooks/nginx_demo.yml` | `linux` | Trung binh | Cai nginx, mo port 80 |
| `playbooks/linux_baseline.yml` | `linux` | Cao | Sua SSH/firewall/sysctl |
| `playbooks/install_docker_ubuntu.yml` | `linux` | Trung binh | Cai Docker tren Ubuntu |
| `playbooks/ping_windows.yml` | `windows` | Thap | Nen chay dau tien cho Windows |
| `playbooks/windows_facts.yml` | `windows` | Thap | Doc facts/hotfixes |
| `playbooks/windows_file_demo.yml` | `windows` | Thap | Tao/xoa file demo |
| `playbooks/windows_iis_demo.yml` | `windows` | Cao | Cai IIS, mo port 8080 |
| `playbooks/site.yml` | `all` | Cao | Chay ca Linux/Windows roles va report |

## 14. Ghi nho quan trong

- Semaphore UI la noi bam nut, nhung nguon su that van la Git repo.
- Inventory tra loi cau hoi "chay tren may nao".
- Key Store tra loi cau hoi "dang nhap bang gi".
- Environment tra loi cau hoi "bien nao duoc truyen vao playbook".
- Task Template tra loi cau hoi "chay playbook nao voi inventory/key/environment nao".
- Voi DevOps, dung ping/facts de chung minh ket noi truoc khi chay playbook co tac dong thay doi he thong.
