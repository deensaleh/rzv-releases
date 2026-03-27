# ==============================================================================
#  Root Zero Vault - Windows Installer (PowerShell)
#  rootzerovault.com / github.com/deensaleh/rzv-releases
#
#  One-liner install:
#    irm https://raw.githubusercontent.com/deensaleh/rzv-releases/main/install_windows.ps1 | iex
#
#  One-liner update:
#    irm https://raw.githubusercontent.com/deensaleh/rzv-releases/main/install_windows.ps1 -OutFile "$env:TEMP\rzv.ps1"; & "$env:TEMP\rzv.ps1" -Update
#
#  What this does:
#    1. Downloads rzv CLI + rsbis-service gateway
#    2. Runs rzv init (generates keys, writes config)
#    3. Starts the gateway
#    4. Prints the console URL
# ==============================================================================

param(
    [switch]$Uninstall,
    [switch]$Update,
    [string]$Namespace = "",
    [int]$Port = 8443,
    [string]$Version = "latest"
)

$Repo       = "deensaleh/rzv-releases"
$InstallDir = "$env:LOCALAPPDATA\RootZeroVault"
$RzvHome    = "$env:USERPROFILE\.rzv"
$LogDir     = "$RzvHome\logs"
$GwDest     = "$InstallDir\rsbis-service.exe"
$RzvDest    = "$InstallDir\rzv.exe"

function Write-Gold { param($msg) Write-Host "[RZV] $msg" -ForegroundColor Yellow }
function Write-Ok   { param($msg) Write-Host " [OK] $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "[ERR] $msg" -ForegroundColor Red; exit 1 }
function Write-Dim  { param($msg) Write-Host "      $msg" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "  Root Zero Vault" -ForegroundColor Yellow
Write-Host "  rootzerovault.com" -ForegroundColor DarkGray
Write-Host ""

# -- Uninstall -----------------------------------------------------------------
if ($Uninstall) {
    Write-Gold "Uninstalling..."
    Stop-Process -Name "rsbis-service" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Uninstalled. Vault data preserved in $RzvHome"
    exit 0
}

# -- Update --------------------------------------------------------------------
if ($Update -or $env:RZV_UPDATE -eq "1") {
    Write-Gold "Updating Root Zero Vault to latest..."

    # Stop gateway if running
    $proc = Get-Process "rsbis-service" -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Gold "Stopping gateway..."
        $proc | Stop-Process -Force
        Start-Sleep 2
        Write-Ok "Gateway stopped"
    }

    $TmpGw  = [System.IO.Path]::Combine($env:TEMP, "rsbis-service-update.exe")
    $TmpRzv = [System.IO.Path]::Combine($env:TEMP, "rzv-update.exe")

    if ($Version -eq "latest") {
        $BaseUrl = "https://github.com/$Repo/releases/latest/download"
    } else {
        $BaseUrl = "https://github.com/$Repo/releases/download/$Version"
    }

    Write-Gold "Downloading gateway..."
    try {
        Invoke-WebRequest -Uri "$BaseUrl/rsbis-gateway-windows-x64.exe" -OutFile $TmpGw -UseBasicParsing
        Copy-Item $TmpGw $GwDest -Force
        Write-Ok "rsbis-service updated"
    } catch {
        Write-Fail "Gateway download failed: $_"
    }

    Write-Gold "Downloading rzv CLI..."
    try {
        Invoke-WebRequest -Uri "$BaseUrl/rzv-windows-x64.exe" -OutFile $TmpRzv -UseBasicParsing
        Copy-Item $TmpRzv $RzvDest -Force
        Write-Ok "rzv updated"
    } catch {
        Write-Gold "rzv CLI download failed (non-fatal)"
    }

    # Restart gateway
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $env:RSBIS_CONFIG = [System.IO.Path]::Combine($RzvHome, "config.yaml")
    Start-Process -FilePath $GwDest `
        -ArgumentList @("up", "--home", $RzvHome) `
        -RedirectStandardOutput ([System.IO.Path]::Combine($LogDir, "gateway.log")) `
        -NoNewWindow -PassThru | Out-Null
    Start-Sleep 2

    Write-Ok "Update complete"
    Write-Gold "Console: http://localhost:$Port/console/"
    exit 0
}

# -- Install -------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path $RzvHome    | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir     | Out-Null

Write-Gold "Install directory: $InstallDir"

if ($Version -eq "latest") {
    $BaseUrl = "https://github.com/$Repo/releases/latest/download"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/download/$Version"
}

# Download binaries
Write-Gold "Downloading gateway binary..."
try {
    Invoke-WebRequest -Uri "$BaseUrl/rsbis-gateway-windows-x64.exe" -OutFile $GwDest -UseBasicParsing
    Write-Ok "Downloaded: rsbis-service.exe"
} catch {
    Write-Fail "Download failed: $_`nBuild from source: cargo build -p rsbis-service --release"
}

Write-Gold "Downloading rzv CLI..."
try {
    Invoke-WebRequest -Uri "$BaseUrl/rzv-windows-x64.exe" -OutFile $RzvDest -UseBasicParsing
    Write-Ok "Downloaded: rzv.exe"
} catch {
    Write-Gold "rzv CLI download failed (non-fatal)"
}

# Add to PATH
$CurrentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($CurrentPath -notlike "*$InstallDir*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$InstallDir;$CurrentPath", "User")
    Write-Ok "Added to PATH"
}
$env:PATH = "$InstallDir;$env:PATH"

# -- Init ----------------------------------------------------------------------
Write-Host ""
Write-Gold "Initializing Root Zero Vault..."
$InitArgs = @("init", "--home", $RzvHome, "--listen", "0.0.0.0:$Port")
if ($Namespace) { $InitArgs += @("--namespace", $Namespace) }
& "$RzvDest" @InitArgs 2>$null
if ($LASTEXITCODE -ne 0) { Write-Gold "Init returned $LASTEXITCODE - may already be initialized" }

# -- Start gateway -------------------------------------------------------------
Write-Host ""
Write-Gold "Starting gateway..."
$env:RSBIS_CONFIG = [System.IO.Path]::Combine($RzvHome, "config.yaml")
Start-Process -FilePath $GwDest `
    -ArgumentList @("up", "--home", $RzvHome) `
    -RedirectStandardOutput ([System.IO.Path]::Combine($LogDir, "gateway.log")) `
    -NoNewWindow -PassThru | Out-Null
Start-Sleep 3

# -- Health check --------------------------------------------------------------
$healthy = $false
for ($i = 1; $i -le 10; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$Port/health" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $healthy = $true; break }
    } catch {}
    Start-Sleep 1
}

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Yellow
if ($healthy) {
    Write-Ok "Root Zero Vault is running"
} else {
    Write-Gold "Gateway starting (check logs if issues)"
}
Write-Host ""
Write-Dim "  Home:    $RzvHome"
Write-Dim "  Console: http://localhost:$Port/console/"
Write-Dim "  Logs:    $LogDir\gateway.log"
Write-Host ""
Write-Gold "  Next: open http://localhost:$Port/console/ in your browser"
Write-Host "  ================================================" -ForegroundColor Yellow
Write-Host ""
