# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/dependencies.sh — packages. Sourced by install.sh.
#
# Which packages: packages/fedora/packages.txt (core) + every selected
# component's lines in components.tsv + the --mode extras + optional GPU
# helpers for a driver already in use (functions/detect.sh). No package name
# is assumed to exist: rpm and the *enabled* repositories are asked.

read_pkgs() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' "$1" | awk 'NF'; }

# Every wanted package spec, one per line ("a|b" alternatives, "?" optional).
wanted_packages() {
    local id
    read_pkgs "$REPO_DIR/packages/fedora/packages.txt"
    for id in $COMPONENTS; do comp_packages "$id"; done
    case "$MODE" in
        recommended) read_pkgs "$REPO_DIR/packages/fedora/recommended.txt" ;;
        complete)
            read_pkgs "$REPO_DIR/packages/fedora/recommended.txt"
            read_pkgs "$REPO_DIR/packages/fedora/optional.txt"
            read_pkgs "$REPO_DIR/packages/fedora/advanced.txt"
            [ "$INTERFACE" = classic ] && read_pkgs "$REPO_DIR/packages/fedora/classic-extra.txt" ;;
    esac
    detect_gpu_packages
}

# Sort the wanted packages into installed / available / missing.
# A line "a|b" is satisfied if any is installed, otherwise the first one the
# repositories offer is installed. "?pkg" is optional: if no repository has
# it, it is dropped quietly (PKG_OPTIONAL_MISSING) instead of reported.
PKG_INSTALLED=(); PKG_AVAILABLE=(); PKG_MISSING=(); PKG_OPTIONAL_MISSING=()
REPOQUERY_FAILED=0
classify_packages() {
    local groups=() line spec
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        # The same package can be wanted twice; a required wish wins over "?".
        spec="${line#\?}"
        if [[ " ${groups[*]} " == *" $spec "* ]]; then continue; fi
        if [ "$line" != "$spec" ] && [[ " ${groups[*]} " == *" ?$spec "* ]]; then continue; fi
        if [ "$line" = "$spec" ] && [[ " ${groups[*]} " == *" ?$spec "* ]]; then
            local i; for i in "${!groups[@]}"; do [ "${groups[$i]}" = "?$spec" ] && groups[i]="$spec"; done
            continue
        fi
        groups+=("$line")
    done < <(wanted_packages)
    PKG_INSTALLED=(); PKG_AVAILABLE=(); PKG_MISSING=(); PKG_OPTIONAL_MISSING=()
    local pending=() unresolved=() alts alt found avail
    for line in "${groups[@]}"; do
        IFS='|' read -r -a alts <<< "${line#\?}"
        found=""
        for alt in "${alts[@]}"; do
            if rpm -q --quiet "$alt" 2>/dev/null || rpm -q --quiet --whatprovides "$alt" 2>/dev/null; then found="$alt"; break; fi
        done
        if [ -n "$found" ]; then
            PKG_INSTALLED+=("$found")
        else
            unresolved+=("$line")
            pending+=("${alts[@]}")
        fi
    done
    [ ${#unresolved[@]} -eq 0 ] && return 0
    if [ -z "$DNF" ]; then
        for line in "${unresolved[@]}"; do
            if [ "${line:0:1}" = "?" ]; then PKG_OPTIONAL_MISSING+=("${line:1}"); else PKG_MISSING+=("${line%%|*}"); fi
        done
        return 0
    fi
    # One repoquery for everything. --qf needs an explicit newline on dnf5.
    local rq_rc=0
    avail="$("$DNF" -q repoquery --available --qf '%{name}\n' "${pending[@]}" 2>/dev/null)" || rq_rc=$?
    if [ "$rq_rc" -ne 0 ]; then
        # Don't report every package as "not available" when the query itself failed.
        warn "dnf repoquery failed (exit $rq_rc; offline or repository error) — package availability is unknown"
        REPOQUERY_FAILED=1
    fi
    avail="$(printf '%s\n' "$avail" | sed 's/\\n$//' | sort -u)"
    for line in "${unresolved[@]}"; do
        IFS='|' read -r -a alts <<< "${line#\?}"
        found=""
        for alt in "${alts[@]}"; do
            if grep -qx "$alt" <<< "$avail"; then found="$alt"; break; fi
        done
        if [ -n "$found" ]; then PKG_AVAILABLE+=("$found")
        elif [ "${line:0:1}" = "?" ] && [ -z "$(copr_for "${alts[0]}")" ]; then PKG_OPTIONAL_MISSING+=("${alts[0]}")
        else PKG_MISSING+=("${alts[0]}"); fi
    done
}

# repos.conf: package|copr-owner/project|why
copr_for() { awk -F'|' -v p="$1" '$0 !~ /^[[:space:]]*#/ && $1 == p {print $2; exit}' "$REPO_DIR/packages/fedora/repos.conf" 2>/dev/null; }

plan_packages() {
    step "Packages (mode: $MODE)"
    if [ "$INSTALL_PACKAGES" -eq 0 ]; then info "--no-packages: skipping."; return 0; fi
    if [ "$OS_ID" != "fedora" ] || [ -z "$DNF" ]; then info "Not Fedora/dnf: skipping."; return 0; fi
    classify_packages
    ok "${#PKG_INSTALLED[@]} already installed"
    if [ ${#PKG_AVAILABLE[@]} -gt 0 ]; then
        info "To install (${#PKG_AVAILABLE[@]}): ${PKG_AVAILABLE[*]}"
    fi
    [ ${#PKG_OPTIONAL_MISSING[@]} -gt 0 ] && info "Optional, not in your repositories (skipped): ${PKG_OPTIONAL_MISSING[*]}"
    local pkg copr
    if [ "$REPOQUERY_FAILED" -eq 1 ]; then
        info "Availability unknown for: ${PKG_MISSING[*]} (repository query failed); dnf will report anything missing at install time."
        return 0
    fi
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

# The COPR repositories that could supply missing packages (one per line).
coprs_needed() {
    local pkg
    for pkg in "${PKG_MISSING[@]}"; do copr_for "$pkg"; done | awk 'NF && !seen[$0]++'
}

# with_pty CMD…: run CMD on a pseudo-terminal when the live panel is drawn,
# so dnf, git and curl show their real progress bars (the panel reads them).
with_pty() {
    if [ "${UI_LIVE:-0}" -eq 1 ] && command -v script >/dev/null 2>&1; then
        local q; q="$(printf '%q ' "$@")"
        script -qefc "$q" /dev/null
    else
        "$@"
    fi
}

install_packages() {
    [ "$INSTALL_PACKAGES" -eq 1 ] && [ "$OS_ID" = "fedora" ] && [ -n "$DNF" ] || return 0
    # COPR repositories, only for packages that are otherwise unobtainable,
    # one explicit question each.
    local pkg copr enabled_any=0
    declare -A asked=()
    if [ "$REPOQUERY_FAILED" -eq 1 ]; then
        # Unknown availability: don't offer third-party repositories on a guess.
        PKG_AVAILABLE+=("${PKG_MISSING[@]}")
        PKG_MISSING=()
    fi
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
        if [ "$DRY" -eq 1 ]; then run sudo "$DNF" install -y "${PKG_AVAILABLE[@]}"
        else with_pty sudo "$DNF" install -y "${PKG_AVAILABLE[@]}"; fi
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
