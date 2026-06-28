#Requires -Version 5.1
<#
.SYNOPSIS
    Generate local secret files and .env from .env.example.
.DESCRIPTION
    Safe to re-run: only creates missing files, never overwrites existing secrets.
.EXAMPLE
    .\scripts\generate-secrets.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$SecretsDir = Join-Path $RepoRoot 'secrets'
$EnvFile    = Join-Path $RepoRoot '.env'
$EnvExample = Join-Path $RepoRoot '.env.example'

function Write-Info  { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }

function New-RandomBase64 {
    param([int]$Count = 32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $randomBytes = New-Object byte[] $Count
    $rng.GetBytes($randomBytes)
    return [Convert]::ToBase64String($randomBytes)
}

function New-SecretFile {
    param(
        [string]$FilePath,
        [string]$Label,
        [int]$ByteCount = 32
    )
    if (Test-Path $FilePath) {
        Write-Warn "$Label already exists - skipping (delete manually to regenerate)"
    } else {
        $secret = New-RandomBase64 -Count $ByteCount
        # Use WriteAllText with explicit no-BOM UTF-8; PS 5.1's Set-Content -Encoding UTF8
        # silently prepends a BOM which breaks Semaphore's base64 validation.
        $noBomUtf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($FilePath, $secret, $noBomUtf8)
        Write-Info "$Label generated -> $FilePath"
    }
}

Write-Host ""
Write-Host "=== Ansible-dev secret generator ===" -ForegroundColor Cyan
Write-Host ""

# Create secrets directory
if (-not (Test-Path $SecretsDir)) {
    New-Item -ItemType Directory -Path $SecretsDir | Out-Null
}
Write-Info "Secrets directory: $SecretsDir"

# Generate secret files
New-SecretFile -FilePath "$SecretsDir\postgres_password.txt"      -Label "PostgreSQL password"
New-SecretFile -FilePath "$SecretsDir\access_key_encryption.txt"  -Label "Semaphore access key encryption" -ByteCount 32
New-SecretFile -FilePath "$SecretsDir\cookie_hash.txt"            -Label "Semaphore cookie hash"           -ByteCount 32
New-SecretFile -FilePath "$SecretsDir\cookie_encryption.txt"      -Label "Semaphore cookie encryption"     -ByteCount 32

# Admin password - shorter, URL-safe
$adminFile = "$SecretsDir\admin_password.txt"
if (Test-Path $adminFile) {
    Write-Warn "Admin password already exists - skipping"
} else {
    $adminPass = (New-RandomBase64 -Count 15) -replace '[/+=]', ''
    $adminPass = $adminPass.Substring(0, [Math]::Min(20, $adminPass.Length))
    $noBomUtf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($adminFile, $adminPass, $noBomUtf8)
    Write-Info "Admin password generated -> $adminFile"
    Write-Host "  Admin password: $adminPass" -ForegroundColor Yellow
}

# Copy .env.example → .env
if (Test-Path $EnvFile) {
    Write-Warn ".env already exists - skipping (edit manually)"
} else {
    Copy-Item -Path $EnvExample -Destination $EnvFile
    Write-Info ".env created from .env.example"
}

$adminPass = Get-Content $adminFile -Raw

Write-Host ""
Write-Info "All secrets ready. Next steps:"
Write-Host "  1. Edit .env if needed (PUBLIC_HOSTNAME, TZ, etc.)"
Write-Host "  2. docker compose --profile linux-target up -d"
Write-Host "  3. Open http://localhost:3000"
Write-Host "  Admin user: admin"
Write-Host "  Admin pass: $adminPass" -ForegroundColor Yellow
Write-Host ""
