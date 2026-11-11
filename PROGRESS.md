# Progress

## 1.0.0-rc.1 — feature-complete release candidate

Tiers as defined below. **Nothing has reached VERIFIED yet**: the checklist in docs/HARDWARE.md
gates 1.0.0.

| Area | Status | Notes |
|---|---|---|
| NVML telemetry, hybrid-safe sampling | **TESTED** | fake libnvidia-ml through real ctypes; real driver needs hardware |
| Rendering diagnostics (`aether render`) | **TESTED** | fixture files and canned probe output |
| GPU-pressure policy, motion profiles, performance tier | **RENDER-TESTED** | |
| Assistant backend (providers, keyring, registry, audit, redaction) | **TESTED** | real local HTTP servers |
| Assistant panel, keyring UI | IMPLEMENTED | |
| Widgets backend (manifest, scanner, install) | **TESTED** | |
| Widget layer + API, 7 built-ins | IMPLEMENTED (built-ins pass the scanner, qmllint) | input regions need a session |
| Themes backend / editor | **TESTED** / IMPLEMENTED | |
| Input, displays (+ watchdog, profiles), autostart, workspaces/sessions | **TESTED** (backend) / IMPLEMENTED (sections) | |
| Island 2.0, notification rules + sounds, privacy service, clipboard privacy | IMPLEMENTED | `aether-clip-store` shellcheck-clean |
| Launcher (settings/actions/files/commands/history) | IMPLEMENTED | |
| 28 Settings sections + search | IMPLEMENTED; section/index/registry consistency **TESTED** | |
| Workspace names/icons, per-workspace wallpaper, gradient/aurora modes, dock previews/recents | IMPLEMENTED | |
| Automation v2 | **TESTED** (backend + contract) / IMPLEMENTED (engine, builder) | |
| Power auto-saver, idle dim | IMPLEMENTED (dim stage **TESTED** in hypridle generation) | |
| Publishing kit (repo-URL tool, CLI reference generator, templates, release workflow) | **TESTED** (generators in CI checks); workflows not yet run on GitHub | |

### Still not implemented

Download/file-transfer progress (no system API), screenshot annotation editor, per-app volume
and equaliser, process-isolated widget sandbox, real-time 3D wallpapers, translations,
hibernation controls, camera detection for apps that bypass PipeWire, Meridian Shell beyond the
"custom zsh file" hook (no Meridian Shell exists in the repository).

## Status tiers

- **TESTED** — executed with real assertions in this repository's test suite (see TEST_REPORT.md).
- **RENDER-TESTED** — QML executed in a real Qt Quick scene (OpenGL RHI) with behaviour and
  pixel assertions. Applies to the parts that don't need Quickshell.
- **IMPLEMENTED** — code exists, passes qmllint/structure/schema/invariant checks and review,
  but needs a live Quickshell + Hyprland session to execute.
- **VERIFIED** — run on a real Fedora machine in a real session. **Nothing has reached this tier
  yet**: this release was built in a headless Linux sandbox (no Wayland compositor, Quickshell,
  PipeWire, Bluetooth, PAM session or physical GPU).
- **NOT IMPLEMENTED** — listed so its absence is explicit.

## 0.3.0

| Area | Status | Notes |
|---|---|---|
| `install.sh` check / dry-run / install / re-install / resume / rollback / bad options | **TESTED** | `tests/integration/test_installer.sh`, run as a normal user in a fake home with Fedora code paths forced (`--no-packages`). |
| Package availability checks, DNF5 detection, COPR consent, Quickshell source build | IMPLEMENTED | Needs a real Fedora with repositories. CI job `fedora-preflight` runs `--check`/`--dry-run` in a `fedora:42` container (not yet executed on GitHub's runners). |
| uninstall / backup / restore / symlink lifecycle | **TESTED** | `test_symlink_lifecycle.sh` (now using the shared managed-path list). |
| Config schema, validation, migrations, import/export, get/set | **TESTED** | `test_desktop.py`; schema generated from `Config.qml` and checked in CI. |
| Snapshots (create/verify/tamper/traversal/links/restore/undo/retention) | **TESTED** | |
| Profiles (11 built-ins, apply, save, import validation) | **TESTED** | Shell UI: IMPLEMENTED. |
| Palettes → kitty/foot/alacritty/ghostty/Hyprland, zsh profiles, quoting | **TESTED** | Live kitty reload: IMPLEMENTED. |
| Icon / cursor theme detection and switching | **TESTED** | Against fake theme directories; gsettings/hyprctl effects need a session. |
| Smart layouts (geometry, matching, launch, skip, apply dispatches, undo) | **TESTED** | Against canned `hyprctl -j` output; real window movement needs Hyprland. |
| `aether capabilities` tiers, never querying a sleeping dGPU | **TESTED** | Fixture hardware. |
| Updates / security / services backends | **TESTED** | Parsing + validation; live data needs Fedora. |
| Automation rule validation, conflicts, loops; Python ≡ JS tables | **TESTED** | Shell engine: IMPLEMENTED. |
| Hyprland: compat generation, rules version selection, rules v1≡v2, keybind conflicts | **TESTED** | `rules-v2.conf` syntax not yet parsed by a live Hyprland 0.53 — `aether hyprland` runs `--verify-config`. |
| Spring engine, motion tokens, palettes/metrics/materials | **RENDER-TESTED** | 46 checks. |
| Shaders: glass, glow, aurora, transitions (wipe/circle), depth parallax | **RENDER-TESTED** | Pixel-verified on Mesa llvmpipe; real GPUs not tested. |
| Wallpaper stage: no black frame, all modes complete, fallback, rapid changes, reduced motion | **RENDER-TESTED** | |
| Components: battery families, gauges, switch, slider keyboard, glass panel | **RENDER-TESTED** | |
| Lock screen unlock path / constant shell scripts / allowlisted actions | **TESTED** (static) | `test_security_invariants.sh`; the invariant test fails on an injected extra unlock. |
| Lock screen (PAM flow, crash re-lock, clocks, widgets) | IMPLEMENTED | Test with a TTY available the first time (RECOVERY.md). |
| Dock, Dynamic Island, Overview, System centre, Layout picker, Edge gestures | IMPLEMENTED | |
| Settings sections (11 new), shell wiring | IMPLEMENTED | |
| Services: Performance, Window, Action, Automation, Timer, Recording, Visualizer, Island, VideoWallpaper, Cli, Profile, Layout, System, Idle; Media/Power/Theme/Wallpaper extensions | IMPLEMENTED | |
| `aether-record`, `aether-terminal` | IMPLEMENTED | shellcheck clean; need wf-recorder / terminals. |
| Safe-mode fallback unit, idle unit | IMPLEMENTED | Structure-checked; `systemd-analyze` not available here. |

### Not implemented (deliberately or pending)

| Item | Why |
|---|---|
| Download progress in the island | Linux has no system-wide download-progress API; browsers don't publish one. Not faked. |
| Screenshot annotation editor | `satty` is in the complete package set; not integrated into the shell yet. |
| Per-application volume, equaliser, microphone monitoring | Planned for the audio centre; PipeWire node streams not wired yet. |
| Third-party widget platform / widget SDK | Not started; would need a sandboxing design first. |
| Real-time 3D wallpaper scenes, AI depth-map generation | Depth maps are supplied by the user; no cloud or ML dependency added. |
| Ken Burns wallpaper motion | Rejected for now: continuous full-screen redraw contradicts the idle-cost rule. |
| Window thumbnails without screencopy support | Falls back to icons. |
| Meridian Shell integration beyond "custom zsh file" | No Meridian Shell exists in the repository; nothing was invented. |
| Translations / i18n catalogue | Strings are plain QML text; not yet wrapped in `qsTr`. |
| Workspace deletion | Hyprland removes empty workspaces itself. |
| Hibernation controls, lid-switch editing | Shown nowhere rather than half-working. |

## Earlier releases

### 0.1 dotfiles layer

| Component | Status | Basis |
|---|---|---|
| `config/hypr/*.conf` | IMPLEMENTED | Brace balance + source-line wiring checked by `tests/hyprland/test_config_syntax.sh` (TESTED — that script itself runs and passes). Actual Hyprland parsing: not possible here, no Hyprland installed. |
| `config/kitty/kitty.conf` | IMPLEMENTED | Follows documented kitty config syntax; not run against a live kitty. |
| `config/zsh/.zshrc` | IMPLEMENTED | Not sourced by a live interactive zsh in this environment. |
| `theme/gtk/*/settings.ini` | IMPLEMENTED | Standard GTK settings.ini format; not applied to a live GTK app. |
| `theme/gtk/gtk-3.0/gtk.css` | IMPLEMENTED | Original AetherOS stylesheet, not stock Adwaita. Brace-balanced and every `@color` reference verified to resolve (real script, `python3` + regex, not eyeballed) — see CHANGELOG. **Not visually verified** — no GTK/display server here to render it against. |
| `theme/gtk/gtk-4.0/gtk.css` | IMPLEMENTED | Deliberately smaller subset than the GTK3 version — see the file's own header comment for why. Same verification tier as GTK3: syntax-checked, not visually checked. |
| `scripts/setup-symlinks.sh` | **TESTED** | Actually run repeatedly against an isolated fake `$HOME` — see `tests/integration/test_symlink_lifecycle.sh`. Confirmed: creates correct symlinks, idempotent on re-run, backs up real files AND unrelated pre-existing symlinks instead of destroying them. |
| `scripts/backup.sh` | **TESTED** | Exercised as part of the integration test. Dereferences repo configs while preserving external symlinks without recursive traversal. |
| `scripts/restore.sh` | **TESTED** | Integration test confirms restored content matches the original. Hardened against path traversal (`..`, absolute paths) and restricted to allowlisted targets with automated test validation. |
| `scripts/uninstall.sh` | **TESTED** | Integration test confirms it removes only symlinks pointing into this repo and leaves anything else (including a symlink pointing elsewhere) untouched. |
| `scripts/bootstrap.sh` | IMPLEMENTED | `bash -n` clean, shellcheck clean. Uses `/etc/os-release` for multi-distro detection with version gating. |
| `scripts/doctor.sh` | **TESTED** | Single source of truth for diagnostics, invoked by both standalone execution and `aether doctor`. |
| `scripts/bin/aether` | **TESTED** | `help` output confirmed; `doctor` delegates directly to `doctor.sh`; `shell-reload` and `logs` integrate with `aether-shell.service`. |
| `scripts/bin/aether-screenshot` | **TESTED** | Dedicated standalone screenshot helper for `grim`/`slurp`/`wl-copy`, replacing dynamic QML shell script construction. |
| `system/systemd/aether-clipboard.service` | **TESTED** | Passed `systemd-analyze verify`. Starts cliphist watcher. |
| `system/systemd/aether-shell.service` | **TESTED** | Supervised systemd user service for Quickshell with `Restart=on-failure`. |
| `tests/` (the whole suite) | **TESTED** | Every suite runs and its assertions were checked, not assumed. `tests/run-all.sh` runs all 5 suites with 0 failures and full shellcheck clean verification. |
| `.github/workflows/*.yml` | IMPLEMENTED | All 4 files pass `yaml.safe_load` (real parse check). The workflows themselves have not executed on GitHub's actual runners — see below. |
| `packaging/tarball/build-tarball.sh` | **TESTED** | Actually run; produced a real tarball, checksum verified with `sha256sum -c`, contents verified with `tar -tzf`. |
| `packaging/rpm/aetheros-dotfiles.spec` | **TESTED** | This is the one packaging format that got the full real treatment: built with `rpmbuild`, linted with `rpmlint` (iterated from 24 errors/14 warnings down to 4/8, fixing real issues each round — missing executable bits, non-relative symlinks, git artifacts leaking into the package, `env`-based shebangs), and **actually installed into a fakeroot** with `rpm --root`, where the installed `aether` CLI was confirmed to run. Remaining rpmlint findings (spelling-error false positives on "symlink"/"configs", `no-signature` for an unsigned local build, `invalid-license MIT` — almost certainly this rpmlint config's incomplete license list, not a real issue, `files-duplicate` — intentional, this package mirrors the full repo on purpose) are documented, not silently ignored. |
| `packaging/arch/PKGBUILD` | IMPLEMENTED | Written to standard PKGBUILD conventions. **Not build-tested** — no `makepkg`/`pacman` in this sandbox. Says so at the top of the file itself. |
| `packaging/rpm/*` CI job (`release.yml`) | IMPLEMENTED | The workflow YAML is valid and its steps mirror the exact command sequence that was manually verified to work (see the RPM row above) — but the workflow itself hasn't executed on a GitHub runner. |
| CONTRIBUTING.md / CHANGELOG.md / SECURITY.md / CODE_OF_CONDUCT.md / ARCHITECTURE.md | IMPLEMENTED | Documentation — "tested" doesn't apply in the executable sense; accuracy was checked against what's actually in the repo at time of writing. |

### 0.2.0 upgrade (hardware-aware desktop)

Built on Windows 11 with Git Bash and Python 3.15 — no Linux, Wayland, Hyprland, Quickshell or
GPU driver stack. Real tools used for verification: shellcheck 0.11, Qt's qmllint (PySide6),
CPython unittest. See [TEST_REPORT.md](TEST_REPORT.md) for the exact runs.

| Component | Status | Basis |
|---|---|---|
| `lib/aether/` CLI backend (hw, graphics, telemetry, performance, theme, cli) | **TESTED** | ~85 unit/CLI tests against fixture sysfs/procfs trees modelled on real Fedora machines (NVIDIA desktop, AMD desktop, Intel laptop, hybrid laptop, NVIDIA without driver + Secure Boot, Kepler, unknown GPU, empty system). CLI also run end-to-end against the real (non-Linux) host to prove graceful degradation. **Not VERIFIED**: never run on physical Linux GPUs. |
| `aether graphics install-nvidia` | **TESTED (plan only)** | Plan generation, branch selection, blockers, Secure Boot steps, `--dry-run`, refusal without confirmation are tested. The execution path (`sudo dnf …`) has not been run on a real Fedora machine. |
| Generated Hyprland fragments (`hardware.conf`, `compat.conf`, `profile.conf`) | **TESTED** (generation) / IMPLEMENTED (in Hyprland) | Content tested per hardware scenario and Hyprland version; not parsed by a real Hyprland here. `aether hyprland` runs `Hyprland --verify-config` on the target system. |
| `config/hypr/*` incl. `recovery.conf` | IMPLEMENTED | Static suite passes (braces, source order, fragments created by setup, no obsolete NVIDIA hacks, namespaces exist). Option names checked against Hyprland's documented options as of 0.45–0.5x; not parsed by Hyprland here. |
| Shell QML (bar, control centre, dashboard, launcher, notifications, settings, OSD, wallpaper, components, services) | IMPLEMENTED | qmllint: 0 syntax errors in all files (before the review fixes — re-run pending, see TEST_REPORT.md); structure/import suite; every `Config.x.y` key declared; every IPC target exists; independent code review pass. **Not run in a live Quickshell session.** |
| `scripts/bootstrap.sh`, `update.sh`, `doctor.sh` changes | IMPLEMENTED | shellcheck clean; not executed on Fedora here. |
| `scripts/setup-symlinks.sh` (fragment creation), `backup.sh` targets | IMPLEMENTED here | shellcheck clean. The integration test could not run on this Windows host (symlink creation needs Developer Mode); it runs in CI on Linux. |
| `system/systemd/aether-shell.service` | IMPLEMENTED | Structural checks; `systemd-analyze` unavailable here. |

### What actually got found and fixed by testing (not just written and assumed correct)

These are listed because they're the concrete evidence for the TESTED claims above — real bugs
that static review alone did not catch:

1. **`restore.sh` timestamp-collision race** — its own pre-restore safety backup could overwrite
   the archive it was about to restore from if both got created within the same second. Fixed by
   adding nanosecond precision to backup filenames AND copying the source archive to a safe
   location before creating the safety backup (defense in depth). Reproduced intermittently
   across repeated runs before the fix, 10/10 clean after.
2. **`set -e` + `grep`-no-match interaction** — a brace-counting helper in an early version of
   `tests/hyprland/test_config_syntax.sh` silently aborted the whole script (no output at all)
   the moment it hit a `.conf` file with zero braces, because `grep` exits 1 on "no matches" and
   `pipefail` propagated that through `set -e`.
3. **Missing executable bit** on `tests/scripts/test_shellcheck.sh` — caught by `rpmlint`'s
   `non-executable-script` check against the built RPM, not by anything run earlier.
4. **Self-matching hygiene scan** — `tests/scripts/scan_repo_hygiene.sh`'s own fake-implementation
   pattern matched its own source line defining that pattern, and its own accumulating "found"
   flag was being overwritten per-section instead of combined, masking failures in earlier
   sections. Both fixed and re-verified.
5. **CI step name self-triggering the TODO scanner** — a workflow step literally named "Scan for
   TODOs..." matched its own TODO-detection regex. Reworded rather than special-cased.
6. **Whole-directory GTK symlinking would have displaced unrelated user files** — an early version
   of the GTK theme change symlinked all of `~/.config/gtk-3.0` (matching the pattern used for
   `hypr`/`kitty`, which this repo fully owns). Unlike those two, `~/.config/gtk-3.0` commonly
   holds files this repo doesn't manage (GTK's own `bookmarks`, `recently-used.xbel`). Caught by
   testing against a fake `$HOME` seeded with a `bookmarks` file before shipping, not by review —
   fixed by switching to per-file symlinks for GTK config specifically.

### Explicitly not started (0.2.0)

Man pages for the CLI tools, an Arch build actually run through `makepkg`, GPG-signing release
artifacts, a live-session QML test harness, physical-hardware validation of the graphics tooling,
and anything on the shell's own not-started list (Overview, widget framework, full
accessibility pass, tray context menus, persisted notification history — see the shell's
PROGRESS.md).
