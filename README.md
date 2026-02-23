# Kiro-Guard 🛡️

Run [Kiro](https://kiro.dev) as a restricted OS user that is **physically blocked** from your secret files — using POSIX ACLs (`setfacl`) on Linux.

---

## The problem

By default, Kiro runs as **you** and has access to every file you can read — including secrets, credentials, and private keys.

![Kiro running as the current user with full access to all project files](kiro-guard2.png)

## The solution

Kiro-Guard runs Kiro as a dedicated restricted user (`kiro-runner`). Sensitive paths are locked at the OS level with explicit **deny** ACLs — so even if Kiro is compromised or misbehaving, it gets a hard `Permission Denied`.

![Kiro running as kiro-runner, blocked from protected files by OS-level ACLs](kiro-guard.png)

`kiro-guard` walks up the directory tree from wherever you call it to find the nearest `.kiro-guard` file — just like `git` finds `.git`. Once installed on your PATH, you never need to `cd` to the project root first.

| Mechanism | Tool |
|-----------|------|
| POSIX ACL deny rules | `setfacl` |

---

## Project structure

```
kiro-guard/
├── .kiro-guard        ← Your exclusion list (one path or glob per line)
├── kiro-guard.py      ← Launcher (sync, run, ask, login, status, test)
├── kg-sync.sh         ← Applies ACL rules via setfacl
├── install.sh         ← Installs kiro-guard globally on PATH
└── README.md
```

---

## Installation

Run once — after this you can call `kiro-guard` from anywhere.

```bash
sudo bash install.sh
```

Installs to `/usr/local/lib/kiro-guard/`, creates a `/usr/local/bin/kiro-guard` wrapper, and copies `kiro-cli` companion binaries into `kiro-runner`'s home so they can run headlessly.

> **Requires:** `acl` package — `sudo apt install acl`

---

## Quick start

### 1. Add `.kiro-guard` to your project root

```ini
# .kiro-guard — paths relative to the project root

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

> `sudo` is required internally — you'll be prompted for your password.

---

### 3. First-time login (once per machine)

```bash
kiro-guard login
```

Since `kiro-runner` runs headless (no display), login uses **device flow** — it prints a URL and a short code. Open the URL in **your own browser**, enter the code, and approve. Tokens are stored under `/home/kiro-runner/`.

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

**Or send a single one-shot question:**
```bash
kiro-guard ask "which files do you have access to?"
```

---

## All commands

| Command | Description |
|---------|-------------|
| `kiro-guard sync` | Apply `.kiro-guard` rules via `setfacl` |
| `kiro-guard run` | Open `kiro-cli` **interactively** as `kiro-runner` |
| `kiro-guard ask "prompt"` | Send a **one-shot prompt** to `kiro-cli` |
| `kiro-guard login` | First-time login via device flow |
| `kiro-guard status` | Show current ACL status for guarded paths |
| `kiro-guard test` | Verify `kiro-runner` is blocked from guarded paths |

All commands auto-discover the project root by walking up the directory tree — no need to `cd` first.

---

## Verifying the lockdown

```bash
# Show ACL breakdown per path
kiro-guard status

# Try to read guarded files as kiro-runner and confirm denial
kiro-guard test
```

Or manually:
```bash
getfacl my-secret/
# Expected line: user:kiro-runner:---
```

---

## Why not `chmod`?

`chmod` works on 3 broad categories: **Owner / Group / Others**. There is no way to block a single specific user without affecting everyone else.

`setfacl` lets you say: *"Block specifically `kiro-runner`, leave everything else untouched."*

| Feature | `chmod` | `setfacl` |
|---------|---------|-----------|
| Target specific user | ❌ | ✅ |
| Granularity | Broad (3 categories) | Fine-grained (per user) |
| Risk of locking yourself out | High | Low |
| View rules | `ls -l` | `getfacl` |

---

## Troubleshooting

**`setfacl: command not found`**
```bash
sudo apt install acl
```

**Parent directory permission error**

`kiro-runner` needs execute (`--x`) on every folder in the path to your project. On bare Ubuntu the home directory may be `700`. Fix:
```bash
chmod o+x /home/your-username
```

**Kiro can still read a file after sync**

Re-run sync — ACL rules may have been reset by a recursive `chmod` or a Git operation:
```bash
kiro-guard sync
kiro-guard test
```

---

## Cleanup

To remove the restricted user and all its ACL rules:

```bash
sudo setfacl -R -x user:kiro-runner .
sudo deluser --remove-home kiro-runner
```

---

## License

[MIT](LICENSE) — Copyright © 2026 StarObject S.A.
