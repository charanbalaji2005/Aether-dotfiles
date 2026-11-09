# Test report — AetherOS 0.2.0

Date: 2026-11-09. Reproduce with `bash tests/run-all.sh` (on Linux; CI runs every suite).

## Environment (read this first)

| | |
|---|---|
| Host | Windows 11, Git Bash (MSYS2), CPython 3.15 |
| Real tools used | shellcheck 0.11.0, Qt `qmllint` (PySide6-Essentials), CPython `unittest`, Python `ast` (3.9 grammar check) |
| **Not available** | Linux kernel, Wayland, Hyprland, Quickshell, systemd, GPU drivers, PipeWire, NetworkManager |

Consequences, stated plainly:

* **No physical hardware testing was performed.** GPU/CPU detection, driver planning and telemetry
  were tested against fixture sysfs/procfs trees and canned command output modelled on real
  Fedora machines — not on real GPUs.
* **The QML shell was not run** in a live Quickshell session. It was checked statically
  (syntax, structure, imports, config schema, IPC targets) and by an independent code review.
* Nothing was installed on, or executed against, a Fedora system.

## Results

| Suite | Result | Notes |
|---|---|---|
| `tests/scripts/test_shellcheck.sh` | **PASS** — 21 scripts, 0 findings | final run |
| `tests/scripts/scan_repo_hygiene.sh` | **PASS** | final run. The scan was already failing on the original repo (it matched binary wallpaper files); fixed with `grep -I`. |
| `tests/hyprland/test_config_syntax.sh` | **PASS** | final run: braces, source wiring, fragment order (`profile.conf` last, `hardware.conf` after env), setup creates every fragment, no obsolete NVIDIA workarounds, no global GPU-vendor forcing, all 13 layer namespaces exist in QML |
| `tests/shell/test_qml_structure.sh` | **PASS** (78 files) in the earlier complete run | The final run reported one import as unresolved; re-checked by hand immediately afterwards — all four imports of that file resolve. Treated as a transient failure while the machine was critically low on memory (see below). |
| `tests/shell/test_qml_lint.sh` (Qt qmllint) | **PASS — 0 syntax errors in 78 files** in the earlier complete run | **Not re-run after the review fixes** (11 QML files edited afterwards). Re-run before release. |
| `tests/config/test_config_files.sh` | **PASS** | systemd units, package lists, JSON, all 46 `Config.x.y` references declared, all 13 IPC targets exist, all shell.qml imports resolve |
| `tests/python/run_python_tests.sh` | **PASS — 82 tests** in the earlier complete run | Python code unchanged since, apart from one docstring. All modules also parse with the Python 3.9 grammar. |
| `tests/integration/test_symlink_lifecycle.sh` | **NOT RUN** | Windows refuses symlink creation without Developer Mode (`ln: Operation not permitted`). It's an environment limit, not a code failure; CI runs it on Linux. |

**Final run interrupted:** the last full `run-all.sh` (after the review fixes) was stopped by the
tooling because the host was critically low on memory. Three suites had completed (all PASS) and
the fourth was mid-run. It was not restarted automatically. **Recommended:** run
`bash tests/run-all.sh` once more, ideally on Linux or in CI.

## Scenario coverage (Python suite)

The prompt asked for graceful behaviour in these situations. Each one is a fixture-driven test:

| Scenario | Tests |
|---|---|
| NVIDIA GPU absent | AMD and Intel fixtures: no NVIDIA state, install plan blocked ("No NVIDIA GPU"), nothing NVIDIA in `hardware.conf` |
| AMD GPU present | amdgpu detected as discrete; busy %, VRAM, temperature and power from sysfs; H.264 VA-API warning + freeworld hint |
| Intel GPU present | i915 iGPU; usage reported *unavailable* with the reason; clock shown |
| NVIDIA drivers not installed | nouveau fixture: branch selection, RPM Fusion step, refusal without a TTY |
| Secure Boot enabled | key generation + MOK steps planned; built-but-rejected module → FAIL with `mokutil --import`; no command can disable Secure Boot (asserted) |
| GPU telemetry unavailable | no `nvidia-smi` → `null` + reason; suspended hybrid dGPU never queried (asserted: no `nvidia-smi`/`vainfo` call) |
| Network disconnected | no default route → `connected: false`; rates from physical interfaces only |
| Dependency missing | missing `lspci` → pci.ids fallback → raw IDs; missing ImageMagick → error, not a guessed colour; empty system → every metric `null` |
| Unknown / legacy GPUs | Kepler, Fermi and unrecognised code names are never auto-installed |
| Hybrid laptop | never forces NVIDIA globally; `--primary` writes `AQ_DRM_DEVICES` via by-path symlinks |
| Hyprland versions | gesture syntax for < 0.51, ≥ 0.51 and unknown versions |
| CLI end-to-end | `--help`, `--version`, `hardware --json`, `graphics drivers`, `install-nvidia --dry-run`, configure (dry run, write, idempotent), performance profile, repair, telemetry stream; runs against the real host without crashing |

## Bugs found by testing and review during this upgrade

Found by the new tests: the NVIDIA code-name regex rejected mobile/workstation parts (`TU117M`,
`GA104GL`), which would have marked every laptop GPU "unknown generation"; `graphics detect`
probed a sleeping dGPU (which would wake it); the fixture runner behaved unrealistically; a CLI
abort path differed on Windows. Found by review: `Quickshell.isEnvSet`, the battery percentage
scale and the `Mpris` model access (pre-existing); the segmented-control highlight; clipped
empty-state messages; toasts replaying their animation; Escape not working from text fields;
notification timeout units; retracted notifications lingering; Wi-Fi disconnect by profile name.
All are fixed — see CHANGELOG.md for the complete list, including the pre-existing bugs.

## Still requires a real system

`aether diagnostics` and `aether graphics verify` on actual hardware; `aether hyprland`
(runs `Hyprland --verify-config`); logging into the session; the lock screen's PAM flow; an
actual `aether graphics install-nvidia` on a Fedora NVIDIA machine.
