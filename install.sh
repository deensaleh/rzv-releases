#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Root Zero Vault — Universal Installer
#  Platforms: macOS · Linux · Android (Termux)
#
#  One-line install:
#    curl -sSf https://raw.githubusercontent.com/deensaleh/rzv-releases/main/install.sh | bash
#
#  With options:
#    bash install.sh [--namespace EGYPT] [--port 8443] [--no-start]
#
#  What this does:
#    1. Detects platform (macOS / Linux / Android via Termux)
#    2. Downloads rzv + rsbis-service from GitHub releases
#    3. Runs rzv init (generates keys, writes config)
#    4. Starts the gateway
#    5. Prints the console URL
#
#  Everything stays local. No data leaves your device.
#  Genesis: cvid:blake3:1544ff7dd978d911083bd60a7a4e6ba9647996bfdefb62aa8a045ccb63158867
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

REPO="deensaleh/rzv-releases"
VERSION="${RZV_VERSION:-latest}"
RZV_HOME="${RZV_HOME:-$HOME/.rzv}"
PORT="${RZV_PORT:-8443}"
NAMESPACE="${RZV_NAMESPACE:-}"
AUTO_START="${RZV_AUTO_START:-true}"
ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-}"

# ── Colors ────────────────────────────────────────────────────────────────────
GOLD='\033[1;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'
info()    { echo -e "${GOLD}[RZV]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }
dim()     { echo -e "${DIM}$1${NC}"; }

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --namespace)  NAMESPACE="$2";     shift 2 ;;
        --port)       PORT="$2";          shift 2 ;;
        --dir)        RZV_HOME="$2";      shift 2 ;;
        --version)    VERSION="$2";       shift 2 ;;
        --no-start)   AUTO_START="false"; shift ;;
        --key)        ANTHROPIC_KEY="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --namespace NAME   Claim a namespace (e.g. EGYPT)"
            echo "  --port PORT        Gateway port (default: 8443)"
            echo "  --dir PATH         RZV home directory (default: ~/.rzv)"
            echo "  --version VER      Specific release version"
            echo "  --no-start         Install only, don't start gateway"
            echo "  --key SK-ANT-...   Set Anthropic API key for AI assistant"
            exit 0 ;;
        *) error "Unknown option: $1" ;;
    esac
done

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${GOLD}ROOT ZERO VAULT${NC}  ${DIM}Constitutional AI Governance${NC}"
echo -e "  ${DIM}rootzerovault.com  ·  github.com/${REPO}${NC}"
echo -e "  ${DIM}Genesis: cvid:blake3:1544ff7d…${NC}"
echo ""

# ── Detect platform ───────────────────────────────────────────────────────────
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
IS_TERMUX=false

# Termux detection
if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
    IS_TERMUX=true
    OS="linux"
    info "Detected: Android (Termux)"
fi

case "$ARCH" in
    x86_64|amd64)   ARCH="x86_64" ;;
    aarch64|arm64)  ARCH="aarch64" ;;
    armv7l|armv8l)  ARCH="aarch64" ;;
    *) error "Unsupported architecture: $ARCH. Build from source: cargo build --release" ;;
esac

case "$OS" in
    linux)  PLATFORM="linux-${ARCH}" ;;
    darwin) PLATFORM="macos-${ARCH}" ;;
    *)      error "Unsupported OS: $OS. On Windows use: install_windows.ps1" ;;
esac

info "Platform: $PLATFORM"

# ── Set install directory ─────────────────────────────────────────────────────
if $IS_TERMUX; then
    # Termux uses its own prefix — /usr/local/bin is correct there
    INSTALL_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
elif [[ ! -w "$(dirname "/usr/local/bin")" ]]; then
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
    info "Using $INSTALL_DIR (no write access to /usr/local/bin)"
else
    INSTALL_DIR="/usr/local/bin"
fi
mkdir -p "$INSTALL_DIR"
info "Install directory: $INSTALL_DIR"

# ── Check prerequisites ───────────────────────────────────────────────────────
info "Checking prerequisites…"
if ! command -v curl >/dev/null 2>&1; then
    if $IS_TERMUX; then
        info "Installing curl via pkg…"
        pkg install curl -y
    else
        error "curl required. Install: apt-get install curl  or  brew install curl"
    fi
fi
success "Prerequisites OK"

# ── Download release binaries ─────────────────────────────────────────────────
info "Downloading Root Zero Vault binaries…"

if [[ "$VERSION" == "latest" ]]; then
    RELEASE_URL="https://github.com/${REPO}/releases/latest/download"
else
    RELEASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
fi

download_binary() {
    local name="$1"
    local dest="$2"
    local url="${RELEASE_URL}/${name}"
    info "Downloading ${name}…"
    if curl -fsSL --progress-bar "$url" -o "$dest"; then
        chmod +x "$dest"
        success "Downloaded: $(basename "$dest")"
    else
        if command -v "$(basename "$dest")" >/dev/null 2>&1; then
            info "$(basename "$dest") already in PATH — skipping"
        else
            error "Failed to download $name\n  URL: $url\n  Build from source: cargo build -p rsbis-service --release"
        fi
    fi
}

RZV_BIN="rsbis-gateway-${PLATFORM}"
GW_BIN="rsbis-gateway-${PLATFORM}"

if [[ ! -f "$INSTALL_DIR/rzv" ]]; then
    download_binary "$RZV_BIN" "$INSTALL_DIR/rzv"
else
    success "rzv already installed"
fi

if [[ ! -f "$INSTALL_DIR/rsbis-service" ]]; then
    download_binary "$GW_BIN" "$INSTALL_DIR/rsbis-service"
else
    success "rsbis-service already installed"
fi

export PATH="$INSTALL_DIR:$PATH"

# ── Add to PATH permanently ───────────────────────────────────────────────────
if [[ "$INSTALL_DIR" != "/usr/local/bin" ]] && ! $IS_TERMUX; then
    SHELL_RC=""
    case "${SHELL:-}" in
        */zsh)  SHELL_RC="$HOME/.zshrc" ;;
        */fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
        *)      SHELL_RC="$HOME/.bashrc" ;;
    esac
    if [[ -n "$SHELL_RC" ]] && ! grep -q "$INSTALL_DIR" "$SHELL_RC" 2>/dev/null; then
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$SHELL_RC"
        info "Added $INSTALL_DIR to PATH in $SHELL_RC"
    fi
fi

# ── Run rzv init ──────────────────────────────────────────────────────────────
echo ""
info "Initializing Root Zero Vault…"
mkdir -p "$RZV_HOME"

INIT_ARGS=(
    "--home" "$RZV_HOME"
    "--listen" "127.0.0.1:${PORT}"
)
[[ -n "$NAMESPACE" ]]     && INIT_ARGS+=("--namespace" "$NAMESPACE")
[[ -n "$ANTHROPIC_KEY" ]] && INIT_ARGS+=("--anthropic-key" "$ANTHROPIC_KEY")

"$INSTALL_DIR/rzv" init "${INIT_ARGS[@]}" || true

# ── Start gateway ─────────────────────────────────────────────────────────────
if [[ "$AUTO_START" == "true" ]]; then
    echo ""
    info "Starting gateway on port ${PORT}…"

    if $IS_TERMUX; then
        # Termux: run in background, output to log
        RZV_HOME="$RZV_HOME" nohup "$INSTALL_DIR/rsbis-service" \
            --home "$RZV_HOME" --listen "127.0.0.1:${PORT}" \
            > "$RZV_HOME/gateway.log" 2>&1 &
        GW_PID=$!
        echo "$GW_PID" > "$RZV_HOME/gateway.pid"
        sleep 1
        if kill -0 "$GW_PID" 2>/dev/null; then
            success "Gateway running (PID $GW_PID)"
        else
            info "Gateway may have failed — check: cat $RZV_HOME/gateway.log"
        fi
    else
        RZV_HOME="$RZV_HOME" "$INSTALL_DIR/rzv" up --daemon \
            --bin "$INSTALL_DIR/rsbis-service" || \
        RZV_HOME="$RZV_HOME" nohup "$INSTALL_DIR/rsbis-service" \
            --home "$RZV_HOME" --listen "127.0.0.1:${PORT}" \
            > "$RZV_HOME/gateway.log" 2>&1 &
    fi
fi

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GOLD}✓ Root Zero Vault is ready${NC}"
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GOLD}Gateway  →${NC}  http://127.0.0.1:${PORT}"
echo -e "  ${GOLD}Health   →${NC}  http://127.0.0.1:${PORT}/health"
echo ""
if $IS_TERMUX; then
    echo -e "  ${GREEN}Android:${NC} Open your browser and load the console HTML file."
    echo -e "  ${DIM}Connect to: http://localhost:${PORT}${NC}"
    echo ""
    echo -e "  ${DIM}To stop:   kill \$(cat $RZV_HOME/gateway.pid)${NC}"
    echo -e "  ${DIM}Logs:      cat $RZV_HOME/gateway.log${NC}"
else
    echo -e "  ${DIM}Manage:${NC}"
    echo -e "  ${DIM}  rzv status   — check health${NC}"
    echo -e "  ${DIM}  rzv down     — stop gateway${NC}"
    echo -e "  ${DIM}  rzv export   — export proof bundle${NC}"
fi
echo ""
echo -e "  ${RED}Backup these files — loss = loss of vault access:${NC}"
echo -e "  ${DIM}  ${RZV_HOME}/store.key${NC}"
echo -e "  ${DIM}  ${RZV_HOME}/custodian.key${NC}"
echo ""
