# shellcheck shell=bash
# ULTRON RECOVERY — operation logging.
# One log file per run in $UR_LOG_DIR; every message also goes to the screen
# (through ui.sh) unless UR_QUIET=1.

UR_LOG_FILE=""

log_init() {
    mkdir -p "$UR_LOG_DIR" || return 1
    UR_LOG_FILE="$UR_LOG_DIR/ultron-$(date +%Y%m%d-%H%M%S)-$$.log"
    : > "$UR_LOG_FILE" || return 1
    log_raw "ULTRON RECOVERY $UR_VERSION — session start (mode=$UR_MODE dry_run=$UR_DRY_RUN user=$(id -un) tty=$(tty 2>/dev/null || echo none))"
    # Keep the newest 50 logs.
    find "$UR_LOG_DIR" -maxdepth 1 -name 'ultron-*.log' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | tail -n +51 | cut -d' ' -f2- | xargs -r rm -f
}

log_raw() { [ -n "$UR_LOG_FILE" ] && printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$UR_LOG_FILE"; return 0; }

log_info()  { log_raw "INFO  $*";  ui_info "$*"; }
log_ok()    { log_raw "OK    $*";  ui_ok "$*"; }
log_warn()  { log_raw "WARN  $*";  ui_warn "$*"; }
log_error() { log_raw "ERROR $*";  ui_error "$*"; }
log_step()  { log_raw "STEP  $*";  ui_step "$*"; }

logs_list() { find "$UR_LOG_DIR" -maxdepth 1 -name 'ultron-*.log' -printf '%T@ %f\n' 2>/dev/null | sort -rn | cut -d' ' -f2-; }

logs_show() {  # logs_show [NAME] — page through a log (newest by default)
    local name="${1:-}" f
    [ -n "$name" ] || name="$(logs_list | sed -n 2p)"   # newest *previous* run
    [ -n "$name" ] || name="$(logs_list | head -1)"
    f="$UR_LOG_DIR/$name"
    [ -f "$f" ] || { ui_warn "No logs yet in $UR_LOG_DIR"; return 1; }
    if [ -t 1 ] && command -v less >/dev/null 2>&1; then less -R "$f"; else cat "$f"; fi
}
