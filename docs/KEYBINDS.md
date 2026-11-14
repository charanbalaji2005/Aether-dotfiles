# Keybinds

`SUPER` is the Windows/Command key. Shared keys are in `config/hypr/keybinds.conf`;
each interface adds its own in `config/hypr/interfaces/<interface>.conf`. In the classic
interface **`SUPER + H`** opens a searchable list of every key, read from those files (the
`#: description` after each bind), so it is always current.

## Classic interface (default)

| Keys | Action |
|---|---|
| `SUPER + D` | Applications |
| `SUPER + R` | Run a command |
| `SUPER + O` | Window switcher |
| `SUPER + SHIFT + E` | Find files |
| `SUPER + H` | Keybinding reference (this list) |
| `SUPER + V` | Clipboard history |
| `SUPER + .` | Emoji picker |
| `SUPER + ALT + C` | Calculator |
| `SUPER + S` | Web search |
| `SUPER + A` | Quick settings |
| `SUPER + I` | Wi-Fi |
| `SUPER + B` | Bluetooth |
| `SUPER + M` | Audio devices |
| `SUPER + T` | Theme and colours |
| `SUPER + SHIFT + T` | Dark / light |
| `SUPER + CTRL + L` | Looks (bar + launcher + colours) |
| `SUPER + CTRL + B` | Waybar layout and style |
| `SUPER + ALT + B` | Hide / show Waybar |
| `ALT + Print` | Capture menu |
| `SUPER + E` | File manager |
| `SUPER + Y` | Yazi (terminal file manager) |
| `SUPER + SHIFT + Esc` | System monitor |
| `SUPER + F12` | System summary (fastfetch) |
| `SUPER + SHIFT + Enter` | Drop-down terminal |
| `SUPER + Z` | Zoom in / out |
| `SUPER + SHIFT + C` | Colour picker (copies the hex code) |
| `SUPER + N` | Notification centre |
| `SUPER + SHIFT + N` | Do not disturb |
| `SUPER + W` | Wallpaper picker |
| `SUPER + SHIFT + W` | Random wallpaper |
| `SUPER + CTRL + W` | Next wallpaper |
| `SUPER + Esc` | Power menu |
| `SUPER + L` | Lock |
| `SUPER + SHIFT + G` | Game mode (no effects) |
| `SUPER + ALT + N` | Night light |
| `SUPER + CTRL + R` | Reload the desktop |
| `SUPER + G` | Group / ungroup windows |
| `SUPER + CTRL + Tab` | Next window in group |
| `Print` | Screenshot: whole screen |
| `SHIFT + Print` | Screenshot: area / window |
| `SUPER + SHIFT + S` | Screenshot: area |
| `SUPER + Print` | Screenshot: active window |
| `CTRL + Print` | Screenshot in 5 s |
| `SUPER + SHIFT + A` | Screenshot and annotate (swappy) |
| `AudioRaiseVolume` | Volume up |
| `AudioLowerVolume` | Volume down |
| `AudioMute` | Mute |
| `AudioMicMute` | Mute microphone |
| `MonBrightnessUp` | Brightness up |
| `MonBrightnessDown` | Brightness down |

## Shared (both interfaces)

| Keys | Action |
|---|---|
| `SUPER + Enter` | Terminal |
| `SUPER + SHIFT + D` | VS Code in a terminal's directory |
| `SUPER + Q` | Close window |
| `SUPER + SHIFT + Q` | Exit Hyprland |
| `SUPER + F` | Fullscreen |
| `SUPER + SHIFT + F` | Maximise |
| `SUPER + Space` | Float / tile window |
| `SUPER + C` | Centre floating window |
| `SUPER + P` | Pseudo-tile |
| `SUPER + J` | Swap split direction |
| `SUPER + Tab` | Previous workspace |
| `SUPER + left` | Focus left |
| `SUPER + right` | Focus right |
| `SUPER + up` | Focus up |
| `SUPER + down` | Focus down |
| `ALT + Tab` | Cycle windows |
| `SUPER + SHIFT + left` | Move window left |
| `SUPER + SHIFT + right` | Move window right |
| `SUPER + SHIFT + up` | Move window up |
| `SUPER + SHIFT + down` | Move window down |
| `SUPER + CTRL + SHIFT + left` | Resize (hold) |
| `SUPER + mouse:272` | Drag window |
| `SUPER + mouse:273` | Drag to resize |
| `SUPER + 1` | Workspace 1–10 (keys 1…0) |
| `SUPER + SHIFT + 1` | Send window to workspace 1–10 |
| `SUPER + CTRL + right` | Next workspace |
| `SUPER + CTRL + left` | Previous workspace (by number) |
| `SUPER + `` | Scratchpad |
| `SUPER + SHIFT + `` | Send window to scratchpad |
| `SUPER + ALT + left` | Focus monitor left |
| `SUPER + ALT + right` | Focus monitor right |
| `SUPER + ALT + SHIFT + left` | Move workspace to left monitor |
| `SUPER + ALT + SHIFT + right` | Move workspace to right monitor |
| `SUPER + SHIFT + R` | Record screen (start/stop) |
| `SUPER + ALT + R` | Record area (start/stop) |
| `AudioPlay` | Play / pause |
| `AudioNext` | Next track |
| `AudioPrev` | Previous track |

Workspaces 1–10 use `SUPER + 1…0`; `SUPER + SHIFT + 1…0` sends the window there.

## Aether interface (Quickshell shell)

| Keys | Action |
|---|---|
| `SUPER + D` | Application launcher |
| `SUPER + A` | Control centre |
| `SUPER + N` | System dashboard |
| `SUPER + ,` | Notification centre |
| `SUPER + V` | Clipboard history |
| `SUPER + I` | Settings |
| `SUPER + B` | Bluetooth manager |
| `SUPER + W` | Wallpaper picker (right-click a wallpaper: this display only) |
| `SUPER + SHIFT + W` | Random wallpaper |
| `SUPER + CTRL + W` | Next wallpaper |
| `SUPER + Escape` | Power menu |
| `SUPER + L` | Lock |
| `SUPER + O` | Overview (all monitors, workspaces, windows) |
| `SUPER + SHIFT + O` | Exposé: windows of the focused app |
| `SUPER + Z` | Show / hide the dock |
| `SUPER + X` | System centre |
| `SUPER + G` | Window layouts |
| `SUPER + U` | Expand / collapse the Dynamic Island |
| `SUPER + Y` | Assistant (when enabled) |
| `SUPER + SHIFT + Y` | Arrange desktop widgets |
| `SUPER + SHIFT + R` | Start / stop screen recording (full screen) |
| `SUPER + ALT + R` | Start / stop screen recording (region) |
| `Print` | Screenshot (full) |
| `SHIFT + Print`, `SUPER + SHIFT + S` | Screenshot (region) |

Inside the launcher, prefixes: `/report` searches your files · `>command` runs a command in your
terminal (only on Enter) · plain text also matches Settings and AetherOS actions.

Inside the overview: type to search · arrows + `Enter` focus · `Delete` (twice) close ·
`1`–`9` switch workspace · drag a window onto another workspace (or "New workspace") · double-click
a workspace title to rename it · `Esc`.

Touchpad: three-finger swipe left/right switches workspaces; up/down are configurable
(Settings → Gestures). `tests/hyprland/test_config_syntax.sh` checks that no key combination is
bound to two different commands.

Inside the launcher: type to search · `↑ ↓` · `PgUp PgDn` · `Home End` · `Enter` launch ·
`Tab / Shift+Tab` categories · `Ctrl+F` (or right-click) toggle favourite · `Esc`.

## Applications

| Keys | Action |
|---|---|
| `SUPER + Return` | Terminal (kitty) |
| `SUPER + E` | File manager |
| `SUPER + SHIFT + D` | VS Code in the current directory |

## Windows

| Keys | Action |
|---|---|
| `SUPER + Q` | Close window |
| `SUPER + F` / `SUPER + SHIFT + F` | Fullscreen / maximise |
| `SUPER + Space` | Toggle floating |
| `SUPER + C` | Centre floating window |
| `SUPER + P` | Pseudo-tile |
| `SUPER + J` | Toggle split |
| `SUPER + ←↑→↓` | Move focus |
| `SUPER + SHIFT + ←↑→↓` | Move window |
| `SUPER + CTRL + SHIFT + ←↑→↓` | Resize (hold to repeat) |
| `ALT + Tab` | Cycle windows |
| `SUPER + drag (left / right)` | Move / resize with the mouse |
| `SUPER + SHIFT + Q` | Exit Hyprland |

## Workspaces & monitors

| Keys | Action |
|---|---|
| `SUPER + 1…0` | Go to workspace 1–10 |
| `SUPER + SHIFT + 1…0` | Move window to workspace |
| `SUPER + Tab` | Previous workspace |
| `SUPER + CTRL + ← / →`, `SUPER + scroll` | Previous / next workspace |
| `SUPER + `` ` `` | Toggle scratchpad |
| `SUPER + SHIFT + `` ` `` | Move window to scratchpad |
| `SUPER + ALT + ← / →` | Focus monitor |
| `SUPER + ALT + SHIFT + ← / →` | Move workspace to monitor |
| Three-finger swipe | Switch workspace (syntax per Hyprland version, see HYPRLAND_GUIDE.md) |

## Hardware keys

Volume, mute, mic mute, brightness (with on-screen display), play/pause/next/previous.

## Bar mouse actions

| Module | Click | Right / middle click | Scroll |
|---|---|---|---|
| Launcher | launcher | settings | |
| Workspaces | switch | | previous/next |
| Clock, stats | dashboard | | |
| Network, battery, sliders | control centre | | |
| Bluetooth | device manager | toggle power | |
| Volume | mute | | volume |
| Microphone | mute | | input gain |
| Bell | notification centre | toggle Do Not Disturb | |
| Media | play/pause | | next/previous track |
| Tray icon | activate | secondary activate (middle) | |
