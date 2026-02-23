#!/bin/bash
# =============================================================================
# Kiro-Guard — macOS Sync Script
#
# Normally called by kiro-guard.py which passes:
#   $1 = project root (absolute path)
#   $2 = resolved-paths file (absolute paths, one per line, already glob-expanded)
#
# Can also be called directly (standalone):
#   sudo bash kg-sync-mac.sh [project-root]
# In standalone mode, walks up from cwd to find .kiro-guard and expands
# glob patterns itself using bash globstar.
#
# Uses macOS native ACLs (chmod +a) — no third-party tools required.
# =============================================================================

set -euo pipefail

RESTRICTED_USER="kiro-runner"
GUARD_FILE=".kiro-guard"

# Full deny rights for both files and directories
DENY_RIGHTS="read,write,execute,delete,list,search,add_file,add_subdirectory,readattr,writeattr,readextattr,writeextattr,readsecurity"

# ── Enable globstar for ** patterns (bash 4+ / homebrew bash) ─────────────────
shopt -s globstar nullglob 2>/dev/null || true

# ── Resolve project root ───────────────────────────────────────────────────────
if [ -n "${1-}" ]; then
    PROJECT_ROOT="$1"
else
    PROJECT_ROOT=""
    dir="$(pwd)"
    while true; do
        if [ -f "$dir/$GUARD_FILE" ]; then
            PROJECT_ROOT="$dir"
            break
        fi
        parent="$(dirname "$dir")"
        if [ "$parent" = "$dir" ]; then
            echo "Error: '$GUARD_FILE' not found in '$(pwd)' or any parent directory." >&2
            exit 1
        fi
        dir="$parent"
    done
fi

# ── Preflight checks ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)." >&2
    exit 1
fi

echo "Project root : $PROJECT_ROOT"
echo ""

# ── Create restricted user if needed ─────────────────────────────────────────
if ! id "$RESTRICTED_USER" &>/dev/null; then
    echo "Creating restricted user: $RESTRICTED_USER"

    # Find the next available UID above 500 (macOS user range)
    MAX_UID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
    NEW_UID=$((MAX_UID + 1))
    NEW_HOME="/var/kiro-runner"

    dscl . create /Users/$RESTRICTED_USER
    dscl . create /Users/$RESTRICTED_USER UserShell /usr/bin/false
    dscl . create /Users/$RESTRICTED_USER RealName "Kiro Runner"
    dscl . create /Users/$RESTRICTED_USER UniqueID "$NEW_UID"
    dscl . create /Users/$RESTRICTED_USER PrimaryGroupID 20
    dscl . create /Users/$RESTRICTED_USER NFSHomeDirectory "$NEW_HOME"

    mkdir -p "$NEW_HOME"
    chown "$RESTRICTED_USER" "$NEW_HOME"
    echo "  Created user '$RESTRICTED_USER' (UID $NEW_UID, home $NEW_HOME)"
else
    echo "User '$RESTRICTED_USER' already exists."
fi

# ── Reset existing deny ACLs for the restricted user on project root ──────────
echo ""
echo "Resetting previous deny ACLs for '$RESTRICTED_USER'..."

# Remove any existing deny entries for kiro-runner recursively
find "$PROJECT_ROOT" -exec chmod -a "$RESTRICTED_USER deny $DENY_RIGHTS" {} \; 2>/dev/null || true
echo "  Cleared existing deny rules on project root."

# ── Build list of resolved absolute paths ─────────────────────────────────────
RESOLVED_PATHS=()

if [ -n "${2-}" ] && [ -f "$2" ]; then
    # --- Mode A: use pre-resolved list from kiro-guard.py --------------------
    echo ""
    echo "Using pre-resolved paths from kiro-guard.py..."
    while IFS= read -r abs_path || [ -n "$abs_path" ]; do
        [[ -z "$abs_path" ]] && continue
        RESOLVED_PATHS+=("$abs_path")
    done < "$2"
else
    # --- Mode B: standalone — read .kiro-guard and expand globs ourselves ----
    GUARD_PATH="$PROJECT_ROOT/$GUARD_FILE"
    echo ""
    echo "Expanding patterns from '$GUARD_FILE' (standalone mode)..."
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        pattern="$(echo "$line" | xargs)"
        [[ -z "$pattern" ]] && continue

        for match in "$PROJECT_ROOT"/$pattern; do
            if [ -e "$match" ]; then
                RESOLVED_PATHS+=("$match")
            fi
        done

        if [ ${#RESOLVED_PATHS[@]} -eq 0 ] || [ ! -e "${RESOLVED_PATHS[-1]}" ]; then
            RESOLVED_PATHS+=("$PROJECT_ROOT/$pattern")
        fi
    done < "$GUARD_PATH"
fi

# ── Apply deny rules ──────────────────────────────────────────────────────────
echo ""
echo "Applying deny rules..."
LOCKED=0
SKIPPED=0

for abs_path in "${RESOLVED_PATHS[@]}"; do
    rel="$(python3 -c "import os; print(os.path.relpath('$abs_path', '$PROJECT_ROOT'))" 2>/dev/null || echo "$abs_path")"
    if [ -e "$abs_path" ]; then
        # Apply deny ACL recursively
        chmod -R +a "$RESTRICTED_USER deny $DENY_RIGHTS" "$abs_path"
        echo "  LOCKED : $rel"
        LOCKED=$((LOCKED + 1))
    else
        echo "  SKIPPED: $rel (not found)"
        SKIPPED=$((SKIPPED + 1))
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Kiro-Guard sync complete (macOS)."
echo "  Locked : $LOCKED path(s)"
echo "  Skipped: $SKIPPED path(s) (not found)"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. First-time login: kiro-guard login"
echo "  2. Run Kiro:         kiro-guard run"
echo "  3. Verify lockdown:  kiro-guard test"
echo ""
echo "Inspect ACLs on any path with: ls -le <path>"
