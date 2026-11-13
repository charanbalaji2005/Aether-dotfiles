# shellcheck shell=bash
# ULTRON RECOVERY — restoring backups.
#
# Every restore: verifies the backup's checksums, shows what will change,
# asks, takes a "pre-restore" backup of the same components (so it can be
# rolled back), then puts each path back exactly as recorded:
#   dir / symlink-to-dir   contents mirrored (files added since are removed,
#                          but they are in the pre-restore backup)
#   file                   replaced atomically (temp file + rename)
#   symlink                the link itself is recreated pointing where it did
#   missing                a path that did not exist then: a symlink there now
#                          is removed, anything else is moved aside, never deleted

_restore_rows() {  # _restore_rows ID [COMPONENT…] — manifest rows to restore
    local id="$1"; shift
    local want=" $* "
    grep -v '^#' "$UR_BACKUP_DIR/$id/MANIFEST" | while IFS=$'\t' read -r n c type p target; do
        [ -n "$n" ] || continue
        if [ "$#" -eq 0 ] || [[ "$want" == *" $c "* ]]; then printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$c" "$type" "$p" "$target"; fi
    done
}

_safe_path() {  # only paths inside $HOME are ever written
    case "$1" in "$HOME"/?*) [[ "$1" != *"/../"* ]] ;; *) return 1 ;; esac
}

# restore_preview ID [COMPONENT…] — print the changes a restore would make.
restore_preview() {
    local id="$1"; shift
    local src n c type p target changes
    while IFS=$'\t' read -r n c type p target; do
        src="$UR_BACKUP_DIR/$id/files/$n"
        case "$type" in
            missing)
                if [ -e "$p" ] || [ -L "$p" ]; then printf '   %s%-12s%s %s: did not exist then — would be %s\n' "$C_CYAN" "$c" "$C_RESET" "${p/#$HOME/\~}" "$([ -L "$p" ] && echo "unlinked" || echo "moved aside")"; fi ;;
            file)
                if ! cmp -s "$src/__file" "$p" 2>/dev/null; then printf '   %s%-12s%s %s: would be replaced\n' "$C_CYAN" "$c" "$C_RESET" "${p/#$HOME/\~}"; fi ;;
            dir|symlink)
                if [ "$type" = symlink ] && [ "$(readlink "$p" 2>/dev/null)" != "$target" ]; then
                    printf '   %s%-12s%s %s: link would point to %s again\n' "$C_CYAN" "$c" "$C_RESET" "${p/#$HOME/\~}" "${target/#$HOME/\~}"
                fi
                if [ -f "$src/__file" ]; then
                    cmp -s "$src/__file" "$p" 2>/dev/null || printf '   %s%-12s%s %s: content would be replaced\n' "$C_CYAN" "$c" "$C_RESET" "${p/#$HOME/\~}"
                elif [ -d "$src" ] && command -v rsync >/dev/null 2>&1; then
                    changes="$(rsync -anic --delete "${UR_BACKUP_EXCLUDES[@]}" "$src/" "$p/" 2>/dev/null | grep -v '^\.d' || true)"
                    if [ -n "$changes" ]; then
                        printf '   %s%-12s%s %s: %s file(s) would change\n' "$C_CYAN" "$c" "$C_RESET" "${p/#$HOME/\~}" "$(printf '%s\n' "$changes" | wc -l)"
                        printf '%s\n' "$changes" | head -8 | sed "s/^/        ${C_GREY}/;s/\$/${C_RESET}/"
                    fi
                fi ;;
        esac
    done < <(_restore_rows "$id" "$@")
}

_restore_row() {  # _restore_row ID n c type path target
    local id="$1" n="$2" c="$3" type="$4" p="$5" target="$6" src tmp
    src="$UR_BACKUP_DIR/$id/files/$n"
    _safe_path "$p" || { log_error "refusing to write outside \$HOME: $p"; return 1; }
    case "$type" in
        missing)
            if [ -L "$p" ]; then rm -f -- "$p" && log_ok "$c: removed link ${p/#$HOME/\~} (did not exist in the backup)"
            elif [ -e "$p" ]; then mv -- "$p" "$p.ultron-moved-$(date +%Y%m%d-%H%M%S)" && log_ok "$c: moved ${p/#$HOME/\~} aside (did not exist in the backup)"
            fi ;;
        file)
            mkdir -p "$(dirname "$p")"
            tmp="$(mktemp "$p.ultron-tmp.XXXXXX")" && cp -a "$src/__file" "$tmp" && mv -f -- "$tmp" "$p" \
                && log_ok "$c: restored ${p/#$HOME/\~}" ;;
        symlink)
            # Recreate the link, then its target's content.
            if [ ! -L "$p" ] || [ "$(readlink "$p")" != "$target" ]; then
                if [ -e "$p" ] && [ ! -L "$p" ]; then mv -- "$p" "$p.ultron-moved-$(date +%Y%m%d-%H%M%S)"; fi
                mkdir -p "$(dirname "$p")"
                ln -sfn -- "$target" "$p" && log_ok "$c: relinked ${p/#$HOME/\~} → ${target/#$HOME/\~}"
            fi
            local real; real="$(readlink -f -- "$p")"
            if [ -f "$src/__file" ]; then
                mkdir -p "$(dirname "$real")"; cp -a "$src/__file" "$real" && log_ok "$c: restored content of ${p/#$HOME/\~}"
            elif [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
                mkdir -p "$real"
                _mirror "$src" "$real" && log_ok "$c: restored content of ${p/#$HOME/\~}"
            fi ;;
        dir)
            if [ -e "$p" ] && [ ! -d "$p" ]; then mv -- "$p" "$p.ultron-moved-$(date +%Y%m%d-%H%M%S)"; fi
            mkdir -p "$p"
            _mirror "$src" "$p" && log_ok "$c: restored ${p/#$HOME/\~}" ;;
    esac
}

_mirror() {  # _mirror SRC DEST — make DEST's contents equal SRC's
    # --checksum: size+mtime can match for a file edited in the same second.
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --checksum --delete "${UR_BACKUP_EXCLUDES[@]}" "$1/" "$2/"
    else
        cp -a "$1/." "$2/"   # no rsync: newer extra files are left in place
    fi
}

# restore_backup ID [COMPONENT…] — the whole guarded restore.
restore_backup() {
    local id="$1"; shift
    local comps=("$@") rows n c type p target ok=0 fail=0
    [ -d "$UR_BACKUP_DIR/$id" ] || { log_error "no backup $id"; return 1; }
    [ "${#comps[@]}" -gt 0 ] || mapfile -t comps < <(backup_components "$id")
    log_step "Restore $id (${comps[*]})"
    backup_verify "$id" || { log_error "Backup is damaged; nothing was restored."; return 1; }
    rows="$(_restore_rows "$id" "${comps[@]}")"
    [ -n "$rows" ] || { log_warn "backup $id has none of: ${comps[*]}"; return 1; }

    echo; ui_info "Changes:"
    local pv; pv="$(restore_preview "$id" "${comps[@]}")"
    if [ -z "$pv" ]; then ui_ok "Nothing differs — already identical to the backup."; return 0; fi
    printf '%s\n' "$pv"
    echo
    if [ "$UR_DRY_RUN" = 1 ]; then log_info "[dry run] nothing restored"; return 0; fi
    if [ "$UR_MODE" = safe ]; then log_warn "SAFE MODE is read-only — switch to standard mode to restore"; return 1; fi
    ui_confirm "Restore these files from $id?" || { log_info "restore cancelled"; return 1; }

    op_begin "restore $id" "${comps[@]}" || return 1
    while IFS=$'\t' read -r n c type p target; do
        if _restore_row "$id" "$n" "$c" "$type" "$p" "$target"; then ok=$((ok + 1)); else fail=$((fail + 1)); log_error "$c: could not restore $p"; fi
    done <<< "$rows"
    op_end
    if [ "$fail" = 0 ]; then log_ok "Restore complete ($ok path(s)). Undo with: ultron-recovery --rollback"
    else log_warn "Restore finished with $fail failure(s); undo with: ultron-recovery --rollback"; fi
    [ "$fail" = 0 ]
}
