<div align="center">

# 🧹 universal-cleaner

**A universal, safe, cross-shell system cleaner for Linux & Termux**

[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=flat-square)](https://github.com/codedbysoumyajit/universal-cleaner/releases)
[![Shell](https://img.shields.io/badge/shell-POSIX%20%7C%20bash%20%7C%20zsh-green?style=flat-square)](#-compatibility)
[![License](https://img.shields.io/badge/license-MIT-orange?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Termux-lightgrey?style=flat-square)](#-compatibility)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](https://github.com/codedbysoumyajit/universal-cleaner/pulls)

One script. Every Linux distro. No dependencies.

[Quick Start](#-quick-start) · [Features](#-features) · [Usage](#-usage) · [Compatibility](#-compatibility) · [Contributing](#-contributing)

</div>

---

## 📋 Overview

`universal-cleaner.sh` is a single, dependency-free shell script that safely frees up disk space on any Linux system or Termux (Android). It auto-detects your environment, package manager, and installed language toolchains — then cleans them all with a clear, color-coded progress display.

Built with **POSIX compatibility** at its core, it runs identically in `sh`, `bash`, and `zsh` with no modifications needed.

```
══════════════════════════════════════════
  Package Manager Cleanup
══════════════════════════════════════════
  ▸ apt: remove unneeded packages
  ▸ apt: clean package cache
  ▸ apt: remove partial downloads
[ OK ]  Package manager cleanup done.

══════════════════════════════════════════
  Cleanup Summary
══════════════════════════════════════════

  ✔ Tasks completed :  9
  ⚠ Tasks skipped   :  3
  ✖ Tasks failed    :  0

  💾 Space freed     : ~214 MB
```

---

## ✨ Features

### 🔍 Smart Environment Detection
- Detects Linux distro via `/etc/os-release` (with `ID_LIKE` fallback)
- Detects Termux (Android) automatically
- Discovers the available package manager dynamically — no hardcoded assumptions
- Detects `sudo` availability and skips it gracefully when absent (e.g. Termux)

### 📦 Package Manager Cleanup

| Manager | Distro | Actions |
|---|---|---|
| `apt` | Debian, Ubuntu, Kali, Pop!\_OS, Mint | `autoremove`, `clean`, `autoclean` |
| `pacman` | Arch, Manjaro, EndeavourOS | `-Sc`, orphan removal |
| `dnf` | Fedora | `autoremove`, `clean all` |
| `yum` | CentOS, RHEL, Rocky | `autoremove`, `clean all` |
| `apk` | Alpine Linux | `cache clean` |
| `pkg` | Termux (Android) | `clean` |

### 🧑‍💻 Language Toolchain Cleanup

Automatically detects and cleans caches for:

- **npm** — `npm cache clean --force`
- **pip / pip3** — `pip cache purge`
- **yarn** — `yarn cache clean`
- **pnpm** — `pnpm store prune`
- **gem** (Ruby) — `gem cleanup`
- **composer** (PHP) — `composer clear-cache`
- **cargo** (Rust) — `cargo cache --autoclean` *(full mode only)*

### 🗑️ System Cleanup

- `/tmp` — user-owned files only (safe, never touches other users' files)
- `~/.cache` — full user cache directory
- Trash — XDG (`~/.local/share/Trash`), legacy (`~/.Trash`), Termux
- Thumbnail caches (`~/.thumbnails`, `~/.cache/thumbnails`)
- Old rotated logs in `/var/log` (`*.gz`, `*.1`, `*.old`) *(full mode, root only)*
- **systemd journal** vacuum (keeps last 7 days)
- **Flatpak** unused runtimes
- **Snap** disabled old revisions *(root only)*

### 🛡️ Safety First

- `--dry-run` previews every action — **nothing is ever deleted**
- `/tmp` cleanup excludes the script's own active temp directory mid-run
- Refuses to run from critical system paths (`/`, `/bin`, `/etc`, etc.)
- Root + `--auto` mode shows a 3-second abort window
- Every external tool is checked with `command -v` before use — zero crashes on missing tools
- `safe_delete` uses `find -mindepth 1 -delete` — never removes a directory itself

### 📊 Reporting

- Disk usage measured **before and after** with human-readable sizes (KB / MB / GB)
- Color-coded terminal output using real ANSI escape bytes (POSIX-safe)
- Optional plain-text log file (`cleanup.log`) with automatic ANSI stripping
- Final summary: tasks completed / skipped / failed + total space freed

---

## 🚀 Quick Start

```bash
sudo curl -fsSL https://raw.githubusercontent.com/codedbysoumyajit/universal-cleaner/main/universal-cleaner.sh \
  -o /usr/local/bin/universal-cleaner && \
sudo chmod +x /usr/local/bin/universal-cleaner && \
universal-cleaner
```

> Want to inspect the script before running? See the [full installation guide](#-installation) below.

---

## 📦 Installation

All methods install the script system-wide so you can run it as `universal-cleaner` (or the short alias `uc`) from any directory.

### Method 1 — `curl` *(recommended)*

```bash
sudo curl -fsSL https://raw.githubusercontent.com/codedbysoumyajit/universal-cleaner/main/universal-cleaner.sh \
  -o /usr/local/bin/universal-cleaner
sudo chmod +x /usr/local/bin/universal-cleaner
```

### Method 2 — `wget`

```bash
sudo wget -qO /usr/local/bin/universal-cleaner \
  https://raw.githubusercontent.com/codedbysoumyajit/universal-cleaner/main/universal-cleaner.sh
sudo chmod +x /usr/local/bin/universal-cleaner
```

### Method 3 — Clone the repo

```bash
git clone https://github.com/codedbysoumyajit/universal-cleaner.git
sudo cp universal-cleaner/universal-cleaner.sh /usr/local/bin/universal-cleaner
sudo chmod +x /usr/local/bin/universal-cleaner
```

### Add a short alias `uc` *(optional)*

After any method above, add a permanent short alias to your shell config:

```bash
# bash
echo 'alias uc="universal-cleaner"' >> ~/.bashrc && source ~/.bashrc

# zsh
echo 'alias uc="universal-cleaner"' >> ~/.zshrc && source ~/.zshrc
```

Now both commands work from anywhere:

```bash
universal-cleaner
uc
```

### Termux (Android)

Termux doesn't have `/usr/local/bin`, so install to `$PREFIX/bin` instead:

```bash
pkg install curl
curl -fsSL https://raw.githubusercontent.com/codedbysoumyajit/universal-cleaner/main/universal-cleaner.sh \
  -o "$PREFIX/bin/universal-cleaner"
chmod +x "$PREFIX/bin/universal-cleaner"
```

Then run:

```bash
universal-cleaner
```

> **No root required on Termux.** The script detects the Termux environment and skips `sudo` automatically.

### Uninstall

```bash
sudo rm /usr/local/bin/universal-cleaner
```

---

## 🔧 Usage

```
universal-cleaner [OPTIONS]
```

| Flag | Description |
|---|---|
| *(none)* | Interactive mode — prompts before each section |
| `--dry-run` | Preview all actions without making any changes |
| `--auto` | Skip all confirmation prompts (auto-confirm everything) |
| `--minimal` | Light cleanup: caches only, skips logs and deep system cleanup |
| `--full` | Full cleanup including logs, snap revisions, journal vacuum *(default)* |
| `--log` | Write output to `cleanup.log` in the current directory |
| `--version` | Print version and exit |
| `--help` | Show help message and exit |

### Examples

```bash
# Safe preview — see exactly what would be cleaned without touching anything
universal-cleaner --dry-run

# Fully automated silent run with logging (great for cron jobs)
universal-cleaner --auto --full --log

# Quick cache-only pass, no prompts
uc --auto --minimal

# Dry-run with full logging for auditing
uc --dry-run --log
```

### Running as a Scheduled Cron Job

```bash
# Edit crontab
crontab -e

# Run every Sunday at 2:00 AM, fully automated with logging
0 2 * * 0 universal-cleaner --auto --full --log
```

---

## 🖥️ Compatibility

| Shell | Supported |
|---|---|
| `sh` (POSIX) | ✅ |
| `bash` | ✅ |
| `zsh` | ✅ |
| `dash` | ✅ |

| Platform | Supported |
|---|---|
| Debian / Ubuntu / Kali / Pop!\_OS / Mint | ✅ |
| Arch Linux / Manjaro / EndeavourOS | ✅ |
| Fedora | ✅ |
| CentOS / RHEL / Rocky / AlmaLinux | ✅ |
| Alpine Linux | ✅ |
| Termux (Android) | ✅ |

> **Requirements:** `sh`, `find`, `du`, `df`, `id` — standard POSIX utilities present on every supported system. No packages need to be installed.

---

## 📁 Project Structure

```
universal-cleaner/
├── universal-cleaner.sh    # The script — single file, zero dependencies
├── README.md               # This file
└── LICENSE                 # MIT License
```

---

## 🤝 Contributing

Contributions, bug reports, and feature requests are welcome!

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/my-feature`
3. **Commit** your changes: `git commit -m 'Add my feature'`
4. **Push** to your branch: `git push origin feature/my-feature`
5. **Open** a Pull Request

Please test any changes using `--dry-run` mode before submitting.

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

Made with ❤️ by [codedbysoumyajit](https://github.com/codedbysoumyajit)

If this saved you some disk space, consider leaving a ⭐

</div>
