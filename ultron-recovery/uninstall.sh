#!/usr/bin/env bash
# ULTRON RECOVERY — uninstaller.
#
#   ./uninstall.sh           remove the application and the command; KEEP backups,
#                            logs, reports and your config
#   ./uninstall.sh --purge   also delete backups, logs, reports and config (asks first)
set -euo pipefail

DATA="${XDG_DATA_HOME:-$HOME/.local/share}/ultron-recovery"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/ultron-recovery"
WRAP="$HOME/.local/bin/ultron-recovery"
PURGE=0
[ "${1:-}" = --purge ] && PURGE=1
case "${1:-}" in -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

echo "ULTRON RECOVERY — uninstalling"
rm -rf -- "$DATA/app" && echo "  removed $DATA/app"
[ -f "$WRAP" ] && grep -q 'ULTRON RECOVERY launcher' "$WRAP" && rm -f -- "$WRAP" && echo "  removed $WRAP"
if [ -L /usr/local/bin/ultron-recovery ] && [ "$(readlink /usr/local/bin/ultron-recovery)" = "$WRAP" ]; then
    echo "  /usr/local/bin/ultron-recovery points here; removing it (sudo)…"
    sudo rm -f /usr/local/bin/ultron-recovery || echo "  could not remove it — do it later: sudo rm /usr/local/bin/ultron-recovery"
fi

if [ "$PURGE" = 1 ]; then
    n="$(find "$DATA/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    printf '  Delete %s backup(s), all logs and reports in %s, and %s? [y/N] ' "$n" "$DATA" "$CONF"
    read -r a || a=""
    case "$a" in
        y|Y|yes) rm -rf -- "$DATA" "$CONF"; echo "  purged" ;;
        *) echo "  kept $DATA and $CONF" ;;
    esac
else
    echo "  kept backups, logs and reports in $DATA (delete with --purge)"
fi
echo "Done."
