#!/usr/bin/bash
# AetherOS installer for Fedora.
#
#   ./install.sh              interactive: preflight, show the plan, ask, install
#   ./install.sh --check      read-only preflight (exit 1 on a blocking problem)
#   ./install.sh --dry-run    show exactly what --install would do; changes nothing
#   ./install.sh --install    install (resumes an interrupted run)
#   ./install.sh --update     pull, re-link, migrate settings, rebuild, validate
#   ./install.sh --uninstall  remove AetherOS's links and services; keeps your files
#   ./install.sh --rollback   undo the installation and put your old configs back
#
# Options:
#   --mode minimal|recommended|complete   which package sets to install (default: recommended)
#   --yes               don't ask before installing packages from enabled repositories
#   --enable-copr       allow adding the COPR repositories listed in packages/fedora/repos.conf
#                       (never added without this flag or an explicit yes at the prompt)
#   --no-packages       configs only: install no packages
#   --skip-quickshell   don't install or build Quickshell
#   --with-zshrc        replace an existing ~/.zshrc (it is moved aside, never deleted)
#   --restart           ignore the saved progress of an interrupted install
#
# What it never does: run as root, change SELinux/firewall/Secure Boot, touch
# the bootloader or kernel, install GPU drivers without its own separate
# confirmation, replace your display manager, or delete a file it didn't create.
#
# Log: ~/.local/state/aether/logs/install-<timestamp>.log

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/scripts/lib/common.sh
. "$REPO_DIR/scripts/lib/common.sh"

MIN_FEDORA=41
ACTION=""
MODE="recommended"
ASSUME_YES=0
ENABLE_COPR=0
INSTALL_PACKAGES=1
INSTALL_QUICKSHELL=1
WITH_ZSHRC=0
RESTART=0
DRY=0

usage() { sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check|--dry-run|--install|--update|--uninstall|--rollback)
            [ -z "$ACTION" ] || { echo "Choose one of --check/--dry-run/--install/--update/--uninstall/--rollback." >&2; exit 2; }
            ACTION="${1#--}" ;;
        --mode)
            shift
            MODE="${1:-}" ;;
        --mode=*) MODE="${1#--mode=}" ;;
        --yes|-y) ASSUME_YES=1 ;;
        --enable-copr) ENABLE_COPR=1 ;;
        --no-packages) INSTALL_PACKAGES=0 ;;
        --skip-quickshell) INSTALL_QUICKSHELL=0 ;;
        --with-zshrc) WITH_ZSHRC=1 ;;
        --restart) RESTART=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
case "$MODE" in minimal|recommended|complete) ;; *) echo "--mode must be minimal, recommended or complete" >&2; exit 2 ;; esac
[ "$ACTION" = "dry-run" ] && DRY=1

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user, not root. sudo is used only for the package steps, and each is shown first." >&2
    exit 1
fi

STATE_DIR="$(aether_state_dir)"
STATE_FILE="$STATE_DIR/install.state"
LOG_DIR="$STATE_DIR/logs"

# ── output ──────────────────────────────────────────────────────────────
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'; else B=""; G=""; Y=""; R=""; D=""; N=""; fi
step()  { printf '\n%s==> %s%s\n' "$B" "$1" "$N"; }
ok()    { printf '  %sPASS%s  %s\n' "$G" "$N" "$1"; }
warn()  { printf '  %sWARN%s  %s\n' "$Y" "$N" "$1"; WARNINGS=$((WARNINGS + 1)); }
bad()   { printf '  %sFAIL%s  %s\n' "$R" "$N" "$1"; BLOCKERS=$((BLOCKERS + 1)); }
info()  { printf '  %s      %s%s\n' "$D" "$1" "$N"; }
WARNINGS=0
BLOCKERS=0

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
state_get()  { [ -f "$STATE_FILE" ] && grep "^$1=" "$STATE_FILE" | tail -1 | cut -d= -f2- || true; }

start_log() {
    mkdir -p "$LOG_DIR"
    chmod 700 "$STATE_DIR" 2>/dev/null || true
    LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
    # Keep the ten most recent logs.
    find "$LOG_DIR" -maxdepth 1 -name 'install-*.log' -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR>10 {print $2}' | xargs -r rm -f
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "AetherOS installer — action=$ACTION mode=$MODE — $(date)"
    echo "Repository: $REPO_DIR ($(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo 'not a git checkout'))"
}

acquire_lock() {
    mkdir -p "$STATE_DIR"
    exec 9>"$STATE_DIR/install.lock"
    if command -v flock >/dev/null 2>&1 && ! flock -n 9; then
        echo "Another AetherOS install is running (lock: $STATE_DIR/install.lock)." >&2
        exit 1
    fi
}

# ── system facts ────────────────────────────────────────────────────────
OS_ID="unknown"; OS_VERSION="0"; OS_VARIANT=""; ARCH="$(uname -m)"
if [ -r /etc/os-release ]; then
    # shellcheck source=/dev/null
    OS_ID="$(. /etc/os-release; echo "${ID:-unknown}")"
    # shellcheck source=/dev/null
    OS_VERSION="$(. /etc/os-release; echo "${VERSION_ID:-0}")"
    # shellcheck source=/dev/null
    OS_VARIANT="$(. /etc/os-release; echo "${VARIANT_ID:-}")"
fi
# Test hook: lets the installer tests exercise Fedora code paths on any host.
OS_ID="${AETHER_TEST_OS_ID:-$OS_ID}"; OS_VERSION="${AETHER_TEST_OS_VERSION:-$OS_VERSION}"

DNF=""
if command -v dnf5 >/dev/null 2>&1; then DNF="dnf5"; elif command -v dnf >/dev/null 2>&1; then DNF="dnf"; fi
dnf_is_v5() { [ "$DNF" = "dnf5" ] || { [ -n "$DNF" ] && "$DNF" --version 2>/dev/null | grep -qi 'dnf5'; }; }

read_pkgs() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' "$1" | awk 'NF'; }

package_lists() {
    echo "$REPO_DIR/packages/fedora/packages.txt"
    case "$MODE" in
        recommended) echo "$REPO_DIR/packages/fedora/recommended.txt" ;;
        complete) echo "$REPO_DIR/packages/fedora/recommended.txt"; echo "$REPO_DIR/packages/fedora/optional.txt"; echo "$REPO_DIR/packages/fedora/advanced.txt" ;;
    esac
}

# Sort the wanted packages into installed / available / unavailable by asking
# rpm and the *enabled* repositories — no package name is assumed to exist.
PKG_INSTALLED=(); PKG_AVAILABLE=(); PKG_MISSING=()
classify_packages() {
    local wanted=() list pkg avail
    while IFS= read -r list; do
        [ -f "$list" ] || continue
        while IFS= read -r pkg; do wanted+=("$pkg"); done < <(read_pkgs "$list")
    done < <(package_lists)
    PKG_INSTALLED=(); PKG_AVAILABLE=(); PKG_MISSING=()
    local pending=()
    for pkg in "${wanted[@]}"; do
        if rpm -q --quiet "$pkg" 2>/dev/null || rpm -q --quiet --whatprovides "$pkg" 2>/dev/null; then
            PKG_INSTALLED+=("$pkg")
        else
            pending+=("$pkg")
        fi
    done
    [ ${#pending[@]} -eq 0 ] && return 0
    if [ -z "$DNF" ]; then PKG_MISSING=("${pending[@]}"); return 0; fi
    # One repoquery for everything. --qf needs an explicit newline on dnf5.
    avail="$("$DNF" -q repoquery --available --qf '%{name}\n' "${pending[@]}" 2>/dev/null | sed 's/\\n$//' | sort -u || true)"
    for pkg in "${pending[@]}"; do
        if grep -qx "$pkg" <<< "$avail"; then PKG_AVAILABLE+=("$pkg"); else PKG_MISSING+=("$pkg"); fi
    done
}

# repos.conf: package|copr-owner/project|why
copr_for() { awk -F'|' -v p="$1" '$0 !~ /^[[:space:]]*#/ && $1 == p {print $2; exit}' "$REPO_DIR/packages/fedora/repos.conf" 2>/dev/null; }

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
    for tool in git python3; do
        if command -v "$tool" >/dev/null 2>&1; then ok "$tool found"; else warn "$tool not found (it is in the package list)"; fi
    done

    local free_kb
    free_kb="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
    if [ -n "$free_kb" ] && [ "$free_kb" -lt 1048576 ]; then warn "Less than 1 GiB free in $HOME."; else ok "Disk space in \$HOME"; fi

    # Security posture: reported, never changed.
    if command -v getenforce >/dev/null 2>&1; then
        case "$(getenforce 2>/dev/null)" in
            Enforcing) ok "SELinux enforcing (left as is)" ;;
            *) warn "SELinux is not enforcing. AetherOS doesn't need that and won't change it." ;;
        esac
    fi

    local dm=""
    dm="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)" .service)"
    if [ -n "$dm" ] && [ "$dm" != "display-manager" ]; then
        ok "Display manager: $dm (kept; pick 'Hyprland' in its session menu)"
    else
        warn "No display manager detected: start the session with 'Hyprland' from a TTY."
    fi

    local running=""
    for proc in waybar mako dunst swaync; do
        pgrep -x "$proc" >/dev/null 2>&1 && running="$running $proc"
    done
    [ -n "$running" ] && warn "Running now:$running — AetherOS provides its own bar and notifications; these would overlap in a Hyprland session."

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
    done < <(aether_targets)
    [ "$found" -eq 0 ] && ok "Nothing in the way at the managed paths."
    [ -f "$STATE_FILE" ] && ! state_done complete && info "An earlier install was interrupted; --install resumes it (--restart starts over)."
    return 0
}

plan_packages() {
    step "Packages (mode: $MODE)"
    if [ "$INSTALL_PACKAGES" -eq 0 ]; then info "--no-packages: skipping."; return 0; fi
    if [ "$OS_ID" != "fedora" ] || [ -z "$DNF" ]; then info "Not Fedora/dnf: skipping."; return 0; fi
    classify_packages
    ok "${#PKG_INSTALLED[@]} already installed"
    if [ ${#PKG_AVAILABLE[@]} -gt 0 ]; then
        info "To install (${#PKG_AVAILABLE[@]}): ${PKG_AVAILABLE[*]}"
    fi
    local pkg copr
    for pkg in "${PKG_MISSING[@]}"; do
        copr="$(copr_for "$pkg")"
        if [ -n "$copr" ]; then
            warn "$pkg is not in your enabled repositories. Available from COPR $copr (https://copr.fedorainfracloud.org/coprs/$copr/)."
        else
            warn "$pkg is not available for Fedora $OS_VERSION in your enabled repositories — skipped; its feature reports itself unavailable."
        fi
    done
    return 0
}

install_packages() {
    [ "$INSTALL_PACKAGES" -eq 1 ] && [ "$OS_ID" = "fedora" ] && [ -n "$DNF" ] || return 0
    # COPR repositories, only for packages that are otherwise unobtainable,
    # one explicit question each.
    local pkg copr enabled_any=0
    declare -A asked=()
    for pkg in "${PKG_MISSING[@]}"; do
        copr="$(copr_for "$pkg")"
        [ -n "$copr" ] || continue
        [ -n "${asked[$copr]:-}" ] && continue
        asked[$copr]=1
        echo
        echo "  $pkg needs the third-party COPR repository '$copr'."
        echo "  COPR repositories are built by community members, not by Fedora."
        if [ "$ENABLE_COPR" -eq 1 ] || confirm_explicit "Enable COPR $copr?"; then
            run sudo "$DNF" copr enable -y "$copr" && enabled_any=1
            state_set "copr" "$copr"
        fi
    done
    [ "$enabled_any" -eq 1 ] && [ "$DRY" -eq 0 ] && classify_packages

    if [ ${#PKG_AVAILABLE[@]} -eq 0 ]; then ok "No packages to install."; return 0; fi
    echo "  sudo $DNF install ${PKG_AVAILABLE[*]}"
    if confirm "Install these ${#PKG_AVAILABLE[@]} packages?"; then
        run sudo "$DNF" install -y "${PKG_AVAILABLE[@]}"
        state_set "installed_pkgs" "${PKG_AVAILABLE[*]}"
    else
        warn "Packages skipped. Features that need them will report 'unavailable'."
    fi
}

install_quickshell() {
    [ "$INSTALL_QUICKSHELL" -eq 1 ] && [ "$INSTALL_PACKAGES" -eq 1 ] || return 0
    step "Quickshell"
    if command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1; then
        ok "Quickshell already installed ($(command -v qs || command -v quickshell))"
        return 0
    fi
    if [ "$DRY" -eq 1 ]; then
        info "Quickshell is not installed. --install would try, in this order:"
        info "  1. the 'quickshell' package from your enabled repositories"
        info "  2. the COPR in packages/fedora/repos.conf (asks first)"
        info "  3. a source build from https://github.com/quickshell-mirror/quickshell (asks first)"
        return 0
    fi
    if rpm -q --quiet quickshell 2>/dev/null; then ok "quickshell package installed"; return 0; fi
    echo "  Quickshell was not installed by the package step."
    echo "  It can be built from its official source repository instead"
    echo "  (https://github.com/quickshell-mirror/quickshell, installs to /usr/local)."
    if ! confirm_explicit "Clone, build and install Quickshell from source now?"; then
        warn "Quickshell not installed: the shell can't start until 'qs' exists."
        return 0
    fi
    local build_dir
    build_dir="$(mktemp -d)"
    # shellcheck disable=SC2064 # expand now: build_dir is local
    trap "rm -rf '$build_dir'" RETURN
    git clone --depth 1 https://github.com/quickshell-mirror/quickshell "$build_dir/quickshell"
    echo "  Building commit $(git -C "$build_dir/quickshell" rev-parse HEAD) as your user…"
    cmake -S "$build_dir/quickshell" -B "$build_dir/quickshell/build" -GNinja -DCMAKE_BUILD_TYPE=Release
    cmake --build "$build_dir/quickshell/build"
    echo "  The build finished. Installing it to /usr/local needs root:"
    echo "    sudo cmake --install $build_dir/quickshell/build"
    if confirm_explicit "Install the build?"; then
        sudo cmake --install "$build_dir/quickshell/build"
        state_set "quickshell" "source:/usr/local"
    fi
}

do_backup() {
    step "Backing up existing configuration"
    if [ "$DRY" -eq 1 ]; then info "would run scripts/backup.sh (archive under ~/.aetheros-backups/)"; return 0; fi
    local out archive
    out="$(bash "$REPO_DIR/scripts/backup.sh")"
    printf '%s\n' "${out//$'\n'/$'\n'  }" | sed '1s/^/  /'
    archive="$(sed -n 's/^Backup complete: //p' <<< "$out")"
    # Only the first backup is the pre-AetherOS state rollback wants.
    [ -n "$archive" ] && [ -z "$(state_get first_backup)" ] && state_set first_backup "$archive"
    return 0
}

do_links() {
    step "Linking configuration"
    local args=()
    [ "$DRY" -eq 1 ] && args+=(--dry-run)
    if [ "$WITH_ZSHRC" -eq 0 ] && [ -e "$HOME/.zshrc" ] && [[ "$(readlink -f "$HOME/.zshrc" 2>/dev/null || true)" != "$REPO_DIR"/* ]]; then
        if [ "$DRY" -eq 1 ] || ! confirm_explicit "Replace your existing ~/.zshrc with AetherOS's? (yours is moved to ~/.zshrc.bak.<timestamp>)"; then
            args+=(--keep-zshrc)
        fi
    fi
    bash "$REPO_DIR/scripts/setup-symlinks.sh" "${args[@]}" | sed 's/^/  /'
}

do_configure() {
    step "Per-machine configuration"
    if ! command -v python3 >/dev/null 2>&1; then warn "python3 missing: hardware detection and settings migration skipped."; return 0; fi
    if [ "$DRY" -eq 1 ]; then
        info "would run: aether config migrate         (upgrade settings from an older AetherOS)"
        info "would run: aether hyprland compat        (rules/gestures for the installed Hyprland)"
        info "would run: aether graphics configure     (GPU environment for this machine)"
        info "would run: aether theme apply            (terminal + border colours)"
        info "would run: aether idle apply             (hypridle timings)"
        info "would run: scripts/build-shaders.sh      (compile shaders for the installed Qt)"
        return 0
    fi
    aether config migrate || warn "settings migration reported a problem (aether config validate)"
    aether hyprland compat || true
    aether graphics configure || true
    aether theme apply >/dev/null || true
    aether idle apply >/dev/null || true
    bash "$REPO_DIR/scripts/build-shaders.sh" || warn "shaders not compiled locally: bundled ones are used, with a non-shader fallback"
    aether hardware || true
    # NVIDIA: only ever a *plan* here; the installer for it asks separately.
    if [ "$OS_ID" = "fedora" ] && grep -qs "^PCI_ID=10DE:" /sys/bus/pci/devices/*/uevent && [ ! -d /sys/module/nvidia ]; then
        echo
        info "An NVIDIA GPU without the proprietary driver was detected."
        info "Nothing was installed. Review the plan with: aether graphics install-nvidia --dry-run"
    fi
}

do_services() {
    step "systemd user services"
    local units=() u
    for u in "$REPO_DIR"/system/systemd/*.service; do
        # Units without [Install] (the safe-mode fallback) are started on demand.
        grep -q '^\[Install\]' "$u" && units+=("$(basename "$u")")
    done
    if [ "$DRY" -eq 1 ]; then info "would enable: ${units[*]}"; return 0; fi
    if systemctl --user daemon-reload 2>/dev/null; then
        systemctl --user enable "${units[@]}" 2>/dev/null || true
        ok "enabled: ${units[*]}"
    else
        info "No systemd user session right now; Hyprland starts the services on first login."
    fi
}

do_validate() {
    step "Validation"
    if [ "$DRY" -eq 1 ]; then info "would run: scripts/doctor.sh, aether hyprland, aether config validate"; return 0; fi
    bash "$REPO_DIR/scripts/doctor.sh" || true
    if command -v python3 >/dev/null 2>&1; then
        aether hyprland || true
        aether config validate || true
    fi
}

run_step() {  # run_step <name> <function>
    if [ "$DRY" -eq 0 ] && state_done "$1"; then
        printf '\n%s==> %s%s %s(already done; --restart to redo)%s\n' "$B" "$1" "$N" "$D" "$N"
        return 0
    fi
    "$2"
    state_mark "$1"
}

do_install() {
    [ "$RESTART" -eq 1 ] && [ "$DRY" -eq 0 ] && rm -f "$STATE_FILE"
    # A finished install starts a fresh run (idempotent re-install).
    if [ "$DRY" -eq 0 ] && state_done complete; then
        local keep_backup
        keep_backup="$(state_get first_backup)"
        rm -f "$STATE_FILE"
        [ -n "$keep_backup" ] && state_set first_backup "$keep_backup"
    fi
    preflight
    if [ "$BLOCKERS" -gt 0 ] && [ "$INSTALL_PACKAGES" -eq 1 ]; then
        echo; echo "${R}$BLOCKERS blocking problem(s) above. Nothing was changed.${N}"
        exit 1
    fi
    plan_packages
    if [ "$DRY" -eq 0 ] && [ "$ACTION" != "install" ]; then
        echo
        confirm_explicit "Proceed with the installation?" || { echo "Nothing was changed."; exit 0; }
    fi
    run_step packages install_packages
    run_step quickshell install_quickshell
    run_step backup do_backup
    run_step links do_links
    run_step configure do_configure
    run_step services do_services
    do_validate
    state_mark complete
    echo
    if [ "$DRY" -eq 1 ]; then
        echo "${B}Dry run complete: nothing was changed.${N}"
    else
        echo "${B}AetherOS is installed.${N}  Log: $LOG_FILE"
        echo "  Log out, choose the Hyprland session at your display manager, and log in."
        echo "  If the shell misbehaves:        aether recover"
        echo "  If Hyprland won't start (TTY):  Hyprland -c ~/.config/hypr/recovery.conf"
        echo "  To undo everything:             ./install.sh --rollback"
    fi
}

do_update() {
    step "Updating AetherOS"
    if [ -d "$REPO_DIR/.git" ]; then
        if [ -n "$(git -C "$REPO_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
            warn "Local changes in $REPO_DIR (your live configs are links into it). Pulling with --ff-only."
        fi
        aether snapshot create --label pre-update >/dev/null 2>&1 || true
        git -C "$REPO_DIR" pull --ff-only || { bad "git pull failed; resolve it (git status) and re-run."; exit 1; }
    else
        info "Not a git checkout: skipping pull."
    fi
    do_links
    do_configure
    do_services
    do_validate
    echo
    echo "${B}Update complete.${N} Apply it with: aether reload"
    echo "  If something regressed: aether snapshot restore latest   (settings)   or   git -C $REPO_DIR reset --hard ORIG_HEAD   (files)"
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
    local pkgs copr
    pkgs="$(state_get installed_pkgs)"; copr="$(state_get copr)"
    echo
    [ -n "$pkgs" ] && echo "  Packages this installer added (remove with 'sudo dnf remove …' or 'sudo dnf history undo'): $pkgs"
    [ -n "$copr" ] && echo "  COPR enabled by this installer (disable with: sudo dnf copr disable $copr)"
    rm -f "$STATE_FILE"
    echo "  ${B}Rollback complete.${N} Your previous session entries and display manager were never changed."
}

case "${ACTION:-interactive}" in
    check)
        preflight
        plan_packages
        echo
        if [ "$BLOCKERS" -gt 0 ]; then echo "${R}$BLOCKERS blocking problem(s), $WARNINGS warning(s).${N}"; exit 1; fi
        echo "${G}Ready to install${N} ($WARNINGS warning(s)). Preview with ./install.sh --dry-run"
        ;;
    dry-run) do_install ;;
    install|interactive) acquire_lock; start_log; do_install ;;
    update) acquire_lock; start_log; do_update ;;
    uninstall) acquire_lock; start_log; do_uninstall ;;
    rollback) acquire_lock; start_log; do_rollback ;;
esac
