#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# AetherOS Dotfiles installer for Fedora — https://github.com/charanbalaji2005/Aether-dotfiles
#
#   ./install.sh              on a terminal: the onboarding installer (menus, component
#                             selection, live progress, validation, final screen)
#   ./install.sh --check      read-only preflight (exit 1 on a blocking problem)
#   ./install.sh --dry-run    show exactly what --install would do; changes nothing
#   ./install.sh --install    install without menus (resumes an interrupted run)
#   ./install.sh --update     pull, re-link, migrate settings, rebuild, validate
#   ./install.sh --restore [--archive FILE]   put a backup back (menu on a terminal)
#   ./install.sh --uninstall  remove AetherOS's links and services; keeps your files
#   ./install.sh --rollback   undo the installation and put your old configs back
#   ./install.sh --list-components
#
# Options:
#   --components a,b,…  install only these components (see --list-components)
#   --preset recommended|all|minimal   a ready-made selection (default: from --mode)
#   --interface classic|aether            classic: Waybar, Rofi, SwayNC, Wlogout, Hyprlock, swww
#                       (macOS-inspired); aether: the Quickshell shell. Default: your current
#                       choice, else classic. Switch later with: aether-interface set …
#   --mode minimal|recommended|complete   which package sets to install (default: recommended)
#   --yes               don't ask before installing packages from enabled repositories
#   --enable-copr       allow adding the COPR repositories listed in packages/fedora/repos.conf
#                       (never added without this flag or an explicit yes at the prompt)
#   --no-packages       configs only: install no packages
#   --skip-quickshell   don't install or build Quickshell
#   --with-zshrc        replace an existing ~/.zshrc (it is moved aside, never deleted)
#   --restart           ignore the saved progress of an interrupted install
#   --no-fonts          don't offer to download JetBrainsMono Nerd Font
#   --no-tui            numbered prompts instead of dialog windows (also: AETHER_UI=plain)
#
# What it never does: run as root, change SELinux/firewall/Secure Boot, touch
# the bootloader or kernel, install or replace GPU drivers, replace your display
# manager, reboot by itself, or delete a file it didn't create.
#
# Log: ~/.local/state/aether/logs/install-<timestamp>.log

set -euo pipefail

AETHER_REPO_SLUG="charanbalaji2005/Aether-dotfiles"
AETHER_REPO_WEB="https://github.com/$AETHER_REPO_SLUG"
AETHER_REPO_URL="$AETHER_REPO_WEB.git"
AETHER_BRANCH="${AETHER_BRANCH:-release-final}"

# ── bootstrap: run as a single downloaded file ──────────────────────────
# Outside a checkout, the repository is cloned (HTTPS, fixed URL) to
# ~/.local/share/aether-dotfiles, the exact commit is shown, and the cloned
# installer runs only after an explicit yes. Nothing else is downloaded or run.
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd || echo /nonexistent)"
if [ ! -f "$REPO_DIR/functions/ui.sh" ]; then
    dest="${AETHER_DIR:-$HOME/.local/share/aether-dotfiles}"
    echo "AetherOS Dotfiles — © 2026 Neelampalli Charan Balaji — $AETHER_REPO_WEB"
    echo
    [ "$(id -u)" -ne 0 ] || { echo "Run this as your normal user, not root." >&2; exit 1; }
    command -v git >/dev/null 2>&1 || { echo "git is needed first: sudo dnf install git" >&2; exit 1; }
    if [ -d "$dest/.git" ]; then
        echo "Updating the existing copy in $dest…"
        git -C "$dest" pull --ff-only
    else
        echo "Downloading AetherOS ($AETHER_BRANCH) to $dest…"
        git clone --depth 1 --branch "$AETHER_BRANCH" --progress "$AETHER_REPO_URL" "$dest"
    fi
    commit="$(git -C "$dest" rev-parse HEAD)"
    echo
    echo "Downloaded commit: $(git -C "$dest" log -1 --format='%h  %s  (%cd)' --date=short)"
    if git -C "$dest" verify-commit HEAD >/dev/null 2>&1; then echo "Signature: valid (git verify-commit)"
    else echo "Signature: none — review it at $AETHER_REPO_WEB/commit/$commit"; fi
    echo
    if [ -t 0 ]; then
        read -r -p "Run the installer from this commit? [y/N] " reply
        [ "$reply" = y ] || [ "$reply" = Y ] || { echo "Nothing was run. The files are in $dest."; exit 0; }
    else
        case " $* " in *" --yes "*|*" -y "*) ;; *) echo "Not a terminal: re-run with --yes to run $dest/install.sh, or run it yourself." >&2; exit 1 ;; esac
    fi
    exec bash "$dest/install.sh" "$@"
fi

# shellcheck source=SCRIPTDIR/scripts/lib/common.sh
. "$REPO_DIR/scripts/lib/common.sh"
for f in "$REPO_DIR"/functions/*.sh "$REPO_DIR"/install-scripts/*.sh; do
    # shellcheck source=/dev/null
    . "$f"
done
AETHER_VERSION="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$REPO_DIR/lib/aether/__init__.py")"

MIN_FEDORA=41
# Oldest Quickshell whose API covers everything the shell uses — verified by
# tests/shell/test_quickshell_api.sh against Quickshell's source (0.1.x lacks
# Quickshell.execDetached and Hyprland.toplevels).
MIN_QUICKSHELL="0.2.0"
ACTION=""
MODE="recommended"
ASSUME_YES=0
ENABLE_COPR=0
INSTALL_PACKAGES=1
INSTALL_QUICKSHELL=1
WITH_ZSHRC=0
RESTART=0
DRY=0
INTERFACE=""
INSTALL_FONTS=1
COMPONENTS_ARG=""
PRESET=""
ARCHIVE=""
ENABLE_BLUETOOTH=""     # "": ask, 1: yes, 0: no
ENABLE_SDDM_THEME=0
UPDATE_PACKAGES=0
COMPONENTS=""

usage() { sed -n '5,37p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check|--dry-run|--install|--update|--uninstall|--rollback|--restore|--list-components)
            [ -z "$ACTION" ] || { echo "Choose one of --check/--dry-run/--install/--update/--restore/--uninstall/--rollback." >&2; exit 2; }
            ACTION="${1#--}" ;;
        --mode) shift; MODE="${1:-}" ;;
        --mode=*) MODE="${1#--mode=}" ;;
        --interface) shift; INTERFACE="${1:-}" ;;
        --interface=*) INTERFACE="${1#--interface=}" ;;
        --components) shift; COMPONENTS_ARG="${1:-}" ;;
        --components=*) COMPONENTS_ARG="${1#--components=}" ;;
        --preset) shift; PRESET="${1:-}" ;;
        --preset=*) PRESET="${1#--preset=}" ;;
        --archive) shift; ARCHIVE="${1:-}" ;;
        --no-fonts) INSTALL_FONTS=0 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --enable-copr) ENABLE_COPR=1 ;;
        --no-packages) INSTALL_PACKAGES=0 ;;
        --skip-quickshell) INSTALL_QUICKSHELL=0 ;;
        --with-zshrc) WITH_ZSHRC=1 ;;
        --restart) RESTART=1 ;;
        --no-tui) export AETHER_UI=plain ;;
        -h|--help) usage; exit 0 ;;
        --version) echo "AetherOS Dotfiles $AETHER_VERSION — © 2026 Neelampalli Charan Balaji"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
case "$MODE" in minimal|recommended|complete) ;; *) echo "--mode must be minimal, recommended or complete" >&2; exit 2 ;; esac
case "$PRESET" in ""|recommended|all|minimal) ;; *) echo "--preset must be recommended, all or minimal" >&2; exit 2 ;; esac
if [ -z "$INTERFACE" ]; then
    INTERFACE="$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/aether-shell/interface" 2>/dev/null || true)"
    case "$INTERFACE" in classic|aether) ;; *) INTERFACE=classic ;; esac
fi
case "$INTERFACE" in classic|aether) ;; *) echo "--interface must be classic or aether" >&2; exit 2 ;; esac
[ "$ACTION" = "dry-run" ] && DRY=1

if [ "$ACTION" = list-components ]; then
    for id in $(comp_list "$INTERFACE"); do
        printf '  %-15s %s%s\n' "$id" "$(comp_label "$id")" "$(comp_preset recommended "$INTERFACE" | grep -qx "$id" && echo '  [recommended]')"
    done
    exit 0
fi

# The selection: --components, else --preset, else what --mode implies.
# An update keeps the components chosen at install time.
resolve_components() {
    if [ -n "$COMPONENTS_ARG" ]; then
        COMPONENTS="$(comp_normalize "$INTERFACE" "$COMPONENTS_ARG")" || exit 2
    elif [ -n "$PRESET" ]; then
        COMPONENTS="$(comp_preset "$PRESET" "$INTERFACE" | tr '\n' ' ')"
    elif [ "$ACTION" = update ] && [ -n "$(comp_saved)" ]; then
        COMPONENTS="$(comp_normalize "$INTERFACE" "$(comp_saved)" 2>/dev/null || comp_preset recommended "$INTERFACE" | tr '\n' ' ')"
    else
        case "$MODE" in
            minimal) COMPONENTS="$(comp_preset minimal "$INTERFACE" | tr '\n' ' ')" ;;
            recommended) COMPONENTS="$(comp_preset recommended "$INTERFACE" | tr '\n' ' ')" ;;
            complete) COMPONENTS="$(comp_preset all "$INTERFACE" | grep -vx login-manager | tr '\n' ' ')" ;;
        esac
    fi
    COMPONENTS="${COMPONENTS% }"
    # Quickshell is built only for the Quickshell shell (the island falls back to Waybar).
    [[ " $COMPONENTS " == *" aether-shell "* ]] || INSTALL_QUICKSHELL=0
}
resolve_components

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user, not root. sudo is used only for the package steps, and each is shown first." >&2
    exit 1
fi

STATE_DIR="$(aether_state_dir)"
STATE_FILE="$STATE_DIR/install.state"
LOG_DIR="$STATE_DIR/logs"
LOG_FILE=""
REPORT_FILE=""
WARN_FILE=""

# ── output ──────────────────────────────────────────────────────────────
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'; else B=""; G=""; Y=""; R=""; D=""; N=""; fi
step()  { printf '\n%s==> %s%s\n' "$B" "$1" "$N"; }
ok()    { printf '  %sPASS%s  %s\n' "$G" "$N" "$1"; }
# Steps run in subshells, so warnings are also counted in a file.
warn()  {
    printf '  %sWARN%s  %s\n' "$Y" "$N" "$1"; WARNINGS=$((WARNINGS + 1))
    [ -z "$WARN_FILE" ] || printf '%s\n' "$1" >> "$WARN_FILE"
}
bad()   { printf '  %sFAIL%s  %s\n' "$R" "$N" "$1"; BLOCKERS=$((BLOCKERS + 1)); }
info()  { printf '  %s      %s%s\n' "$D" "$1" "$N"; }
WARNINGS=0
BLOCKERS=0

# try_step <description> <command…>: run a non-fatal step. A failure is never
# hidden: it is reported as a warning (with the exit code) and counted in
# the final summary.
try_step() {
    local what="$1"; shift
    local rc=0
    # 9>&-: daemons a step starts (waybar, swaync…) must not inherit the
    # install lock, or they hold it and block every later install.
    "$@" 9>&- || rc=$?
    if [ "$rc" -ne 0 ]; then
        warn "$what failed (exit $rc) — the install continues; see the log above"
    fi
    return 0
}

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ -t 0 ] || { echo "  $1 -> skipped (not a terminal; pass --yes)"; return 1; }
    local reply
    read -r -p "  $1 [y/N] " reply || return 1
    [ "$reply" = "y" ] || [ "$reply" = "Y" ]
}

# Things that are never implied by --yes (adding a repository, building and
# installing software from source, replacing a personal dotfile).
confirm_explicit() {
    [ -t 0 ] || { echo "  $1 -> skipped (needs an interactive yes)"; return 1; }
    local reply
    read -r -p "  $1 [y/N] " reply || return 1
    [ "$reply" = "y" ] || [ "$reply" = "Y" ]
}

# run <cmd...>: execute, or print under --dry-run.
run() {
    if [ "$DRY" -eq 1 ]; then printf '  %swould run:%s %s\n' "$D" "$N" "$*"; return 0; fi
    "$@"
}

aether() { bash "$REPO_DIR/scripts/bin/aether" "$@"; }

# ── install state (resume after interruption) ───────────────────────────
state_done() { [ -f "$STATE_FILE" ] && grep -qx "done=$1" "$STATE_FILE"; }
state_mark() { [ "$DRY" -eq 1 ] || { mkdir -p "$STATE_DIR"; echo "done=$1" >> "$STATE_FILE"; }; }
state_set()  { [ "$DRY" -eq 1 ] || { mkdir -p "$STATE_DIR"; echo "$1=$2" >> "$STATE_FILE"; }; }
# A missing key is a normal answer (empty), not an error.
state_get()  { [ -f "$STATE_FILE" ] && grep "^$1=" "$STATE_FILE" | tail -1 | cut -d= -f2- || true; }

start_log() {
    mkdir -p "$LOG_DIR"
    chmod 700 "$STATE_DIR" 2>/dev/null || echo "WARNING: couldn't restrict permissions on $STATE_DIR" >&2
    LOG_FILE="$LOG_DIR/${ACTION:-install}-$(date +%Y%m%d-%H%M%S).log"
    # Keep the ten most recent logs.
    find "$LOG_DIR" -maxdepth 1 -name '*.log' -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR>10 {print $2}' | xargs -r rm -f
    if [ "$UI_LIVE" -eq 1 ]; then
        # The terminal shows the live panel; the full output goes to the log.
        exec >> "$LOG_FILE" 2>&1
    else
        # 9>&-: the logger must not hold the install lock (see acquire_lock).
        exec > >(tee -a "$LOG_FILE" 9>&-) 2>&1
    fi
    echo "AetherOS installer $AETHER_VERSION — action=$ACTION mode=$MODE interface=$INTERFACE — $(date)"
    echo "Components: $COMPONENTS"
    echo "Repository: $REPO_DIR ($(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo 'not a git checkout'))"
}

# Only the installer itself holds the lock: its actions run with fd 9 closed
# (bash keeps a close-on-exec copy, so the lock stays held), so nothing they
# start (Waybar, the Quickshell island, the dock…) inherits it and blocks
# every later install, update or rollback until it exits.
acquire_lock() {
    mkdir -p "$STATE_DIR"
    exec 9>"$STATE_DIR/install.lock"
    if command -v flock >/dev/null 2>&1 && ! flock -n 9; then
        echo "Another AetherOS install is running (lock: $STATE_DIR/install.lock)." >&2
        exit 1
    fi
}

# ── system facts ────────────────────────────────────────────────────────
detect_system
OS_ID="$DET_OS_ID"; OS_VERSION="$DET_OS_VERSION"; OS_VARIANT=""; ARCH="$DET_ARCH"
# shellcheck source=/dev/null
[ -r /etc/os-release ] && OS_VARIANT="$(. /etc/os-release; echo "${VARIANT_ID:-}")"
# Test hook: lets the installer tests exercise Fedora code paths on any host.
OS_ID="${AETHER_TEST_OS_ID:-$OS_ID}"; OS_VERSION="${AETHER_TEST_OS_VERSION:-$OS_VERSION}"

DNF=""
if command -v dnf5 >/dev/null 2>&1; then DNF="dnf5"; elif command -v dnf >/dev/null 2>&1; then DNF="dnf"; fi
dnf_is_v5() { [ "$DNF" = "dnf5" ] || { [ -n "$DNF" ] && "$DNF" --version 2>/dev/null | grep -qi 'dnf5'; }; }

# The managed paths of the selected components (plus AetherOS's commands).
selected_targets() {
    local id g
    for g in bin systemd; do aether_group_targets_rel "$g"; done
    for id in $COMPONENTS; do
        for g in $(comp_groups "$id"); do aether_group_targets_rel "$g"; done
    done | while IFS= read -r rel; do echo "$HOME/$rel"; done
}

# ── preflight ───────────────────────────────────────────────────────────
preflight() {
    step "Preflight"
    if [ "$OS_ID" = "fedora" ]; then
        if [ "$OS_VERSION" -ge "$MIN_FEDORA" ] 2>/dev/null; then
            ok "Fedora $OS_VERSION${OS_VARIANT:+ ($OS_VARIANT)}, $ARCH"
        else
            bad "Fedora $OS_VERSION is older than the minimum supported release ($MIN_FEDORA)."
        fi
        case "$OS_VARIANT" in
            silverblue|kinoite|sericea|onyx|*atomic*)
                bad "Atomic/ostree Fedora ($OS_VARIANT) is not supported: this installer layers packages with dnf."
                info "Use a toolbox for the tools and run: ./install.sh --install --no-packages" ;;
        esac
    else
        bad "This installer supports Fedora only (detected: $OS_ID)."
        info "Configs only, with your own packages: ./install.sh --install --no-packages"
        info "Package names for other distributions: packages/generic/README.md"
    fi
    case "$ARCH" in
        x86_64|aarch64) ;;
        *) warn "Architecture $ARCH is untested." ;;
    esac

    if [ "$INSTALL_PACKAGES" -eq 1 ]; then
        if [ -n "$DNF" ]; then ok "Package manager: $DNF$(dnf_is_v5 && echo ' (DNF5)' || echo ' (DNF4)')"; else bad "dnf not found."; fi
        if command -v sudo >/dev/null 2>&1; then ok "sudo available (used only for package installation)"; else bad "sudo not found: packages can't be installed."; fi
    fi
    if [ "$INSTALL_QUICKSHELL" -eq 1 ] && { command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1; }; then
        local qsv
        qsv="$( (qs --version 2>/dev/null || quickshell --version 2>/dev/null) | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        if [ -z "$qsv" ]; then
            warn "Quickshell is installed but its version couldn't be read; AetherOS needs $MIN_QUICKSHELL or newer."
        elif [ "$(printf '%s\n%s\n' "$MIN_QUICKSHELL" "$qsv" | sort -V | head -1)" != "$MIN_QUICKSHELL" ]; then
            bad "Quickshell $qsv is older than $MIN_QUICKSHELL (the shell uses APIs added in $MIN_QUICKSHELL)."
        else
            ok "Quickshell $qsv (>= $MIN_QUICKSHELL)"
        fi
    fi
    for tool in git python3; do
        if command -v "$tool" >/dev/null 2>&1; then ok "$tool found"; else warn "$tool not found (it is in the package list)"; fi
    done

    if [ "$DET_DISK_FREE_MB" -gt 0 ] && [ "$DET_DISK_FREE_MB" -lt 1024 ]; then warn "Less than 1 GiB free in $HOME."; else ok "Disk space: $DET_DISK"; fi
    if [ "$DET_RAM_MB" -gt 0 ] && [ "$DET_RAM_MB" -lt 3800 ]; then warn "Less than 4 GiB of memory: use --mode minimal and the 'eco' quality tier."; else ok "Memory: $DET_RAM"; fi
    local g
    for g in "${DET_GPUS[@]}"; do info "GPU: $g"; done
    case "$DET_GPU_VENDORS" in
        *nvidia*) [ "$DET_NVIDIA_DRIVER" -eq 1 ] && ok "NVIDIA proprietary driver in use (kept)" \
            || info "NVIDIA GPU on nouveau/no driver: nothing is installed or replaced (plan: aether graphics install-nvidia --dry-run)" ;;
    esac

    # Security posture: reported, never changed.
    if command -v getenforce >/dev/null 2>&1; then
        case "$(getenforce 2>/dev/null)" in
            Enforcing) ok "SELinux enforcing (left as is)" ;;
            *) warn "SELinux is not enforcing. AetherOS doesn't need that and won't change it." ;;
        esac
    fi

    if [ "$DET_DM" != none ]; then
        ok "Display manager: $DET_DM (kept; pick 'Hyprland' in its session menu)"
    else
        warn "No display manager detected: start the session with 'Hyprland' from a TTY."
    fi

    ok "Interface: $INTERFACE$([ "$INTERFACE" = classic ] && echo ' (Waybar, Rofi, SwayNC, Wlogout, Hyprlock, swww)' || echo ' (Quickshell shell)')"
    info "Components: $COMPONENTS"
    local running="" procs=(mako dunst)
    [ "$INTERFACE" = aether ] && procs+=(waybar swaync)
    for proc in "${procs[@]}"; do
        pgrep -u "$(id -u)" -x "$proc" >/dev/null 2>&1 && running="$running $proc"
    done
    [ -n "$running" ] && warn "Running now:$running — AetherOS starts its own bar/notifications; these would overlap in a Hyprland session."

    step "Existing configuration"
    local found=0 t
    while IFS= read -r t; do
        if [ -L "$t" ] && [[ "$(readlink -f "$t" 2>/dev/null || true)" == "$REPO_DIR"/* ]]; then
            continue
        elif [ -e "$t" ] || [ -L "$t" ]; then
            if [ "$t" = "$HOME/.zshrc" ] && [ "$WITH_ZSHRC" -eq 0 ]; then
                info "$t exists — kept (use --with-zshrc to replace it)"
            else
                info "$t exists — will be moved aside to ${t}.bak.<timestamp>"
            fi
            found=1
        fi
    done < <(selected_targets)
    [ "$found" -eq 0 ] && ok "Nothing in the way at the managed paths."
    [ -f "$STATE_FILE" ] && ! state_done complete && info "An earlier install was interrupted; --install resumes it (--restart starts over)."
    return 0
}

# run_step <state-name> <label> <command…>: a resumable, numbered step.
run_step() {
    local name="$1" label="$2"; shift 2
    if [ "$DRY" -eq 0 ] && state_done "$name"; then
        UI_STEP_N=$((UI_STEP_N + 1))
        printf '\n%s==> %s%s %s(already done; --restart to redo)%s\n' "$B" "$name" "$N" "$D" "$N"
        [ "$UI_LIVE" -eq 1 ] && printf '  %s%s%s [%d/%d] %s %s(already done)%s\n' "$U_OK" "$U_TICK" "$U_N" "$UI_STEP_N" "$UI_STEP_TOTAL" "$label" "$U_D" "$U_N" > "$UI_TTY"
        UI_DONE+=("$label")
        return 0
    fi
    ui_task "$label" "$@"
    [ "$UI_LAST_RC" -ne 0 ] || state_mark "$name"
}

validate_and_report() {
    step "Validation"
    if [ "$DRY" -eq 1 ]; then info "would check every component, broken links and duplicate startup, and write a report"; return 0; fi
    validate_all
    write_report "$REPORT_FILE"
    printf '%s %s\n' "$V_FAILS" "$V_WARNS" > "$REPORT_FILE.counts"
    echo "  Report: $REPORT_FILE"
}

PLANNED=0   # 1: the onboarding already ran preflight and the package plan
do_install() {
    [ "$RESTART" -eq 1 ] && [ "$DRY" -eq 0 ] && rm -f "$STATE_FILE"
    # A finished install starts a fresh run (idempotent re-install).
    if [ "$DRY" -eq 0 ] && state_done complete; then
        local keep_backup
        keep_backup="$(state_get first_backup)"
        rm -f "$STATE_FILE"
        [ -n "$keep_backup" ] && state_set first_backup "$keep_backup"
    fi
    [ -n "$WARN_FILE" ] || WARN_FILE="$(mktemp)"
    if [ "$PLANNED" -eq 0 ]; then
        preflight
        if [ "$BLOCKERS" -gt 0 ] && [ "$INSTALL_PACKAGES" -eq 1 ]; then
            echo; echo "${R}$BLOCKERS blocking problem(s) above. Nothing was changed.${N}"
            exit 1
        fi
        plan_packages
        if [ "$DRY" -eq 0 ] && [ "$ACTION" = "" ]; then
            echo
            confirm_explicit "Proceed with the installation?" || { echo "Nothing was changed."; exit 0; }
        fi
    fi
    [ "$DRY" -eq 1 ] || { mkdir -p "$(dirname "$(comp_saved_file)")"; echo "$COMPONENTS" > "$(comp_saved_file)"; }
    REPORT_FILE="$STATE_DIR/reports/install-$(date +%Y%m%d-%H%M%S).txt"

    local id total=6
    [ "$INSTALL_QUICKSHELL" -eq 1 ] && total=$((total + 1))
    for id in $COMPONENTS; do total=$((total + 1)); done
    ui_steps_begin "$total"
    run_step packages "Downloading and installing dependencies" install_packages
    [ "$INSTALL_QUICKSHELL" -eq 1 ] && run_step quickshell "Installing Quickshell" install_quickshell
    run_step backup "Backing up your current configuration" do_backup
    run_step links "Deploying AetherOS commands and services" deploy_core
    for id in $COMPONENTS; do
        run_step "component-$id" "$(comp_step "$id")" deploy_component "$id"
    done
    run_step configure "Final configuration" do_configure
    run_step services "Enabling user services" do_services
    ui_task "Validating the installation" validate_and_report
    [ ${#UI_FAILED[@]} -eq 0 ] && state_mark complete
    finish_summary install
    [ ${#UI_FAILED[@]} -eq 0 ] || return 1
}

# The final summary, on the terminal (and in the log).
finish_summary() {
    local what="$1" id installed=() skipped=() failed=() counts vf=0 vw=0 warns=0
    [ -n "$WARN_FILE" ] && [ -f "$WARN_FILE" ] && warns="$(wc -l < "$WARN_FILE")"
    if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE.counts" ]; then read -r vf vw < "$REPORT_FILE.counts"; fi
    for id in $(comp_list "$INTERFACE"); do
        if [[ " ${UI_FAILED[*]-} " == *" $(comp_step "$id") "* ]]; then failed+=("$id")
        elif [[ " $COMPONENTS " == *" $id "* ]]; then installed+=("$id")
        else skipped+=("$id"); fi
    done
    local out
    out="$(
        echo
        if [ "$DRY" -eq 1 ]; then echo "${B}Dry run complete: nothing was changed.${N}"; exit 0; fi
        if [ ${#UI_FAILED[@]} -eq 0 ]; then echo "${B}${G}✔ AetherOS $what completed successfully${N}"
        else echo "${B}${R}✖ AetherOS $what finished with ${#UI_FAILED[@]} failed step(s)${N}: ${UI_FAILED[*]}"; fi
        [ "$what" = install ] && {
            echo "  Installed:  ${installed[*]:-none}"
            echo "  Skipped:    ${skipped[*]:-none}"
            echo "  Failed:     ${failed[*]:-none}"
        }
        echo "  Checks:     $vf failed, $vw warning(s); $warns installer warning(s)"
        local backup; backup="$(state_get last_backup | sed "s|^$HOME|~|")"
        echo "  Backup:     ${backup:-none (nothing was in the way)}${D}; anything replaced is also beside its path as *.bak.<time>${N}"
        echo "  Log:        ${LOG_FILE/#$HOME/\~}"
        [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ] && echo "  Report:     ${REPORT_FILE/#$HOME/\~}"
        echo
        echo "  Next: log out, choose the Hyprland session at your login screen, and log in."
        if [ "$INTERFACE" = classic ]; then
            echo "  Keys: Super+D apps · Super+A settings · Super+H all keybindings · Super+Esc power"
            echo "  Already in Hyprland? Reload the desktop: Super+Ctrl+R (aether-classic-start --reload)"
        else
            echo "  If the shell misbehaves:        aether recover"
        fi
        echo "  If Hyprland won't start (TTY):  Hyprland -c ~/.config/hypr/recovery.conf"
        echo "  To undo everything:             ./restore.sh   (or ./install.sh --rollback)"
        echo
        echo "  ⭐ Enjoying AetherOS? Star it: $AETHER_REPO_WEB — © 2026 Neelampalli Charan Balaji"
    )"
    printf '%s\n' "$out"
    [ "$UI_LIVE" -eq 1 ] && printf '%s\n' "$out" > "$UI_TTY"
    return 0
}

update_links() {
    step "Re-linking the configuration"
    local args=(--interface "$INTERFACE")
    [ "$WITH_ZSHRC" -eq 1 ] || args+=(--keep-zshrc)
    bash "$REPO_DIR/scripts/setup-symlinks.sh" "${args[@]}" | sed 's/^/  /'
}

pull_updates() {
    step "Fetching updates"
    if [ ! -d "$REPO_DIR/.git" ]; then info "Not a git checkout: skipping pull."; return 0; fi
    if [ -n "$(git -C "$REPO_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        warn "Local changes in $REPO_DIR (your live configs are links into it). Pulling with --ff-only."
    fi
    if ! aether snapshot create --label pre-update >/dev/null 2>&1; then
        warn "couldn't snapshot settings before updating (aether snapshot create) — continuing"
    fi
    local before; before="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
    with_pty git -C "$REPO_DIR" pull --ff-only --progress
    echo "  $before -> $(git -C "$REPO_DIR" rev-parse --short HEAD)"
}

do_update() {
    WARN_FILE="$(mktemp)"
    REPORT_FILE="$STATE_DIR/reports/update-$(date +%Y%m%d-%H%M%S).txt"
    local total=5
    [ "$UPDATE_PACKAGES" -eq 1 ] && total=6
    ui_steps_begin "$total"
    ui_task "Fetching updates" pull_updates
    if [ "$UI_LAST_RC" -ne 0 ]; then
        bad "git pull failed; resolve it (git -C $REPO_DIR status) and re-run."
        finish_summary update
        return 1
    fi
    if [ "$UPDATE_PACKAGES" -eq 1 ]; then plan_packages > /dev/null; ui_task "Installing new dependencies" install_packages; fi
    ui_task "Re-linking the configuration" update_links
    ui_task "Final configuration" do_configure
    ui_task "Enabling user services" do_services
    ui_task "Validating the installation" validate_and_report
    finish_summary update
    if [ "$INTERFACE" = classic ]; then
        echo "${B}Apply it with:${N} aether-classic-start --reload (Super+Ctrl+R)"
    else
        echo "${B}Apply it with:${N} aether reload"
    fi
    echo "  If something regressed: aether snapshot restore latest   (settings)   or   git -C $REPO_DIR reset --hard ORIG_HEAD   (files)"
    [ ${#UI_FAILED[@]} -eq 0 ] || return 1
}

do_uninstall() {
    step "Uninstalling AetherOS"
    echo "  Removes AetherOS's symlinks and user services. Kept: packages, your settings"
    echo "  (~/.config/aether-shell), snapshots, backups, and anything AetherOS didn't create."
    confirm "Continue?" || { echo "Nothing was changed."; exit 0; }
    bash "$REPO_DIR/scripts/uninstall.sh" --yes | sed 's/^/  /'
    echo
    echo "  To also put your previous configuration back: ./install.sh --rollback"
}

do_rollback() {
    step "Rolling back the AetherOS installation"
    local manifest
    manifest="$(aether_manifest)"
    echo "  1. remove AetherOS's symlinks and user services"
    echo "  2. move back every file the installer moved aside (from $manifest)"
    echo "  Packages are not removed. Your AetherOS settings and backups are kept."
    confirm "Continue?" || { echo "Nothing was changed."; exit 0; }
    bash "$REPO_DIR/scripts/uninstall.sh" --yes | sed 's/^/  /'
    bash "$REPO_DIR/scripts/rollback.sh" | sed 's/^/  /'
    local pkgs copr sddm
    pkgs="$(state_get installed_pkgs)"; copr="$(state_get copr)"; sddm="$(state_get sddm_theme)"
    echo
    [ -n "$pkgs" ] && echo "  Packages this installer added (remove with 'sudo dnf remove …' or 'sudo dnf history undo'): $pkgs"
    [ -n "$copr" ] && echo "  COPR enabled by this installer (disable with: sudo dnf copr disable $copr)"
    [ -n "$sddm" ] && echo "  SDDM theme selected by this installer (undo with: sudo rm $sddm)"
    rm -f "$STATE_FILE" "$(comp_saved_file)" "$(aether_groups_file)"
    echo "  ${B}Rollback complete.${N} Your previous session entries and display manager were never changed."
}

# Backup archives, newest first.
list_archives() {
    find "$HOME/.aetheros-backups" -maxdepth 1 -name 'aetheros-backup-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-
}

do_restore() {
    if [ -n "$ARCHIVE" ]; then
        local args=("$ARCHIVE"); [ "$ASSUME_YES" -eq 1 ] && args+=(--yes)
        bash "$REPO_DIR/scripts/restore.sh" "${args[@]}"
        return
    fi
    if ui_has_tty; then tui_restore; return; fi
    echo "Backups (newest first):"; list_archives | sed 's/^/  /'
    echo "Restore one with: ./restore.sh --archive FILE   ·   undo the whole install: ./install.sh --rollback"
}

# ── onboarding (an interactive terminal, no action flag) ────────────────
tui_welcome() {
    printf '\033[2J\033[H' > "$UI_TTY"
    ui_banner "$REPO_DIR/assets/logo.txt" "$AETHER_VERSION"
    detect_summary | sed 's/^/  /' > "$UI_TTY"
    ui_say ""
    local p prereq=""
    for p in git sudo python3 curl; do command -v "$p" >/dev/null 2>&1 || prereq+=" $p"; done
    [ -n "$DNF" ] || prereq+=" dnf"
    if [ -n "$prereq" ]; then ui_say "  ${U_WARN}Missing prerequisites:$prereq${U_N}"
    else ui_say "  ${U_OK}${U_TICK}${U_N} Prerequisites: git, sudo, python3, curl, $DNF — all present"; fi
    [ "$OS_ID" = fedora ] || ui_say "  ${U_WARN}Not Fedora ($OS_ID): only a configs-only install is possible.${U_N}"
    ui_say ""
    printf '  Press Enter to continue ' > "$UI_TTY"; IFS= read -r _ < "$UI_TTY" || true
}

tui_info() {
    local f; f="$(mktemp)"
    cat > "$f" <<EOF
AetherOS Dotfiles $AETHER_VERSION
© 2026 Neelampalli Charan Balaji — GPL-3.0-or-later
$AETHER_REPO_WEB

WHAT IT INSTALLS
$(for id in $(comp_list "$INTERFACE"); do printf '  • %s\n' "$(comp_label "$id")"; done)

WHERE
  Configs are symlinked from $REPO_DIR into
  ~/.config/{hypr,waybar,rofi,quickshell,kitty,swaync,gtk-3.0,gtk-4.0,…}
  Commands: ~/.local/bin/aether*      Settings: ~/.config/aether-shell
  Logs and reports: ~/.local/state/aether/

YOUR FILES ARE SAFE
  • Everything at those paths is archived to ~/.aetheros-backups/ first.
  • Anything in the way is moved aside to <path>.bak.<time>, never deleted.
  • Your wallpapers and Hyprland scripts are kept; your old keybinds are saved
    (commented out) in ~/.config/aether-shell/hypr/user.conf.
  • "Restore Previous Configuration" puts it all back.

NEVER DONE
  Running as root, rebooting by itself, changing SELinux, firewall, Secure Boot,
  the bootloader or kernel, installing or replacing GPU drivers, replacing your
  display manager, or running downloaded scripts without verification
  (the Nerd Font is SHA-256 checked; COPR repositories are asked one by one).

PREREQUISITES
  Fedora $MIN_FEDORA or newer (not Atomic), a user with sudo, internet access,
  about 1 GiB free. sudo is asked once, only when packages are installed.

WITHOUT MENUS
  ./install.sh --install --components hyprland,waybar,rofi
  ./install.sh --dry-run · --check · --update · --restore · --rollback
  ./install.sh --list-components · --help
EOF
    ui_textbox "Installation information" "$f"
    rm -f "$f"
}

tui_select_components() {
    local preset sel items=() id
    preset="$(ui_menu "Choose components" "What would you like to install?" \
        recommended "Recommended installation — the complete AetherOS desktop" \
        all "Select all — everything, including the login screen theme" \
        custom "Custom installation — pick each component" \
        none "Deselect all — start from nothing and pick")" || return 1
    case "$preset" in
        recommended|all) COMPONENTS="$(comp_preset "$preset" "$INTERFACE" | tr '\n' ' ')"; COMPONENTS="${COMPONENTS% }"; return 0 ;;
    esac
    local on
    for id in $(comp_list "$INTERFACE"); do
        on=off
        [ "$preset" = custom ] && comp_preset recommended "$INTERFACE" | grep -qx "$id" && on=on
        items+=("$id" "$(comp_label "$id")" "$on")
    done
    sel="$(ui_checklist "Components" "Space toggles · Enter confirms. Unselected parts keep your current configuration." "${items[@]}")" || return 1
    [ -n "$sel" ] || { ui_msg "Nothing selected" "Select at least one component."; return 1; }
    COMPONENTS="$(comp_normalize "$INTERFACE" "$sel")"
}

needs_sudo() {
    [ "$INSTALL_PACKAGES" -eq 1 ] && [ ${#PKG_AVAILABLE[@]} -gt 0 ] && return 0
    [ "$ENABLE_COPR" -eq 1 ] && [ -n "$(coprs_needed)" ] && return 0
    [ "${ENABLE_BLUETOOTH:-0}" = 1 ] && return 0
    [ "$ENABLE_SDDM_THEME" -eq 1 ]
}

tui_install() {
    tui_select_components || return 0
    [[ " $COMPONENTS " == *" aether-shell "* ]] || INSTALL_QUICKSHELL=0
    local plan; plan="$(mktemp)"
    # Same shell (no subshell): the package plan is kept for the steps.
    WARN_FILE="$(mktemp)"
    preflight > "$plan" 2>&1
    plan_packages >> "$plan" 2>&1
    sed -i 's/\x1b\[[0-9;]*m//g' "$plan"
    if [ "$BLOCKERS" -gt 0 ] && [ "$INSTALL_PACKAGES" -eq 1 ]; then
        ui_textbox "Can't install: $BLOCKERS blocking problem(s)" "$plan"
        return 0
    fi
    # Every question is asked now, so the installation itself runs unattended.
    if [ "$INSTALL_PACKAGES" -eq 1 ] && [ ${#PKG_AVAILABLE[@]} -gt 0 ]; then
        if ui_yesno "Packages" "${#PKG_AVAILABLE[@]} packages will be installed from your enabled Fedora repositories (sudo dnf install):

$(printf '%s ' "${PKG_AVAILABLE[@]}" | fold -s -w 70)

Install them?"; then ASSUME_YES=1; else INSTALL_PACKAGES=0; fi
    fi
    local coprs; coprs="$(coprs_needed)"
    if [ "$INSTALL_PACKAGES" -eq 1 ] && [ -n "$coprs" ]; then
        ui_yesno "Community repositories (COPR)" "These packages aren't in your enabled repositories: ${PKG_MISSING[*]}

They are available from these COPR repositories, built by community members (not Fedora):
$(sed 's/^/  • /' <<< "$coprs")

Enable them?" no && ENABLE_COPR=1
    fi
    if [[ " $COMPONENTS " == *" shell "* ]] && [ -e "$HOME/.zshrc" ] && [[ "$(readlink -f "$HOME/.zshrc")" != "$REPO_DIR"/* ]]; then
        ui_yesno "Your ~/.zshrc" "You already have a ~/.zshrc. Replace it with AetherOS's?
(Yours is moved to ~/.zshrc.bak.<time>, never deleted.) No keeps yours." no && WITH_ZSHRC=1
    fi
    if [[ " $COMPONENTS " == *" fonts "* ]] && ! fc-list 2>/dev/null | grep -qi "Nerd Font"; then
        ui_yesno "Icon font" "The bar and menu icons need JetBrainsMono Nerd Font (not packaged by Fedora).
Download it from its GitHub release (SHA-256 verified) to ~/.local/share/fonts?" || INSTALL_FONTS=0
    fi
    if [[ " $COMPONENTS " == *" bluetooth "* ]] && ! systemctl is-enabled bluetooth.service >/dev/null 2>&1; then
        if ui_yesno "Bluetooth" "Enable and start the Bluetooth service (sudo systemctl enable --now bluetooth)?"; then ENABLE_BLUETOOTH=1; else ENABLE_BLUETOOTH=0; fi
    fi
    if [[ " $COMPONENTS " == *" login-manager "* ]] && [ "$DET_DM" = sddm ]; then
        ui_yesno "Login screen" "Install the AetherOS SDDM theme? It is copied to /usr/share/sddm/themes/aether
and selected by /etc/sddm.conf.d/10-aetheros.conf (delete it to undo)." no && ENABLE_SDDM_THEME=1
    fi
    local summary
    summary="Components ($(wc -w <<< "$COMPONENTS")): $(echo "$COMPONENTS" | sed 's/ /, /g')

Packages: $([ "$INSTALL_PACKAGES" -eq 1 ] && echo "${#PKG_AVAILABLE[@]} to install" || echo "none (skipped)")
Backup:   ~/.aetheros-backups/ + <path>.bak.<time> for anything replaced
Interface: $INTERFACE

Nothing is overwritten or deleted, and nothing reboots. Start the installation?
(Full preflight: choose No and see \"Installation information\".)"
    if ! ui_yesno "Ready to install" "$summary"; then
        ui_textbox "Preflight and package plan" "$plan"
        ui_yesno "Ready to install" "$summary" || { rm -f "$plan"; return 0; }
    fi
    printf '\033[2J\033[H' > "$UI_TTY"
    ui_banner "$REPO_DIR/assets/logo.txt" "$AETHER_VERSION"
    if needs_sudo; then
        ui_say "  Administrator rights are needed for: packages / system services. Your password is asked once."
        if ! sudo -v < "$UI_TTY"; then
            ui_msg "No administrator rights" "sudo failed: the installation continues without packages or system services."
            INSTALL_PACKAGES=0; ENABLE_COPR=0; ENABLE_BLUETOOTH=0; ENABLE_SDDM_THEME=0
        else
            # Keep the credentials fresh while the installer runs (no inherited lock).
            ( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) 9>&- &
        fi
    fi
    ui_say "  ${U_B}Installing AetherOS${U_N} — $(wc -w <<< "$COMPONENTS") components. ${U_D}Full log: ~/.local/state/aether/logs/${U_N}"
    ACTION=install; PLANNED=1; UI_LIVE=1
    acquire_lock
    start_log
    cat "$plan"; rm -f "$plan"
    local rc=0
    do_install 9>&- || rc=$?
    tui_finish "$rc"
}

tui_finish() {
    local choice items=()
    while true; do
        items=()
        [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && items+=(restart "Restart the Hyprland desktop now (config, bar, notifications)")
        items+=(reboot "Reboot the computer" logs "View the installation log")
        [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ] && items+=(report "View the installation report")
        items+=(exit "Exit")
        printf '\n  Press Enter for the final menu ' > "$UI_TTY"; IFS= read -r _ < "$UI_TTY" || true
        choice="$(ui_menu "$([ "${1:-0}" -eq 0 ] && echo 'Installation complete ✔' || echo 'Installation finished with problems')" \
            "Log out and choose Hyprland at your login screen to start AetherOS.
Backup: $(b="$(state_get last_backup)"; echo "${b:-none needed (nothing was in the way)}" | sed "s|^$HOME|~|")
Log: ${LOG_FILE/#$HOME/\~}" "${items[@]}")" || return 0
        case "$choice" in
            restart)
                if [ "$INTERFACE" = classic ]; then setsid -f bash "$REPO_DIR/scripts/bin/aether-classic-start" --reload >/dev/null 2>&1 9>&- || true
                else setsid -f bash "$REPO_DIR/scripts/bin/aether" reload >/dev/null 2>&1 9>&- || true; fi
                ui_msg "Desktop restarted" "Hyprland reloaded its configuration and the desktop was restarted.
For a completely fresh start, log out and back in." ;;
            reboot)
                ui_yesno "Reboot" "Reboot the computer now? Save your work first." no && { systemctl reboot; return 0; } ;;
            logs) ui_textbox "Installation log" "$LOG_FILE" ;;
            report) ui_textbox "Installation report" "$REPORT_FILE" ;;
            exit) return 0 ;;
        esac
    done
}

tui_update() {
    ui_yesno "Update AetherOS" "Pull the latest AetherOS from $AETHER_BRANCH, re-link your components, regenerate
machine settings and validate. Your settings are snapshotted first
(undo: aether snapshot restore latest)." || return 0
    [ -n "$DNF" ] && [ "$OS_ID" = fedora ] && ui_yesno "Packages" "Also install packages that the new version needs (sudo dnf)?" && UPDATE_PACKAGES=1 && ASSUME_YES=1
    printf '\033[2J\033[H' > "$UI_TTY"
    ui_banner "$REPO_DIR/assets/logo.txt" "$AETHER_VERSION"
    [ "$UPDATE_PACKAGES" -eq 1 ] && { sudo -v < "$UI_TTY" || UPDATE_PACKAGES=0; }
    ACTION=update; UI_LIVE=1
    COMPONENTS_ARG="" PRESET=""; resolve_components
    acquire_lock
    start_log
    local rc=0
    do_update 9>&- || rc=$?
    tui_finish "$rc"
}

tui_restore() {
    local choice a items=() n=0
    choice="$(ui_menu "Restore previous configuration" "What would you like to restore?" \
        rollback "Undo the AetherOS installation — put my original configs back" \
        archive "Restore a backup archive from ~/.aetheros-backups" \
        back "Back")" || return 0
    case "$choice" in
        rollback)
            ui_yesno "Undo the installation" "Remove AetherOS's links and services and move every original file back
(from the moved-aside list). Packages and your AetherOS settings are kept." no || return 0
            printf '\033[2J\033[H' > "$UI_TTY"
            ACTION=rollback; ASSUME_YES=1
            acquire_lock; start_log
            do_rollback 9>&-
            ui_msg "Rollback complete" "Your previous configuration is back. Log: ${LOG_FILE/#$HOME/\~}" ;;
        archive)
            while IFS= read -r a; do
                items+=("$a" "$(basename "$a" .tar.gz | sed 's/aetheros-backup-//')  ($(du -h "$a" | cut -f1))"); n=$((n + 1))
            done < <(list_archives)
            [ "$n" -gt 0 ] || { ui_msg "No backups" "No archives in ~/.aetheros-backups yet."; return 0; }
            a="$(ui_menu "Backup archives" "Newest first. The current state is backed up again before restoring." "${items[@]}")" || return 0
            ui_yesno "Restore" "Restore $(basename "$a")? Current configs at the managed paths are archived first, then replaced." no || return 0
            printf '\033[2J\033[H' > "$UI_TTY"
            bash "$REPO_DIR/scripts/restore.sh" "$a" --yes 9>&- > "$UI_TTY" 2>&1 \
                && ui_msg "Restored" "$(basename "$a") was restored." || ui_msg "Restore failed" "See the messages above." ;;
    esac
}

tui_main() {
    tui_welcome
    support_screen
    local choice note=""
    [ -f "$STATE_FILE" ] && ! state_done complete && note="

An earlier installation was interrupted — Start Installation resumes it."
    while true; do
        choice="$(ui_menu "AetherOS Dotfiles $AETHER_VERSION" "Welcome, ${USER:-friend}! A macOS-inspired Hyprland desktop for Fedora.

$DET_OS · kernel $DET_KERNEL
$(printf '%s\n' "${DET_GPUS[@]}")
$DET_RAM · $DET_DESKTOP$note" \
            install "Start installation" \
            update "Update existing dotfiles" \
            restore "Restore previous configuration" \
            info "Installation information" \
            support "Support the project ⭐" \
            exit "Exit")" || exit 0
        case "$choice" in
            install) tui_install; exit 0 ;;
            update) tui_update; exit 0 ;;
            restore) tui_restore ;;
            info) tui_info ;;
            support) support_screen always ;;
            exit) exit 0 ;;
        esac
    done
}

ui_init
case "${ACTION:-interactive}" in
    check)
        preflight
        plan_packages
        echo
        if [ "$BLOCKERS" -gt 0 ]; then echo "${R}$BLOCKERS blocking problem(s), $WARNINGS warning(s).${N}"; exit 1; fi
        echo "${G}Ready to install${N} ($WARNINGS warning(s)). Preview with ./install.sh --dry-run"
        ;;
    dry-run) do_install ;;
    interactive)
        if ui_has_tty && [ -t 1 ]; then tui_main
        else ACTION=""; acquire_lock; start_log; do_install 9>&-; fi ;;
    install) acquire_lock; start_log; do_install 9>&- ;;
    update) acquire_lock; start_log; do_update 9>&- ;;
    restore) do_restore ;;
    uninstall) acquire_lock; start_log; do_uninstall 9>&- ;;
    rollback) acquire_lock; start_log; do_rollback 9>&- ;;
esac
