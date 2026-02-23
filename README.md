# Kiro-Guard 🛡️

Run [Kiro](https://kiro.dev) as a restricted OS user that is **physically blocked** from your secret files — using native filesystem ACLs on both Linux and Windows.

---

## The problem

By default, Kiro runs as **you** and has access to every file you can read — including secrets, credentials, and private keys.

![kiro-guard2.png — Kiro running as the current user with full access to all project files](kiro-guard2.png)

## The solution

Kiro-Guard runs Kiro as a dedicated restricted user (`kiro-runner`). Sensitive paths are locked at the OS level with explicit **deny** ACLs — so even if Kiro is compromised or misbehaving, it gets a hard `Permission Denied`.

![kiro-guard.png — Kiro running as kiro-runner, blocked from protected files by OS-level ACLs](kiro-guard.png)

`kiro-guard` walks up the directory tree from wherever you call it to find the nearest `.kiro-guard` file — just like `git` finds `.git`. Once installed on your PATH, you never need to `cd` to the project root first.

| Platform | Mechanism | Tool |
|----------|-----------|------|
| Linux (Ubuntu/WSL) | POSIX ACL deny rules | `setfacl` |
| Windows | NTFS ACL deny rules | `icacls` |

---

## Project structure

```
kiro-guard/
├── .kiro-guard        ← Your exclusion list (one path per line)
├── kiro-guard.py      ← Cross-platform launcher (sync, run, ask, login, status, test)
├── kg-sync.sh         ← Linux: apply ACL rules
├── kg-sync.bat        ← Windows: apply ACL rules
├── install.sh         ← Linux: install kiro-guard globally on PATH
├── install.bat        ← Windows: install kiro-guard globally on PATH
└── README.md
```

---

## Installation (put it on PATH)

Run once — after this you can call `kiro-guard` from anywhere.

**Linux:**
```bash
sudo bash install.sh
```
Installs to `/usr/local/lib/kiro-guard/` and creates a `/usr/local/bin/kiro-guard` wrapper.

**Windows (run as Administrator):**
```bat
install.bat
```
Installs to `%ProgramFiles%\KiroGuard\` and adds it to the system PATH.

> Open a new terminal after Windows installation for the PATH change to take effect.

---

## Quick start

### 1. Add `.kiro-guard` to your project root

```ini
# .kiro-guard — paths are relative to the project root

# ── Directories ───────────────────────────────────────────────────
my-secret/
.ssh/
certificates/

# ── Specific files ────────────────────────────────────────────────
environments/.env.prod
environments/.env.staging
config/secrets.yaml

# ── Recursive wildcards (**) — any depth ─────────────────────────
**/.env
**/.env.*
**/secrets/*

# ── Single-level wildcards (*) — one directory only ──────────────
certs/*.key
certs/*.pem
```

Lines starting with `#` are ignored. Paths are relative to the project root (where `.kiro-guard` lives).

#### Pattern reference

| Pattern | What it matches |
|---------|----------------|
| `my-secret/` | The whole `my-secret/` directory |
| `environments/.env.prod` | Exact file |
| `**/.env` | Any file named `.env` at **any depth** |
| `**/.env.*` | Any `.env.prod`, `.env.local` … at any depth |
| `**/secrets/*` | All files inside any `secrets/` directory |
| `certs/*.key` | Any `.key` file directly inside `certs/` |

---

### 2. Sync rules (once, or whenever `.kiro-guard` changes)

```bash
# From anywhere inside your project:
kiro-guard sync
```

This will:
1. Create the `kiro-runner` local user if it doesn't exist.
2. Grant `kiro-runner` read+execute access on the project root.
3. Apply a **hard deny** for every path listed in `.kiro-guard`.

> Linux requires `sudo` internally — you'll be prompted.  
> Windows requires the terminal to be running as Administrator.

---

### 3. First-time login (once per machine)

Kiro needs to authenticate once under the `kiro-runner` identity:

```bash
kiro-guard login
```

Since `kiro-runner` runs headless (no display), login uses **device flow** — it prints a URL and a code. Open the URL in **your own browser**, enter the code, and approve. Tokens are stored under `/home/kiro-runner/` (Linux) or `C:\Users\kiro-runner\` (Windows).

```
▰▰▰▱▱▱▱ Waiting for browser... 
Open this URL: https://auth.kiro.dev/device?user_code=XXXX-XXXX
```

---

### 4. Use Kiro

**Open the full interactive CLI session** (recommended):
```bash
kiro-guard run
```
This is equivalent to:
```bash
# Linux
sudo -u kiro-runner /path/to/kiro-cli
```

**Or send a single one-shot question:**
```bash
kiro-guard ask "which files do you have access to?"
```

---

## All commands

| Command | Description |
|---------|-------------|
| `kiro-guard sync` | Apply `.kiro-guard` rules to the OS |
| `kiro-guard run` | Open `kiro-cli` **interactively** as the restricted user |
| `kiro-guard ask "prompt"` | Send a **one-shot prompt** to `kiro-cli` |
| `kiro-guard login` | First-time login via device flow (no browser needed in session) |
| `kiro-guard status` | Show current ACL status for guarded paths |
| `kiro-guard test` | Verify restricted user is blocked (Linux only) |

All commands auto-discover the project root by walking up the directory tree — no need to `cd` first.

---

## Verifying the lockdown

```bash
# Show ACL breakdown per path
kiro-guard status

# Try to read guarded files as kiro-runner and confirm denial
kiro-guard test
```

Or manually (Linux):
```bash
getfacl circabc-secrets/
# Expected: user:kiro-runner:---
```

---

## Understanding the permission models

### Why not `chmod`?

`chmod` works on 3 broad categories: **Owner / Group / Others**. There is no way to target a single user without affecting everyone else.

`setfacl` / `icacls` let you say: *"Block specifically `kiro-runner`, leave everything else untouched."*

### Comparison

| Feature | `chmod` | `setfacl` / `icacls` |
|---------|---------|----------------------|
| Target specific user | ❌ | ✅ |
| Granularity | Broad (3 categories) | Fine-grained (per user) |
| Risk of locking yourself out | High | Low |
| View full rules | `ls -l` | `getfacl` / `icacls` |

---

## Troubleshooting

**`setfacl: command not found` (Linux)**
```bash
sudo apt install acl
```

**Parent directory permission error**

`kiro-runner` needs execute (`--x`) on every folder in the path leading to your project. On bare Ubuntu the home directory may be `700`. Fix:
```bash
chmod o+x /home/your-username
```

**Windows: `runas` prompts for a password**

Set a password for `kiro-runner` after creating the user:
```bat
net user kiro-runner YourChosenPassword
```

**Kiro can still read a file after sync**

Re-run sync — ACL rules may have been reset by a recursive `chmod` or a Git operation:
```bash
kiro-guard sync
kiro-guard test
```

---

## Cleanup

To remove the restricted user and all its rules:

**Linux:**
```bash
sudo setfacl -R -x user:kiro-runner .
sudo deluser kiro-runner
```

**Windows:**
```bat
icacls . /remove kiro-runner /t
net user kiro-runner /delete
```

---

## License

[MIT](LICENSE) — Copyright © 2026 StarObject S.A.
