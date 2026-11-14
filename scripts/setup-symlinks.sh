#!/usr/bin/bash
# Symlinks this repo's configs into their real XDG locations.
# Existing files/directories are backed up (renamed with a timestamp
# suffix) rather than overwritten or deleted.

#
# Options:
#   --dry-run       print what would be linked / moved aside; change nothing
#   --keep-zshrc    leave an existing ~/.zshrc that isn't ours untouched
#   --interface classic|aether
#                   interface to select when none is chosen yet (default: classic);
#                   an existing choice is kept — change it with aether-interface set
#   --only GROUPS   link only these groups (comma-separated; see AETHER_LINK_GROUPS
#                   in scripts/lib/common.sh). They are added to the saved set in
#                   ~/.config/aether-shell/link-groups. Without --only: the saved
#                   set, or every group on a first run.
#
# Every link created and every file moved aside is recorded in
# ~/.local/state/aether/manifest.tsv, which `install.sh --rollback` reads to
# put the originals back.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=SCRIPTDIR/lib/common.sh
. "$REPO_DIR/scripts/lib/common.sh"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
KEEP_ZSHRC=0
INTERFACE=classic
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --keep-zshrc) KEEP_ZSHRC=1 ;;
        --interface) shift; INTERFACE="${1:-}" ;;
        --interface=*) INTERFACE="${1#--interface=}" ;;
        --only) shift; ONLY="${1:-}" ;;
        --only=*) ONLY="${1#--only=}" ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$INTERFACE" in classic|aether) ;; *) echo "--interface must be classic or aether" >&2; exit 2 ;; esac

GROUPS_FILE="$(aether_groups_file)"
if [ -n "$ONLY" ]; then
    SELECTED=" ${ONLY//,/ } "
elif [ -s "$GROUPS_FILE" ]; then
    SELECTED=" $(tr '\n' ' ' < "$GROUPS_FILE") "
else
    SELECTED=" $AETHER_LINK_GROUPS "
fi
for g in $SELECTED; do
    [[ " $AETHER_LINK_GROUPS " == *" $g "* ]] || { echo "Unknown link group: $g (known: $AETHER_LINK_GROUPS)" >&2; exit 2; }
done
want() { [[ "$SELECTED" == *" $1 "* ]]; }

link() {
    local src="$1"
    local dest="$2"

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
            echo "  unchanged  $dest"
        elif [ -L "$dest" ] && [[ "$(readlink -f "$dest" 2>/dev/null || true)" == "$REPO_DIR"/* ]]; then
            echo "  relink     $dest -> $src"
        elif [ -e "$dest" ] || [ -L "$dest" ]; then
            echo "  move aside $dest -> ${dest}${BACKUP_SUFFIX}"
            echo "  link       $dest -> $src"
        else
            echo "  link       $dest -> $src"
        fi
        return 0
    fi

    if [ -L "$dest" ]; then
        local real
        real="$(readlink -f "$dest" 2>/dev/null || true)"
        if [ "$(readlink "$dest")" = "$src" ]; then
            return 0  # already correct: nothing to do, nothing to record
        elif [[ "$real" == "$REPO_DIR"/* ]]; then
            # Owned symlink pointing into this repo; safe to replace
            rm "$dest"
        else
            # Unrelated symlink pointing elsewhere; back it up rather than deleting
            echo "Backing up existing external symlink $dest -> ${dest}${BACKUP_SUFFIX}"
            mv "$dest" "${dest}${BACKUP_SUFFIX}"
            manifest_add backup "$dest" "${dest}${BACKUP_SUFFIX}"
        fi
    elif [ -e "$dest" ]; then
        echo "Backing up existing $dest -> ${dest}${BACKUP_SUFFIX}"
        mv "$dest" "${dest}${BACKUP_SUFFIX}"
        manifest_add backup "$dest" "${dest}${BACKUP_SUFFIX}"
    fi

    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
    manifest_add link "$dest" "$src"
    echo "Linked $dest -> $src"
}

echo "Linking AetherOS dotfiles from $REPO_DIR"
echo

want hypr && link "$REPO_DIR/config/hypr" "$HOME/.config/hypr"
want shell-aether && link "$REPO_DIR/config/quickshell/aether-shell" "$HOME/.config/quickshell/aether-shell"
want island && link "$REPO_DIR/config/quickshell/island" "$HOME/.config/quickshell/island"
want kitty && link "$REPO_DIR/config/kitty" "$HOME/.config/kitty"
# Shells for aether-terminal (zsh is the default; Super+Alt+Return picks one).
want tmux && link "$REPO_DIR/config/tmux" "$HOME/.config/tmux"
# Fedora's ~/.bashrc sources every file in ~/.bashrc.d (link creates it).
want bash && link "$REPO_DIR/config/bash/aether.bash" "$HOME/.bashrc.d/aether.bash"
# Classic interface (Waybar, Rofi, SwayNC, Wlogout, wallust, fastfetch).
# Generated colours live outside these directories, in
# ~/.config/aether-shell/classic, so the repository is never written to.
for app in waybar rofi swaync wlogout wallust fastfetch; do
    want "$app" && link "$REPO_DIR/config/$app" "$HOME/.config/$app"
done
if want zsh; then
    if [ "$KEEP_ZSHRC" -eq 1 ] && [ -e "$HOME/.zshrc" ] && [[ "$(readlink -f "$HOME/.zshrc" 2>/dev/null || true)" != "$REPO_DIR"/* ]]; then
        echo "Keeping your existing ~/.zshrc (--keep-zshrc). AetherOS's version: $REPO_DIR/config/zsh/.zshrc"
    else
        link "$REPO_DIR/config/zsh/.zshrc" "$HOME/.zshrc"
    fi
fi
if want gtk; then
    for v in gtk-3.0 gtk-4.0; do
        link "$REPO_DIR/theme/gtk/$v/settings.ini" "$HOME/.config/$v/settings.ini"
        link "$REPO_DIR/theme/gtk/$v/gtk.css" "$HOME/.config/$v/gtk.css"
    done
fi

if want systemd; then
    for unit in "$REPO_DIR"/system/systemd/*.service; do
        [ -f "$unit" ] || continue
        link "$unit" "$HOME/.config/systemd/user/$(basename "$unit")"
    done
    for dropin in "$REPO_DIR"/system/systemd/*.service.d/*.conf; do
        [ -f "$dropin" ] || continue
        link "$dropin" "$HOME/.config/systemd/user/$(basename "$(dirname "$dropin")")/$(basename "$dropin")"
    done
fi

if want bin; then
    [ "$DRY_RUN" -eq 1 ] || mkdir -p "$HOME/.local/bin"
    for helper in "$REPO_DIR"/scripts/bin/*; do
        [ -f "$helper" ] || continue
        [ "$DRY_RUN" -eq 1 ] || chmod +x "$helper"
        link "$helper" "$HOME/.local/bin/$(basename "$helper")"
    done
fi

if want wallpapers && [ -d "$REPO_DIR/theme/wallpapers" ]; then
    link "$REPO_DIR/theme/wallpapers" "$HOME/.config/aether-shell/wallpapers"
fi

# Record the groups so updates and `aether repair` re-link exactly these.
if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$GROUPS_FILE")"
    { [ -s "$GROUPS_FILE" ] && [ -n "$ONLY" ] && cat "$GROUPS_FILE"; printf '%s\n' $SELECTED; } | awk 'NF && !seen[$0]++' > "$GROUPS_FILE.tmp"
    mv "$GROUPS_FILE.tmp" "$GROUPS_FILE"
fi

# Everything below configures Hyprland: only when its group is deployed.
if ! want hypr; then
    [ "$DRY_RUN" -eq 1 ] && { echo; echo "Dry run: nothing was changed."; }
    exit 0
fi

# Per-machine Hyprland fragments. hyprland.conf sources these, so they must
# exist before Hyprland first starts. They are created empty (comments
# only) and NEVER overwritten here — `aether graphics configure`,
# `aether hyprland compat` and `aether performance hyprland` fill them in.
FRAG_DIR="$HOME/.config/aether-shell/hypr"
ensure_fragment() {
    local path="$1" how="$2"
    if [ ! -e "$path" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then echo "  create     $path"; return 0; fi
        mkdir -p "$(dirname "$path")"
        printf '# Placeholder created by AetherOS. Generate real settings with: aether %s\n' "$how" > "$path"
        manifest_add file "$path" "-"
        echo "Created $path"
    fi
}
ensure_fragment "$FRAG_DIR/hardware.conf" "graphics configure"
ensure_fragment "$FRAG_DIR/compat.conf" "hyprland compat"
ensure_fragment "$FRAG_DIR/profile.conf" "performance hyprland <profile>"
ensure_fragment "$FRAG_DIR/theme.conf" "theme apply"
# kitty.conf includes this; `aether theme apply` fills it in.
ensure_fragment "$HOME/.config/aether-shell/terminal/kitty-theme.conf" "theme apply"
ensure_fragment "$HOME/.config/aether-shell/terminal/kitty-local.conf" "theme apply"
ensure_fragment "$FRAG_DIR/cursor.conf" "theme cursor --set <theme>"
ensure_fragment "$FRAG_DIR/input.conf" "input apply"
ensure_fragment "$FRAG_DIR/displays.conf" "display apply"
ensure_fragment "$FRAG_DIR/apprules.conf" "workspace rules"
ensure_fragment "$FRAG_DIR/interface-theme.conf" "interface set classic"
ensure_fragment "$FRAG_DIR/look.conf" "aether-look apply NAME"
ensure_fragment "$FRAG_DIR/glass.conf" "aether-glass acrylic"
# Yours: own binds, rules and settings, sourced last. Never overwritten; the
# installer imports keybinds from a moved-aside config here (commented out).
if [ ! -e "$FRAG_DIR/user.conf" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then echo "  create     $FRAG_DIR/user.conf"
    else
        mkdir -p "$FRAG_DIR"
        printf '%s\n' "# Your own Hyprland settings: binds, rules, options. Sourced last by" \
            "# ~/.config/hypr/hyprland.conf, so anything here wins. AetherOS never" \
            "# overwrites this file. Check new binds with: aether-bindings check" > "$FRAG_DIR/user.conf"
        manifest_add file "$FRAG_DIR/user.conf" "-"
        echo "Created $FRAG_DIR/user.conf"
    fi
fi
if [ "$DRY_RUN" -eq 0 ] && ! grep -qs aether-glass "$FRAG_DIR/glass.conf"; then
    HOME="$HOME" bash "$REPO_DIR/scripts/bin/aether-glass" init >/dev/null 2>&1 || true
fi

# The active interface. hyprland.conf sources interface.conf, which must
# select one, or Hyprland starts with no bar, launcher or menu keys. An
# existing choice is kept; a missing or placeholder one gets --interface.
CHOICE="$HOME/.config/aether-shell/interface"
if [ ! -s "$CHOICE" ] || ! grep -qs "interfaces/" "$FRAG_DIR/interface.conf"; then
    chosen="$(cat "$CHOICE" 2>/dev/null || true)"
    case "$chosen" in classic|aether) ;; *) chosen="$INTERFACE" ;; esac
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  interface  $chosen (writes $FRAG_DIR/interface.conf)"
    else
        [ -e "$FRAG_DIR/interface.conf" ] || manifest_add file "$FRAG_DIR/interface.conf" "-"
        HOME="$HOME" bash "$REPO_DIR/scripts/bin/aether-interface" set "$chosen" --no-reload --no-services >/dev/null \
            || echo "WARNING: couldn't select the $chosen interface (run: aether-interface set $chosen)" >&2
        echo "Interface: $chosen"
    fi
fi

# First install: start with the "home" look (top bar, island, dock).
if [ "$DRY_RUN" -eq 0 ] && [ "$(cat "$CHOICE" 2>/dev/null)" = classic ] \
    && ! grep -qs '^look=' "$HOME/.config/aether-shell/classic/state.conf"; then
    HOME="$HOME" bash "$REPO_DIR/scripts/bin/aether-look" apply home >/dev/null 2>&1 \
        && echo "Look: home (change with Super+Ctrl+L)" || echo "WARNING: couldn't apply the default look (run: aether-look apply home)" >&2
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo
    echo "Dry run: nothing was changed."
    exit 0
fi

echo
echo "Done. Backups (if any) are alongside the original paths with a $BACKUP_SUFFIX suffix."
echo "Make sure \$HOME/.local/bin is on your PATH (config/zsh/.zshrc already adds it)."
