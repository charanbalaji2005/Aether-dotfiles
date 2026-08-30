# Progress (dotfiles layer)

For the shell's own feature-by-feature status, see
`config/quickshell/aether-shell/PROGRESS.md` — this file covers the layer around it.

## Status definitions (read this before the tables below)

- **NOT_STARTED** — no code/config exists.
- **IN_PROGRESS** — partially built, known gaps.
- **IMPLEMENTED** — code/config exists and passes every *static* check available in this
  development environment (syntax validation, shellcheck, structural checks, and — where a real
  tool exists — an actual build/lint against that tool, e.g. `rpmbuild`/`rpmlint` for the RPM).
- **TESTED** — actually *executed* and its behavior verified against real assertions (not just
  "it didn't crash"). Where this appears below, it means a real test ran and I checked its output,
  not that I assumed it would work.
- **VERIFIED** — TESTED, on the actual target system this is meant for (a real Hyprland session
  on real hardware). **Nothing in this repo has reached this tier.** This development environment
  is a headless Linux sandbox with no display server, no Wayland, no Hyprland, no Quickshell/Qt6
  installation, and no Bluetooth/audio hardware — anything needing those can only reach
  IMPLEMENTED or TESTED-in-isolation here, never VERIFIED. That's a real, structural limit of
  where this was built, not a formality.

## Dotfiles layer

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

## What actually got found and fixed by testing (not just written and assumed correct)

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

## Explicitly not started

Wallpaper engine beyond a
hyprpaper pointer, man pages for the CLI tools, an Arch build actually run through `makepkg`,
GPG-signing release artifacts, and anything on the shell's own not-started list (Overview,
Settings app, widget framework, accessibility pass, Bluetooth pairing UI — see the shell's
PROGRESS.md).
