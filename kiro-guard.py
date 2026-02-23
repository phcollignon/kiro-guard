#!/usr/bin/env python3
"""
kiro-guard.py — Cross-platform launcher for Kiro with access control.

Can be installed globally on PATH. Automatically walks up the directory tree
to find the nearest .kiro-guard file (like git finds .git).
Supports * and ** glob patterns in .kiro-guard.

Usage:
    kiro-guard sync            # Sync .kiro-guard rules to the OS
    kiro-guard run "prompt"    # Run Kiro as the restricted user
    kiro-guard login           # Perform first-time Kiro login as restricted user
    kiro-guard status          # Show current ACL status for guarded paths
    kiro-guard test            # Verify restricted user cannot read guarded paths

Requires:
    Linux : setfacl / acl package (sudo apt install acl)
    Windows: icacls (built-in), run as Administrator for sync
"""

import glob
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# ── Configuration ──────────────────────────────────────────────────────────────
RESTRICTED_USER = "kiro-runner"
GUARD_FILENAME = ".kiro-guard"
OS = platform.system()  # "Linux" | "Windows" | "Darwin"

# Directory where this script lives (used to find kg-sync.sh / kg-sync.bat)
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))


# ── Auto-discovery ─────────────────────────────────────────────────────────────

def find_guard_root() -> str:
    """
    Walk up from cwd until we find a directory containing .kiro-guard.
    Returns the absolute path to that directory, or exits with an error.
    Similar to how git finds .git.
    """
    current = Path(os.getcwd()).resolve()
    while True:
        if (current / GUARD_FILENAME).is_file():
            return str(current)
        parent = current.parent
        if parent == current:
            print(
                f"Error: '{GUARD_FILENAME}' not found in '{os.getcwd()}' "
                "or any parent directory."
            )
            print("Create one in your project root and list the paths to protect.")
            sys.exit(1)
        current = parent


# ── Helpers ────────────────────────────────────────────────────────────────────

def read_raw_patterns(guard_root: str) -> list[str]:
    """Return the raw pattern lines from .kiro-guard (no expansion)."""
    guard_file = os.path.join(guard_root, GUARD_FILENAME)
    patterns = []
    with open(guard_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            patterns.append(line)
    return patterns


def expand_patterns(guard_root: str, patterns: list[str]) -> list[str]:
    """
    Expand glob patterns relative to guard_root.
    Supports * (single-level) and ** (recursive).
    Returns a sorted, deduplicated list of absolute paths that actually exist.
    """
    resolved: set[str] = set()
    root = Path(guard_root)

    for pattern in patterns:
        # Use pathlib glob (supports ** recursion)
        matches = list(root.glob(pattern))
        if matches:
            for match in matches:
                resolved.add(str(match.resolve()))
        else:
            # Pattern matched nothing — keep it so we can report it as "not found"
            resolved.add(str((root / pattern).resolve()))

    return sorted(resolved)


def run(cmd, **kwargs) -> int:
    """Run a command and return its exit code."""
    display = cmd if isinstance(cmd, str) else " ".join(str(c) for c in cmd)
    print(f"  $ {display}")
    result = subprocess.run(cmd, **kwargs)
    return result.returncode


def resolve_bin(name: str) -> str:
    """
    Return the absolute path of a binary visible to the *current* user.
    sudo -u strips PATH, so we must pass the full path explicitly.
    Exits with a helpful message if the binary is not found.
    """
    path = shutil.which(name)
    if not path:
        print(f"Error: '{name}' not found in PATH.")
        print(f"Make sure Kiro is installed and on your PATH, then retry.")
        sys.exit(1)
    return path


# ── Commands ───────────────────────────────────────────────────────────────────

def cmd_sync(guard_root: str):
    """
    Expand globs, write resolved absolute paths to a temp file,
    then call the OS-specific sync script with that file.
    """
    patterns = read_raw_patterns(guard_root)
    resolved = expand_patterns(guard_root, patterns)

    print(f"Project root : {guard_root}")
    print(f"Patterns     : {len(patterns)} rule(s) → {len(resolved)} resolved path(s)")
    print(f"Syncing on {OS}...\n")

    # Write resolved paths to a temp file for the shell script to consume
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".kiroguard-resolved", delete=False, encoding="utf-8"
    ) as tmp:
        tmp_path = tmp.name
        for p in resolved:
            tmp.write(p + "\n")

    try:
        if OS == "Linux":
            script = os.path.join(SCRIPT_DIR, "kg-sync.sh")
            if not os.path.isfile(script):
                print(f"Error: 'kg-sync.sh' not found at '{SCRIPT_DIR}'.")
                sys.exit(1)
            run(["sudo", "bash", script, guard_root, tmp_path])
        elif OS == "Windows":
            script = os.path.join(SCRIPT_DIR, "kg-sync.bat")
            if not os.path.isfile(script):
                print(f"Error: 'kg-sync.bat' not found at '{SCRIPT_DIR}'.")
                sys.exit(1)
            run(f'"{script}" "{guard_root}" "{tmp_path}"', shell=True)
        else:
            print(f"Unsupported OS: {OS}")
            sys.exit(1)
    finally:
        os.unlink(tmp_path)


def cmd_run(prompt: str):
    """Run Kiro as the restricted user with the given prompt."""
    if not prompt.strip():
        print("Error: prompt cannot be empty.")
        sys.exit(1)
    print(f"Running Kiro as '{RESTRICTED_USER}'...\n")
    kiro_bin = resolve_bin("kiro")
    if OS == "Linux":
        run(["sudo", "-u", RESTRICTED_USER, kiro_bin, prompt])
    elif OS == "Windows":
        run(f'runas /user:{RESTRICTED_USER} "{kiro_bin} \\"{prompt}\\""', shell=True)
    else:
        print(f"Unsupported OS: {OS}")
        sys.exit(1)


def cmd_login():
    """Perform first-time Kiro CLI login as the restricted user."""
    print(f"Starting Kiro login for user '{RESTRICTED_USER}'...\n")
    # Both sudo -u (Linux) and runas (Windows) strip the calling user's PATH.
    # Resolve the binary to its absolute path before switching users.
    kiro_cli_bin = resolve_bin("kiro-cli")
    if OS == "Linux":
        run(["sudo", "-u", RESTRICTED_USER, kiro_cli_bin, "login"])
    elif OS == "Windows":
        run(f'runas /user:{RESTRICTED_USER} "{kiro_cli_bin} login"', shell=True)
    else:
        print(f"Unsupported OS: {OS}")
        sys.exit(1)


def cmd_status(guard_root: str):
    """Show ACL status for all resolved paths from .kiro-guard."""
    patterns = read_raw_patterns(guard_root)
    resolved = expand_patterns(guard_root, patterns)

    print(f"Project root : {guard_root}")
    print(f"Patterns     : {len(patterns)} rule(s) → {len(resolved)} resolved path(s)\n")
    print(f"ACL status (user: {RESTRICTED_USER}):\n")

    for abs_path in resolved:
        exists = os.path.exists(abs_path)
        rel = os.path.relpath(abs_path, guard_root)
        tag = "EXISTS   " if exists else "NOT FOUND"
        print(f"  [{tag}] {rel}")
        if exists:
            if OS == "Linux":
                result = subprocess.run(
                    ["getfacl", "--omit-header", abs_path],
                    capture_output=True, text=True
                )
                for line in result.stdout.splitlines():
                    if RESTRICTED_USER in line or line.startswith("user::") or line.startswith("other::"):
                        print(f"             {line}")
            elif OS == "Windows":
                result = subprocess.run(
                    ["icacls", abs_path], capture_output=True, text=True
                )
                for line in result.stdout.splitlines():
                    if RESTRICTED_USER in line:
                        print(f"             {line.strip()}")
        print()


def cmd_test(guard_root: str):
    """Verify the restricted user cannot read any resolved guarded path (Linux only)."""
    if OS != "Linux":
        print("The 'test' command is only supported on Linux.")
        sys.exit(1)

    patterns = read_raw_patterns(guard_root)
    resolved = expand_patterns(guard_root, patterns)

    print(f"Project root : {guard_root}")
    print(f"Testing {len(resolved)} resolved path(s) for '{RESTRICTED_USER}':\n")
    passed = 0
    failed = 0

    for abs_path in resolved:
        rel = os.path.relpath(abs_path, guard_root)
        if not os.path.exists(abs_path):
            print(f"  [SKIP]  {rel} (not found)")
            continue
        result = subprocess.run(
            ["sudo", "-u", RESTRICTED_USER, "ls", abs_path],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"  [PASS]  {rel} — access correctly denied")
            passed += 1
        else:
            print(f"  [FAIL]  {rel} — WARNING: user can still read this!")
            failed += 1

    print(f"\nResult: {passed} blocked, {failed} accessible (should be 0).")
    if failed > 0:
        print("Run 'kiro-guard sync' to reapply the rules.")
        sys.exit(1)


# ── Entry point ────────────────────────────────────────────────────────────────

USAGE = """
Kiro-Guard — Restrict Kiro AI access to sensitive files

Usage:
  kiro-guard sync              Apply .kiro-guard rules to the OS
  kiro-guard run "prompt"      Run Kiro as the restricted user
  kiro-guard login             First-time login as restricted user
  kiro-guard status            Show ACL status for guarded paths
  kiro-guard test              Verify restricted user is blocked (Linux)

Kiro-Guard searches for .kiro-guard starting from your current directory
and walking up, so you can call it from anywhere within your project.

Glob patterns supported in .kiro-guard:
  my-secret/        directory and all its contents
  **/.env           any .env file at any depth (recursive)
  config/*.key      any .key file directly in config/
"""

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(USAGE)
        sys.exit(0)

    command = sys.argv[1].lower()

    # Commands that need project root
    if command in ("sync", "status", "test"):
        root = find_guard_root()

    if command == "sync":
        cmd_sync(root)
    elif command == "run":
        if len(sys.argv) < 3:
            print('Error: provide a prompt. Example: kiro-guard run "your prompt"')
            sys.exit(1)
        cmd_run(" ".join(sys.argv[2:]))
    elif command == "login":
        cmd_login()
    elif command == "status":
        cmd_status(root)
    elif command == "test":
        cmd_test(root)
    else:
        print(f"Unknown command: '{command}'")
        print(USAGE)
        sys.exit(1)
