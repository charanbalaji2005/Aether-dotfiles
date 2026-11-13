#!/usr/bin/env bash
# ULTRON RECOVERY — installer. No root needed.
#
#   ./install.sh             install for your user
#   ./install.sh --system    also link /usr/local/bin/ultron-recovery (asks for sudo),
#                            so it is on PATH in every TTY even without ~/.local/bin
#   ./install.sh --dry-run   show what would be done
#
# The application is COPIED to ~/.local/share/ultron-recovery/app (not linked),
# so it keeps working even if this repository or the desktop is broken.
# Backups, logs and reports live in ~/.local/share/ultron-recovery/.
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/ultron-recovery"
APP="$DATA/app"
BIN="$HOME/.local/bin"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/ultron-recovery"
DRY=0; SYSTEM=0
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        --system) SYSTEM=1 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done
run() { if [ "$DRY" = 1 ]; then echo "  [dry run] $*"; else "$@"; fi; }

echo "ULTRON RECOVERY — installing"
for c in bash sha256sum find; do command -v "$c" >/dev/null || { echo "missing required program: $c" >&2; exit 1; }; done
command -v rsync >/dev/null || echo "  note: rsync not found — restores will not remove files added after a backup (sudo dnf install rsync)"
command -v python3 >/dev/null || echo "  note: python3 not found — config validation is limited (sudo dnf install python3)"

# The dotfiles repo this copy came from: the known-good release for repairs.
REPO=""
[ -d "$SRC/../config/hypr" ] && REPO="$(cd "$SRC/.." && pwd)"

run mkdir -p "$DATA/backups" "$DATA/logs" "$DATA/reports" "$DATA/state" "$BIN" "$CONF"
if [ "$DRY" = 0 ]; then
    rm -rf "$APP.new"; mkdir -p "$APP.new"
    cp -a "$SRC/recovery.sh" "$SRC/core" "$SRC/modules" "$SRC/assets" "$SRC/config" "$SRC/README.md" "$APP.new/"
    for f in install.sh uninstall.sh update.sh; do cp -a "$SRC/$f" "$APP.new/"; done
    { echo "# written by install.sh $(date '+%F %T')"; [ -n "$REPO" ] && echo "SOURCE_REPO=$REPO"; echo "INSTALLED_FROM=$SRC"; } > "$APP.new/install.conf"
    chmod +x "$APP.new/recovery.sh" "$APP.new/install.sh" "$APP.new/uninstall.sh" "$APP.new/update.sh"
    rm -rf "$APP.old"; [ -d "$APP" ] && mv "$APP" "$APP.old"
    mv "$APP.new" "$APP" && rm -rf "$APP.old"
else
    echo "  [dry run] copy $SRC → $APP"
fi
echo "  app      $APP"

WRAP="$BIN/ultron-recovery"
if [ "$DRY" = 0 ]; then
    printf '#!/usr/bin/env bash\n# ULTRON RECOVERY launcher (install.sh)\nexec bash "%s/recovery.sh" "$@"\n' "$APP" > "$WRAP.tmp"
    chmod +x "$WRAP.tmp"; mv -f "$WRAP.tmp" "$WRAP"
fi
echo "  command  $WRAP"
[ -f "$CONF/recovery.conf" ] || run cp "$SRC/config/recovery.conf" "$CONF/recovery.conf"
echo "  config   $CONF/recovery.conf"
echo "  data     $DATA (backups, logs, reports)"
[ -n "$REPO" ] && echo "  repo     $REPO (known-good release for repairs)"

if [ "$SYSTEM" = 1 ]; then
    echo "  linking /usr/local/bin/ultron-recovery (sudo)…"
    run sudo ln -sfn "$WRAP" /usr/local/bin/ultron-recovery
fi
case ":$PATH:" in
    *":$BIN:"*) ;;
    *) echo
       echo "  ~/.local/bin is not on your PATH in this shell. Fedora adds it for new"
       echo "  logins; until then run $WRAP, or re-run with --system." ;;
esac
echo
echo "Done. Run: ultron-recovery   (from any directory or a TTY: Ctrl+Alt+F3)"
