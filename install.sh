#!/bin/bash
# =============================================================================
# Kiro-Guard — Linux Installer
# Installs kiro-guard.py + kg-sync.sh to /usr/local/bin so they are on PATH.
# Usage: sudo bash install.sh
# =============================================================================

set -euo pipefail

INSTALL_DIR="/usr/local/lib/kiro-guard"
BIN_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Error: Run this script as root: sudo bash install.sh" >&2
    exit 1
fi

echo "Installing Kiro-Guard..."
echo "  Source  : $SCRIPT_DIR"
echo "  Library : $INSTALL_DIR"
echo "  Binary  : $BIN_DIR/kiro-guard"
echo ""

# Copy library files
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/kiro-guard.py" "$INSTALL_DIR/kiro-guard.py"
cp "$SCRIPT_DIR/kg-sync.sh"    "$INSTALL_DIR/kg-sync.sh"
chmod +x "$INSTALL_DIR/kg-sync.sh"

# Create wrapper on PATH
cat > "$BIN_DIR/kiro-guard" << 'EOF'
#!/bin/bash
exec python3 /usr/local/lib/kiro-guard/kiro-guard.py "$@"
EOF
chmod +x "$BIN_DIR/kiro-guard"

echo "✔  Done! You can now run 'kiro-guard' from anywhere."
echo ""
echo "Try it:"
echo "  kiro-guard sync       (from inside any project with a .kiro-guard file)"
echo "  kiro-guard login      (first-time auth as kiro-runner)"
echo "  kiro-guard run        (open kiro-cli interactive session)"
echo "  kiro-guard ask \"your question\""
