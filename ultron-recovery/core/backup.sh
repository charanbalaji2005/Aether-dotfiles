# shellcheck shell=bash
# ULTRON RECOVERY — backups.
#
# A backup is a directory $UR_BACKUP_DIR/<id>/ with
#   MANIFEST     "# key: value" header, then one TSV row per saved path:
#                index  component  type(dir|file|symlink|missing)  path  link-target
#   files/<n>/   the content of path n (a directory's contents, or __file)
#   SHA256SUMS   checksums of everything under files/ (integrity check)
# A symlinked config (e.g. ~/.config/hypr → your dotfiles repo) is recorded as
# a symlink and its target's content is saved, so a restore puts back both.
# Backups only read your files; nothing is ever deleted from them except by
# `backup_delete` after confirmation.

UR_LAST_BACKUP=""
# Never worth saving: caches and build output inside config dirs.
UR_BACKUP_EXCLUDES=(--exclude=__pycache__/ --exclude=node_modules/ --exclude='*.pyc' --exclude=.cache/ --exclude=.git/)

backup_ids() {  # newest first
    find "$UR_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -E '^[0-9]{8}-[0-9]{6}-' | sort -r
}

backup_meta() {  # backup_meta ID KEY
    sed -n "s/^# $2: //p" "$UR_BACKUP_DIR/$1/MANIFEST" 2>/dev/null | head -1
}

backup_components() {  # backup_components ID — component names it holds
    grep -v '^#' "$UR_BACKUP_DIR/$1/MANIFEST" 2>/dev/null | cut -f2 | sort -u
}

_copy_tree() {  # _copy_tree SRC_DIR DEST_DIR — contents of SRC into DEST
    mkdir -p "$2"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a "${UR_BACKUP_EXCLUDES[@]}" "$1/" "$2/"
    else
        cp -a "$1/." "$2/"
    fi
}

# backup_create LABEL COMPONENT… — sets UR_LAST_BACKUP to the new id.
backup_create() {
    local label="$1"; shift
    local comps=("$@") id dir n=0 c p type target total=0 done_=0
    [ "${#comps[@]}" -gt 0 ] || comps=("${UR_COMPONENTS[@]}")
    label="$(printf '%s' "$label" | tr -c 'a-zA-Z0-9_-' '-' | cut -c1-40)"
    id="$(date +%Y%m%d-%H%M%S)-${label:-manual}"
    dir="$UR_BACKUP_DIR/$id"
    while [ -e "$dir" ]; do sleep 1; id="$(date +%Y%m%d-%H%M%S)-${label:-manual}"; dir="$UR_BACKUP_DIR/$id"; done

    if [ "$UR_DRY_RUN" = 1 ]; then
        log_info "[dry run] would create backup $id of: ${comps[*]}"
        UR_LAST_BACKUP="(dry-run)"; return 0
    fi
    mkdir -p "$dir/files" || { log_error "cannot create $dir"; return 1; }
    {
        echo "# ultron-backup: 1"
        echo "# id: $id"
        echo "# label: ${label:-manual}"
        echo "# created: $(date '+%F %T %z')"
        echo "# host: $(uname -n)"
        echo "# components: ${comps[*]}"
    } > "$dir/MANIFEST"

    for c in "${comps[@]}"; do total=$((total + $(component_paths "$c" | wc -l))); done
    for c in "${comps[@]}"; do
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            n=$((n + 1)); target=""
            if [ -L "$p" ]; then
                type=symlink; target="$(readlink "$p")"
                if [ -d "$p" ]; then _copy_tree "$p" "$dir/files/$n"
                elif [ -f "$p" ]; then mkdir -p "$dir/files/$n"; cp -aL "$p" "$dir/files/$n/__file"
                else mkdir -p "$dir/files/$n"; fi          # dangling link: record it only
            elif [ -d "$p" ]; then type=dir; _copy_tree "$p" "$dir/files/$n"
            elif [ -f "$p" ]; then type=file; mkdir -p "$dir/files/$n"; cp -a "$p" "$dir/files/$n/__file"
            else type=missing; fi
            printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$c" "$type" "$p" "$target" >> "$dir/MANIFEST"
            done_=$((done_ + 1)); ui_progress "$done_" "$total" "$c"
        done < <(component_paths "$c")
    done

    ( cd "$dir" && find files -type f -print0 | sort -z | xargs -0 -r sha256sum > SHA256SUMS ) \
        || { log_error "could not checksum backup $id"; return 1; }
    echo "# size: $(du -sh "$dir" | cut -f1)" >> "$dir/MANIFEST"
    UR_LAST_BACKUP="$id"
    log_ok "Backup $id created ($(backup_meta "$id" size), ${comps[*]})"
    backup_prune
}

backup_verify() {  # backup_verify ID — 0 when every file matches its checksum
    local d="$UR_BACKUP_DIR/$1"
    [ -f "$d/MANIFEST" ] && grep -q '^# ultron-backup: 1' "$d/MANIFEST" || { log_error "$1: not a valid backup (no manifest)"; return 1; }
    [ -f "$d/SHA256SUMS" ] || { log_error "$1: checksum list missing"; return 1; }
    local bad
    bad="$(cd "$d" && sha256sum -c --quiet SHA256SUMS 2>&1 | grep -v '^sha256sum: WARNING' || true)"
    if [ -n "$bad" ]; then
        log_error "$1: integrity check FAILED"
        printf '%s\n' "$bad" | head -10 | sed 's/^/      /'
        return 1
    fi
    log_ok "$1: integrity verified ($(wc -l < "$d/SHA256SUMS") files)"
}

backup_preview() {  # backup_preview ID — what a backup holds
    local d="$UR_BACKUP_DIR/$1" n c type p target count
    [ -f "$d/MANIFEST" ] || { log_error "no backup $1"; return 1; }
    ui_kv "Backup" "$1"
    ui_kv "Created" "$(backup_meta "$1" created)"
    ui_kv "Size" "$(backup_meta "$1" size)"
    ui_kv "Components" "$(backup_meta "$1" components)"
    echo
    while IFS=$'\t' read -r n c type p target; do
        case "$n" in '#'*|'') continue ;; esac
        count="$(find "$d/files/$n" -type f 2>/dev/null | wc -l)"
        printf '   %s%-14s%s %-8s %s%s %s(%s files)%s\n' "$C_CYAN" "$c" "$C_RESET" "$type" "${p/#$HOME/\~}" \
            "${target:+ → ${target/#$HOME/\~}}" "$C_GREY" "$count" "$C_RESET"
    done < "$d/MANIFEST"
}

backup_list() {
    local id any=0
    while IFS= read -r id; do
        any=1
        printf '   %s%s%s  %s%-6s%s %s\n' "$C_CYAN" "$id" "$C_RESET" "$C_GREY" "$(backup_meta "$id" size)" "$C_RESET" "$(backup_meta "$id" components)"
    done < <(backup_ids)
    [ "$any" = 1 ] || ui_info "No backups yet in $UR_BACKUP_DIR"
}

backup_delete() {
    local id="$1"
    [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[A-Za-z0-9_-]+$ ]] && [ -d "$UR_BACKUP_DIR/$id" ] || { log_error "no backup $id"; return 1; }
    ui_confirm "Permanently delete backup $id?" || { log_info "kept $id"; return 1; }
    if [ "$UR_DRY_RUN" = 1 ]; then log_info "[dry run] would delete backup $id"; return 0; fi
    rm -rf -- "${UR_BACKUP_DIR:?}/$id" && log_ok "Deleted backup $id"
}

backup_prune() {  # keep the newest UR_KEEP_BACKUPS automatic (pre-*) backups
    local keep="${UR_KEEP_BACKUPS:-20}" id
    backup_ids | grep -E -- '-pre-' | tail -n +"$((keep + 1))" | while IFS= read -r id; do
        rm -rf -- "${UR_BACKUP_DIR:?}/$id" && log_raw "pruned old automatic backup $id"
    done
}
