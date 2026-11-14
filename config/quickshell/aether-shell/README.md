# AetherOS Shell

A Hyprland desktop shell built on [Quickshell](https://quickshell.org), designed for AetherOS.
Independently designed and implemented — see [THIRD_PARTY.md](./THIRD_PARTY.md) for a note on
provenance and every runtime dependency this project talks to.

**Status: Phase 1 (Foundation + Bar).** This is the first of several implementation passes.
See [PROGRESS.md](./PROGRESS.md) for exactly what works today and what's still to come — nothing
below is marked done unless it actually runs.

## What's implemented right now

- Theme engine (colors, typography, spacing/radius, motion tokens) — original design system
- Config engine — JSON config at `~/.config/aether-shell/config.json`, hot-reloaded, auto-created
- Logger + EventBus core services
- `HyprlandService` — reactive workspaces/monitors via Quickshell's native Hyprland IPC integration
- `AudioService` — PipeWire volume/mute via Quickshell's Pipewire integration
- `PowerService` — battery state via UPower
- `NetworkService` — connection state via `nmcli`
- A working top bar: workspaces, active window title, system tray, media, Bluetooth, network,
  audio, battery, clock
- An application launcher: fuzzy search over installed `.desktop` entries, keyboard + mouse nav
- A notification popup system for freedesktop desktop notifications
- MPRIS media controls (play/pause, skip) for whatever's currently playing
- Bluetooth power toggle (full device management is a later phase — see PROGRESS.md)
- Clipboard history (via `cliphist`) with search/filter and copy-to-restore
- Screenshots (full screen or region select) via `grim`/`slurp`, auto-copied to clipboard
- A real lock screen (Wayland `ext-session-lock-v1`, not a fake overlay) with PAM authentication
- A power menu (Lock/Log Out/Suspend/Reboot/Shut Down) with confirm-to-execute on destructive actions
- A dashboard: Do Not Disturb/Bluetooth/Mute toggles, live CPU/RAM/disk stats, a calendar
- A settings app: accent color, bar opacity/position/height, per-module bar visibility — all
  persisted and live-applied, no restart needed

Every service degrades gracefully and hides its module if the underlying system isn't available
(no Hyprland, no battery, no PipeWire, no `nmcli`, no `cliphist`, no `grim`) instead of crashing
or showing fake data.

**About the lock screen:** it uses Quickshell's real Wayland session-lock protocol, which only
wlroots-based compositors support — Hyprland does, GNOME and current KWin don't. The PAM
authentication piece is implemented to my best understanding of Quickshell's API but I could not
verify its exact method/property names against an authoritative source (see PROGRESS.md for
detail). Test it — lock, then confirm you can unlock — before relying on it.

## Hyprland keybinds

Add to `hyprland.conf`:

```
bind = SUPER, D, exec, qs -c aether-shell ipc call launcher toggle
bind = SUPER, V, exec, qs -c aether-shell ipc call clipboard toggle
bind = SUPER, Escape, exec, qs -c aether-shell ipc call powermenu toggle
bind = SUPER, L, exec, qs -c aether-shell ipc call sessionlock lock
bind = , Print, exec, qs -c aether-shell ipc call screenshot full
bind = SHIFT, Print, exec, qs -c aether-shell ipc call screenshot region
bind = SUPER, N, exec, qs -c aether-shell ipc call dashboard toggle
```

## Requirements

- [Hyprland](https://hyprland.org)
- [Quickshell](https://quickshell.org) ≥ 0.2
- Qt6 with QtQuick, QtQuick.Layouts, QtQuick.Window
- PipeWire + WirePlumber (for audio)
- UPower (for battery, laptops only)
- NetworkManager with `nmcli` on `PATH` (for network status)
- BlueZ (for the Bluetooth toggle; optional, module hides itself if unavailable)
- An MPRIS-compatible media player (optional; media module hides itself if none is running)
- `cliphist` + `wl-clipboard` on `PATH` (optional, for clipboard history)
- `grim` + `slurp` on `PATH` (optional, for screenshots)
- A font with regular/semibold weights — defaults to "Manrope", falls back to system sans-serif.
  JetBrains Mono is referenced for future monospace/diagnostic UI but nothing in Phase 1 requires it.

## Install / run

```sh
mkdir -p ~/.config/quickshell
ln -s "$(pwd)/aether-shell" ~/.config/quickshell/aether-shell
qs -c aether-shell
```

To run it as your Hyprland bar, add to `hyprland.conf`:

```
exec-once = qs -c aether-shell
```

## Configuration

On first run, `~/.config/aether-shell/config.json` is created with defaults (bar position, height,
accent color). Edit it and the bar updates live — no restart needed. There's no settings GUI yet;
that's a later phase (see PROGRESS.md).

## License

Copyright (C) 2026 Neelampalli Charan Balaji. Licensed under GPL-3.0-or-later.

Licensed under GPL-3.0-or-later — see [LICENSE](./LICENSE).
