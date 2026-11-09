# Installing AetherOS

Target: **Fedora 40+** with Hyprland. Arch is supported for packages; other distributions can
use the configs after installing the dependencies by hand (`packages/generic/README.md`).
Hardware: NVIDIA, AMD and Intel GPUs, hybrid laptops, Intel and AMD CPUs — detected
automatically, nothing is assumed.

## 1. Before you start

* A fully updated system, rebooted into the newest kernel:
  ```sh
  sudo dnf upgrade --refresh && sudo reboot
  ```
  (This matters for NVIDIA: akmods builds the driver for the newest installed kernel.)
* Run everything as your **normal user**. Scripts use `sudo` only for individual package
  commands, and show you the command first.
* Keep a TTY in mind (**Ctrl+Alt+F3**) for the first login — see Recovery below.

## 2. Install

```sh
git clone <this-repo> ~/aetheros-dotfiles
cd ~/aetheros-dotfiles
./install.sh            # options: --yes, --no-packages, --skip-quickshell
```

`install.sh` (→ `scripts/bootstrap.sh`) does, in order — asking before anything that installs
software:

1. **Packages** — `packages/fedora/packages.txt` (required) and `packages/fedora/optional.txt`
   (each feature hides itself if its package is missing; unavailable ones are skipped).
2. **Quickshell** — built from its official source repository if `qs` isn't installed
   (Fedora has no package), installed to `/usr/local`.
3. **Backup** — `scripts/backup.sh` archives your current configs to `~/.aetheros-backups/`.
4. **Links** — `scripts/setup-symlinks.sh` symlinks `config/` into `~/.config` (existing files are
   renamed `*.bak.<timestamp>`, never deleted) and creates the per-machine Hyprland fragments.
5. **Hardware** — `aether hardware`, then version-specific Hyprland settings
   (`aether hyprland compat`), driver recommendations (`aether graphics drivers`) and the GPU
   fragment (`aether graphics configure`, shows a diff and asks).
6. **NVIDIA** — only if an NVIDIA GPU without the proprietary driver is present, offers
   `aether graphics install-nvidia`, which prints its own plan and asks separately
   ([docs/NVIDIA_GUIDE.md](docs/NVIDIA_GUIDE.md)).
7. **Services** — enables `aether-shell.service` and `aether-clipboard.service` (systemd user).
8. **Validation** — `scripts/doctor.sh` and `aether hyprland` (real `Hyprland --verify-config`).

Log out, pick **Hyprland** at the login screen.

### Already have the dependencies?

```sh
./scripts/bootstrap.sh --no-packages     # links + hardware setup + validation
# or only the links:
./scripts/setup-symlinks.sh
```

## 3. Dependencies

| Area | Fedora packages |
|---|---|
| Compositor | `hyprland xdg-desktop-portal-hyprland hyprpolkitagent` |
| Shell runtime | Quickshell (built from source), `qt6-qtbase qt6-qtdeclarative qt6-qtwayland` |
| AetherOS CLI backend | `python3` (standard library only), `pciutils hwdata mokutil` |
| Audio / network / power / BT | `pipewire wireplumber NetworkManager upower brightnessctl bluez` |
| Clipboard / screenshots | `wl-clipboard cliphist grim slurp` |
| Optional | `hyprsunset power-profiles-daemon nwg-displays ImageMagick vulkan-tools libva-utils egl-utils glx-utils libnotify` |

## 4. After the first login

```sh
aether diagnostics          # everything in one report (saved to ~/.local/state/aether/)
aether graphics verify      # GPU stack checks
aether performance          # power + Hyprland profiles
```

Shortcuts: `SUPER+D` launcher, `SUPER+A` control centre, `SUPER+N` dashboard, `SUPER+I` settings
— full list in [docs/KEYBINDS.md](docs/KEYBINDS.md).

## 5. Updating

```sh
aether update      # git pull --ff-only, re-link, recreate missing fragments, validate
```

After a Hyprland upgrade also run `aether hyprland compat` and `aether hyprland`.

## 6. Backup, restore, uninstall

```sh
scripts/backup.sh                         # → ~/.aetheros-backups/aetheros-backup-<ts>.tar.gz
scripts/restore.sh <archive>              # backs up the current state first, then restores
scripts/uninstall.sh                      # removes only symlinks that point into this repo
```

`restore.sh` rejects archives containing anything outside the managed paths (path-traversal
protected). Packages are never removed automatically.

## 7. Recovery

If the session doesn't come up:

1. **Ctrl+Alt+F3**, log in.
2. `Hyprland -c ~/.config/hypr/recovery.conf` (minimal, no GPU settings, opens a terminal), or
   inspect with `aether diagnostics`.
3. `aether repair` fixes missing fragments, broken links, an invalid `config.json`, disabled units.
4. GPU problems: `aether graphics verify`; roll back drivers per NVIDIA_GUIDE.md §6.
5. Full rollback of configs: `scripts/restore.sh ~/.aetheros-backups/<archive>`.
