# Changelog

Dates reflect when each phase was built, not calendar releases — this hasn't been tagged/released
yet (see top-level `PROGRESS.md` for current status before treating anything below as "shipped").

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
