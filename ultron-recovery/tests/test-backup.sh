#!/usr/bin/env bash
# ULTRON RECOVERY — backup tests (isolated fake $HOME; see helpers.sh).
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/helpers.sh"
echo "test-backup"
setup_home
ln -s style.css "$HOME/.config/waybar/style-link.css"   # a symlink inside a saved tree

ury --backup >/dev/null 2>&1
id="$(newest_backup)"
check "full backup created" test -n "$id"
check "manifest lists every component" grep -q '^# components: hyprland waybar rofi quickshell island kitty shell themes fonts' "$BK/$id/MANIFEST"
check "a linked config is recorded as a symlink with its target" grep -qP "\thyprland\tsymlink\t$HOME/.config/hypr\t$T/repo/config/hypr" "$BK/$id/MANIFEST"
check "a real directory is recorded as dir" grep -qP "\twaybar\tdir\t$HOME/.config/waybar\t" "$BK/$id/MANIFEST"
check "a path that does not exist is recorded as missing" grep -qP "\tthemes\tmissing\t$HOME/.config/gtk-3.0\t" "$BK/$id/MANIFEST"
n="$(grep -P "\thyprland\t" "$BK/$id/MANIFEST" | cut -f1)"
check "the link target's content is saved" test -f "$BK/$id/files/$n/hyprland.conf"
check "checksums cover the saved files" test "$(wc -l < "$BK/$id/SHA256SUMS")" -ge 10
w="$(grep -P "\twaybar\t" "$BK/$id/MANIFEST" | cut -f1)"
check "a symlink inside a saved tree stays a symlink" test -L "$BK/$id/files/$w/style-link.css"

check "integrity check passes on a fresh backup" ur --verify "$id"
echo tampered >> "$BK/$id/files/$n/hyprland.conf"
if ur --verify "$id" >/dev/null 2>&1; then fail "integrity check detects a modified file"; else pass "integrity check detects a modified file"; fi

before="$(count_backups)"
ury --dry-run --backup >/dev/null 2>&1
check "dry-run backup writes nothing" test "$(count_backups)" = "$before"

ury --backup hyprland >/dev/null 2>&1
id2="$(newest_backup)"
check "component backup holds only that component" test "$(grep -v '^#' "$BK/$id2/MANIFEST" | cut -f2 | sort -u)" = hyprland

check "list shows backups" sh -c "bash '$UR' --no-color --list-backups | grep -q '$id2'"
check "preview shows contents" sh -c "bash '$UR' --no-color --preview '$id2' | grep -q 'hyprland'"

# Delete needs confirmation: without a terminal and without --yes it refuses.
if bash -c "source '$UR_TEST_ROOT/core/ui.sh'; source '$UR_TEST_ROOT/core/logging.sh'; UR_BACKUP_DIR='$BK'; UR_DRY_RUN=0; UR_COMPONENTS=(); source '$UR_TEST_ROOT/core/backup.sh'; backup_delete '$id2'" </dev/null >/dev/null 2>&1; then
    fail "deleting a backup without confirmation is refused"
else pass "deleting a backup without confirmation is refused"; fi
check "…and the backup is still there" test -d "$BK/$id2"
bash -c "source '$UR_TEST_ROOT/core/ui.sh'; source '$UR_TEST_ROOT/core/logging.sh'; UR_BACKUP_DIR='$BK'; UR_DRY_RUN=0; UR_ASSUME_YES=1; source '$UR_TEST_ROOT/core/backup.sh'; backup_delete '$id2'" </dev/null >/dev/null 2>&1
check "deleting with confirmation removes it" test ! -d "$BK/$id2"

check "logs are written" sh -c "ls '$XDG_DATA_HOME/ultron-recovery/logs/'ultron-*.log"
finish
