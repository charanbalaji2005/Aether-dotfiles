# shellcheck shell=bash
# Test fixture: a throwaway $HOME with a fake dotfiles repo, so tests never
# touch your real configuration, backups, repo or running desktop.

UR_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$*"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
finish() { echo; echo "  $PASS passed, $FAIL failed"; rm -rf "$T"; [ "$FAIL" = 0 ]; }

# setup_home — fresh fake HOME and repo; exports everything ULTRON reads.
setup_home() {
    T="$(mktemp -d "${TMPDIR:-/tmp}/ultron-test.XXXXXX")"
    export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_DATA_HOME="$T/home/.local/share" XDG_CACHE_HOME="$T/home/.cache"
    export UR_REPO_OVERRIDE="$T/repo" UR_NO_PROCESS=1 NO_COLOR=1 UR_NO_CLEAR=1
    unset UR_ASSUME_YES
    local r="$T/repo/config"
    mkdir -p "$HOME/.config" "$r/hypr" "$r/waybar/scripts" "$r/rofi/themes" "$r/kitty" "$r/quickshell/island" "$r/zsh" "$r/tmux" "$r/bash"
    printf 'monitor = , preferred, auto, 1\nsource = ~/.config/hypr/keybinds.conf\nexec-once = true\n' > "$r/hypr/hyprland.conf"
    printf 'bind = SUPER, Return, exec, true\n' > "$r/hypr/keybinds.conf"
    printf 'monitor = , preferred, auto, 1\n' > "$r/hypr/monitors.conf"
    printf '// waybar\n{ "include": ["~/.config/waybar/modules.jsonc"], "modules-left": ["clock"], }\n' > "$r/waybar/config.jsonc"
    printf '{ "clock": { "format": "{:%%H:%%M}" } }\n' > "$r/waybar/modules.jsonc"
    printf 'window#waybar { background: transparent; }\n' > "$r/waybar/style.css"
    printf '#!/usr/bin/bash\necho hi\n' > "$r/waybar/scripts/hello.sh"; chmod +x "$r/waybar/scripts/hello.sh"
    printf 'configuration { modi: "drun"; }\n@theme "themes/base.rasi"\n' > "$r/rofi/config.rasi"
    printf '* { bg: #000000; }\n' > "$r/rofi/themes/base.rasi"
    printf 'font_family monospace\n' > "$r/kitty/kitty.conf"
    printf 'import QtQuick\nItem { }\n' > "$r/quickshell/island/shell.qml"
    printf 'PROMPT="> "\n' > "$r/zsh/.zshrc"
    printf 'set -g mouse on\n' > "$r/tmux/tmux.conf"
    printf '# bash\n' > "$r/bash/aether.bash"
    # Linked like setup-symlinks.sh does; waybar is a real copy (both kinds covered).
    ln -s "$r/hypr" "$HOME/.config/hypr"
    cp -a "$r/waybar" "$HOME/.config/waybar"
    ln -s "$r/rofi" "$HOME/.config/rofi"
    ln -s "$r/kitty" "$HOME/.config/kitty"
    mkdir -p "$HOME/.config/quickshell"; ln -s "$r/quickshell/island" "$HOME/.config/quickshell/island"
    ln -s "$r/zsh/.zshrc" "$HOME/.zshrc"
    printf '# bashrc\n' > "$HOME/.bashrc"
    UR="$UR_TEST_ROOT/recovery.sh"
    BK="$XDG_DATA_HOME/ultron-recovery/backups"
}

ur() { bash "$UR" --no-color "$@"; }           # run ULTRON (no terminal: never prompts)
ury() { UR_ASSUME_YES=1 bash "$UR" --no-color "$@"; }
# By creation time: two backups in the same second sort by label otherwise.
newest_backup() { find "$BK" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2; }
count_backups() { find "$BK" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l; }
