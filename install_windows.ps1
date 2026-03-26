# ═══════════════════════════════════════════════════════════════════════════════
#  Root Zero Vault — Windows Installer (PowerShell)
#  rootzerovault.com · github.com/deensaleh/rzv-releases
#
#  Run (as Administrator):
#    powershell -ExecutionPolicy Bypass -File install_windows.ps1
#
#  One-liner install (PowerShell):
#    irm https://raw.githubusercontent.com/deensaleh/rzv-releases/main/install_windows.ps1 | iex
# ═══════════════════════════════════════════════════════════════════════════════

param(
    [switch]$Uninstall,
    [string]$Namespace = "",
    [int]$Port = 8443,
    [string]$Version = "latest"
)

$Repo       = "deensaleh/rzv-releases"
$InstallDir = "$env:LOCALAPPDATA\RootZeroVault"
$RzvHome    = "$env:USERPROFILE\.rzv"
$LogDir     = "$RzvHome\logs"

function Write-Gold { param($msg) Write-Host "[RZV] $msg" -ForegroundColor Yellow }
function Write-Ok   { param($msg) Write-Host " [OK] $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "[ERR] $msg" -ForegroundColor Red; exit 1 }
function Write-Dim  { param($msg) Write-Host "      $msg" -ForegroundColor DarkGray }

# ── Banner ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ROOT ZERO VAULT  Constitutional AI Governance" -ForegroundColor Yellow
Write-Dim  "  rootzerovault.com · github.com/$Repo"
Write-Dim  "  Genesis: cvid:blake3:1544ff7d..."
Write-Host ""

# ── Uninstall ─────────────────────────────────────────────────────────────────
if ($Uninstall) {
    Write-Gold "Uninstalling..."
    Stop-Process -Name "rsbis-service" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Uninstalled. Vault data preserved in $RzvHome"
    exit 0
}

# ── Download binaries ─────────────────────────────────────────────────────────
Write-Gold "Detecting platform..."
$Arch = if ([System.Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }
Write-Ok "Platform: windows-$Arch"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path $RzvHome | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if ($Version -eq "latest") {
    $BaseUrl = "https://github.com/$Repo/releases/latest/download"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/download/$Version"
}

Write-Gold "Downloading Root Zero Vault binaries..."

$BinName = "rsbis-gateway-windows-x64.exe"
$GwDest  = "$InstallDir\rsbis-service.exe"
$RzvDest = "$InstallDir\rzv.exe"

try {
    Write-Gold "Downloading $BinName..."
    Invoke-WebRequest -Uri "$BaseUrl/$BinName" -OutFile $GwDest -UseBasicParsing
    Copy-Item $GwDest $RzvDest -Force
    Write-Ok "Downloaded to $InstallDir"
} catch {
    Write-Fail "Download failed: $_`nBuild from source: cargo build -p rsbis-service --release --target x86_64-pc-windows-msvc"
}

# ── Add to PATH ───────────────────────────────────────────────────────────────
$CurrentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($CurrentPath -notlike "*$InstallDir*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$InstallDir;$CurrentPath", "User")
    Write-Ok "Added $InstallDir to PATH"
}
$env:PATH = "$InstallDir;$env:PATH"

# ── Init ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Gold "Initializing Root Zero Vault..."
$InitArgs = @("init", "--home", $RzvHome, "--listen", "127.0.0.1:$Port")
if ($Namespace) { $InitArgs += @("--namespace", $Namespace) }
& "$RzvDest" @InitArgs 2>$null
if ($LASTEXITCODE -ne 0) { Write-Gold "Init returned $LASTEXITCODE — may already be initialized" }

# ── Start gateway ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Gold "Starting gateway on port $Port..."
$GwArgs = @("--home", $RzvHome, "--listen", "127.0.0.1:$Port")
Start-Process -FilePath $GwDest -ArgumentList $GwArgs `
    -RedirectStandardOutput "$LogDir\gateway.log" `
    -RedirectStandardError  "$LogDir\gateway-err.log" `
    -WindowStyle Hidden -PassThru | Out-Null

Start-Sleep 2
try {
    $health = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 3
    Write-Ok "Gateway healthy"
} catch {
    Write-Gold "Gateway starting — check logs at $LogDir\gateway.log"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  Root Zero Vault is ready" -ForegroundColor Yellow
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Gateway  ->  http://127.0.0.1:$Port" -ForegroundColor Yellow
Write-Host "  Health   ->  http://127.0.0.1:$Port/health" -ForegroundColor Yellow
Write-Host ""
Write-Dim  "  Backup these files:"
Write-Dim  "    $RzvHome\store.key"
Write-Dim  "    $RzvHome\custodian.key"
Write-Host ""
