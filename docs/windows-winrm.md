# Windows WinRM Setup for Ansible

Reference: [Ansible Windows WinRM docs](https://docs.ansible.com/ansible/latest/os_guide/windows_winrm.html)

## Overview

Ansible manages Windows hosts via **WinRM** (Windows Remote Management).
This lab uses **WinRM HTTPS on port 5986** with **NTLM** authentication and a **self-signed certificate**.

> For production: use Kerberos transport with a CA-signed certificate.

## Step 1 — Run the setup script on the Windows target

Copy `scripts/windows/Enable-WinRM-For-Ansible.ps1` to the target host and run as Administrator:

```powershell
# On the Windows target host
Set-ExecutionPolicy RemoteSigned -Scope Process
.\Enable-WinRM-For-Ansible.ps1
```

The script:
1. Enables PSRemoting
2. Creates a self-signed TLS certificate (5-year validity)
3. Creates HTTPS listener on port 5986
4. Configures NTLM authentication
5. Opens firewall ports 5985 and 5986
6. Creates `ansible_svc` local admin account

## Step 2 — Configure inventory

Copy `inventories/windows/hosts.yml.example` → `inventories/windows/hosts.yml`:

```yaml
all:
  children:
    windows:
      vars:
        ansible_connection: winrm
        ansible_winrm_scheme: https
        ansible_port: 5986
        ansible_winrm_transport: ntlm
        ansible_winrm_server_cert_validation: ignore   # lab only
      hosts:
        win-lab-01:
          ansible_host: 192.168.1.100    # your Windows host IP
          ansible_user: ansible_svc
          ansible_password: "{{ vault_win_password }}"
```

## Step 3 — Store WinRM password in Vault

```bash
# Create vault file
ansible-vault create group_vars/windows/vault.yml
```

Add:
```yaml
vault_win_password: "YourActualPassword"
```

Encrypt with a vault password stored in `secrets/vault_pass.txt` (gitignored).

## Step 4 — Test connectivity

```bash
# Ping test
ansible-playbook -i inventories/windows/hosts.yml playbooks/ping_windows.yml \
  --vault-password-file secrets/vault_pass.txt

# Gather facts
ansible-playbook -i inventories/windows/hosts.yml playbooks/windows_facts.yml \
  --vault-password-file secrets/vault_pass.txt
```

## Transports comparison

| Transport | Security | Requirements |
|-----------|----------|-------------|
| **NTLM** | Moderate | Local account or domain |
| **Kerberos** | High (domain) | Domain-joined + MIT Kerberos libs |
| **Certificate** | High | PKI infrastructure |
| **Basic** | Low (plain) | HTTPS only, not recommended |

## Troubleshooting WinRM

### Test from Windows target itself

```powershell
# Test HTTPS connectivity
Test-WSMan -ComputerName localhost -UseSSL

# List listeners
winrm enumerate winrm/config/Listener

# Check auth config
Get-WSManInstance -ResourceURI winrm/config/service/Auth
```

### Test from Linux/Ansible controller

```bash
# Manual WinRM curl test
curl -v -k \
  --ntlm --user "ansible_svc:PASSWORD" \
  https://WINDOWS_HOST:5986/wsman

# Python test (pywinrm)
python3 -c "
import winrm
s = winrm.Session('https://WINDOWS_HOST:5986/wsman',
    auth=('ansible_svc', 'PASSWORD'),
    transport='ntlm',
    server_cert_validation='ignore')
r = s.run_cmd('ipconfig')
print(r.std_out.decode())
"
```

### Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Connection refused on port 5986` | WinRM not started or firewall | Run setup script, check `winrm quickconfig` |
| `AuthenticationError: 401` | Wrong credentials or transport | Check user, password, transport setting |
| `SSL: CERTIFICATE_VERIFY_FAILED` | Self-signed cert | Set `ansible_winrm_server_cert_validation: ignore` (lab only) |
| `WinRMOperationTimeoutError` | Slow host or short timeout | Increase `operation_timeout_sec` |
| `No module named winrm` | pywinrm not installed | `pip install pywinrm pypsrp` |

## Production hardening

1. Replace self-signed cert with a CA-signed certificate
2. Switch to Kerberos transport for domain accounts
3. Set `ansible_winrm_server_cert_validation: validate`
4. Restrict WinRM access to Ansible controller IP via firewall
5. Use Just Enough Administration (JEA) instead of local admin
6. Enable WinRM HTTPS only (disable HTTP on 5985)
