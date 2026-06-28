#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configure WinRM for Ansible management (lab setup).
.DESCRIPTION
    Enables WinRM HTTPS listener on port 5986 with a self-signed certificate.
    Also enables HTTP on port 5985 for lab testing only.

    WARNING: Self-signed certificates and NTLM are suitable for LAB USE ONLY.
    For production, use a CA-signed certificate and Kerberos transport.
    See: https://docs.ansible.com/ansible/latest/os_guide/windows_winrm.html

.PARAMETER Transport
    WinRM transport to configure: NTLM (default, lab) or Kerberos (domain/prod).
.PARAMETER Force
    Skip confirmation prompt.
.EXAMPLE
    .\Enable-WinRM-For-Ansible.ps1
.EXAMPLE
    .\Enable-WinRM-For-Ansible.ps1 -Transport NTLM -Force
#>
[CmdletBinding()]
param(
    [ValidateSet('NTLM', 'Kerberos')]
    [string]$Transport = 'NTLM',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Header { Write-Host "`n=== $args ===" -ForegroundColor Cyan }
function Write-OK     { Write-Host "[OK]  $args" -ForegroundColor Green }
function Write-Warn   { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Err    { Write-Host "[ERR] $args" -ForegroundColor Red }

Write-Host @"

#################################################################
#  WinRM Ansible Setup — LAB CONFIGURATION
#
#  WARNING: Self-signed cert + NTLM is for LAB USE ONLY.
#  Do NOT use this configuration on production hosts.
#################################################################

"@ -ForegroundColor Yellow

if (-not $Force) {
    $confirm = Read-Host "Continue? [y/N]"
    if ($confirm -notin 'y', 'Y', 'yes', 'Yes') {
        Write-Host "Aborted." -ForegroundColor Red
        exit 0
    }
}

# ── 1. Enable WinRM service ──────────────────────────────────────────────────
Write-Header "WinRM Service"
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Write-OK "PSRemoting enabled"
} catch {
    Write-Warn "Enable-PSRemoting: $($_.Exception.Message)"
}

Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM
Write-OK "WinRM service started (Automatic)"

# ── 2. Self-signed certificate for HTTPS ────────────────────────────────────
Write-Header "SSL Certificate"
$hostname = $env:COMPUTERNAME
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq "CN=$hostname" } | Select-Object -First 1

if (-not $cert) {
    $cert = New-SelfSignedCertificate `
        -DnsName $hostname `
        -CertStoreLocation 'Cert:\LocalMachine\My' `
        -NotAfter (Get-Date).AddYears(5)
    Write-OK "Self-signed certificate created: $($cert.Thumbprint)"
} else {
    Write-Warn "Certificate already exists: $($cert.Thumbprint)"
}

# ── 3. HTTPS listener on 5986 ───────────────────────────────────────────────
Write-Header "WinRM HTTPS Listener (5986)"
$httpsListener = Get-WSManInstance -ResourceURI 'winrm/config/Listener' -SelectorSet @{Address='*'; Transport='HTTPS'} -ErrorAction SilentlyContinue

if ($httpsListener) {
    Write-Warn "HTTPS listener already exists — updating certificate"
    Set-WSManInstance -ResourceURI 'winrm/config/Listener' `
        -SelectorSet @{Address='*'; Transport='HTTPS'} `
        -ValueSet @{CertificateThumbprint=$cert.Thumbprint}
} else {
    New-WSManInstance -ResourceURI 'winrm/config/Listener' `
        -SelectorSet @{Address='*'; Transport='HTTPS'} `
        -ValueSet @{Enabled='True'; CertificateThumbprint=$cert.Thumbprint} | Out-Null
    Write-OK "HTTPS listener created on port 5986"
}

# ── 4. HTTP listener on 5985 (lab only) ─────────────────────────────────────
Write-Header "WinRM HTTP Listener (5985 — Lab Only)"
Write-Warn "HTTP listener is insecure — use HTTPS in production"
$httpListener = Get-WSManInstance -ResourceURI 'winrm/config/Listener' -SelectorSet @{Address='*'; Transport='HTTP'} -ErrorAction SilentlyContinue
if (-not $httpListener) {
    New-WSManInstance -ResourceURI 'winrm/config/Listener' `
        -SelectorSet @{Address='*'; Transport='HTTP'} `
        -ValueSet @{Enabled='True'} | Out-Null
    Write-OK "HTTP listener created on port 5985"
} else {
    Write-Warn "HTTP listener already exists"
}

# ── 5. WinRM authentication ─────────────────────────────────────────────────
Write-Header "WinRM Authentication ($Transport)"
$useNtlm     = if ($Transport -eq 'NTLM')     { 'true' } else { 'false' }
$useKerberos = if ($Transport -eq 'Kerberos') { 'true' } else { 'false' }
Set-WSManInstance -ResourceURI 'winrm/config/service/Auth' -ValueSet @{
    Basic       = 'false'
    NTLM        = $useNtlm
    Kerberos    = $useKerberos
    Certificate = 'false'
}
Set-WSManInstance -ResourceURI 'winrm/config/service' -ValueSet @{
    AllowUnencrypted = 'false'
}
Write-OK "Authentication set: $Transport only, encryption required"

# ── 6. Firewall rules ────────────────────────────────────────────────────────
Write-Header "Windows Firewall"
$rules = @(
    @{ Name='WinRM-HTTPS-5986'; Port=5986; Description='WinRM HTTPS for Ansible' }
    @{ Name='WinRM-HTTP-5985';  Port=5985; Description='WinRM HTTP for Ansible (lab only)' }
)
foreach ($r in $rules) {
    $existing = Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Protocol TCP `
            -LocalPort $r.Port -Action Allow -Profile Any -Description $r.Description | Out-Null
        Write-OK "Firewall rule created: $($r.Name) (port $($r.Port))"
    } else {
        Write-Warn "Firewall rule already exists: $($r.Name)"
    }
}

# ── 7. Create ansible service account ───────────────────────────────────────
Write-Header "Ansible Service Account"
$ansibleUser = 'ansible_svc'
$existingUser = Get-LocalUser -Name $ansibleUser -ErrorAction SilentlyContinue

if (-not $existingUser) {
    $securePass = Read-Host "Set password for '$ansibleUser'" -AsSecureString
    New-LocalUser -Name $ansibleUser -Password $securePass `
        -FullName 'Ansible Service Account' `
        -Description 'Used by Ansible for WinRM management' `
        -PasswordNeverExpires
    Add-LocalGroupMember -Group 'Administrators' -Member $ansibleUser
    Write-OK "User '$ansibleUser' created and added to Administrators"
} else {
    Write-Warn "User '$ansibleUser' already exists"
}

# ── 8. Verification ──────────────────────────────────────────────────────────
Write-Header "Verification"
winrm enumerate winrm/config/Listener
Write-OK "WinRM listeners active"

Write-Host @"

#################################################################
#  Setup complete!
#
#  Ansible inventory snippet (inventories/windows/hosts.yml):
#
#    win-lab-01:
#      ansible_host: $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } | Select-Object -First 1).IPAddress)
#      ansible_user: $ansibleUser
#      ansible_password: "{{ vault_win_password }}"
#      ansible_connection: winrm
#      ansible_winrm_scheme: https
#      ansible_port: 5986
#      ansible_winrm_transport: $($Transport.ToLower())
#      ansible_winrm_server_cert_validation: ignore
#
#  Test from Ansible controller:
#    ansible -i inventories/windows/hosts.yml windows -m ansible.windows.win_ping
#################################################################
"@ -ForegroundColor Cyan
