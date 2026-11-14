# Test report — AetherOS 1.0.0-rc.1

Run with `bash tests/run-all.sh` on 2026-11-11 in a headless Linux sandbox (Ubuntu 24.04 host,
Python 3.12, PySide6 6.12 for qmllint and the runtime suite, Mesa llvmpipe under Xvfb,
shellcheck 0.11). Run twice — **as root and as an unprivileged user — 11 of 11 suites passed
both times.** As root, 3 checks skip by design (the installer test and 2 CLI tests verify
behaviour that only exists for non-root users); as a normal user nothing is skipped.

## Results

| Suite | Result | What it proves |
|---|---|---|
| `scripts/test_shellcheck.sh` | PASS — 31 scripts, 0 findings | every shell script, all severities, following sourced files |
| `scripts/scan_repo_hygiene.sh` | PASS | no leftover work markers, stub markers or machine-specific paths |
| `hyprland/test_config_syntax.sh` | PASS | every fragment sourced; rules only via compat.conf; 0.52 → `rules.conf`, 0.53 → `rules-v2.conf`; both cover the same 21 namespaces and 11 window patterns; 91 keybinds with no conflicting combinations |
| `shell/test_qml_structure.sh` | PASS — 160 files | balance on code only; relative and `.js` imports resolve; **every shell type used is imported** (new; verified to fail when an import is removed) |
| `shell/test_qml_lint.sh` | PASS — 160 files | Qt's qmllint: no syntax errors |
| `shell/test_security_invariants.sh` | PASS | one unlock statement, inside PAM's success branch (fails on an injected unlock); `WlSessionLock.locked` bound only to it; every `sh -c` script is a single constant literal; no command-like automation action |
| `shell/runtime` | PASS — 8 files, 186 checks | see below |
| `config/test_config_files.sh` | PASS | systemd units; package lists; config schema; generated files current; all 21 IPC calls (keybinds, CLI, touchpad gestures, hypridle) resolve to a handler function |
| `python` | PASS — 193 tests | see below |
| `integration/test_symlink_lifecycle.sh` | PASS | link → backup → restore → uninstall |
| `integration/test_installer.sh` | PASS (normal user) | dry-run changes nothing; check; install keeps an existing ~/.zshrc; idempotent re-install; resume after interruption; rollback restores originals and keeps settings; bad options rejected |

### Python (193 tests)

Earlier releases (136): hardware/graphics/NVIDIA/telemetry against fixture sysfs trees, config
schema and migrations, snapshots (tampering, traversal, links), profiles, layouts, capabilities,
palettes, terminals, appearance themes, automation, compat, hypridle.

New in 1.0 (57): **NVML** against a fake `libnvidia-ml` driven through real ctypes pointers
(sampling, unsupported counters → None, process merge, "not available" memory, init failure);
**hybrid dGPU** never opened by bar sampling, transient session closed after detail samples;
**rendering** report runs no commands, PRIME/forced-backend notes, lavapipe isn't hardware
Vulkan, probe parsing; **desktop entries** (Exec quoting, field codes, class mapping);
**session** save/restore quotes every word and skips unknown or tampered ids; **app rules** in
both Hyprland syntaxes; **autostart** overrides, OnlyShowIn, never deleting system files;
**input** XKB validation and live apply; **displays** reject unreported modes and scales, the
watchdog reverts unless confirmed, profiles match monitor sets; **themes** create/validate/import,
reach terminals; **assistant** against real local HTTP servers speaking Ollama NDJSON and OpenAI
SSE (streaming, action validation, no shell action, key from the keyring sent as Bearer and
absent from the audit log, local-only, unreachable endpoint, model listing, opt-in redacted
history); **registry** limits; **secrets** via stdin, never argv; **redaction**; **audit**
permissions and rotation; **widgets** (built-ins pass the scanner, 10 escape techniques blocked,
manifest rules, zip traversal, no shadowing built-ins); **automation v2**; **contracts**
between Settings, its search index, the assistant's registry and the shell's action handlers.

### Runtime suite (`tests/shell/runtime`, 186 checks)

Qt-only layers loaded in a real Qt Quick scene, rendered through Qt's OpenGL RHI on Mesa
llvmpipe, with behaviour and pixel assertions on captured frames.

| File | Checks | Highlights |
|---|---|---|
| `tst_spring.qml` | 20 | settles exactly; idle springs cost nothing; retargeting keeps velocity; overshoot preset; snaps under reduced motion |
| `tst_theme.qml` | 26 | 18 palettes; dark/light; high contrast; colour-blind; UI/corner scale; motion durations; spring damping ratios; glass presets |
| `tst_policy.qml` | 15 | GPU pressure needs 3 hot samples, holds in the hysteresis band, recovers after 10 cool samples, ignores spikes and unknown telemetry; motion profiles; user palettes |
| `tst_shaders.qml` | 14 | wipe/circle transitions, glass specular inside the radius only, glow on the edge only, aurora varies |
| `tst_wallpaper.qml` | 17 | hidden images as shader textures; depth parallax moves near pixels by exactly half a stripe period and far pixels not at all |
| `tst_wallpaper_stage.qml` | 14 | no black frame mid-transition; every mode completes; shader modes fall back to fade; rapid changes settle; reduced motion is instant |
| `tst_components.qml` | 16 | battery families and state colours, gauges, switch/slider binding safety and keyboard |
| `tst_icons.qml` | 64 | every one of 62 glyphs draws; an empty control cell stays black |

## Classic interface run (Unreleased)

`bash tests/run-all.sh` as an unprivileged user (Ubuntu 24.04 sandbox, Python 3.12, PySide6
6.12, GTK 3 via python3-gi, Rofi 1.7.5 under Xvfb, shellcheck 0.11): **18 suites — 17 passed,
0 failed, 1 skipped** (RPM build: no rpmbuild on the host).

| Suite | Result | What it proves |
|---|---|---|
| `classic/test_classic_interface.sh` | PASS | setup links the classic interface and selects it; a re-run keeps an existing choice; switching both ways; 7 Waybar layouts parse and use only defined modules; every Waybar/SwayNC/Wlogout stylesheet passes **GTK 3's own parser** with the generated palette (and the check rejects a broken sheet); every Rofi theme and `config.rasi` pass **Rofi**, which also picks up the generated palette; SwayNC/Wlogout/Pyprland/wallust configs parse; every `aether-*` command the configs call exists; key reference (116 rows); calculator refuses code; weather makes no request by default; filenames with spaces |
| `python` (incl. `test_classic_colors.py`) | PASS — 223 tests | 17 new: contrast of every preset in both modes, histogram and wallust palettes, template formats, init/toggle/fallback behaviour |
| `hyprland/test_config_syntax.sh` | PASS | classic 115 / aether 93 keybinds without conflicts; interface fragments sourced in the right order; hyprlock/hypridle never sourced; rule files cover the same 22 namespaces and 13 window patterns |
| `integration/test_installer.sh` | PASS | also: an existing `~/.config/waybar` is moved aside and restored by `--rollback`; `rofi-wayland\|rofi` picks the available one; unavailable packages are reported; the plan follows `--interface` |
| `shell/runtime` | PASS — 186 checks | after the fixture fix above |

Looks (second run, same result: 17 passed, 0 failed, 1 skipped): 14 Waybar layouts and 11
styles parse; 8 looks reference existing parts and `aether-look apply` records all of them.
Beyond the suite, every look was rendered by real Waybar 0.10 on headless Sway and every
launcher by real Rofi 1.7.5 under Xvfb (docs/images/); that rendering found and fixed the
launcher banner that never showed and blank default workspace buttons.

Still needs a live Hyprland session: everything visible in the classic interface (see the
checklist at the end of [docs/CLASSIC_INTERFACE.md](docs/CLASSIC_INTERFACE.md)).

## Not tested — needs a live session or real hardware

Run the checklist in [docs/HARDWARE.md](docs/HARDWARE.md#validation-checklist-needed-before-calling-a-release-100)
and record results here before tagging 1.0.0.

| Needs | Items |
|---|---|
| Quickshell + Hyprland session | every window and surface; Hyprland IPC; layer rules; widget input regions; assistant streaming in the panel; window thumbnails |
| NVIDIA driver on real hardware | NVML on your driver; RTX 4050 counters; VRAM behaviour under load; the dGPU actually runtime-suspending at idle |
| Hyprland 0.53+ | `rules-v2.conf` and app-rule syntax (`aether hyprland` runs `--verify-config`) |
| PAM | real authentication; lock re-acquisition after a crash |
| PipeWire / BlueZ / NetworkManager / UPower / MPRIS | audio, Bluetooth, Wi-Fi, VPN detection, mic/camera indicators, battery alerts, media |
| Fedora repositories | package availability, DNF5 transactions, COPR prompts (CI job `fedora-preflight` configured, not yet run) |
| Multi-monitor / hotplug / suspend / long sessions | per-screen surfaces, display profiles, resume, memory over hours |
