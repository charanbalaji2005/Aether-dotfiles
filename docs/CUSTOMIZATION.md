# Customizing AetherOS

Everything below is in **Settings** (`SUPER+I`) and persists in
`~/.config/aether-shell/config.json` (validated on every load; `aether config validate`).
Command-line equivalents are given where they exist.

## Palettes, glass, shape

* **Palettes** (Settings → Style): AetherOS (follows Dark/Light/Auto and your accent), Catppuccin
  Mocha/Latte, Nord, Dracula, Tokyo Night, Gruvbox, Rosé Pine, Everforest, Solarized, One Dark,
  Monokai. The palette also themes kitty, foot, alacritty, ghostty and Hyprland's window borders
  (`aether theme palette <id>`, `aether theme apply`). The single source is
  `config/quickshell/aether-shell/theme/Palettes.js` — add a palette there (every token is
  required; the tests check) and it appears everywhere.
* **Glass**: Opaque, Light, Medium, Heavy, Ultra-clear, Adaptive (more opaque on battery) or
  Custom (slider). Real blur behind panels comes from Hyprland's layer rules.
* **Corner roundness**, accent edges, UI scale (Accessibility).
* **Icons and cursor** (Settings → Style): only installed themes are offered
  (`sudo dnf install papirus-icon-theme`, …); applied to GTK (gsettings), Qt (qt6ct) and
  Hyprland (`aether theme icons --set …`, `aether theme cursor --set … --size 24`).

## Effects and motion

Settings → Effects & motion. *Automatic* quality comes from `aether capabilities` (sysfs only),
power state and measured frame pacing; the reasons are shown live. Eco = no shaders or ambient
work; Balanced = glass and transitions; Ultra = particles and richer lighting. Springs,
reduced motion and an animation-speed multiplier apply to every animation.

## Wallpapers

* Folders scanned: `~/.config/aether-shell/wallpapers`, `~/.local/share/wallpapers[/aetheros]`,
  `~/Pictures/Wallpapers`, `/usr/share/wallpapers`, `/usr/share/backgrounds`.
* **Transitions**: none, fade, zoom, slide, wipe, circle, dissolve, blinds, random.
* **Depth**: put a grey-scale depth map next to an image as `<name>.depth.png` (white = near).
  With parallax on, near pixels move more than far ones. Without a map, the picture moves as one
  plane — the UI says which you have. Depth maps can be made with any monocular depth tool
  offline; AetherOS doesn't generate them and never calls a cloud service.
* **Ambient**: stars, snow, rain, dust (Ultra quality) or aurora; paused under fullscreen apps.
* **Schedules**: every N minutes (favourites first) or day/night.
* **Video** (`mpvpaper`): no audio, hardware decoding where mpv considers it safe, paused while
  locked, under fullscreen windows and (optionally) on battery; static wallpaper underneath.

## Profiles

Settings → Profiles or `aether profile list|apply|save|import|export`. Built-ins: AetherOS
Default, Deep Glass, Minimal, Developer, Productivity, Gaming, Cinematic, Neon, Battery Saver,
Transparent, Classic Linux. A profile file looks like:

```json
{ "aetherProfile": 1, "label": "Mine", "summary": "…", "hyprland": "balanced",
  "config": { "bar": { "style": "floating" }, "appearance": { "palette": "nord", "glassStyle": "heavy" } } }
```

Only known settings with valid values are accepted; unknown fields reject the whole file;
profiles can't carry automation rules or anything executable.

## Automation

Settings → Automation builds rules: **When** (power, battery level, Bluetooth device, app
opened/closed, workspace, monitor, network, time, focus session) **If** (on battery/AC, time
range, battery above/below) **Then** (quality, theme mode, palette, profile, power profile,
wallpaper, launch an app *by desktop id*, workspace, volume, DND, dock, notification). There is
deliberately no "run a command" action. Rules can be tested, toggled, exported and imported
(`aether automation import file.json` — imported rules arrive disabled). A circuit breaker
switches automation off after 20 actions in a minute and tells you why.

## Gestures

* Touchpad (3 fingers): left/right workspaces; up/down any shell action. Written into
  `compat.conf` for your Hyprland version (vertical swipes need 0.51+).
* Screen edges: rest the pointer at an edge for the configured time (default 220 ms); corners
  and fullscreen apps are excluded.

## Terminal and shell

Settings → Terminal: default terminal (`aether-terminal` honours it everywhere), kitty font,
size, opacity, padding and cursor (live reload), and a Zsh profile — minimal, developer (fzf,
zoxide, git helpers), power (+ Starship, fastfetch) or **custom**, which sources a file you
choose (e.g. your Meridian Shell configuration). AetherOS never changes your login shell.

## Dock, island, battery, lock screen

See their Settings sections; every option there is live. Battery icon styles: classic, outline,
filled, segmented, circular, compact, bar, number — with your own colours per state.
