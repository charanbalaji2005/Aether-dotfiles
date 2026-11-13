#!/usr/bin/env bash
# ULTRON RECOVERY — restore, rollback, interrupted recovery and repair tests
# (isolated fake $HOME and repo; see helpers.sh).
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/helpers.sh"
echo "test-restore"
setup_home
W="$HOME/.config/waybar"
H="$T/repo/config/hypr"

ury --backup >/dev/null 2>&1
good="$(newest_backup)"

# Damage: edit, delete, add (real dir) and edit through a link (repo target).
echo 'broken {' > "$W/style.css"
rm "$W/modules.jsonc"
echo extra > "$W/added-later.txt"
echo 'bogus = 1' >> "$H/hyprland.conf"

# Dry run changes nothing.
ury --dry-run --restore "$good" >/dev/null 2>&1
check "dry-run restore leaves files alone" grep -q 'broken {' "$W/style.css"
check "dry-run restore takes no backup" test "$(count_backups)" = 1

# Safe mode refuses.
ury --safe --restore "$good" >/dev/null 2>&1
check "safe mode does not restore" grep -q 'broken {' "$W/style.css"

# Without a terminal or --yes, a restore is not confirmed.
ur --restore "$good" >/dev/null 2>&1
check "restore without confirmation changes nothing" grep -q 'broken {' "$W/style.css"

# The real restore.
ury --restore "$good" >/dev/null 2>&1
check "edited file restored" grep -q 'background: transparent' "$W/style.css"
check "deleted file restored" test -f "$W/modules.jsonc"
check "file added after the backup removed from the mirror" test ! -e "$W/added-later.txt"
check "file edited through a symlink restored in its target" sh -c "! grep -q bogus '$H/hyprland.conf'"
check "the config link itself is intact" test -L "$HOME/.config/hypr"
check "a pre-restore backup was taken" sh -c "ls '$BK' | grep -q -- '-pre-restore'"

# Rollback undoes that restore (back to the damaged state).
ury --rollback >/dev/null 2>&1
check "rollback brings back the state before the restore" grep -q 'broken {' "$W/style.css"
check "rollback brings back the file added later" test -f "$W/added-later.txt"
# …and a second rollback undoes the rollback.
ury --rollback >/dev/null 2>&1
check "a second rollback undoes the first" grep -q 'background: transparent' "$W/style.css"

# A link replaced by a directory: the restore relinks and moves the dir aside.
rm "$HOME/.config/rofi"; mkdir "$HOME/.config/rofi"; echo mine > "$HOME/.config/rofi/personal.rasi"
ury --restore "$good" rofi >/dev/null 2>&1
check "replaced link is a link again" test "$(readlink "$HOME/.config/rofi")" = "$T/repo/config/rofi"
check "the directory that was in the way is kept, not deleted" sh -c "ls -d '$HOME/.config/'rofi.ultron-moved-* >/dev/null && grep -q mine '$HOME/.config/'rofi.ultron-moved-*/personal.rasi"

# A damaged backup is never restored.
n="$(grep -P "\twaybar\t" "$BK/$good/MANIFEST" | cut -f1)"
echo 'evil' > "$W/style.css"
echo tamper >> "$BK/$good/files/$n/style.css"
ury --restore "$good" waybar >/dev/null 2>&1
check "a backup that fails its integrity check is not restored" grep -q evil "$W/style.css"

# Interrupted recovery: the journal says "running"; --rollback restores its backup.
ury --backup waybar >/dev/null 2>&1
snap="$(newest_backup)"
mv "$BK/$snap" "$BK/${snap%-manual}-pre-repair"; snap="${snap%-manual}-pre-repair"
sed -i 's/^# id: .*/# id: '"$snap"'/' "$BK/$snap/MANIFEST"
printf 'status=running\nop=repair waybar\nbackup=%s\ntime=now\n' "$snap" > "$XDG_DATA_HOME/ultron-recovery/state/journal"
echo 'half-written' > "$W/style.css"
ury --rollback >/dev/null 2>&1
check "rollback after an interrupted recovery restores its backup" grep -q evil "$W/style.css"

# Repairs: missing link, non-executable script, missing sourced file.
echo 'window#waybar { background: transparent; }' > "$W/style.css"
rm "$HOME/.config/kitty"
chmod -x "$W/scripts/hello.sh"
ury --dry-run --repair kitty >/dev/null 2>&1
check "dry-run repair does not relink" test ! -e "$HOME/.config/kitty"
ury --repair kitty >/dev/null 2>&1
check "repair relinks a missing config" test "$(readlink "$HOME/.config/kitty")" = "$T/repo/config/kitty"
ury --repair waybar >/dev/null 2>&1
check "repair makes a script executable again" test -x "$W/scripts/hello.sh"
rm "$H/keybinds.conf"
ury --repair hyprland >/dev/null 2>&1
check "repair recreates a missing sourced file so Hyprland can start" test -f "$H/keybinds.conf"
check "repairs back up first" sh -c "ls '$BK' | grep -q -- '-pre-repair'"
chmod -x "$W/scripts/hello.sh"
ury --safe --repair waybar >/dev/null 2>&1
check "safe-mode repair only recommends (script stays non-executable)" test ! -x "$W/scripts/hello.sh"

finish
