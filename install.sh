#!/bin/bash
# =============================================================================
# Kiro-Guard — Linux Installer
# Installs kiro-guard.py + kg-sync.sh to /usr/local/lib/kiro-guard and
# creates a /usr/local/bin/kiro-guard wrapper.
# Also symlinks kiro-cli (and kiro) into /usr/local/bin/ so the restricted
# user (kiro-runner) can execute them without needing access to the
# installing user's home directory.
# Usage: sudo bash install.sh
# =============================================================================

set -eu

INSTALL_DIR="/usr/local/lib/kiro-guard"
BIN_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Run this script as root: sudo bash install.sh" >&2
    exit 1
fi

echo "Installing Kiro-Guard..."
echo "  Source  : $SCRIPT_DIR"
echo "  Library : $INSTALL_DIR"
echo "  Binary  : $BIN_DIR/kiro-guard"
echo ""

# ── Copy library files ────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/kiro-guard.py" "$INSTALL_DIR/kiro-guard.py"
cp "$SCRIPT_DIR/kg-sync.sh"    "$INSTALL_DIR/kg-sync.sh"
chmod +x "$INSTALL_DIR/kg-sync.sh"

# ── Create kiro-guard wrapper on PATH ─────────────────────────────────────────
cat > "$BIN_DIR/kiro-guard" << 'EOF'
#!/bin/sh
exec python3 /usr/local/lib/kiro-guard/kiro-guard.py "$@"
EOF
chmod +x "$BIN_DIR/kiro-guard"

# ── Symlink kiro-cli & kiro into /usr/local/bin so kiro-runner can reach them ─
# The binaries are often installed in the calling user's ~/.local/bin which is
# not accessible to kiro-runner.  A system-wide symlink fixes that.
echo "Locating Kiro binaries..."
SUDO_USER_HOME=""
if [ -n "${SUDO_USER:-}" ]; then
    SUDO_USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi

for bin_name in kiro-cli kiro; do
    # Search common locations: system PATH first, then the invoking user's home
    found=""
    for search_path in \
        "$BIN_DIR/$bin_name" \
        "/usr/bin/$bin_name" \
        "${SUDO_USER_HOME:+$SUDO_USER_HOME/.local/bin/$bin_name}" \
        "${SUDO_USER_HOME:+$SUDO_USER_HOME/.kiro/bin/$bin_name}"; do
        [ -z "$search_path" ] && continue
        if [ -x "$search_path" ] && [ "$search_path" != "$BIN_DIR/$bin_name" ]; then
            found="$search_path"
            break
        fi
    done

    if [ -n "$found" ]; then
        rm -f "$BIN_DIR/$bin_name"          # remove old symlink or stale copy first
        cp "$found" "$BIN_DIR/$bin_name"
        chmod a+rx "$BIN_DIR/$bin_name"
        echo "  Copied : $found → $BIN_DIR/$bin_name"
    elif [ -x "$BIN_DIR/$bin_name" ]; then
        echo "  Already in $BIN_DIR: $bin_name"
    else
        echo "  Not found: $bin_name (install Kiro first, then re-run this script)"
    fi
done

echo ""
echo "✔  Done! You can now run 'kiro-guard' from anywhere."
echo ""
echo "Try it:"
echo "  kiro-guard sync        (from inside any project with a .kiro-guard file)"
echo "  kiro-guard login       (first-time auth as kiro-runner)"
echo "  kiro-guard run         (open kiro-cli interactive session)"
echo "  kiro-guard ask \"your question\""
