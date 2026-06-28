# Semaphore UI — Setup Guide

Hướng dẫn cấu hình Semaphore UI sau khi stack Docker đã chạy.
Xem thêm: [semaphore-ui-troubleshoot.md](semaphore-ui-troubleshoot.md) nếu gặp lỗi.

---

## 1. Tạo Project

1. Đăng nhập vào `http://localhost:3000`
2. Click **New Project**
3. Điền **Name**: `ansible-dev-lab`
4. Click **Create**

---

## 2. Key Store — Thêm credentials

Vào **Key Store → New Key** để thêm từng loại credential.

### SSH Key (cho Linux targets)

| Field | Value |
|-------|-------|
| Name | `ansible-ssh-key` |
| Type | `SSH Key` |
| Private Key | Nội dung file `~/.ssh/ansible_lab_ed25519` |

```powershell
# Lấy nội dung private key để paste
Get-Content "$env:USERPROFILE\.ssh\ansible_lab_ed25519" | Set-Clipboard
```

> Tạo keypair nếu chưa có:
> ```powershell
> ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\ansible_lab_ed25519" -C "ansible-lab" -N '""'
> ```

### Login với Password (cho Linux/Windows targets dùng password SSH)

| Field | Value |
|-------|-------|
| Name | `vm-local-password` |
| Type | `Login with password` |
| Login | username trên target host |
| Password | password SSH |

### WinRM (cho Windows targets)

| Field | Value |
|-------|-------|
| Name | `win-lab-credentials` |
| Type | `Login with password` |
| Login | `ansible_svc` |
| Password | WinRM user password |

### Vault Password

| Field | Value |
|-------|-------|
| Name | `vault-password` |
| Type | `Login with password` |
| Login | *(để trống)* |
| Password | Ansible Vault password |

---

## 3. Repository

**Repositories → New Repository**

| Field | Value |
|-------|-------|
| Name | `ansible-dev-lab` |
| URL | URL git repo của bạn |
| Branch | `main` |
| Access Key | `ansible-ssh-key` (SSH URL) hoặc None (HTTPS public) |

> **Lưu ý:** Semaphore clone repo này mỗi khi chạy task. Các file playbook, inventory, role phải được commit và push lên remote trước khi chạy.

---

## 4. Inventories

Vào **Inventory → New Inventory** cho từng environment.

### Linux VM / VPS (dùng password SSH)

| Field | Value |
|-------|-------|
| Name | `vm-local` |
| Type | `Static` |
| SSH Key | `vm-local-password` |

Paste vào ô **Inventory** (dùng **YAML format**):

```yaml
all:
  children:
    linux:
      hosts:
        ubuntu-vm:
          ansible_host: 192.168.118.128
          ansible_connection: ssh
          ansible_become: true
          ansible_become_method: sudo
          ansible_host_key_checking: false
```

> Username và password Semaphore tự inject từ SSH Key đã chọn — không cần khai báo trong inventory.

### Linux VM (dùng SSH key)

```yaml
all:
  children:
    linux:
      hosts:
        ubuntu-vm:
          ansible_host: 192.168.118.128
          ansible_connection: ssh
          ansible_become: true
          ansible_become_method: sudo
          ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
```

### File-based Inventory (từ repo)

| Field | Value |
|-------|-------|
| Name | `internet-lab` |
| Type | `File` |
| Path | `inventories/internet-lab/hosts.yml` |
| SSH Key | `ansible-ssh-key` |

### Windows

| Field | Value |
|-------|-------|
| Name | `windows-lab` |
| Type | `File` |
| Path | `inventories/windows/hosts.yml` |
| SSH Key | `win-lab-credentials` |

---

## 5. Environment (Variable Groups)

**Environment → New Environment**

| Field | Value |
|-------|-------|
| Name | `lab-defaults` |

Extra variables (JSON):

```json
{
  "lab_environment": "local-docker",
  "ansible_python_interpreter": "/usr/bin/python3"
}
```

---

## 6. Task Templates

**Task Templates → New Template** — tạo theo bảng dưới.

> **Quan trọng:** Field **Playbook Filename** phải có đủ đường dẫn từ root repo, bao gồm thư mục `playbooks/`.

### Linux

| Name | Playbook Filename | Inventory | Ghi chú |
|------|------------------|-----------|---------|
| `Linux Ping` | `playbooks/ping_linux.yml` | `vm-local` | Chạy đầu tiên để test kết nối |
| `Linux Facts` | `playbooks/linux_facts.yml` | `vm-local` | Xem thông tin host |
| `Linux Network System Info` | `playbooks/linux_network_systeminfo.yml` | `vm-local` | Kiem tra network, routing, DNS, RAM, disk, service |
| `Linux Baseline` | `playbooks/linux_baseline.yml` | `vm-local` | SSH hardening, ufw, sysctl |
| `Install Docker` | `playbooks/install_docker_ubuntu.yml` | `vm-local` | Cài Docker Engine |
| `Nginx Demo` | `playbooks/nginx_demo.yml` | `vm-local` | Demo web server |

### Windows

| Name | Playbook Filename | Inventory |
|------|------------------|-----------|
| `Windows Ping` | `playbooks/ping_windows.yml` | `windows-lab` |
| `Windows Facts` | `playbooks/windows_facts.yml` | `windows-lab` |
| `Windows File Demo` | `playbooks/windows_file_demo.yml` | `windows-lab` |

### Cross-platform

| Name | Playbook Filename | Inventory |
|------|------------------|-----------|
| `Site — All Hosts` | `playbooks/site.yml` | `vm-local` |

---

## 7. Chạy Task đầu tiên

**Thứ tự khuyến nghị cho lab mới:**

1. Chạy **Linux Ping** — xác nhận kết nối SSH OK
2. Chạy **Linux Facts** — xem thông tin host
3. Chạy **Linux Network System Info** — kiem tra network, DNS, RAM, disk, service
4. Chạy **Linux Baseline** — áp dụng hardening
5. Chạy **Install Docker** (nếu cần Docker trên target)
6. Chạy **Nginx Demo** (nếu muốn test web server)

---

## 8. Schedules (Tùy chọn)

Trong Task Template, click **Schedules → Add** để tự động hóa:

```
# Chạy Linux Baseline mỗi ngày lúc 2:00 SA
0 2 * * *
```

---

## 9. Notifications (Tùy chọn)

Cấu hình Slack/email tại **Project → Alert**.
