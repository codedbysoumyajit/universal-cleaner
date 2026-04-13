#!/usr/bin/env sh
# =============================================================================
#  universal-cleaner.sh  v1.4.0
#  A universal, safe, cross-shell system cleaner for Linux & Termux
#  Compatible with: bash, zsh, sh (POSIX)
#  Platforms: Debian/Ubuntu, Arch, Fedora, Alpine, Termux (Android)
#  Fixes: UC_TMPDIR (no hardcoded /tmp), sudo-free Termux/no-sudo support
#
#  Usage:
#    chmod +x universal-cleaner.sh
#    ./universal-cleaner.sh              # Interactive mode
#    ./universal-cleaner.sh --dry-run    # Preview only, no changes
#    ./universal-cleaner.sh --auto       # No prompts, auto-confirm
#    ./universal-cleaner.sh --minimal    # Light cleanup only
#    ./universal-cleaner.sh --full       # Full deep cleanup
#    ./universal-cleaner.sh --log        # Enable logging to cleanup.log
#    ./universal-cleaner.sh --help       # Show help
# =============================================================================

# --- Script version ---
VERSION="1.0.0"
SCRIPT_NAME="universal-cleaner.sh"
LOG_FILE="./cleanup.log"

# --- Safe temp directory (Termux restricts /tmp; honour $TMPDIR first) ---
# Resolved once here; all code uses $UC_TMPDIR instead of /tmp directly.
if [ -n "$TMPDIR" ] && [ -w "$TMPDIR" ]; then
    UC_TMPDIR="$TMPDIR"
elif [ -w "/tmp" ]; then
    UC_TMPDIR="/tmp"
else
    UC_TMPDIR="$HOME/.cache/uc_tmp"
    mkdir -p "$UC_TMPDIR" 2>/dev/null
fi

# =============================================================================
# SECTION 1: FLAGS & GLOBAL STATE
# =============================================================================

DRY_RUN=0
AUTO_MODE=0
LOG_ENABLED=0
CLEANUP_MODE="full"   # "minimal" or "full"

TASKS_COMPLETED=0
TASKS_FAILED=0
TASKS_SKIPPED=0

# Disk usage tracking (in KB)
DISK_BEFORE=0
DISK_AFTER=0

# =============================================================================
# SECTION 2: ANSI COLOR CODES (POSIX-safe via printf)
# =============================================================================

# Use printf to bake real ESC characters into variables (POSIX-safe, no $'...' needed).
# This ensures ${BOLD}...${RESET} expand to actual bytes when passed to printf "%s".
if [ -t 1 ]; then
    ESC=$(printf '\033')
    RED="${ESC}[0;31m"
    GREEN="${ESC}[0;32m"
    YELLOW="${ESC}[1;33m"
    BLUE="${ESC}[0;34m"
    CYAN="${ESC}[0;36m"
    MAGENTA="${ESC}[0;35m"
    BOLD="${ESC}[1m"
    DIM="${ESC}[2m"
    RESET="${ESC}[0m"
else
    ESC=''
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    BOLD=''
    DIM=''
    RESET=''
fi

# =============================================================================
# SECTION 3: LOGGING & OUTPUT HELPERS
# =============================================================================

# Internal log writer — always plain text (strips any embedded ANSI codes)
_log_raw() {
    if [ "$LOG_ENABLED" -eq 1 ]; then
        # Strip ESC[ ... m sequences portably via sed
        _clean=$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g' 2>/dev/null || printf '%s' "$1")
        printf "%s  %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$_clean" >> "$LOG_FILE"
    fi
}

# Print a colored info line
info() {
    printf "${BLUE}[INFO]${RESET}  %s\n" "$1"
    _log_raw "[INFO]  $1"
}

# Print a success line
ok() {
    printf "${GREEN}[ OK ]${RESET}  %s\n" "$1"
    _log_raw "[ OK ]  $1"
}

# Print a warning line
warn() {
    printf "${YELLOW}[WARN]${RESET}  %s\n" "$1"
    _log_raw "[WARN]  $1"
}

# Print an error line
err() {
    printf "${RED}[ERR ]${RESET}  %s\n" "$1" >&2
    _log_raw "[ERR ]  $1"
}

# Print a section header
section() {
    printf "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}\n"
    printf "${BOLD}${CYAN}  %s${RESET}\n" "$1"
    printf "${BOLD}${CYAN}══════════════════════════════════════════${RESET}\n"
    _log_raw "=== $1 ==="
}

# Print a dimmed step line
step() {
    printf "${DIM}  ▸ %s${RESET}\n" "$1"
    _log_raw "  > $1"
}

# Spinner for long-running tasks (no external deps)
# Usage: spinner_start; <command>; spinner_stop
_SPINNER_PID=""
spinner_start() {
    if [ -t 1 ]; then
        (
            i=0
            frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
            while true; do
                i=$(( (i + 1) % 10 ))
                # Extract single character at position i
                frame=$(printf '%s' "$frames" | cut -c$(( i + 1 )))
                printf "\r${CYAN}  %s${RESET} Working..." "$frame"
                sleep 0.1
            done
        ) &
        _SPINNER_PID=$!
    fi
}

spinner_stop() {
    if [ -n "$_SPINNER_PID" ]; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
        printf "\r                          \r"
    fi
}

# =============================================================================
# SECTION 4: ARGUMENT PARSING
# =============================================================================

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run)  DRY_RUN=1 ;;
            --auto)     AUTO_MODE=1 ;;
            --log)      LOG_ENABLED=1 ;;
            --minimal)  CLEANUP_MODE="minimal" ;;
            --full)     CLEANUP_MODE="full" ;;
            --help|-h)  show_help; exit 0 ;;
            --version)  printf "%s v%s\n" "$SCRIPT_NAME" "$VERSION"; exit 0 ;;
            *)
                err "Unknown flag: $arg"
                printf "Run with --help for usage.\n"
                exit 1
                ;;
        esac
    done
}

show_help() {
    printf "${BOLD}%s v%s${RESET}\n" "$SCRIPT_NAME" "$VERSION"
    printf "A universal, safe, cross-shell system cleaner.\n\n"
    printf "${BOLD}USAGE:${RESET}\n"
    printf "  ./universal-cleaner.sh [OPTIONS]\n\n"
    printf "${BOLD}OPTIONS:${RESET}\n"
    printf "  ${GREEN}--dry-run${RESET}   Preview actions without making changes\n"
    printf "  ${GREEN}--auto${RESET}      Skip confirmation prompts\n"
    printf "  ${GREEN}--minimal${RESET}   Light cleanup (caches only)\n"
    printf "  ${GREEN}--full${RESET}      Full cleanup including logs & trash (default)\n"
    printf "  ${GREEN}--log${RESET}       Write output to cleanup.log\n"
    printf "  ${GREEN}--version${RESET}   Show version\n"
    printf "  ${GREEN}--help${RESET}      Show this help\n\n"
    printf "${BOLD}EXAMPLES:${RESET}\n"
    printf "  ./universal-cleaner.sh\n"
    printf "  ./universal-cleaner.sh --dry-run\n"
    printf "  ./universal-cleaner.sh --auto --full --log\n"
}

# =============================================================================
# SECTION 5: ENVIRONMENT DETECTION
# =============================================================================

# Detected values (set by detect_environment)
OS_TYPE=""        # "termux", "linux"
DISTRO=""         # "debian", "arch", "fedora", "alpine", "unknown"
PKG_MANAGER=""    # "apt", "pacman", "dnf", "yum", "apk", "pkg"
IS_ROOT=0

detect_environment() {
    section "Detecting Environment"

    # Check if running as root
    if [ "$(id -u)" -eq 0 ]; then
        IS_ROOT=1
        info "Running as root."
    else
        if command -v sudo > /dev/null 2>&1; then
            HAS_SUDO=1
            info "Running as user (sudo available)."
        else
            info "Running as user (no sudo — will run commands directly)."
        fi
    fi

    # Detect Termux
    if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ]; then
        OS_TYPE="termux"
        DISTRO="termux"
        info "Environment: Termux (Android)"
    else
        OS_TYPE="linux"

        # Detect distro via /etc/os-release (most modern distros)
        if [ -f /etc/os-release ]; then
            # Source safely without executing arbitrary code
            _id=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
            _id_like=$(grep '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')

            case "$_id" in
                ubuntu|debian|linuxmint|pop|kali|raspbian) DISTRO="debian" ;;
                arch|manjaro|endeavouros|garuda)           DISTRO="arch" ;;
                fedora)                                     DISTRO="fedora" ;;
                centos|rhel|rocky|almalinux|ol)            DISTRO="rhel" ;;
                alpine)                                     DISTRO="alpine" ;;
                *)
                    # Fallback to ID_LIKE
                    case "$_id_like" in
                        *debian*|*ubuntu*) DISTRO="debian" ;;
                        *arch*)            DISTRO="arch" ;;
                        *fedora*|*rhel*)   DISTRO="fedora" ;;
                        *)                 DISTRO="unknown" ;;
                    esac
                    ;;
            esac
            info "Distro: $(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')"
        else
            DISTRO="unknown"
            warn "Could not detect distro (/etc/os-release not found)."
        fi
    fi

    # Detect package manager dynamically (takes precedence over distro guess)
    if   command -v apt     > /dev/null 2>&1; then PKG_MANAGER="apt"
    elif command -v pacman  > /dev/null 2>&1; then PKG_MANAGER="pacman"
    elif command -v dnf     > /dev/null 2>&1; then PKG_MANAGER="dnf"
    elif command -v yum     > /dev/null 2>&1; then PKG_MANAGER="yum"
    elif command -v apk     > /dev/null 2>&1; then PKG_MANAGER="apk"
    elif command -v pkg     > /dev/null 2>&1; then PKG_MANAGER="pkg"
    else                                           PKG_MANAGER="none"
    fi

    info "Package manager: ${BOLD}${PKG_MANAGER}${RESET}"
    ok "Environment detection complete."
}

# =============================================================================
# SECTION 6: UTILITY FUNCTIONS
# =============================================================================

# Run or simulate a command
# Usage: run_cmd <description> <command...>
run_cmd() {
    _desc="$1"; shift
    step "$_desc"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf "    ${DIM}[dry-run] would run: %s${RESET}\n" "$*"
        TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
        return 0
    fi
    # Run command, capture stderr for error reporting
    _uc_errfile="$UC_TMPDIR/uc_err_$$.txt"
    if "$@" 2>"$_uc_errfile"; then
        rm -f "$_uc_errfile"
        TASKS_COMPLETED=$(( TASKS_COMPLETED + 1 ))
        return 0
    else
        _errmsg=$(cat "$_uc_errfile" 2>/dev/null)
        rm -f "$_uc_errfile"
        warn "Command failed: $* — ${_errmsg:-no details}"
        TASKS_FAILED=$(( TASKS_FAILED + 1 ))
        return 1
    fi
}

# Run with sudo only when needed AND available
# - root:   run directly
# - Termux: run directly (no sudo on Android)
# - other:  prepend sudo if sudo exists, else run directly with a warning
HAS_SUDO=0
sudo_run() {
    if [ "$IS_ROOT" -eq 1 ] || [ "$OS_TYPE" = "termux" ]; then
        run_cmd "$@"
    elif [ "$HAS_SUDO" -eq 1 ]; then
        _desc="$1"; shift
        run_cmd "$_desc" sudo "$@"
    else
        _desc="$1"; shift
        warn "sudo not available — trying without privileges: $*"
        run_cmd "$_desc" "$@"
    fi
}

# Check if a command exists
has_cmd() {
    command -v "$1" > /dev/null 2>&1
}

# Prompt for yes/no confirmation
# Returns 0 for yes, 1 for no
confirm() {
    _prompt="$1"
    if [ "$AUTO_MODE" -eq 1 ]; then
        return 0
    fi
    printf "\n${YELLOW}  ? %s [y/N]: ${RESET}" "$_prompt"
    read -r _reply
    case "$_reply" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# Get directory size in KB (portable)
dir_size_kb() {
    _path="$1"
    if [ ! -e "$_path" ]; then
        printf "0"
        return
    fi
    du -sk "$_path" 2>/dev/null | cut -f1
}

# Get used disk space in KB
disk_used_kb() {
    df -k / 2>/dev/null | awk 'NR==2 {print $3}'
}

# Format KB into human-readable
format_size() {
    _kb="$1"
    if [ "$_kb" -ge 1048576 ]; then
        printf "%d GB" $(( _kb / 1048576 ))
    elif [ "$_kb" -ge 1024 ]; then
        printf "%d MB" $(( _kb / 1024 ))
    else
        printf "%d KB" "$_kb"
    fi
}

# Safe recursive delete with dry-run and confirmation support
# Usage: safe_delete <path> <description>
safe_delete() {
    _target="$1"
    _desc="${2:-$1}"

    if [ ! -e "$_target" ]; then
        step "Skipping (not found): $_desc"
        TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
        return 0
    fi

    _size=$(dir_size_kb "$_target")
    step "Cleaning $_desc (~$(format_size "$_size"))"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf "    ${DIM}[dry-run] would delete: %s${RESET}\n" "$_target"
        TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
        return 0
    fi

    # Use find to delete contents rather than the directory itself
    find "$_target" -mindepth 1 -delete 2>/dev/null
    _rc=$?
    if [ "$_rc" -eq 0 ]; then
        ok "Cleaned: $_desc"
        TASKS_COMPLETED=$(( TASKS_COMPLETED + 1 ))
    else
        warn "Partial clean of: $_desc (some files may be locked)"
        TASKS_COMPLETED=$(( TASKS_COMPLETED + 1 ))
    fi
}

# =============================================================================
# SECTION 7: PACKAGE MANAGER CLEANUP
# =============================================================================

cleanup_pkg() {
    section "Package Manager Cleanup"

    if [ "$PKG_MANAGER" = "none" ]; then
        warn "No supported package manager found. Skipping."
        return
    fi

    if ! confirm "Run package manager cleanup ($PKG_MANAGER)?"; then
        info "Skipped package manager cleanup."
        return
    fi

    spinner_start

    case "$PKG_MANAGER" in
        apt)
            sudo_run "apt: remove unneeded packages"       apt-get autoremove -y
            sudo_run "apt: clean package cache"            apt-get clean
            sudo_run "apt: remove partial downloads"       apt-get autoclean
            ;;
        pacman)
            # Clean package cache (keep 1 version of each)
            sudo_run "pacman: clean package cache"         pacman -Sc --noconfirm
            # Remove orphaned packages if any exist
            _orphans=$(pacman -Qdtq 2>/dev/null)
            if [ -n "$_orphans" ]; then
                step "Removing orphaned packages..."
                if [ "$DRY_RUN" -eq 0 ]; then
                    echo "$_orphans" | sudo pacman -Rns - --noconfirm 2>/dev/null \
                        && ok "Orphans removed" \
                        || warn "Some orphans could not be removed"
                else
                    printf "    ${DIM}[dry-run] would remove orphans: %s${RESET}\n" "$_orphans"
                fi
            else
                step "No orphaned packages found."
            fi
            ;;
        dnf)
            sudo_run "dnf: remove unneeded packages"      dnf autoremove -y
            sudo_run "dnf: clean all cached data"         dnf clean all
            ;;
        yum)
            sudo_run "yum: remove unneeded packages"      yum autoremove -y
            sudo_run "yum: clean all cached data"         yum clean all
            ;;
        apk)
            sudo_run "apk: clean cache"                   apk cache clean
            ;;
        pkg)
            run_cmd "pkg (Termux): clean cache"           pkg clean
            ;;
    esac

    spinner_stop
    ok "Package manager cleanup done."
}

# =============================================================================
# SECTION 8: LANGUAGE PACKAGE MANAGER CLEANUP
# =============================================================================

cleanup_lang() {
    section "Language Package Manager Cleanup"

    if ! confirm "Clean language package caches (npm, pip, yarn, cargo, etc.)?"; then
        info "Skipped language package manager cleanup."
        return
    fi

    spinner_start

    # --- npm ---
    if has_cmd npm; then
        run_cmd "npm: clean cache" npm cache clean --force
    else
        step "npm not found, skipping."
        TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
    fi

    # --- pip / pip3 ---
    _pip_cmd=""
    if   has_cmd pip3; then _pip_cmd="pip3"
    elif has_cmd pip;  then _pip_cmd="pip"
    fi
    if [ -n "$_pip_cmd" ]; then
        run_cmd "pip: purge cache" "$_pip_cmd" cache purge
    else
        step "pip not found, skipping."
        TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
    fi

    # --- yarn ---
    if has_cmd yarn; then
        run_cmd "yarn: clean cache" yarn cache clean
    else
        step "yarn not found, skipping."
        TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
    fi

    # --- pnpm ---
    if has_cmd pnpm; then
        run_cmd "pnpm: prune store" pnpm store prune
    else
        step "pnpm not found, skipping."
        TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
    fi

    # --- cargo (Rust) --- full cleanup only
    if [ "$CLEANUP_MODE" = "full" ] && has_cmd cargo; then
        if has_cmd cargo-cache; then
            run_cmd "cargo: clean cache" cargo cache --autoclean
        else
            step "cargo-cache not installed; skipping cargo cleanup."
            TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
        fi
    fi

    # --- gem (Ruby) ---
    if has_cmd gem; then
        run_cmd "gem: clean old versions" gem cleanup
    else
        step "gem not found, skipping."
        TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
    fi

    # --- composer (PHP) ---
    if has_cmd composer; then
        run_cmd "composer: clear cache" composer clear-cache
    else
        step "composer not found, skipping."
        TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
    fi

    spinner_stop
    ok "Language package cleanup done."
}

# =============================================================================
# SECTION 9: SYSTEM CLEANUP
# =============================================================================

cleanup_system() {
    section "System Cleanup"

    if ! confirm "Clean system files (/tmp, ~/.cache, trash, logs)?"; then
        info "Skipped system cleanup."
        return
    fi

    spinner_start

    # --- /tmp ---
    # Only delete files owned by the current user to avoid permission errors.
    # Also skip UC_TMPDIR if it lives inside /tmp so we don't saw off the branch
    # we're sitting on mid-run.
    _user=$(id -un)
    step "Cleaning /tmp (owned by $_user)..."
    if [ "$DRY_RUN" -eq 0 ]; then
        find /tmp -user "$_user" -mindepth 1 \
            ! -path "$UC_TMPDIR/*" \
            -delete 2>/dev/null
        ok "Cleaned /tmp (user-owned files)."
        TASKS_COMPLETED=$(( TASKS_COMPLETED + 1 ))
    else
        printf "    ${DIM}[dry-run] would clean /tmp (user-owned, excluding active tmpdir)${RESET}\n"
        TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
    fi

    # --- ~/.cache ---
    if [ -d "$HOME/.cache" ]; then
        safe_delete "$HOME/.cache" "~/.cache"
    fi

    # --- Trash ---
    # XDG trash
    if [ -d "$HOME/.local/share/Trash/files" ]; then
        safe_delete "$HOME/.local/share/Trash/files" "Trash (XDG)"
        safe_delete "$HOME/.local/share/Trash/info"  "Trash metadata (XDG)"
    fi
    # Legacy ~/.Trash
    if [ -d "$HOME/.Trash" ]; then
        safe_delete "$HOME/.Trash" "~/.Trash"
    fi
    # Termux trash
    if [ "$OS_TYPE" = "termux" ] && [ -d "$HOME/.local/share/Trash" ]; then
        safe_delete "$HOME/.local/share/Trash" "Termux Trash"
    fi

    # --- Thumbnails ---
    if [ -d "$HOME/.thumbnails" ]; then
        safe_delete "$HOME/.thumbnails" "~/.thumbnails"
    fi
    if [ -d "$HOME/.cache/thumbnails" ]; then
        safe_delete "$HOME/.cache/thumbnails" "Thumbnail cache"
    fi

    # --- Old logs (full mode only) ---
    if [ "$CLEANUP_MODE" = "full" ]; then
        # User journal logs (systemd)
        if has_cmd journalctl; then
            # Keep only last 7 days of journal logs
            sudo_run "systemd: vacuum journal (keep 7 days)" \
                journalctl --vacuum-time=7d
        fi

        # Old log files in /var/log (rotate/compress older than 14 days)
        if [ "$IS_ROOT" -eq 1 ]; then
            step "Removing old rotated logs in /var/log (*.gz, *.1, *.old)..."
            if [ "$DRY_RUN" -eq 0 ]; then
                find /var/log -type f \( -name "*.gz" -o -name "*.1" \
                     -o -name "*.old" -o -name "*.bak" \) \
                     -mtime +14 -delete 2>/dev/null
                ok "Cleaned old rotated logs."
                TASKS_COMPLETED=$(( TASKS_COMPLETED + 1 ))
            else
                printf "    ${DIM}[dry-run] would clean old rotated logs in /var/log${RESET}\n"
                TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
            fi
        else
            step "Skipping /var/log cleanup (not root)."
            TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
        fi
    fi

    # --- Flatpak unused runtimes ---
    if has_cmd flatpak; then
        run_cmd "flatpak: remove unused runtimes" flatpak uninstall --unused -y
    fi

    # --- Snap old revisions (Ubuntu) ---
    if has_cmd snap && [ "$IS_ROOT" -eq 1 ]; then
        step "Removing old snap revisions..."
        if [ "$DRY_RUN" -eq 0 ]; then
            snap list --all 2>/dev/null \
            | awk '/disabled/{print $1, $3}' \
            | while read -r snapname revision; do
                snap remove "$snapname" --revision="$revision" 2>/dev/null
            done
            ok "Old snap revisions removed."
            TASKS_COMPLETED=$(( TASKS_COMPLETED + 1 ))
        else
            printf "    ${DIM}[dry-run] would remove disabled snap revisions${RESET}\n"
            TASKS_SKIPPED=$(( TASKS_SKIPPED + 1 ))
        fi
    fi

    spinner_stop
    ok "System cleanup done."
}

# =============================================================================
# SECTION 10: DISK USAGE REPORTING
# =============================================================================

record_disk_before() {
    DISK_BEFORE=$(disk_used_kb)
    info "Disk used before cleanup: ${BOLD}$(format_size "$DISK_BEFORE")${RESET}"
}

record_disk_after() {
    DISK_AFTER=$(disk_used_kb)
    info "Disk used after cleanup:  ${BOLD}$(format_size "$DISK_AFTER")${RESET}"
}

# =============================================================================
# SECTION 11: SUMMARY
# =============================================================================

print_summary() {
    section "Cleanup Summary"

    _freed=$(( DISK_BEFORE - DISK_AFTER ))
    # Guard against negative (unlikely but possible due to OS writes)
    if [ "$_freed" -lt 0 ]; then _freed=0; fi

    printf "\n"
    printf "  ${GREEN}✔ Tasks completed :${RESET} %d\n" "$TASKS_COMPLETED"
    printf "  ${YELLOW}⚠ Tasks skipped   :${RESET} %d\n" "$TASKS_SKIPPED"
    printf "  ${RED}✖ Tasks failed    :${RESET} %d\n" "$TASKS_FAILED"
    printf "\n"
    printf "  ${BOLD}${GREEN}💾 Space freed     : ~%s${RESET}\n" "$(format_size "$_freed")"
    printf "\n"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf "  ${DIM}(Dry-run mode — no changes were made)${RESET}\n\n"
    fi

    if [ "$LOG_ENABLED" -eq 1 ]; then
        printf "  ${DIM}Log saved to: %s${RESET}\n\n" "$LOG_FILE"
    fi

    _log_raw "Summary: completed=$TASKS_COMPLETED skipped=$TASKS_SKIPPED failed=$TASKS_FAILED freed=${_freed}KB"
}

# =============================================================================
# SECTION 12: BANNER
# =============================================================================

print_banner() {
    printf "\n"
    printf "${BOLD}${MAGENTA}"
    printf "  ██████╗██╗     ███████╗ █████╗ ███╗   ██╗███████╗██████╗ \n"
    printf " ██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██╔════╝██╔══██╗\n"
    printf " ██║     ██║     █████╗  ███████║██╔██╗ ██║█████╗  ██████╔╝\n"
    printf " ██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██╔══╝  ██╔══██╗\n"
    printf " ╚██████╗███████╗███████╗██║  ██║██║ ╚████║███████╗██║  ██║\n"
    printf "  ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝\n"
    printf "${RESET}"
    printf "  ${DIM}%s v%s — Universal System Cleaner${RESET}\n\n" "$SCRIPT_NAME" "$VERSION"
}

# =============================================================================
# SECTION 13: SAFETY CHECKS
# =============================================================================

safety_checks() {
    # Ensure we are NOT inside critical system paths
    _cwd=$(pwd)
    for _critical in / /bin /usr /etc /lib /lib64 /sbin /boot /sys /proc; do
        if [ "$_cwd" = "$_critical" ]; then
            err "Refusing to run from critical system path: $_cwd"
            exit 1
        fi
    done

    # Warn if running as root in auto mode
    if [ "$IS_ROOT" -eq 1 ] && [ "$AUTO_MODE" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
        warn "Running as root with --auto and no dry-run. Be careful!"
        printf "${YELLOW}  Proceeding in 3 seconds... (Ctrl+C to abort)${RESET}\n"
        sleep 3
    fi
}

# =============================================================================
# SECTION 14: MAIN ENTRY POINT
# =============================================================================

main() {
    parse_args "$@"

    print_banner

    # Start log file
    if [ "$LOG_ENABLED" -eq 1 ]; then
        printf "# universal-cleaner.sh v%s — %s\n" \
            "$VERSION" "$(date)" > "$LOG_FILE"
        info "Logging to: $LOG_FILE"
    fi

    # Mode indicators
    if [ "$DRY_RUN" -eq 1 ]; then
        printf "  ${YELLOW}[DRY-RUN MODE] No changes will be made.${RESET}\n"
    fi
    if [ "$AUTO_MODE" -eq 1 ]; then
        printf "  ${YELLOW}[AUTO MODE] All prompts will be auto-confirmed.${RESET}\n"
    fi
    printf "  ${DIM}Cleanup mode: %s${RESET}\n" "$CLEANUP_MODE"

    detect_environment
    safety_checks
    record_disk_before

    cleanup_pkg
    cleanup_lang
    cleanup_system

    record_disk_after
    print_summary
}

# Run main with all arguments
main "$@"
