#!/bin/bash
# =============================================================================
# Kiro-Guard — macOS Installer
# Installs kiro-guard.py + kg-sync-mac.sh to /usr/local/lib/kiro-guard and
# creates a /usr/local/bin/kiro-guard wrapper.
# Locates kiro-cli, grants kiro-runner access to it, and copies companion
# binaries into kiro-runner's home.
# Usage: sudo bash install-mac.sh
# =============================================================================

set -eu

INSTALL_DIR="/usr/local/lib/kiro-guard"
BIN_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESTRICTED_USER="kiro-runner"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Run this script as root: sudo bash install-mac.sh" >&2
    exit 1
fi

echo "Installing Kiro-Guard..."
echo "  Source  : $SCRIPT_DIR"
echo "  Library : $INSTALL_DIR"
echo "  Binary  : $BIN_DIR/kiro-guard"
echo ""

# ── Install library files ─────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/kiro-guard.py"   "$INSTALL_DIR/"
cp "$SCRIPT_DIR/kg-sync-mac.sh"  "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/kg-sync-mac.sh"

# ── Install global wrapper ────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/kiro-guard" << 'EOF'
#!/bin/bash
exec python3 /usr/local/lib/kiro-guard/kiro-guard.py "$@"
EOF
chmod +x "$BIN_DIR/kiro-guard"

# ── Locate calling user's home (sudo strips $HOME) ────────────────────────────
SUDO_USER_HOME=""
if [ -n "${SUDO_USER:-}" ]; then
    SUDO_USER_HOME="$(dscl . -read /Users/"$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    # Fallback
    [ -z "$SUDO_USER_HOME" ] && SUDO_USER_HOME="/Users/$SUDO_USER"
fi

# ── Locate Kiro binaries ──────────────────────────────────────────────────────
echo "Locating Kiro binaries..."

for bin_name in kiro-cli kiro; do
    found=""
    for search_path in \
        "$BIN_DIR/$bin_name" \
        "/usr/bin/$bin_name" \
        "${SUDO_USER_HOME:+$SUDO_USER_HOME/.local/bin/$bin_name}" \
        "${SUDO_USER_HOME:+$SUDO_USER_HOME/Library/Application Support/kiro/bin/$bin_name}"; do
        [ -z "$search_path" ] && continue
        if [ -x "$search_path" ] && [ "$search_path" != "$BIN_DIR/$bin_name" ]; then
            found="$search_path"
            break
        fi
    done

    if [ -n "$found" ]; then
        # Grant kiro-runner read+execute on the binary
        if chmod +a "$RESTRICTED_USER allow read,execute" "$found" 2>/dev/null; then
            echo "  Granted rx: $found"
        else
            echo "  Warning: could not set ACL on $found (ACLs may not be supported)"
        fi

        # Grant kiro-runner traverse (--x only) on every parent directory
        dir="$(dirname "$found")"
        while [ "$dir" != "/" ]; do
            chmod +a "$RESTRICTED_USER allow execute,search" "$dir" 2>/dev/null || true
            echo "  Granted search: $dir"
            dir="$(dirname "$dir")"
        done

        # Symlink into BIN_DIR
        rm -f "$BIN_DIR/$bin_name"
        ln -s "$found" "$BIN_DIR/$bin_name"
        echo "  Symlinked: $found → $BIN_DIR/$bin_name"
    elif [ -x "$BIN_DIR/$bin_name" ]; then
        echo "  Already in $BIN_DIR: $bin_name"
    else
        echo "  Not found: $bin_name (install Kiro first, then re-run this script)"
    fi
done

# ── Provision kiro-runner's home with companion binaries ──────────────────────
# kiro-cli looks for kiro-cli-* companions in the running user's ~/.local/bin/
KIRO_RUNNER_HOME="$(dscl . -read /Users/$RESTRICTED_USER NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[ -z "$KIRO_RUNNER_HOME" ] && KIRO_RUNNER_HOME="/var/kiro-runner"
KIRO_RUNNER_BIN="$KIRO_RUNNER_HOME/.local/bin"

if [ -d "$KIRO_RUNNER_HOME" ]; then
    echo ""
    echo "Provisioning $RESTRICTED_USER home with Kiro companion binaries..."
    mkdir -p "$KIRO_RUNNER_BIN"
    chown "$RESTRICTED_USER" "$KIRO_RUNNER_HOME/.local" "$KIRO_RUNNER_BIN" 2>/dev/null || true

    companion_found=0
    if [ -n "$SUDO_USER_HOME" ]; then
        for companion in "$SUDO_USER_HOME/.local/bin/kiro-cli-"*; do
            [ -x "$companion" ] || continue
            dest="$KIRO_RUNNER_BIN/$(basename "$companion")"
            cp "$companion" "$dest"
            chown "$RESTRICTED_USER" "$dest"
            chmod 755 "$dest"
            echo "  Copied companion: $(basename "$companion") → $KIRO_RUNNER_BIN/"
            companion_found=1
        done
    fi

    if [ "$companion_found" -eq 0 ]; then
        echo "  No companion binaries found (expected kiro-cli-* in $SUDO_USER_HOME/.local/bin/)"
    fi
else
    echo "  Warning: home directory '$KIRO_RUNNER_HOME' not found for '$RESTRICTED_USER'"
    echo "  Run 'sudo bash kg-sync-mac.sh' first to create the user."
fi

echo ""
echo "✔  Done! You can now run 'kiro-guard' from anywhere."
echo ""
echo "Try it:"
echo "  kiro-guard sync        (from inside any project with a .kiro-guard file)"
echo "  kiro-guard login       (first-time auth as kiro-runner)"
echo "  kiro-guard run         (open kiro-cli interactive session)"
echo "  kiro-guard ask \"your question\""
