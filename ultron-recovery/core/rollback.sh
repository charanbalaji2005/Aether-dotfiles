# shellcheck shell=bash
# ULTRON RECOVERY — operation journal and rollback.
#
# Every change goes through op_begin/op_end: op_begin takes an automatic
# "pre-<op>" backup of the components about to change and writes the journal
# ($UR_STATE_DIR/journal: status, operation, backup id, time). If a run is
# interrupted (Ctrl+C, closed TTY, crash) the journal still says "running" and
# the next start offers to roll back. Rollback restores the journal's backup.

UR_JOURNAL=""
UR_OP_ACTIVE=0

journal_init() { mkdir -p "$UR_STATE_DIR"; UR_JOURNAL="$UR_STATE_DIR/journal"; }

journal_write() {  # journal_write STATUS OP BACKUP
    printf 'status=%s\nop=%s\nbackup=%s\ntime=%s\n' "$1" "$2" "$3" "$(date '+%F %T')" > "$UR_JOURNAL.tmp" && mv -f "$UR_JOURNAL.tmp" "$UR_JOURNAL"
}
journal_get() { sed -n "s/^$1=//p" "$UR_JOURNAL" 2>/dev/null | head -1; }

# op_begin "description" COMPONENT… — back up first, then mark as running.
op_begin() {
    local desc="$1"; shift
    [ "$UR_DRY_RUN" = 1 ] && return 0
    log_info "Automatic backup before changes…"
    backup_create "pre-$(printf '%s' "$desc" | cut -d' ' -f1)" "$@" || { log_error "Pre-recovery backup failed — aborting, nothing changed."; return 1; }
    journal_write running "$desc" "$UR_LAST_BACKUP"
    UR_OP_ACTIVE=1
    trap 'op_interrupted' INT TERM HUP
}

op_end() {
    [ "$UR_DRY_RUN" = 1 ] && return 0
    journal_write done "$(journal_get op)" "$(journal_get backup)"
    UR_OP_ACTIVE=0
    trap - INT TERM HUP
}

op_interrupted() {
    echo
    log_error "Interrupted during: $(journal_get op)"
    journal_write interrupted "$(journal_get op)" "$(journal_get backup)"
    log_warn "Roll back to the state before it with: ultron-recovery --rollback"
    exit 130
}

# On start: an operation that never finished?
journal_check() {
    local st; st="$(journal_get status)"
    case "$st" in running|interrupted) ;; *) return 0 ;; esac
    log_warn "The last recovery did not finish: $(journal_get op) ($(journal_get time))"
    log_warn "Backup taken before it: $(journal_get backup)"
    if ui_interactive && ui_confirm "Roll back to that backup now?"; then rollback_last
    else ui_info "You can roll back later: ultron-recovery --rollback"; fi
}

rollback_last() {
    local id; id="$(journal_get backup)"
    if [ -z "$id" ] || [ ! -d "$UR_BACKUP_DIR/$id" ]; then
        id="$(backup_ids | grep -E -- '-pre-' | head -1)"
    fi
    [ -n "$id" ] || { log_warn "Nothing to roll back: no automatic backup found."; return 1; }
    log_step "Rollback to $id (taken before: $(journal_get op))"
    # restore_backup journals itself with its own pre-restore backup, so a
    # second rollback undoes this one.
    restore_backup "$id"
}
