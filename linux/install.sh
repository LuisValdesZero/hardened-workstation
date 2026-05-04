#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  DNSCrypt-Proxy Installation"
echo "============================================"
echo ""

# Configuration
VERSION="2.1.15"
ARCHIVE_NAME="dnscrypt-proxy-linux_x86_64-${VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/${VERSION}/${ARCHIVE_NAME}"
INSTALL_DIR="$HOME/applications/dnscrypt-proxy"
CONFIG_SOURCE="$(dirname "$(readlink -f "$0")")/../common/dnscrypt-proxy.toml"

# Check if already installed
if [[ -f "$INSTALL_DIR/dnscrypt-proxy" ]]; then
    echo "[*] DNSCrypt-Proxy already installed at $INSTALL_DIR"
    echo "[*] Skipping download. To re-install, remove the directory first."
    echo ""
else
    # Create install directory
    mkdir -p "$INSTALL_DIR"

    echo "[*] Downloading DNSCrypt-Proxy ${VERSION}..."
    echo "[*] URL: $DOWNLOAD_URL"

    if command -v curl &>/dev/null; then
        curl -fsSL "$DOWNLOAD_URL" -o "/tmp/$ARCHIVE_NAME"
    elif command -v wget &>/dev/null; then
        wget -q "$DOWNLOAD_URL" -O "/tmp/$ARCHIVE_NAME"
    else
        echo "[!] Error: curl or wget is required to download DNSCrypt-Proxy"
        exit 1
    fi

    echo "[+] Download complete. Extracting..."
    tar -xzf "/tmp/$ARCHIVE_NAME" -C "$INSTALL_DIR" --strip-components=1
    rm -f "/tmp/$ARCHIVE_NAME"

    echo "[+] Binary installed to $INSTALL_DIR"
fi

# Copy config if not exists
if [[ -f "$INSTALL_DIR/dnscrypt-proxy.toml" ]]; then
    echo "[*] Config already exists, skipping copy"
else
    if [[ -f "$CONFIG_SOURCE" ]]; then
        cp "$CONFIG_SOURCE" "$INSTALL_DIR/dnscrypt-proxy.toml"
        echo "[+] Config copied to $INSTALL_DIR/dnscrypt-proxy.toml"
    else
        echo "[!] Warning: Config source not found at $CONFIG_SOURCE"
    fi
fi

# Make binary executable
chmod +x "$INSTALL_DIR/dnscrypt-proxy" 2>/dev/null || true

echo ""
echo "[+] Installation complete!"
echo ""
echo "To start DNSCrypt-Proxy:"
echo "  cd $INSTALL_DIR"
echo "  ./dnscrypt-proxy -config dnscrypt-proxy.toml"
echo ""
echo "To install as a systemd service (run as root):"
echo "  sudo $INSTALL_DIR/dnscrypt-proxy -config dnscrypt-proxy.toml -service install"
echo "  sudo systemctl enable dnscrypt-proxy"
echo "  sudo systemctl start dnscrypt-proxy"
echo ""
echo "Done."