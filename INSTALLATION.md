# Installing AetherOS

**Target:** Fedora Workstation (or any Fedora edition with DNF) **41 or newer**, x86_64 or
aarch64, using a currently supported Fedora release. Atomic editions (Silverblue, Kinoite…) are
refused by the installer because it layers packages with dnf; their users can run
`./install.sh --install --no-packages` after installing the tools in a toolbox.

Other distributions: the installer is Fedora-only on purpose. `packages/generic/README.md` lists
what to install by hand; then use `--no-packages`.

## 1. Before you start

```sh
sudo dnf upgrade --refresh && sudo reboot     # newest kernel first (matters for NVIDIA akmods)
```

Run everything as your **normal user** — the installer refuses root and uses `sudo` only for
package transactions, each shown before it runs. Keep a TTY in mind for the first login
(**Ctrl+Alt+F3**); see [RECOVERY.md](RECOVERY.md).

## 2. Check, preview, install

```sh
git clone https://github.com/OWNER/aetheros-dotfiles ~/aetheros-dotfiles && cd ~/aetheros-dotfiles
./install.sh --check                 # read-only preflight; exit 1 on a blocking problem
./install.sh --dry-run               # every link, move, package and command it would run
./install.sh                         # interactive: preflight → plan → "Proceed?" → install
./install.sh --install               # same, without the final "Proceed?" question
```

| Option | Meaning |
|---|---|
| `--interface classic\|aether` | classic: Waybar · Rofi · SwayNC · Wlogout · Hyprlock · swww (default); aether: the Quickshell shell. Re-runs keep your current choice. See [docs/CLASSIC_INTERFACE.md](docs/CLASSIC_INTERFACE.md) |
| `--no-fonts` | don't offer JetBrainsMono Nerd Font (the classic interface's icons need a Nerd Font) |
| `--mode minimal\|recommended\|complete` | package sets (default `recommended`, see §3) |
| `--yes` | don't ask before installing packages from **already enabled** repositories |
| `--enable-copr` | allow the COPR repositories in `packages/fedora/repos.conf` (otherwise asked one by one; never implied by `--yes`) |
| `--no-packages` | configs only |
| `--skip-quickshell` | don't install or build Quickshell |
| `--with-zshrc` | replace an existing `~/.zshrc` (moved to `~/.zshrc.bak.<time>`) |
| `--restart` | ignore the saved progress of an interrupted install |

What `--install` does, as resumable steps (an interrupted run continues where it stopped):

1. **Preflight** — Fedora release and edition, architecture, DNF5 vs DNF4, sudo, disk space,
   SELinux state (reported, never changed), display manager (kept), conflicting bars/notification
   daemons, and every managed path that already has something in it.
2. **Packages** — each name is checked with `rpm -q` and `dnf repoquery` against *your enabled
   repositories* first; missing ones are reported, never assumed. If a package is only available
   from COPR (`repos.conf`), you're asked about that repository explicitly.
3. **Quickshell** — from your repositories if available; otherwise, after an explicit yes, a
   source build of the official repository as your user, then a separate yes for
   `sudo cmake --install`.
4. **Backup** — `scripts/backup.sh` archives current configs to `~/.aetheros-backups/`.
5. **Links** — `scripts/setup-symlinks.sh`: existing files are *moved aside*
   (`*.bak.<timestamp>`), recorded in `~/.local/state/aether/manifest.tsv`, never deleted.
6. **Per-machine configuration** — settings migration, Hyprland version-specific syntax and
   rules, GPU fragment, terminal/border theme, hypridle timings, shaders compiled for your Qt.
   An NVIDIA GPU without the driver gets a *plan* only (`aether graphics install-nvidia`).
7. **Services** — enables `aether-shell`, `aether-clipboard` and `aether-idle` user units.
8. **Validation** — `scripts/doctor.sh`, `aether hyprland` (real `Hyprland --verify-config`),
   `aether config validate`.

Then log out and choose **Hyprland** in your display manager's session menu. GDM/SDDM and your
other desktops are untouched.

Log of every run: `~/.local/state/aether/logs/install-<time>.log` (last ten kept).

## 3. Packages

| Set | File | Contents |
|---|---|---|
| required (all modes) | `packages/fedora/packages.txt` | Hyprland + portal + polkit agent, Qt 6, PipeWire/WirePlumber, UPower, brightnessctl, NetworkManager, BlueZ, playerctl, wl-clipboard, grim/slurp/cliphist, kitty, zsh, fonts, python3, build tools for Quickshell |
| recommended | `packages/fedora/recommended.txt` | hypridle, qt6-qtshadertools, hyprsunset, power-profiles-daemon, ImageMagick, libnotify, wf-recorder, nautilus, libsecret (assistant keys), sound-theme-freedesktop + libcanberra-gtk3 (sounds), plocate (file search) |
| complete | `optional.txt` + `advanced.txt` | nwg-displays, graphics diagnostics, mpvpaper/mpv, cava, satty, fzf, zoxide, fastfetch, starship, egl-utils + vulkan-tools (`aether render --probe`) |

Not packaged by Fedora and therefore not installed: **Ollama** (for the local assistant — see
docs/AI_ASSISTANT.md). NVIDIA telemetry uses `libnvidia-ml.so.1`, which comes with the NVIDIA
driver's CUDA libraries (`xorg-x11-drv-nvidia-cuda-libs` from RPM Fusion).

Every optional feature reports "unavailable" with the reason when its package is missing.
COPR candidates (`packages/fedora/repos.conf`) are only consulted when Fedora doesn't ship a
package; check the project page shown at the prompt before agreeing.

## 4. Update, uninstall, roll back

```sh
./install.sh --update      # snapshot settings → git pull --ff-only → re-link → migrate → regenerate → validate
./install.sh --uninstall   # remove links + user services; keep packages, settings, snapshots, backups
./install.sh --rollback    # uninstall, then move every recorded original back (only where the path is free)
```

Rollback lists the packages and any COPR the installer added, with the exact commands to remove
them — it doesn't remove packages itself (other software may depend on them).

`aether update` and `scripts/update.sh` call `./install.sh --update`; `scripts/bootstrap.sh`
calls `./install.sh --install` (kept for older instructions).

## 5. After installing

* `aether diagnostics` — full health report. `aether graphics verify` — GPU stack checks.
* `aether capabilities` — which visual quality the shell will pick and why.
* Work through the hardware checklist in [docs/HARDWARE.md](docs/HARDWARE.md) — 1.0.0-rc.1 hasn't
  been validated on physical hardware yet, and your results are what turns it into 1.0.0.
* `aether snapshot mark-good` once the desktop works the way you like: `aether recover` can
  return to it.
* Settings: `SUPER+I`. Keybinds: [docs/KEYBINDS.md](docs/KEYBINDS.md).
