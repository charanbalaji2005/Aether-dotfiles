# Architecture

AetherOS Shell follows a strict one-way dependency chain:

```
shell/        (presentation: bars, future launcher/dashboard/etc.)
  ↓
components/   (reusable, theme-aware UI primitives — no system access)
  ↓
services/     (reactive wrappers around one system concern each)
  ↓
Quickshell system-integration modules (Hyprland, Pipewire, UPower, SystemTray, Io)
  ↓
Linux / Hyprland / D-Bus / PipeWire / NetworkManager / UPower
```

`core/` and `theme/` sit outside this chain and are available to every layer: `core/` holds
cross-cutting concerns (logging, the event bus, config, path resolution), `theme/` holds design
tokens (color, type, spacing, motion).

## Why this split

- **UI components never talk to the system directly.** A `Capsule` or `AetherIcon` has no idea
  what PipeWire or Hyprland are. This keeps the component library reusable across every future
  surface (launcher, dashboard, settings) without rewriting anything.
- **Every service exposes an `available` property.** UI modules bind their `visible` to it, so a
  missing dependency (no battery, no `nmcli`, no PipeWire) hides the relevant module instead of
  showing broken or fake data. This is enforced per-service, not bolted on afterward.
- **Services are the only files that import Quickshell's system modules**
  (`Quickshell.Hyprland`, `Quickshell.Services.Pipewire`, `Quickshell.Services.UPower`,
  `Quickshell.Io`). If PipeWire's QML API changes, exactly one file needs to change.

## Current services (Phase 1)

| Service | Wraps | Notes |
|---|---|---|
| `HyprlandService` | `Quickshell.Hyprland` | Reactive workspace/monitor state, `dispatch()` helpers |
| `AudioService` | `Quickshell.Services.Pipewire` | Default sink/source volume + mute, reactive |
| `PowerService` | `Quickshell.Services.UPower` | Battery percentage/state via the UPower display device |
| `NetworkService` | `nmcli` via `Quickshell.Io.Process` | Polled every 5s; no native Quickshell NetworkManager module exists yet, so this talks to the stable `nmcli` CLI rather than parsing D-Bus by hand |
| `ApplicationService` | `.desktop` files via `Quickshell.Io.Process` | Scans XDG app directories itself and parses the Desktop Entry format; no Quickshell module for this exists |
| `NotificationService` | `Quickshell.Services.Notifications` | Freedesktop notifications, urgency-based auto-dismiss |
| `BluetoothService` | `Quickshell.Bluetooth` | Power toggle only in this phase; device list is exposed but not yet wired to a UI |
| `MediaService` | `Quickshell.Services.Mpris` | First connected MPRIS player; play/pause/next/previous |
| `ClipboardService` | `cliphist` via `Quickshell.Io.Process` | No Quickshell clipboard-history module exists; wraps the standard wlroots-ecosystem tool |
| `ScreenshotService` | `grim`/`slurp` via `Quickshell.Io.Process` | Same reasoning as Clipboard — these are the standard tools, not something to reimplement |
| `SessionService` | `systemctl`/`hyprctl` via `Quickshell.Io.Process` | Power actions only; deliberately has no Wayland dependency — lock is delegated via `EventBus.lockRequested()` so the actual lock surface (`Quickshell.Wayland.WlSessionLock`) stays isolated to `shell/lockscreen/` |

Active-window title in the bar is fetched via `hyprctl -j activewindow` (Process) rather than
guessed QML properties, refreshed on every Hyprland IPC event plus a 2s fallback poll — this
avoids relying on internal Quickshell type fields that aren't part of its documented public API.

## Services added in 0.2.0

| Service | Wraps | Notes |
|---|---|---|
| `SystemMonitorService` (rewritten) | `aether telemetry --stream` (one long-lived process) | CPU/RAM/swap/disk/net/GPU/temps/load/uptime + 60-sample histories; process table only while the dashboard asks; falls back to the original `/proc` polling if the backend can't run |
| `HardwareService` | `aether hardware --json` (once, lazily) | static facts for the dashboard/About |
| `ThemeService` | config + `gsettings` + `aether theme accent` + `hyprctl keyword` | dark/light/auto, GTK sync, wallpaper accent, blur override re-applied after config reloads |
| `BrightnessService` | `brightnessctl` | debounced writes, clamped to ≥1 % |
| `NightLightService` | `hyprsunset` | on = process running |
| `PowerProfileService` | `powerprofilesctl` | battery saver / performance |
| `DisplayService` | `hyprctl -j monitors`, `hyprctl keyword monitor`, `nwg-displays` | runtime scale changes, says so in the UI |
| `NetworkService` (extended) | `nmcli` | radio, `--rescan no` polling, on-demand scan, connect/disconnect/forget; terse-field escaping handled |
| `AudioService` (extended) | PipeWire + `wpctl set-default` | device lists, input volume, OSD events |
| `NotificationService` (extended) | NotificationServer | grouping, unread, single expiry timer, config timeouts, local (shell) notifications |

## Bridges (the only places layers meet)

`shell.qml` binds `Colors.{accent,dark,glassOpacity}`, `Motion.{reducedMotion,speed}` and
`ShellState.{activeScreen,onBattery}` from Config/services. `theme/`, `core/` and `components/`
therefore never import `services/`. `PopupPanel` (components) reads `ShellState.activeScreen` to
open on the focused monitor and listens to `EventBus.closePopups` so only one popup is open.

Helpers are always started through `Paths.helper(name, args)` / `Paths.aether(args)`:
`sh -c 'PATH="$HOME/.local/bin:$PATH"; exec "$0" "$@"' name args…` — arguments are positional,
never interpolated into the script.

## Config

`core/Config.qml` uses Quickshell's `FileView` + `JsonAdapter` pattern: a JSON file on disk is
bound directly to QML properties, with automatic reload on external edits and automatic write-back
on property changes (50ms-debounced internally by Quickshell). Defaults live as literal property
values in the adapter, so the file is self-documenting on first creation.

## Theme

`theme/Colors.qml`, `Typography.qml`, `Metrics.qml`, and `Motion.qml` are the only place visual
constants are allowed to live. Components and shell modules reference these tokens; nothing
hardcodes a hex color or a pixel size outside `theme/`.

## Iconography

Rather than depend on an external icon font or SVG set, `components/AetherIcon.qml` draws a small
original vector icon kit directly with `QtQuick.Canvas` (workspace dot, volume states, wifi/
ethernet, battery). This keeps Phase 1 dependency-free; a fuller icon set can replace or extend it
later without changing how components consume `AetherIcon`.

## What's deliberately not here yet

Service lifecycle states beyond `available` (`loading`/`error`/`disabled`), the event bus is wired
but only partially used, and the config engine isn't yet consumed by every module. These are
Phase 2+ items — see PROGRESS.md.
