# Changelog

Dates reflect when each phase was built. Known limits of a release are listed in
[README.md](README.md#status) and [docs/HARDWARE.md](docs/HARDWARE.md).

## 1.0.0 — 2026-11-14

### Added — installer
- **Onboarding installer** (`./install.sh` on a terminal): logo, version and copyright, a
  system summary (distribution, kernel, CPU, GPUs and their drivers, memory, display, desktop,
  Hyprland/Waybar/Quickshell versions, login manager, disk), prerequisites, and a main menu —
  Start installation · Update · Restore previous configuration · Installation information.
  Dialogs use whiptail; `--no-tui`/`AETHER_UI=plain` gives numbered prompts.
- **First-run support screen** with the repository link; it can open the repository in the
  browser or star it with a signed-in GitHub CLI — only when chosen. Shown once.
- **Components**: Hyprland, Waybar, Dynamic Island, macOS Dock, Rofi Launchpad, Kitty, Zsh,
  GTK themes and icons, wallpapers, fonts, notifications, Bluetooth, audio, SDDM login theme,
  application configs (and the Quickshell shell for the aether interface). Presets:
  Recommended, Select all, Deselect all, Custom. Without menus: `--components a,b`,
  `--preset`, `--list-components`. Unselected components keep your existing configuration.
- **Packages per component** (`packages/fedora/components.tsv`, `?optional`, `a|b`
  alternatives); optional GPU userspace helpers only for a driver already in use — drivers are
  never installed or replaced.
- **Live progress**: numbered steps `[n/N]`, spinner and elapsed time, download bar with
  percentage, speed and size (DNF, git, curl), the latest log lines, ✔/✖ per step; every
  question is asked before the run so it proceeds unattended.
- **Preservation**: keybinds from a replaced Hyprland config are saved (commented out) in
  `~/.config/aether-shell/hypr/user.conf`, its scripts in
  `~/.config/aether-shell/user/hypr-scripts`, replaced wallpapers in `~/Pictures/Wallpapers`.
- **Validation and report**: per-component checks (Hyprland, Waybar layouts, Rofi themes,
  Quickshell, SwayNC, required programs), broken symlinks, duplicate startup (exec-once,
  enabled units, running daemons) → `~/.local/state/aether/reports/`.
- **Final screen**: installed / skipped / failed components, backup, log and report; restart
  the Hyprland desktop, reboot (asked, never automatic), view the log or report.
- `update.sh` and `restore.sh` at the top level; `install.sh --restore [--archive FILE]`.
- Run as a single downloaded file, the installer clones the repository's `release-final`
  branch over HTTPS, shows the exact commit (and its signature, if any) and runs it only
  after an explicit yes.
- `~/.config/aether-shell/hypr/user.conf`: your own Hyprland settings, sourced last.

### Changed — installer
- Steps are isolated: a failing component is reported and the rest still installs; an
  interrupted run resumes per component.
- `setup-symlinks.sh --only GROUPS`; updates and `aether repair` re-link the saved selection.
- The Quickshell build toolchain is planned only for the Quickshell shell.
- License notice: copyright Neelampalli Charan Balaji, GPL-3.0-or-later (the contradictory
  "All rights reserved" was removed).

### Added — classic interface
- **Classic interface** (now the default; `aether-interface set aether` restores the Quickshell
  shell): Waybar (7 layouts, 4 styles), Rofi launcher and menus (Wi-Fi, Bluetooth, audio,
  clipboard, emoji, calculator, web search, keybinding reference, theme, quick settings),
  SwayNC control centre, Wlogout with original icons (Rofi fallback), Hyprlock, Hypridle
  (suspend only on battery), swww wallpapers with previews, per-monitor wallpapers, slideshow
  and video wallpapers (still frame on battery), Pyprland drop-down terminal and zoom,
  screenshots with annotation, OSD for volume/brightness, night light, game mode, keep-awake,
  airplane mode.
- `aether-colors`: one palette for every app from wallust, the wallpaper (built-in) or six
  presets, with enforced contrast and automatic fallback.
- `aether-interface` (status / set / doctor), `install.sh --interface`, `--no-fonts`;
  checksum-pinned Nerd Font installer (`scripts/install-fonts.sh`).
- Package lists accept alternatives (`rofi-wayland|rofi`).
- Tests: `tests/classic/` (real GTK 3 and Rofi parsers, layouts, configs, isolated-home
  lifecycle) and `tests/python/test_classic_colors.py`; installer test now covers an existing
  Waybar config being preserved and restored, and alternative package selection.

- **Looks** (`aether-look`, Super+Ctrl+L): lofi, frost, desk, orbit, retro, pixel, blocks and
  default — bar layout + style + launcher + palette + gaps/rounding in one step; 7 new Waybar
  layouts and styles (incl. bottom docks with `wlr/taskbar`), 3 new launchers (grid, side,
  strip), 3 new palettes (lagoon, slate, synth); presets can name their accent colour;
  `aether-fetch` (fastfetch with the wallpaper as its picture).

- **Identity looks** anime (new default), cyber, glass, emerald, retrowave, devpro; palettes
  dusk, neon, emerald; Waybar styles anime and cyber.
- **Lock screen designs** (`aether-lock`): signature, anime, minimal, typography, cyber, glass,
  retro; each look sets one.
- **Wallpaper gallery**: title, search, favourites, recent first, sub-folder categories,
  slideshow key.
- `aether-bindings list|search|check`; Super+Ctrl+P visual profile menu.

- **Home look** (new default): top bar, an island that expands on hover with now-playing art,
  title and controls (event-driven MPRIS), and a macOS-style dock with real app icons
  (`aether-dock`) and a full-screen **Launchpad** (Super+Alt+D) that pops in (Hyprland layer
  animation). **Mono** look and palette. Lock designs **stacked** and **island**.

- **Island** now sizes itself: time pill → music card (rounded art, title, artist, controls,
  upcoming events from khal/calcurse or the date) → volume/brightness level bar for 2 s.
- **AetherOS Settings** window (`aether-settings`, Super+Ctrl+S): looks, appearance, bar,
  island, dock, lock screen, wallpaper, keyboard shortcuts, system — wired to the helpers;
  modern design: profile header, searchable sidebar with coloured tiles, grouped cards,
  palette strips on looks, toast results.
- Dock: more first-run apps (browser, files, terminal, editor, chat, music, notes, calendar,
  monitor, graphics — each only if installed).

- Island shows **only while useful** (music, volume/brightness) as its own Waybar, so it no
  longer covers windows; setting "Only show while something is happening".
- Dock shows **running apps** (with their icons) beside the pins; Launchpad has **Apps / Open
  windows** tabs and reports errors instead of silently doing nothing (its `fullscreen` theme
  property didn't work on Rofi's Wayland build).
- Home top bar redesigned: one floating glass strip, animated workspace pills, shortcuts and
  Launchpad buttons. Bars slide in, the launcher pops in (Hyprland layer animations).
- **aether-keys** (Super+H): keyboard-shortcut window with key caps by category, searchable.

- `tools/preview-lockscreen.py`: preview any lock design without locking; island design's
  clock/date spacing and avatar fixed after previewing.

- **Control Centre** (Super+A): frosted-glass panel with 22 real controls (layer-shell, blurred),
  and an editor in Settings with a control gallery, Add/Remove/reorder and live preview.
- Control Centre redesigned like a phone control centre (connectivity card, coloured toggles,
  tall fill sliders, round buttons, album art).
- **Frosted glass by default** (`aether-glass`, acrylic): stronger blur, translucent windows
  (opaque exceptions for browsers, video, games, editors), translucent Rofi/SwayNC/bar/panels.

### Changed
- Keybinds split into shared keys and per-interface files (`config/hypr/interfaces/`).
- RPM/PKGBUILD: Quickshell is optional (Suggests/optdepends) instead of required.
- `aether` session commands (launcher, lock, reload…) and `aether repair` follow the active interface.

### Fixed
- Wallpaper picker listed only favourites when there was no history yet (a failing `tac` under
  `set -e -o pipefail` ended the list) — found by rendering it; the test now runs the script
  with its real error settings and was confirmed to fail on the old code.
- Wallpaper picker keys Alt+F/Alt+S collided with Rofi's own bindings (Rofi showed an error
  instead of the gallery); now Alt+V/Alt+C/Alt+P, with a test against Rofi's defaults.
- Rofi launcher: the "AetherOS" banner and sidebar never rendered (custom containers need a
  `box-` name and textboxes take `content`, not `str`) — found by rendering it with real Rofi.
- Default Waybar workspaces drew blank buttons; plain dots are used now.
- `exec-once = hyprpolkitagent` never started the agent on Fedora (it is in /usr/libexec);
  the systemd unit is used, with the libexec path as fallback.
- The QML runtime suite loaded fixture images from /tmp that nothing created (it only passed
  where they were left over); the harness now generates them.

## 1.0.0-rc.2 — 2026-11-11

Release hardening — no new features. Status: **ready for private testing**; publisher identity
(`tools/set-publisher.sh`) and the hardware checklist (docs/HARDWARE.md) are required before a
public release candidate.

### Security
- Lock screen verified against Quickshell's PAM API source (password over a private pipe to a
  forked PAM helper). Fixed: `pam.start()` failure was ignored (field stuck for 30 s); in-flight
  conversations are aborted on teardown. Optional hyprlock backend (Settings → Lock screen).
- Widgets: third-party widgets off by default; explicit trust pinned to a SHA-256 of the files;
  install ≠ trust; safe mode and `aether recover` disable them; stricter static checks.

### Fixed
- Packaged entry points (`/usr/bin/aetheros-dotfiles-setup` …) crashed: 11 scripts located
  themselves through the symlink.
- GPU: widgets showed unavailable values as 0; hybrid dGPU detail counters never reached the
  dashboard; System Centre read a non-existent field; NVML session never closed; NVML errors
  now explain the fix.
- Network state polled with 4 nmcli processes every 5 s → event-driven (`nmcli monitor`).
- Installer, uninstall, diagnostics and layouts no longer hide failures (`|| true` audit).
- RPM Source0/`%setup` didn't match the tarball; PKGBUILD skipped checksums; duplicate wallpaper.

### Verification added
- Quickshell API conformance checker against v0.2.0 and v0.3.2 (minimum Quickshell: 0.2.0,
  enforced by the installer); duplicate-assignment check; reproducible tarball; RPM built with
  rpmbuild + rpmlint; PKGBUILD package() exercised; actionlint; release metadata; symlinked
  entry points; skipped suites reported as skipped.

### CI
- Releases require lint + all tests + strict metadata; Fedora job runs the full suite and an RPM
  build with no suppressed failures; artifacts: tarball, checksum, PKGBUILD, RPM, SRPM.

## 1.0.0-rc.1 — 2026-11-11

Release candidate for 1.0. Feature-complete and tested in CI-style environments; **not yet
validated on physical hardware** — see docs/HARDWARE.md for the checklist that gates 1.0.0.

### GPU and rendering
- NVIDIA telemetry through NVML (ctypes, no subprocess, no root): usage, VRAM, temperature,
  power and power limit, clocks, per-GPU processes with names. `nvidia-smi` remains the fallback.
- Hybrid laptops: the dGPU is queried only while a detail view is open, through a session closed
  after each sample, so it can runtime-suspend (the 0.2 polling kept it awake).
- GPU-pressure policy with hysteresis (VRAM/load thresholds) steps effects down and back up.
- New "performance" quality tier; `aether render` diagnostics (files only; `--probe` optional).

### Desktop
- Assistant (`SUPER+Y`): Ollama or OpenAI-compatible, streaming, local-only by default, keys in
  the keyring, proposals from a validated action registry that run only on click, audit log.
- Desktop widgets with a permission-filtered API, static capability checks, 7 built-ins,
  `aether widget install|remove`, edit mode (`SUPER+SHIFT+Y`).
- Dynamic Island 2.0: microphone/camera in use (PipeWire), network and VPN, screenshots,
  clipboard, messages from scripts (`aether island post`), history, durations.
- Launcher: Settings and action results, file search (`/`), terminal commands (`>`, Enter only),
  search history (never commands or paths).
- Settings: 11 new sections (28 total) and search — keyboard (XKB-validated), mouse & touchpad,
  displays (auto-revert unless kept, profiles per monitor set), workspaces (names, icons,
  per-workspace wallpaper, app rules, session restore), widgets, GPU & rendering, privacy &
  security, AI assistant, startup apps (XDG autostart), backup & recovery, developer.
- Custom colour themes (editor + `aether themes`), 6 new palettes (OLED, Midnight, Aurora, Frost,
  Minimal, High Contrast); motion profiles; gradient and aurora wallpapers.
- Notifications: per-app normal/priority/mute and sounds. Clipboard privacy: password-manager
  secrets never stored, excluded apps, scheduled clearing. Automatic power saver, idle dimming.
- Dock window previews and recent apps; automation rules with multiple actions, startup and
  profile triggers.

### Publishing
- `tools/set-repo-url.sh`, generated `docs/CLI_REFERENCE.md`, issue/PR templates, release
  workflow, code of conduct, `.editorconfig`/`.gitattributes`, PUBLISHING.md, new guides
  (HARDWARE, GPU_OPTIMIZATION, SETTINGS, AI_ASSISTANT, AUTOMATION, WIDGETS, TESTING).

### Fixed (found by the new tests)
- Widget scanner: comment stripping removed `//` inside strings, hiding `"file:///…"` URLs.
- Redaction missed single-quoted `api_key: '…'`.
- Schema generator truncated string defaults containing `//` (URLs).
- Assistant registry was missing the `widgets` settings section (contract test).

### Upgrading from 0.3
`./install.sh --update`. Settings migrate to schema 4 (a snapshot is taken first). The
clipboard service now runs `aether-clip-store`; re-enable user services if you manage them by hand.

## 0.3.0 — 2026-11-11

The production and experience release: a real installer lifecycle, a recovery story, an
original animation/graphics engine, and the desktop surfaces built on it.

### Installer, recovery, configuration
- `install.sh --check | --dry-run | --install | --update | --uninstall | --rollback`, install
  modes, per-package availability checks against enabled repositories (DNF5/DNF4), consent-gated
  COPR (`repos.conf`), resumable steps, lock file, logs, and an install manifest that rollback
  uses to move originals back. `scripts/bootstrap.sh` and `scripts/update.sh` now wrap it.
- One managed-path list (`scripts/lib/common.sh`) for setup, backup, restore and uninstall
  (they had drifted apart).
- `aether-shell-safe.service`: started automatically when the shell crash-loops.
- Config schema generated from `Config.qml`; validation, migrations (v1→v3), import/export,
  `aether config get/set`; config.json is written 0600.
- Snapshots with SHA-256 manifests, preview diffs, last-known-good, undo-before-restore;
  `aether recover`, `aether safe-mode`.
- The shell re-acquires the session lock after a crash while locked
  (`misc:allow_session_lock_restore`).

### Engine
- Physics springs (interruptible, idle-free), native spring behaviours, staggered reveals,
  gesture velocity tracking, frame-pacing measurement and adaptive quality.
- Five original GLSL shaders (glass, glow, aurora, transitions, depth parallax) with fallbacks;
  `scripts/build-shaders.sh`; `aether capabilities` (sysfs only, never wakes a dGPU).
- Design system: 12 palettes shared with terminals and Hyprland borders, glass presets, UI and
  corner scaling, high-contrast and colour-blind modes, elevation.

### Desktop
- New: Dynamic Island, dock, overview / exposé, system centre, smart window layouts, edge
  gestures, configurable touchpad swipes, automation engine, desktop profiles, screen
  recording (`aether-record`), timers and focus sessions, audio visualiser (cava, output only).
- Wallpaper engine: 7 transitions, depth-map parallax, ambient particles/aurora, schedules,
  favourites, mpvpaper video with lifecycle rules.
- Lock screen: four clock styles, blurred wallpaper + aurora, media/battery/notification count,
  failure feedback; hardened PAM flow (see Fixed).
- Battery: 8 icon families, thresholds, per-state colours, alerts with hysteresis.
- Settings: 11 new sections (17 total). Icon/cursor theme switching, terminal settings, Zsh
  profiles (incl. a custom file, e.g. a Meridian Shell config), `aether-terminal`.
- Media: player selection prefers the playing player; artwork; seek.
- Hyprland: version-selected rules (`rules.conf` / `rules-v2.conf`), compat regenerated at
  login when Hyprland changes, palette borders, cursor fragment, new keybinds.

### Fixed
- Lock screen: a PAM *error* left the password field disabled forever; responses relied on
  `this` in a signal handler. Now explicit, with a 30 s timeout; password cleared after each try.
- Zsh plugins were loaded from Arch paths and never worked on Fedora.
- kitty `allow_remote_control yes` let escape sequences control the terminal → `socket-only`.
- Dashboard and system centre would have fought over the process-list flag (now ref-counted).
- `snap()` in early spring code leaked the animation counter (caught by the runtime tests).
- A `focus` property in the depth-image component collided with `Item.focus` (FINAL) and would
  have prevented the wallpaper from loading (caught by the runtime tests).

### Tests
- New: runtime QML suite (Qt Quick + OpenGL on Mesa/Xvfb, pixel assertions), security
  invariants, installer lifecycle, 46 desktop backend tests, rule/keybind/contract checks.

## 0.2.0 — Hardware-aware desktop upgrade (2026-11-09)

### Added — AetherOS CLI backend (`lib/aether/`, Python 3.9+, standard library only)
- `aether system | hardware | cpu | gpu`: OS/kernel/session/Secure Boot; CPU vendor, model,
  cores/threads, frequency, governor, scaling driver, EPP, boost, temperature (coretemp/k10temp/
  zenpower), VT-x/AMD-V + KVM; GPUs from PCI sysfs (vendor, model via lspci/pci.ids, PCI IDs,
  kernel driver, DRM nodes, boot GPU, runtime-PM state, integrated/discrete/virtual); storage;
  battery health. `--watch` live views, `--json` everywhere.
- `aether graphics detect | drivers | verify`: Mesa version, OpenGL renderer (eglinfo/glxinfo,
  flags llvmpipe), Vulkan ICDs/devices, VA-API decode/encode per render node, NVIDIA module/
  version/build-for-kernel/signer, akmods failure logs, akmods key enrolment, nvidia_drm modeset/
  fbdev, GBM backend, explicit-sync capability, suspend services, persistence daemon, CUDA,
  nouveau conflicts; per-vendor codec recommendations (RPM Fusion freeworld / intel-media-driver
  / libva-nvidia-driver). PASS/WARN/FAIL with fixes.
- `aether graphics install-nvidia`: driver branch chosen from the chip code name (Turing+ →
  akmod-nvidia; Maxwell/Pascal/Volta → 580xx when available, else a warning; Kepler/Fermi/
  unknown → refused). Checks Fedora, existing driver, stale kernel, RPM Fusion; Secure Boot key
  generation + MOK enrolment steps (never disables Secure Boot); prints the plan, needs typed
  confirmation, records every command + package diff, prints rollback commands. `--dry-run`.
- `aether graphics configure`: writes `~/.config/aether-shell/hypr/hardware.conf` with only the
  environment the hardware needs; never forces NVIDIA on hybrid laptops; explicit compositor GPU
  choice via `--primary` (AQ_DRM_DEVICES with by-path symlinks). Diff + backup + confirm.
- `aether gpu run <cmd>`: PRIME offload to the discrete GPU (NVIDIA or Mesa `DRI_PRIME`).
- `aether performance`: power profiles via powerprofilesctl; Hyprland profiles quality /
  balanced / low-latency / battery written to `profile.conf`.
- `aether hyprland [verify|compat]`: `Hyprland --verify-config` + `hyprctl configerrors`;
  version-specific syntax (touchpad gestures changed in 0.51) generated for the installed version.
- `aether diagnostics` (saved report), `aether repair` (missing fragments, invalid config.json,
  broken links, exec bits, disabled units — with `--dry-run`), `aether theme accent|mode`.
- `aether telemetry --stream`: one long-lived JSON-lines process for the shell. Never wakes a
  runtime-suspended dGPU; one `nvidia-smi -lms` child on NVIDIA desktops; `null` + reason for
  unavailable metrics; optional process table.
- Logging to `~/.local/state/aether/aether.log`.

### Added — Shell
- Design system: dark + light palettes (dark/light/auto by time), accent presets + hex input +
  accent from wallpaper, configurable panel transparency, motion speed multiplier on top of
  reduced motion, new tokens (surface, onAccent, scrim…), ~45 new original icons.
- Components: PopupPanel (shared animated popup: open/close transitions, click-outside, Esc,
  opens on the focused monitor, closes other popups), GlassPanel sheen/gradient, IconButton,
  ToggleTile, StatTile, Sparkline graphs, SegmentedControl, SettingRow, SectionLabel, Spinner.
- Panel: floating / full / dock styles, launcher button, centred clock, CPU/RAM/GPU chips with
  temperatures, network speed, microphone, notification bell with unread badge + DND, control
  centre button; animated workspace pills with hover numbers and scroll switching.
- Control centre (`SUPER+A`): Wi-Fi (radio, scan, connect with password, disconnect, forget),
  Bluetooth, DND, night light (hyprsunset), dark mode, microphone, battery saver + performance
  (powerprofilesctl), volume/mic/brightness sliders, output/input device selection (wpctl),
  media mini-player, displays (scale, nwg-displays), wallpaper, lock/power/settings.
- Dashboard rewritten as a system monitor: CPU/RAM/GPU/network history graphs, temperatures,
  VRAM, disk, per-thread load, top processes (sampled only while open), uptime, hardware, calendar.
- Launcher: favourites, recents, categories, keyword/description search, open/close animation,
  PgUp/PgDn/Home/End/Tab/Ctrl+F; apps launched detached.
- Notifications: grouped history, per-item/per-app clear, unread count, persisted DND (critical
  still shows), configurable timeouts and max visible, animated toasts with icons/images.
- OSD for volume, microphone and brightness. Settings expanded to six sections.
- Wallpapers: per-display, blur (rendered once), GIF playback gated on AC/reduced motion,
  decoded at screen size.

### Added — Hyprland / install
- Generated per-machine fragments (hardware/compat/profile) sourced from `hyprland.conf`;
  `recovery.conf` minimal session; refined animation curves, shadows, blur, smart gaps, vfr;
  explicit layer namespaces for blur rules; new binds (control centre, region screenshot,
  scratchpad, resize, multi-monitor, ALT+Tab).
- `bootstrap.sh`: confirms package installs, optional package list with skip-unavailable,
  backup before linking, hardware detection, fragment generation, NVIDIA plan offer, validation.
- `update.sh` validates after pulling; `backup.sh` includes config.json and fragments.
- Docs: INSTALLATION, DRIVER_GUIDE, NVIDIA_GUIDE, HYPRLAND_GUIDE, TEST_REPORT; README,
  ARCHITECTURE, TROUBLESHOOTING, KEYBINDS, SECURITY updated.
- Tests: Python unit suite (fixture sysfs for NVIDIA desktop, AMD, Intel laptop, hybrid, no
  driver, Secure Boot, Kepler/unknown GPUs, no telemetry), Qt qmllint suite, config/schema/IPC
  suite; extended Hyprland invariants; CI jobs for all of them.

### Fixed (pre-existing bugs found during the upgrade)
- **Shell failed to load**: `WallpaperBackground.qml` used `WlLayer.layer` without importing
  `Quickshell.Wayland` (and `WlLayer` isn't the type name) — an error there stops `shell.qml`.
- **Command injection**: wallpaper path was interpolated into a `bash -c` string.
- `Colors.surface` / `Colors.surfaceHover` were used by Settings and the wallpaper picker but
  never defined.
- Shell notifications (`EventBus.notificationRequested`: screenshot saved, wallpaper applied)
  had no listener and were never shown.
- `aether-shell.service` hard-coded `/usr/bin/qs` (source builds install to `/usr/local`) and
  lacked `~/.local/bin` on PATH, so `aether-screenshot` couldn't be found under systemd.
- `Slider` and `Switch` overwrote their own bound `value`/`checked`, silently breaking bindings
  (e.g. the volume slider stopped following media-key changes after one drag).
- Apps were launched as children of the shell through one shared `Process` (restarting the
  shell killed them; a second launch could be ignored) — now `execDetached`.
- Network polling ran `nmcli device wifi list` every 5 s, which triggers periodic Wi-Fi rescans;
  now `--rescan no`, scanning only on demand.
- Active-window title re-queried `hyprctl` on every Hyprland event; now only on focus/title events.
- `aether shell-reload` killed *every* `qs` process and logged to a predictable `/tmp` path.
- Repo hygiene scan matched binary wallpaper files (it was failing on the original repo).

## Unreleased (before 0.2.0)

### Added — Wallpaper Engine & Management
- `config/quickshell/aether-shell/services/WallpaperService.qml`: wallpaper discovery singleton across standard XDG and AetherOS wallpaper directories with title humanization, state synchronization, random selection, and sequential cycling.
- `config/quickshell/aether-shell/shell/wallpaper/WallpaperBackground.qml`: full-screen background renderer on `WlLayer.Background` for all monitors with smooth cross-fade animation and optional dimming overlay.
- `config/quickshell/aether-shell/shell/wallpaper/WallpaperPicker.qml`: visual GUI modal selector ($mod + W) with live search, responsive preview cards, active indicators, and randomize action.
- `scripts/bin/aether-wallpaper` and `aether wallpaper`: CLI management utility for random selection, cycling, listing, and setting wallpapers.
- `config/hypr/keybinds.conf`: added `$mod + W` (Wallpaper Picker), `$mod + SHIFT + W` (Random wallpaper apply), and `$mod + CTRL + W` (Next wallpaper).
- `config/quickshell/aether-shell/shell/settings/Settings.qml`: added Wallpaper section in Appearance tab with active preview, browse button, and randomize button.
- `config/quickshell/aether-shell/shell/lockscreen/LockScreen.qml`: integrated active wallpaper background with subtle darkening backdrop.

### Added & Hardened — Production-Readiness & Security Fixes
- `scripts/setup-symlinks.sh`: protected pre-existing external symlinks from deletion. Unrelated symlinks are backed up to `${dest}.bak.<timestamp>` rather than removed.
- `scripts/restore.sh`: hardened against archive path-traversal attacks (`..`, leading `/`) and restricted restoration strictly to allowlisted managed targets.
- `scripts/backup.sh`: stopped recursively following external symlinks; dereferences only repo-owned symlinks and preserves external symlinks with `cp -P`.
- `config/quickshell/aether-shell/services/ApplicationService.qml`: full Desktop Entry specification `Exec` field parser handling quotes, backslash escapes, and XDG field codes (`%f`, `%F`, `%u`, `%U`, `%i`, `%c`, `%k`). Launches directly via argument arrays (`argv[]`) without shell wrappers (`bash -lc`).
- `system/systemd/aether-shell.service`: added systemd user unit for Quickshell with `Restart=on-failure` for automatic supervision; Hyprland config autostart updated to use the systemd unit.
- `scripts/bin/aether-screenshot`: created dedicated standalone screenshot helper wrapping `grim`, `slurp`, and `wl-copy`, replacing dynamic bash string construction in `ScreenshotService.qml`.
- `scripts/bin/aether`: unified `aether doctor` to directly invoke `scripts/doctor.sh` as the single source of truth; updated `shell-reload` and `logs` to integrate with `aether-shell.service`.
- `scripts/bootstrap.sh`: robust distro detection via `/etc/os-release`, Fedora 40+ version check, friendly manual-distro guidance, and dual service enablement.
- `tests/integration/test_symlink_lifecycle.sh`: added automated test assertions verifying external symlink preservation, path-traversal rejection, and backup symlink safety.
- `theme/gtk/gtk-3.0/gtk.css`: original AetherOS stylesheet (buttons, entries, switches,
  sliders, checks/radios, menus/popovers, tabs, scrollbars, tooltips, selection) — colors mirror
  the shell's `theme/Colors.qml` tokens. Verified: brace-balanced, every `@color` reference
  resolves to a real `@define-color` (checked with a real script, not eyeballed). NOT visually
  verified — no GTK/display server in this environment.
- `theme/gtk/gtk-4.0/gtk.css`: a deliberately smaller subset (GTK4's CSS engine diverged enough
  from GTK3, especially for libadwaita apps, that porting the full GTK3 stylesheet without a way
  to check it against a live GTK4 session felt like overclaiming coverage)
- Symlinking changed from whole-directory (`~/.config/gtk-3.0`) to per-file
  (`settings.ini`, `gtk.css`) after finding a real problem in testing: whole-directory symlinking
  would have displaced any pre-existing GTK-managed files (bookmarks, recently-used) that live in
  the same directory. Confirmed fixed with a real test using a fake `$HOME` containing a
  pre-existing bookmarks file.

### Added — Aether Shell, Phase 7
- Reduced motion now actually works — `Motion.reducedMotion` bound to `Config.general.reducedMotion`
  at the shell root, all 9 `Behavior` animation blocks across the shell gate on it
- Bluetooth device manager (`$mod + B`): power, scan, pair, connect/disconnect, forget, battery
  display where available. Connect/disconnect use the confirmed Quickshell API; scan/pair/forget
  are best-effort and clearly flagged as unverified in both code and PROGRESS.md
- Notification history/center (`$mod + ,`): persistent-during-session log of all notifications
  (including DND-suppressed ones), Do Not Disturb toggle, clear-all
- Bar's Bluetooth capsule now opens the manager instead of directly toggling power

### Added — Aether Shell, Phase 6
- Settings app: Appearance (accent color, bar opacity, reduced motion toggle), Bar (position,
  height, per-module visibility), About (live service status)
- Accent color is now genuinely live-configurable — `Colors.accent` is bound to
  `Config.appearance.accent` at the shell root instead of being a hardcoded constant
- `Config.bar.showNetwork/showAudio/showBattery/showMedia/showBluetooth` — per-module bar
  visibility, wired into every relevant bar module
- New reusable components: `Slider`, `Switch`, `ColorSwatch`

### Added — Dotfiles layer (this phase)
- `scripts/bootstrap.sh`: distro-detecting installer (Fedora/Arch), replacing the earlier
  Fedora-only `install.sh`
- `scripts/doctor.sh`: standalone PASS/WARN/FAIL diagnostics
- `scripts/backup.sh`, `scripts/restore.sh`, `scripts/uninstall.sh`: safe, tested
  backup/restore/uninstall lifecycle
- `tests/`: real automated test suite (shellcheck, Hyprland config syntax, QML structure,
  full install/backup/restore/uninstall integration test) — see `tests/run-all.sh`
- `packages/{fedora,arch,generic}/`: per-distro package lists
- Fixed two real bugs found by actually running the new tests: a timestamp-collision race in
  `restore.sh` that could clobber its own source archive, and a `set -e`/`grep`-no-match
  interaction that silently aborted a test script

### Added — Dotfiles layer (earlier phase)
- `config/hypr/`: full modular Hyprland configuration (monitors, workspaces, ~60 keybinds,
  window/layer rules, environment, animations/decoration/blur)
- `config/kitty/`, `config/zsh/`: terminal and shell config, colors matching the shell's theme
  tokens
- `theme/gtk/`: GTK3/4 dark-mode settings + an original AetherOS stylesheet (`gtk.css`, colors
  matching the shell's own theme tokens) — no longer just a stock Adwaita-dark pointer
- `scripts/setup-symlinks.sh`, `scripts/update.sh`, `scripts/bin/aether` CLI
- Repository restructured: the standalone shell project became
  `config/quickshell/aether-shell/` inside this repo

### Added — Aether Shell (config/quickshell/aether-shell/)
Built in phases; see that directory's own `PROGRESS.md` for the full feature-by-feature
breakdown. Summary:
- Phase 1: theme engine, core services (Logger/EventBus/Config), Hyprland/Audio/Power/Network
  services, working bar
- Phase 2: application launcher, notification popups
- Phase 3: Bluetooth toggle, MPRIS media controls, clipboard history, screenshots
- Phase 4: real Wayland session lock + power menu (PAM auth flagged unverified)
- Phase 5: dashboard (quick toggles, live system stats, calendar)

### Known issues
- Lock screen PAM authentication is implemented but not verified against Quickshell's
  authoritative API docs — see `SECURITY.md` and the shell's `PROGRESS.md`.
- No custom AetherOS GTK theme yet (stock Adwaita-dark).
- No Settings app, Overview, widget framework, or wallpaper engine yet.
- No CI has actually run these workflows yet (see `.github/workflows/`) — they're written and
  the underlying test commands work locally, but the workflow YAML itself hasn't executed on
  GitHub's runners.
