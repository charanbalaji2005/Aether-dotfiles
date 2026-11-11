# Settings guide

`SUPER+I`, or `aether config get|set section.key value`. Settings live in
`~/.config/aether-shell/config.json` (0600), validated on every load against the schema in
`core/Config.qml`; older files are migrated (`aether config migrate`). Search with the box at the
top of the sidebar. Every section can be reset (Backup & recovery → reset a section; a snapshot
is taken first).

| Section | What it controls | Applied through |
|---|---|---|
| Appearance | dark/light/auto, accent (or from wallpaper), bar/panel transparency, blur | shell (live) |
| Style & palette | 18 palettes, **your own themes** (editor), glass presets, corners, icon & cursor themes | shell; terminals + Hyprland borders via `aether theme apply`; gsettings/qt6ct |
| Effects & motion | quality tier, adaptive quality, shaders, glow, particles, **motion profile**, springs, speed | shell |
| Bar | position, style, height, modules | shell |
| Dock & island | dock position/size/magnification/auto-hide/recent apps/previews; island activities, durations, history; timers | shell |
| Notifications | DND, timeouts, grouping, **per-app normal/priority/mute + sound** | shell |
| Wallpaper / Wallpaper effects | images per monitor; **image / gradient / aurora**; transitions, depth parallax, ambient, schedules, video | shell, mpvpaper |
| Battery | icon family, thresholds, colours, alerts, **automatic power saver** | shell, power-profiles-daemon |
| Lock screen | clock style, widgets, idle lock / **dim** / display off / suspend | shell; hypridle via `aether idle apply` |
| Gestures | touchpad swipes, screen edges | Hyprland (`compat.conf`); shell |
| Automation | rules (multi-action) | shell |
| Profiles | 11 built-in looks, save/share your own | `aether profile` |
| Terminal | default terminal, kitty font/size/opacity/padding/cursor, Zsh profile | `aether theme apply` |
| Keyboard | XKB layouts (validated), switch shortcut, Caps Lock, repeat | `input.conf` + live hyprctl |
| Mouse & touchpad | speed, acceleration, natural scroll, tap-to-click, disable while typing | `input.conf` + live hyprctl |
| Displays | mode (only reported modes), scale; **auto-revert in 15 s unless kept**; profiles per monitor set | `displays.conf` + live hyprctl |
| Workspaces | names, icons, wallpaper per workspace, app → workspace rules, session restore | shell; `apprules.conf`; `aether workspace` |
| Widgets | enable, arrange, grid, installed widgets and their permissions | shell; `aether widget` |
| GPU & rendering | live counters, GPU-pressure thresholds, backend diagnostics | shell; `aether render` |
| Accessibility | UI scale, high contrast, colour-blind status colours, focus rings, reduced motion, 24-h clock | shell |
| Privacy & security | mic/camera in use, clipboard retention & exclusions, sounds, launcher history, security posture, audit log | shell; `aether-clip-store` |
| AI assistant | enable, provider, endpoint, model, local-only, API key (keyring), context & history | `aether ai` |
| Startup apps | XDG autostart entries on/off, add, remove | `~/.config/autostart` |
| Backup & recovery | snapshots, known-good, restore, reset sections, recovery commands | `aether snapshot` |
| Performance | Hyprland visual profile, compositor blur, telemetry interval | `aether performance` |
| Developer | safe mode, internals (tier, shaders, frame times), redacted log | shell; `aether logs` |
| About | version, dependency status | — |
