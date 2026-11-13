# shellcheck shell=bash
# ULTRON RECOVERY — Waybar: JSONC configs, CSS, modules used by layouts,
# includes, scripts, duplicate processes.

WAYBAR_DIR="$HOME/.config/waybar"

mod_waybar_paths() { echo "$WAYBAR_DIR"; }
mod_waybar_deps()  { printf '%s\n' "waybar:waybar" "jq:jq" "playerctl:playerctl"; }

# Modules a layout uses that no config defines.
waybar_undefined_modules() {
    python3 -I - "$WAYBAR_DIR" <<'PY'
import glob, json, os, re, sys
d = sys.argv[1]
def load(p):
    t = re.sub(r"(?m)^\s*//.*$", "", open(p, encoding="utf-8").read())
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", t))
defined = set()
for p in glob.glob(os.path.join(d, "*.jsonc")) + glob.glob(os.path.join(d, "**", "*.jsonc"), recursive=True):
    try: data = load(p)
    except Exception: continue
    for bar in data if isinstance(data, list) else [data]:
        if isinstance(bar, dict): defined.update(k for k, v in bar.items() if isinstance(v, dict))
builtin = {"tray", "clock", "cpu", "memory", "battery", "network", "pulseaudio", "bluetooth", "backlight", "temperature", "disk", "idle_inhibitor", "mpris", "power-profiles-daemon", "hyprland/workspaces", "hyprland/window", "hyprland/language", "hyprland/submap", "wlr/taskbar", "privacy", "keyboard-state", "upower", "wireplumber"}
for p in sorted(glob.glob(os.path.join(d, "layouts", "*.jsonc")) + glob.glob(os.path.join(d, "islands", "*.jsonc"))):
    try: data = load(p)
    except Exception: continue
    for bar in data if isinstance(data, list) else [data]:
        if not isinstance(bar, dict): continue
        for side in ("modules-left", "modules-center", "modules-right"):
            for m in bar.get(side, []):
                if m in defined or m.split("#")[0] in builtin or m.startswith(("group/dock-pins", "custom/launchpad", "image#dock-", "wlr/taskbar#dock")): continue
                print("%s: module %s is not defined" % (os.path.relpath(p, d), m))
PY
}

waybar_duplicates() {  # PIDs of extra Waybars started with the same config
    [ "${UR_NO_PROCESS:-0}" = 1 ] && return 0
    pgrep -a -x waybar 2>/dev/null | awk '{ cfg = ""; for (i = 3; i <= NF; i++) if ($(i-1) == "-c") cfg = $i; n[cfg]++; if (n[cfg] > 1) print $1 }'
}

mod_waybar_check() {
    local p0=${#UR_PROBLEMS[@]}
    if [ -L "$WAYBAR_DIR" ] && [ ! -e "$WAYBAR_DIR" ]; then problem waybar "~/.config/waybar is a broken link → $(readlink "$WAYBAR_DIR")"; return; fi
    [ -d "$WAYBAR_DIR" ] || { problem waybar "~/.config/waybar is missing"; return; }
    command -v waybar >/dev/null 2>&1 || problem waybar "Waybar is not installed (sudo dnf install waybar)"
    local f out n=0
    while IFS= read -r f; do
        n=$((n + 1))
        out="$(validate_jsonc "$f" 2>&1)" || problem waybar "invalid JSONC ${f#"$WAYBAR_DIR"/}: $out"
    done < <(find -L "$WAYBAR_DIR" -maxdepth 3 -type f \( -name '*.jsonc' -o -name config \) 2>/dev/null)
    while IFS= read -r f; do
        out="$(validate_css "$f" 2>&1)" || problem waybar "invalid CSS ${f#"$WAYBAR_DIR"/}: $out"
    done < <(find -L "$WAYBAR_DIR" -maxdepth 3 -type f -name '*.css' 2>/dev/null)
    while IFS= read -r f; do [ -n "$f" ] && problem waybar "$f"; done < <(waybar_undefined_modules)
    while IFS= read -r f; do
        out="$(validate_shell "$f" 2>&1)" || problem waybar "script syntax error ${f#"$WAYBAR_DIR"/}: $(head -1 <<< "$out")"
    done < <(find -L "$WAYBAR_DIR/scripts" -maxdepth 1 -type f -name '*.sh' 2>/dev/null)
    local l; while IFS= read -r l; do problem waybar "broken link: ${l/#$HOME/\~}"; done < <(broken_symlinks "$WAYBAR_DIR")
    while IFS= read -r l; do problem waybar "$l"; done < <(permission_problems "$WAYBAR_DIR")
    local d; for d in $(waybar_duplicates); do problem waybar "duplicate Waybar process (PID $d, same config as another)"; done
    if det_hypr_running && ! pgrep -x waybar >/dev/null 2>&1; then problem waybar "Waybar is not running"; fi
    [ "${#UR_PROBLEMS[@]}" -eq "$p0" ] && check_ok "Waybar: $n config file(s), styles, modules and scripts valid"
    return 0
}

mod_waybar_repair() {
    repair_link "$WAYBAR_DIR" config/waybar
    repair_deleted_tracked config/waybar
    repair_missing_copy "$WAYBAR_DIR" config/waybar
    repair_broken_links "$WAYBAR_DIR"
    repair_perms "$WAYBAR_DIR"
    local d; for d in $(waybar_duplicates); do change "stop duplicate Waybar (PID $d)" kill "$d"; done
    repair_full_restore waybar config/waybar
    if det_hypr_running && ! pgrep -x waybar >/dev/null 2>&1; then restart_component waybar; fi
}
