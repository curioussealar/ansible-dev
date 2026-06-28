# Semaphore UI — Troubleshooting

Tổng hợp các lỗi thường gặp khi cấu hình và chạy playbook qua Semaphore UI.
Xem thêm: [troubleshooting.md](troubleshooting.md) cho lỗi Docker/Ansible CLI.

---

## Lỗi khởi động container

### `panic: access_key_encryption must be a valid base64 string`

**Nguyên nhân:** File `secrets/access_key_encryption.txt` chứa UTF-8 BOM do `Set-Content -Encoding UTF8` trong PowerShell 5.1 tự động thêm 3 byte `EF BB BF` vào đầu file.

**Fix:**
```powershell
# Xóa toàn bộ secrets cũ
Remove-Item -Path secrets\* -Force

# Tạo lại (script đã fix dùng WriteAllText no-BOM)
.\scripts\generate-secrets.ps1

# Xóa volume cũ và restart
docker compose down
docker volume rm ansible-dev_postgres_data
docker compose up -d
```

---

### `pq: password authentication failed for user "semaphore" (28P01)`

**Nguyên nhân:** Postgres đã khởi tạo database với password cũ (có BOM). Sau khi tạo lại secrets với password mới, Postgres volume vẫn giữ password cũ.

**Fix:** Xóa Postgres data volume để reinitialize:
```powershell
docker compose down
docker volume rm ansible-dev_postgres_data
docker compose up -d
```

> **Cảnh báo:** Lệnh này xóa toàn bộ dữ liệu Semaphore (projects, task history). Chỉ dùng cho fresh setup.

---

### `ERROR: No matching distribution found for pypsrp>=1.0.0`

**Nguyên nhân:** `pypsrp` chưa có bản stable `1.0.0` trên PyPI (chỉ có `1.0.0b1` beta). Container bị restart loop vì cài pip thất bại.

**Fix:** Đã được sửa trong `requirements.txt` — đổi thành `pypsrp>=0.9.0`. Nếu vẫn gặp, kiểm tra file:

```powershell
Get-Content requirements.txt | Select-String "pypsrp"
# Phải hiện: pypsrp>=0.9.0
```

Sau đó restart container để cài lại:
```powershell
docker compose restart semaphore
```

---

## Lỗi chạy Task Template

### `[ERROR]: the playbook: ping_linux.yml could not be found`

**Nguyên nhân:** Field **Playbook Filename** trong Task Template thiếu prefix `playbooks/`.

**Fix:** Vào Task Template → Edit → sửa field **Playbook Filename**:

| Sai | Đúng |
|-----|------|
| `ping_linux.yml` | `playbooks/ping_linux.yml` |
| `linux_baseline` | `playbooks/linux_baseline.yml` |
| `site` | `playbooks/site.yml` |

---

### `YAML inventory has invalid structure` / `Section [linux:vars] not valid for undefined group`

**Nguyên nhân:** Semaphore parse inventory thất bại với cả YAML lẫn INI format. Thường do dùng INI format không đúng trong Static inventory.

**Fix:** Dùng **YAML format** trong ô Static Inventory của Semaphore:

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

> Username/password không cần khai báo trong inventory — Semaphore inject từ SSH Key đã chọn.

---

### `PLAY [<tên play>] skipping: no hosts matched`

**Nguyên nhân:** Inventory parse thất bại (lỗi trên) nên không có host nào → tất cả play bị skip.

**Fix:** Sửa inventory theo hướng dẫn YAML format ở trên, sau đó chạy lại task.

---

### `[WARNING]: Could not match supplied host pattern, ignoring: linux`

**Nguyên nhân:** Inventory không có group `linux` — thường do inventory parse lỗi hoặc cấu trúc YAML sai.

**Kiểm tra:**
- Inventory YAML phải có `children: linux:` đúng indentation
- Chạy lại task sau khi sửa inventory

---

## Lỗi kết nối SSH

### `Permission denied (publickey)`

**Nguyên nhân 1:** SSH Key trong Key Store chưa được thêm vào `authorized_keys` trên target host.

```bash
# Trên target host
cat ~/.ssh/authorized_keys
# Phải có dòng public key tương ứng
```

**Nguyên nhân 2:** Permissions của SSH key file quá rộng (Windows).

```powershell
$key = "$env:USERPROFILE\.ssh\ansible_lab_ed25519"
icacls $key /inheritance:r
icacls $key /remove "Everyone"
icacls $key /remove "BUILTIN\Users"
icacls $key /grant:r "${env:USERNAME}:F"
```

---

### `Authentication failed (Login with password)`

**Nguyên nhân:** Username hoặc password sai trong Key Store.

**Fix:** Key Store → chọn key → Edit → kiểm tra lại Login/Password → Save.

**Test thủ công:**
```bash
ssh username@192.168.118.128
# Nhập password để xác nhận credentials đúng
```

---

### `sudo: a terminal is required to read the password`

**Nguyên nhân:** User trên target host có sudo nhưng yêu cầu nhập password (không phải passwordless sudo).

**Fix A — Cấp passwordless sudo trên target host:**
```bash
echo "username ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/username
sudo chmod 440 /etc/sudoers.d/username
```

**Fix B — Dùng `su` thay `sudo` trong inventory:**
```yaml
ansible_become_method: su
ansible_become_password: "root_password"
```

---

## Lỗi Galaxy / Collections

### `No /tmp/semaphore/.../requirements.yml file found`

**Không phải lỗi** — Semaphore tìm `requirements.yml` ở nhiều vị trí và thông báo skip nếu không tìm thấy. Task vẫn chạy bình thường.

---

### `collections/requirements.yml has no changes. Skip galaxy install process`

**Không phải lỗi** — Collections đã được cache, Semaphore skip bước cài lại. Đây là behavior bình thường.

---

## Kiểm tra tổng quát

```powershell
# Xem log Semaphore realtime
docker compose logs -f semaphore

# Kiểm tra container health
docker compose ps

# Test API
Invoke-WebRequest http://localhost:3000/api/ping
```
