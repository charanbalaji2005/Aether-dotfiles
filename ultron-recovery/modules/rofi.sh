# shellcheck shell=bash
# ULTRON RECOVERY — Rofi: config.rasi, theme syntax and theme references.

ROFI_DIR="$HOME/.config/rofi"

mod_rofi_paths() { echo "$ROFI_DIR"; }
mod_rofi_deps()  { printf '%s\n' "rofi:rofi-wayland"; }

mod_rofi_check() {
    local p0=${#UR_PROBLEMS[@]} f out n=0
    if [ -L "$ROFI_DIR" ] && [ ! -e "$ROFI_DIR" ]; then problem rofi "~/.config/rofi is a broken link → $(readlink "$ROFI_DIR")"; return; fi
    [ -d "$ROFI_DIR" ] || { problem rofi "~/.config/rofi is missing"; return; }
    command -v rofi >/dev/null 2>&1 || problem rofi "Rofi is not installed (sudo dnf install rofi-wayland)"
    [ -f "$ROFI_DIR/config.rasi" ] || problem rofi "launcher configuration config.rasi is missing"
    while IFS= read -r f; do
        n=$((n + 1))
        out="$(validate_rasi "$f" 2>&1)" || problem rofi "${f#"$ROFI_DIR"/}: $out"
    done < <(find -L "$ROFI_DIR" -maxdepth 3 -type f -name '*.rasi' 2>/dev/null)
    local l; while IFS= read -r l; do problem rofi "broken link: ${l/#$HOME/\~}"; done < <(broken_symlinks "$ROFI_DIR")
    while IFS= read -r l; do problem rofi "$l"; done < <(permission_problems "$ROFI_DIR")
    [ "${#UR_PROBLEMS[@]}" -eq "$p0" ] && check_ok "Rofi: $n theme file(s) valid, references resolve"
    return 0
}

mod_rofi_repair() {
    repair_link "$ROFI_DIR" config/rofi
    repair_deleted_tracked config/rofi
    repair_missing_copy "$ROFI_DIR" config/rofi
    repair_broken_links "$ROFI_DIR"
    repair_perms "$ROFI_DIR"
    repair_full_restore rofi config/rofi
}
