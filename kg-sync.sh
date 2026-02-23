#!/bin/bash
# =============================================================================
# Kiro-Guard — Linux Sync Script
#
# Normally called by kiro-guard.py which passes:
#   $1 = project root (absolute path)
#   $2 = resolved-paths file (absolute paths, one per line, already glob-expanded)
#
# Can also be called directly (standalone):
#   sudo bash kg-sync.sh [project-root]
# In standalone mode, walks up from cwd to find .kiro-guard and expands
# glob patterns itself using bash globstar.
# =============================================================================

set -euo pipefail

RESTRICTED_USER="kiro-runner"
GUARD_FILE=".kiro-guard"

# ── Enable globstar for ** patterns (bash 4+) ─────────────────────────────────
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

if ! command -v setfacl &>/dev/null; then
    echo "Error: 'setfacl' not installed. Run: sudo apt install acl" >&2
    exit 1
fi

echo "Project root : $PROJECT_ROOT"
echo ""

# ── Create restricted user if needed ─────────────────────────────────────────
if ! id "$RESTRICTED_USER" &>/dev/null; then
    echo "Creating restricted user: $RESTRICTED_USER"
    adduser --disabled-password --gecos "" "$RESTRICTED_USER"
else
    echo "User '$RESTRICTED_USER' already exists."
fi

# ── Reset existing ACLs for the restricted user ───────────────────────────────
echo ""
echo "Resetting previous ACLs for '$RESTRICTED_USER'..."
setfacl -R -x "u:$RESTRICTED_USER" "$PROJECT_ROOT" 2>/dev/null || true

# Grant kiro-runner read+write on the whole project root.
# Capital X = execute only on directories (traverse) and existing executables —
# not on regular source files.  Deny rules applied below override this grant
# for locked paths.
setfacl -R -m "u:$RESTRICTED_USER:rwX" "$PROJECT_ROOT"
echo "  Granted rwX recursively on project root."

# ── Build list of resolved absolute paths ─────────────────────────────────────
# If called from kiro-guard.py, $2 is a temp file with one absolute path per line.
# Otherwise, expand patterns ourselves using bash globstar.
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

        # Expand pattern relative to project root
        for match in "$PROJECT_ROOT"/$pattern; do
            if [ -e "$match" ]; then
                RESOLVED_PATHS+=("$match")
            fi
        done

        # If nothing matched, add literal path so it shows as "not found"
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
    rel="$(realpath --relative-to="$PROJECT_ROOT" "$abs_path" 2>/dev/null || echo "$abs_path")"
    if [ -e "$abs_path" ]; then
        setfacl -R -m "u:$RESTRICTED_USER:---" "$abs_path"
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
echo "  Kiro-Guard sync complete."
echo "  Locked : $LOCKED path(s)"
echo "  Skipped: $SKIPPED path(s) (not found)"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. First-time login: kiro-guard login"
echo "  2. Run Kiro:         kiro-guard run"
echo "  3. Verify lockdown:  kiro-guard test"
echo ""
echo "Inspect ACLs on any path with: getfacl <path>"
