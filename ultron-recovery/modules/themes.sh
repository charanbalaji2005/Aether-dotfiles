# shellcheck shell=bash
# ULTRON RECOVERY — GTK themes, icons, cursor (component "themes") and fonts &
# wallpapers (component "fonts").

GTK3="$HOME/.config/gtk-3.0/settings.ini"
GTK4="$HOME/.config/gtk-4.0/settings.ini"
THEME_DIRS=("$HOME/.themes" "$HOME/.local/share/themes" /usr/share/themes)
ICON_DIRS=("$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons)

mod_themes_paths() { printf '%s\n' "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; }
mod_themes_deps()  { printf '%s\n' "gsettings:glib2" "fc-list:fontconfig"; }

gtk_get() { sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*(.*)$/\1/p" "$1" 2>/dev/null | tail -1 | sed 's/[[:space:]]*$//'; }
theme_exists() { local d; for d in "${THEME_DIRS[@]}"; do [ -d "$d/$1" ] && return 0; done; case "$1" in Adwaita|Adwaita-dark|HighContrast|HighContrastInverse) return 0 ;; esac; return 1; }
icons_exist()  { local d; for d in "${ICON_DIRS[@]}"; do [ -d "$d/$1" ] && return 0; done; return 1; }
cursor_exists() { local d; for d in "${ICON_DIRS[@]}"; do [ -d "$d/$1/cursors" ] && return 0; done; return 1; }

# themes_bad FILE — "key|value|fallback" for every broken reference in FILE
themes_bad() {
    local f="$1" v fam
    v="$(gtk_get "$f" gtk-theme-name)"; [ -n "$v" ] && ! theme_exists "$v" && echo "gtk-theme-name|$v|Adwaita-dark"
    v="$(gtk_get "$f" gtk-icon-theme-name)"; [ -n "$v" ] && ! icons_exist "$v" && echo "gtk-icon-theme-name|$v|Adwaita"
    v="$(gtk_get "$f" gtk-cursor-theme-name)"; [ -n "$v" ] && ! cursor_exists "$v" && echo "gtk-cursor-theme-name|$v|Adwaita"
    v="$(gtk_get "$f" gtk-font-name)"
    if [ -n "$v" ]; then fam="$(sed -E 's/[[:space:]]+[0-9.]+$//' <<< "$v")"; font_family_installed "$fam" || echo "gtk-font-name|$v|Noto Sans 10"; fi
}

mod_themes_check() {
    local p0=${#UR_PROBLEMS[@]} f row
    for f in "$GTK3" "$GTK4"; do
        if [ ! -f "$f" ]; then problem themes "${f/#$HOME/\~} is missing"; continue; fi
        while IFS='|' read -r k v _; do [ -n "$k" ] && problem themes "${f/#$HOME/\~}: $k '$v' is not installed"; done < <(themes_bad "$f")
    done
    if command -v gsettings >/dev/null 2>&1; then
        row="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")"
        [ -n "$row" ] && ! icons_exist "$row" && problem themes "GNOME setting icon-theme '$row' is not installed"
        row="$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")"
        [ -n "$row" ] && ! cursor_exists "$row" && problem themes "GNOME setting cursor-theme '$row' is not installed"
    fi
    [ "${#UR_PROBLEMS[@]}" -eq "$p0" ] && check_ok "GTK: theme '$(gtk_get "$GTK3" gtk-theme-name)', icons '$(gtk_get "$GTK3" gtk-icon-theme-name)', cursor '$(gtk_get "$GTK3" gtk-cursor-theme-name)' installed"
    return 0
}

mod_themes_repair() {
    local f k v fb
    for f in "$GTK3" "$GTK4"; do
        if [ ! -f "$f" ]; then
            change "create ${f/#$HOME/\~} with Adwaita-dark defaults" sh -c 'mkdir -p "$(dirname "$1")" && printf "%s\n" "[Settings]" "gtk-application-prefer-dark-theme=1" "gtk-theme-name=Adwaita-dark" "gtk-icon-theme-name=Adwaita" "gtk-cursor-theme-name=Adwaita" "gtk-cursor-theme-size=24" "gtk-font-name=Noto Sans 10" > "$1"' sh "$f"
            continue
        fi
        while IFS='|' read -r k v fb; do
            [ -n "$k" ] || continue
            change "${f/#$HOME/\~}: $k '$v' → '$fb' (installed)" sed -i -E "s|^([[:space:]]*$k[[:space:]]*=).*|\\1$fb|" "$f"
        done < <(themes_bad "$f")
    done
    if command -v gsettings >/dev/null 2>&1; then
        v="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")"
        [ -n "$v" ] && ! icons_exist "$v" && change "GNOME icon-theme '$v' → Adwaita" gsettings set org.gnome.desktop.interface icon-theme Adwaita
        v="$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")"
        [ -n "$v" ] && ! cursor_exists "$v" && change "GNOME cursor-theme '$v' → Adwaita" gsettings set org.gnome.desktop.interface cursor-theme Adwaita
    fi
    return 0
}

# ── fonts & wallpapers ────────────────────────────────────────────────
STATE_CONF="$HOME/.config/aether-shell/classic/state.conf"
mod_fonts_paths() { printf '%s\n' "$HOME/.config/fontconfig" "$STATE_CONF"; }
mod_fonts_deps()  { printf '%s\n' "fc-cache:fontconfig" "swww:swww" "magick:ImageMagick"; }

wallpaper_dirs() { printf '%s\n' "$HOME/Pictures/Wallpapers" "$HOME/.config/aether-shell/wallpapers" "${UR_REPO:+$UR_REPO/theme/wallpapers}"; }
first_wallpaper() {
    local d
    while IFS= read -r d; do
        [ -d "$d" ] || continue
        find -L "$d" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -1 | grep . && return 0
    done < <(wallpaper_dirs)
    return 1
}

mod_fonts_check() {
    local p0=${#UR_PROBLEMS[@]} f w
    while IFS= read -r f; do case "$f" in *MISSING) problem fonts "font ${f%%:*} is not installed" ;; esac; done < <(det_fonts)
    if [ -f "$STATE_CONF" ]; then
        w="$(sed -n 's/^wallpaper=//p' "$STATE_CONF" | tail -1)"
        if [ -n "$w" ] && [ ! -f "$w" ]; then problem fonts "wallpaper file is gone: ${w/#$HOME/\~}"; fi
    fi
    first_wallpaper >/dev/null || problem fonts "no wallpapers found (~/Pictures/Wallpapers or the dotfiles' theme/wallpapers)"
    command -v swww >/dev/null 2>&1 || command -v hyprpaper >/dev/null 2>&1 || command -v swaybg >/dev/null 2>&1 \
        || problem fonts "no wallpaper program installed (swww, hyprpaper or swaybg)"
    [ "${#UR_PROBLEMS[@]}" -eq "$p0" ] && check_ok "Fonts installed; wallpaper ${w:+$(basename "$w") }present"
    return 0
}

mod_fonts_repair() {
    local fonts; fonts="$(det_fonts)"
    if grep -q 'JetBrainsMono Nerd Font: MISSING' <<< "$fonts"; then
        if [ -n "${UR_REPO:-}" ] && [ -x "$UR_REPO/scripts/install-fonts.sh" ]; then
            change "install JetBrainsMono Nerd Font into ~/.local/share/fonts (download, checksum-verified)" "$UR_REPO/scripts/install-fonts.sh"
        else
            ui_info "Install JetBrainsMono Nerd Font: https://www.nerdfonts.com/ (unpack into ~/.local/share/fonts)"
        fi
    fi
    grep -q 'Noto Sans: MISSING' <<< "$fonts" && ui_info "Install Noto Sans: sudo dnf install google-noto-sans-fonts"
    grep -q 'Noto Color Emoji: not installed' <<< "$fonts" && ui_info "Install emoji: sudo dnf install google-noto-color-emoji-fonts"
    change "rebuild the font cache" fc-cache -f
    local w new
    if [ -f "$STATE_CONF" ]; then
        w="$(sed -n 's/^wallpaper=//p' "$STATE_CONF" | tail -1)"
        if [ -n "$w" ] && [ ! -f "$w" ] && new="$(first_wallpaper)"; then
            change "wallpaper → ${new/#$HOME/\~} (the old one is gone)" sed -i "s|^wallpaper=.*|wallpaper=$new|" "$STATE_CONF"
            command -v aether-wall >/dev/null 2>&1 && det_hypr_running && change "apply the wallpaper" aether-wall restore
        fi
    fi
}
