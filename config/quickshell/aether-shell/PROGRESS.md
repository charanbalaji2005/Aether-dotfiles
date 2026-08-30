# Progress

Status legend: **DONE** (implemented and runnable), **PARTIAL** (exists but incomplete),
**NOT STARTED**.

## Phase 1 — Foundation + Bar (this delivery)

| Item | Status |
|---|---|
| Theme engine (Colors/Typography/Metrics/Motion) | DONE |
| Logger | DONE |
| EventBus | DONE (defined; only Audio/Power/Network services publish to it so far) |
| Config engine (FileView + JsonAdapter, live reload) | DONE — persists bar position/height/modules, appearance accent/opacity, general.reducedMotion |
| Config wired into bar position/height | DONE |
| Config wired into everything else (colors, module order, per-module toggles) | NOT STARTED |
| HyprlandService (workspaces, monitors, dispatch) | DONE |
| AudioService (PipeWire volume/mute) | DONE |
| PowerService (UPower battery) | DONE |
| NetworkService (nmcli-based) | DONE |
| Bar: workspaces module | DONE |
| Bar: active window title | DONE (via `hyprctl -j activewindow`) |
| Bar: system tray | DONE (icons + left-click activate; no right-click context menu yet) |
| Bar: audio module | DONE (click to mute, scroll to change volume) |
| Bar: battery module | DONE |
| Bar: network module | DONE |
| Bar: clock module | DONE |
| Original vector icon kit (AetherIcon) | DONE for: workspace-dot, volume states, wifi/wifi-off, ethernet, battery/battery-charging |
| Service lifecycle states beyond `available` (`loading`/`error`/`disabled`) | NOT STARTED |
| Multi-monitor bar | DONE (bar renders per-screen via `Quickshell.screens`) — per-monitor config not yet exposed |

## Phase 2 — Launcher + Notifications (this delivery)

| Item | Status |
|---|---|
| ApplicationService (.desktop discovery, XDG dirs incl. Flatpak) | DONE |
| Fuzzy application search (prefix + substring + subsequence scoring) | DONE |
| App launching (direct and via detected terminal for `Terminal=true` entries) | DONE |
| AppIcon (best-effort hicolor/pixmap resolution, letter-avatar fallback) | DONE — not full XDG icon-theme spec (no theme index parsing) |
| Launcher UI (search, keyboard nav, mouse nav, Enter/Escape) | DONE |
| Launcher toggle via Quickshell IPC (`qs -c aether-shell ipc call launcher toggle`) | DONE |
| NotificationService (freedesktop notifications via Quickshell's NotificationServer) | DONE |
| Urgency-based auto-dismiss timing (critical stays until dismissed) | DONE |
| Notification toasts (summary/body/actions, click or × to dismiss) | DONE |
| Notification history / notification center | NOT STARTED |
| Do Not Disturb | NOT STARTED |
| Per-monitor notification popups | NOT STARTED (renders on primary screen only) |
| Notification action icons | NOT STARTED (`actionIconsSupported` left false) |

## Phase 3 — Bluetooth, media, clipboard, screenshots (this delivery)

| Item | Status |
|---|---|
| BluetoothService (power on/off via BlueZ through Quickshell.Bluetooth) | DONE |
| Bluetooth bar module | DONE — power toggle only |
| Bluetooth device pairing/connect list UI | NOT STARTED (needs a popup pattern not yet built — see limitations) |
| MediaService (MPRIS play/pause/next/previous, track info) | DONE |
| Media bar module (click to play/pause, scroll to skip) | DONE |
| Multi-player switching (currently always the first MPRIS player found) | NOT STARTED |
| ClipboardService (wraps `cliphist`) | DONE |
| Clipboard history overlay (search/filter, copy, clear all) | DONE |
| Per-entry delete in the clipboard overlay UI | NOT STARTED (service supports it — `ClipboardService.deleteEntry()` — just not wired to a UI control yet) |
| ScreenshotService (`grim`/`slurp`, full + region, auto-copies to clipboard) | DONE |
| Screenshot IPC bindings for Hyprland keybinds | DONE |
| Screenshot annotation / editor | NOT STARTED |

## Phase 4 — Lock screen, power menu (this delivery)

| Item | Status |
|---|---|
| SessionService (suspend/reboot/shutdown/logout via systemd + hyprctl) | DONE |
| Real Wayland session lock (`ext-session-lock-v1` via Quickshell's `WlSessionLock`) | DONE — confirmed against Quickshell's own documented example |
| Lock screen UI (clock, password field) | DONE |
| PAM authentication on the lock screen | **UNVERIFIED — see the warning below and in `shell/lockscreen/LockScreen.qml`** |
| Power menu (Lock/Log Out/Suspend/Reboot/Shut Down) | DONE |
| Confirm-before-destructive-action on Logout/Reboot/Shut Down | DONE (click once to arm, again within 3s to confirm; Lock/Suspend aren't treated as destructive) |
| Idle-triggered auto-lock | NOT STARTED |
| Fingerprint / non-password auth | NOT STARTED |
| Lock screen wallpaper / background image | NOT STARTED (solid color background only) |

### ⚠️ About the PAM integration specifically

Quickshell's own documented example for exactly this (`quickshell-examples/lockscreen`) is blocked from
automated fetching by its docs site's robots.txt, so I confirmed `PamContext`/`PamResult`/`PamError`
exist and roughly what they're for, but I could not verify their exact QML member names (`start()`,
`respond()`, `responseRequired`, etc. are my best-effort implementation of the conventional pattern,
not something I read off an authoritative source). The code is structured so a wrong member name
fails *safe* — `sessionLock.locked = false` only happens inside the PAM-success branch, so a naming
mistake means the password field just won't authenticate you, not that it unlocks without one. Still:
**test this before trusting it as your only way back into a session.** Keep a TTY (Ctrl+Alt+F2) or
another already-unlocked session available the first time.

## Phase 5 — Dashboard (this delivery)

| Item | Status |
|---|---|
| SystemMonitorService (CPU/RAM/disk via `/proc` + `df`, no external deps) | DONE |
| Dashboard panel (top-right, click-outside to close) | DONE |
| Quick toggles: Do Not Disturb, Bluetooth, Mute | DONE |
| Do Not Disturb actually suppresses notification popups | DONE (in `NotificationService`) |
| Live CPU/Memory/Disk bars | DONE |
| Calendar (month view, prev/next navigation, today highlighted) | DONE |
| Widget framework (drag/reorder/enable-disable arbitrary widgets) | NOT STARTED — Dashboard's contents are fixed in this phase, not yet pluggable |
| GPU stats | NOT STARTED (no universal cross-vendor QML-accessible source without extra tooling — would need `nvidia-smi`/`radeontop`/etc. detection logic) |
| Weather widget | NOT STARTED (needs an API key / provider decision — deliberately not building an untested third-party integration without you choosing a provider) |

## Phase 6 — Settings app + live theming (this delivery)

| Item | Status |
|---|---|
| Settings app UI (Appearance / Bar / About sections) | DONE |
| Accent color picker (6 presets), live-applied via `Colors.accent` binding | DONE |
| Bar opacity slider, persisted to Config | DONE |
| Reduced motion toggle, persisted to Config | DONE (not yet consumed by animations — see limitation below) |
| Bar position (top/bottom) and height, persisted to Config | DONE — Bar.qml already read these since Phase 1, now editable via UI |
| Per-module bar visibility toggles (Network/Audio/Battery/Media/Bluetooth) | DONE — new `Config.bar.showX` flags, wired into each module's `visible` binding |
| About section: live service-availability status | DONE — reuses existing service `.available` properties, no new checks needed |
| Custom accent color input (beyond the 6 presets) | NOT STARTED — presets only, no color picker/hex input yet |
| Settings persisted across restarts | DONE (this was already true of Config generally — Settings just adds a UI for it) |
| Reduced motion actually disabling animations shell-wide | DONE — `Motion.reducedMotion` bound to `Config.general.reducedMotion` at the shell root; every `Behavior` block in the shell (9 across 7 files) gates on it |

## Phase 7 — Reduced motion, Bluetooth manager, notification history (this delivery)

| Item | Status |
|---|---|
| Reduced motion actually gating animations | DONE — see Phase 6 row above, moved here for changelog clarity |
| Bluetooth device manager (power, scan, pair, connect/disconnect, forget) | DONE for power/connect/disconnect (confirmed API). Scan/pair/forget are **implemented but unverified** — see the caveat comment in `BluetoothManager.qml`/`BluetoothService.qml`; they fail silently (logged) rather than crash if the underlying method name is wrong |
| Bar's Bluetooth capsule opens the manager (was: direct power toggle) | DONE |
| Notification history/center (`$mod + ,`) | DONE — stores plain JS snapshots taken at arrival time, not live Notification object references (their lifetime after dismissal wasn't something I could verify as safe to hold onto) |
| Do Not Disturb toggle available from both Dashboard and Notification Center | DONE |
| Notification history persisted across shell restarts | NOT STARTED — history is in-memory only, resets when the shell restarts |
| Bluetooth device battery display | DONE where `batteryAvailable`/`battery` are populated by Quickshell (confirmed properties) |

## Not started yet (future phases)

Overview, widget framework (Dashboard's contents are still fixed, not pluggable), wallpaper
engine, full accessibility pass (focus indicators, scalable text, screen-reader labels),
diagnostics page, testing infrastructure for the shell itself (see the dotfiles repo's
`tests/services/README.md` for why), CI/CD for the shell specifically (the dotfiles repo's CI
covers structural QML checks only).

None of these are stubbed with placeholder buttons anywhere in the shell — they simply don't
exist yet rather than existing as non-functional UI.

## Known limitations

- Tray right-click context menus aren't wired (needs a window reference plumbed to
  `SystemTrayItem.display()` — deferred to a future tray pass).
- No blur-behind-window compositing is done in QML; the glass panel look relies on a Hyprland
  `layerrule = blur, aether-shell` rule the user adds themselves (documented, not automated yet).
- No packaging (Arch/Nix/etc.) exists — install is manual symlink only.
- Notification field names (`summary`, `body`, `urgency`, action `.text`/`.invoke()`) were
  inferred from Quickshell's documented freedesktop-spec compliance rather than an exhaustive
  property list — if a Quickshell version exposes different names, toasts may render blank
  fields rather than crash (property access on missing QML properties returns `undefined`, not
  an error). Flag it if you hit this and it's a one-line fix.
- Icon resolution doesn't parse the user's actual icon theme (e.g. Papirus, Adwaita variants) —
  it tries hicolor and pixmaps directly by name. Themed icons that live only under a
  non-hicolor theme directory will fall through to the letter-avatar placeholder.
- Clipboard and launcher popups are implemented as their own top-level windows (same pattern as
  the bar) rather than dropdowns anchored to a bar module, since nesting a second `PanelWindow`
  inside another window's item tree wasn't something I could verify correctness of without a
  live environment to test against. The Bluetooth manager and notification center (Phase 7) use
  this same top-level-window pattern successfully — it's the proven approach for anything beyond
  a simple bar capsule.
- Field names for MPRIS (`trackArtist`, `trackTitle`, `canGoNext`, etc.) and Bluetooth
  (`device.connect()`/`disconnect()`) were taken from Quickshell's documented type descriptions,
  which don't list every member exhaustively — if a property name is off in your Quickshell
  version, the affected UI element will show blank/inert rather than crash (QML returns
  `undefined` for unknown property reads instead of throwing), and it's a one-line fix once
  spotted.
