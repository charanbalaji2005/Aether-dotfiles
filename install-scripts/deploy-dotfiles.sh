# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Neelampalli Charan Balaji
#
# install-scripts/deploy-dotfiles.sh — backups and linking. Sourced by install.sh.
#
# Configs are deployed as symlinks into this repository (so `update` is a
# git pull), by scripts/setup-symlinks.sh. Anything in the way is never
# overwritten: it is moved aside to <path>.bak.<timestamp> and recorded in
# the manifest that `restore`/`--rollback` reads. Before that, everything at
# the managed paths is archived to ~/.aetheros-backups/ (scripts/backup.sh).

do_backup() {
    step "Backing up existing configuration"
    if [ "$DRY" -eq 1 ]; then info "would run scripts/backup.sh (archive under ~/.aetheros-backups/)"; return 0; fi
    local out archive
    out="$(bash "$REPO_DIR/scripts/backup.sh")"
    printf '%s\n' "${out//$'\n'/$'\n'  }" | sed '1s/^/  /'
    archive="$(sed -n 's/^Backup complete: //p' <<< "$out")"
    [ -n "$archive" ] && state_set last_backup "$archive"
    # Only the first backup is the pre-AetherOS state rollback wants.
    [ -n "$archive" ] && [ -z "$(state_get first_backup)" ] && state_set first_backup "$archive"
    return 0
}

# link_groups GROUP… : setup-symlinks.sh for these groups only.
link_groups() {
    local args=(--only "$(IFS=,; echo "$*")" --interface "$INTERFACE")
    [ "$DRY" -eq 1 ] && args+=(--dry-run)
    if [[ " $* " == *" zsh "* ]] && [ "$WITH_ZSHRC" -eq 0 ] && [ -e "$HOME/.zshrc" ] \
        && [[ "$(readlink -f "$HOME/.zshrc" 2>/dev/null || true)" != "$REPO_DIR"/* ]]; then
        if [ "$DRY" -eq 1 ] || ! confirm_explicit "Replace your existing ~/.zshrc with AetherOS's? (yours is moved to ~/.zshrc.bak.<timestamp>)"; then
            args+=(--keep-zshrc)
        fi
    fi
    bash "$REPO_DIR/scripts/setup-symlinks.sh" "${args[@]}" | sed 's/^/  /'
}

# AetherOS's own commands and user services: every component uses them.
deploy_core() {
    step "Deploying AetherOS commands and services"
    link_groups bin systemd
}

# deploy_component ID: link its configs, then its own install step.
deploy_component() {
    local id="$1" groups fn
    step "$(comp_label "$id")"
    groups="$(comp_groups "$id")"
    # shellcheck disable=SC2086 # groups is a word list
    [ -n "$groups" ] && link_groups $groups
    fn="$(comp_fn "$id" install)"
    [ -n "$fn" ] && "$fn"
    return 0
}

# The manifest's most recent "moved aside" record for a path ("" if none).
moved_aside() {
    awk -F'\t' -v d="$1" '$2 == "backup" && $3 == d {p = $4} END {print p}' "$(aether_manifest)" 2>/dev/null
}

# copy_tree SRC DEST: copy without ever replacing a file already at DEST.
copy_tree() {
    mkdir -p "$2"
    if command -v rsync >/dev/null 2>&1; then rsync -a --ignore-existing "$1/" "$2/"
    else cp -rn "$1/." "$2/"; fi
}
