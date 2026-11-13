# Installing AetherOS Dotfiles

© 2026 Neelampalli Charan Balaji · GPL-3.0-or-later · <https://github.com/charanbalaji2005/Aether-dotfiles>

**Target:** Fedora Workstation (or any Fedora edition with DNF) **41 or newer**, x86_64 or
aarch64. Atomic editions (Silverblue, Kinoite…) are refused because the installer layers packages
with dnf; their users can run `./install.sh --install --no-packages` after installing the tools in
a toolbox. Other distributions: `packages/generic/README.md` lists what to install by hand, then
use `--no-packages`.

## 1. Before you start

```sh
sudo dnf upgrade --refresh && sudo reboot     # newest kernel first (matters for NVIDIA akmods)
```

Run everything as your **normal user** — the installer refuses root and asks for `sudo` once,
only when it installs packages or enables a system service. Keep a TTY in mind for the first
login (**Ctrl+Alt+F3**); see [RECOVERY.md](RECOVERY.md).

## 2. Install with the onboarding installer

One command (like JaKooLit's installers):

```sh
sh <(curl -fsSL https://raw.githubusercontent.com/charanbalaji2005/Aether-dotfiles/release-final/auto-install.sh)
```

`auto-install.sh` installs git if needed, clones the `release-final` branch to
`~/.local/share/aether-dotfiles` (your desktop runs from there afterwards — don't delete it),
shows the exact commit and starts `./install.sh`. Add `--auto` to install everything
recommended without a single question: all packages, the COPR repositories they need, the Nerd
Font, AetherOS's `~/.zshrc` (yours is moved aside), zsh as login shell, Bluetooth, and SDDM if
the machine has no login manager. sudo asks for your password once.

Or clone it yourself:

```sh
git clone -b release-final https://github.com/charanbalaji2005/Aether-dotfiles ~/Aether-dotfiles
cd ~/Aether-dotfiles
./install.sh
```

**Fedora 44 ships no Hyprland.** Hyprland, hypridle, hyprlock, the portal, polkit agent,
hyprsunset, hyprpicker, hyprpaper, swww and nwg-look come from the
[sdegler/hyprland](https://copr.fedorainfracloud.org/coprs/sdegler/hyprland/) COPR, which the
installer enables after asking (or with `--auto` / `--enable-copr`).

What you see:

1. **Welcome** — logo, version and copyright, then this machine: distribution, kernel, CPU,
   GPUs with the driver in use, memory, display, desktop, Hyprland/Waybar/Quickshell versions,
   login manager, free disk space, and whether the prerequisites are present.
2. **Support** (first run only) — the repository link; open it in your browser or star it with
   the GitHub CLI, only if you choose to.
3. **Main menu** — *Start installation* · *Update existing dotfiles* · *Restore previous
   configuration* · *Installation information* · *Exit*. An interrupted installation is
   detected here and resumed.
4. **Components** — *Recommended*, *Select all*, *Custom* (pre-ticked with the recommended set)
   or *Deselect all*. Components you don't select keep your current configuration.
5. **Questions, all up front** — the packages to install (sudo dnf), COPR repositories if a
   package is only there, replacing your `~/.zshrc`, the Nerd Font download, enabling the
   Bluetooth service, the SDDM theme. Then a summary and *Start installation?*
6. **Live progress** — `[3/20] Installing Waybar` with a spinner and elapsed time, a download
   bar with percentage, speed and size (DNF, git, curl), the latest log lines, then ✔ or ✖
   per step. A failing component doesn't stop the others.
7. **Validation** — every component is checked; a report is written.
8. **Final screen** — installed, skipped and failed components, the backup, log and report;
   *Restart the Hyprland desktop*, *Reboot* (asked; never automatic), *View the log/report*.

Dialogs use whiptail (`newt`, installed on Fedora). `./install.sh --no-tui` (or
`AETHER_UI=plain`) uses numbered prompts instead.

### Components

| ID | Component |
|---|---|
| `hyprland` | Hyprland configuration — keys, rules, animations, idle and lock |
| `waybar` | Waybar — macOS-inspired top bar |
| `dynamic-island` | Dynamic Island — music player in the bar (Quickshell; falls back to a Waybar island) |
| `dock` | macOS Dock — magnifying dock with running-app dots (GTK layer-shell) |
| `rofi` | Rofi Launchpad — apps, Wi-Fi, Bluetooth, clipboard and emoji menus |
| `terminal` | Kitty, themed from your wallpaper, with tmux |
| `shell` | Zsh and shell configuration (your `~/.zshrc` is kept unless you say otherwise) |
| `themes` | GTK themes and icons (adw-gtk3, Papirus) |
| `wallpapers` | 21 bundled wallpapers; yours are kept |
| `fonts` | JetBrains Mono, Noto, JetBrainsMono Nerd Font (SHA-256 verified download) |
| `notifications` | SwayNC centre and popups |
| `bluetooth` | BlueZ and Blueman; the service is enabled only with your yes |
| `audio` | PipeWire, WirePlumber, volume and media keys |
| `login-manager` | SDDM theme only — GDM and others are never modified (not in Recommended) |
| `apps` | power menu (wlogout), colours (wallust), fastfetch, file manager |
| `aether-shell` | the Quickshell desktop (with `--interface aether`, instead of waybar/rofi/…) |

`./install.sh --list-components` prints this list for your interface.

## 3. Without menus

```sh
./install.sh --check                 # read-only preflight; exit 1 on a blocking problem
./install.sh --dry-run               # every link, move, package and command it would run
./install.sh --install               # install the recommended components
./install.sh --install --components hyprland,waybar,rofi,terminal
./install.sh --install --preset minimal
```

| Option | Meaning |
|---|---|
| `--components a,b,…` | install only these components |
| `--preset recommended\|all\|minimal` | a ready-made selection |
| `--interface classic\|aether` | classic: Waybar · Rofi · SwayNC · Wlogout · Hyprlock · swww (default); aether: the Quickshell shell. Re-runs keep your choice. See [docs/CLASSIC_INTERFACE.md](docs/CLASSIC_INTERFACE.md) |
| `--mode minimal\|recommended\|complete` | without `--components`/`--preset`: the selection and the extra package sets (default `recommended`, see §5) |
| `--yes` | don't ask before installing packages from **already enabled** repositories |
| `--enable-copr` | allow the COPR repositories in `packages/fedora/repos.conf` (otherwise asked one by one; never implied by `--yes`) |
| `--no-packages` | configs only |
| `--skip-quickshell` | don't install or build Quickshell |
| `--with-zshrc` | replace an existing `~/.zshrc` (moved to `~/.zshrc.bak.<time>`) |
| `--no-fonts` | don't offer the Nerd Font download |
| `--restart` | ignore the saved progress of an interrupted install |
| `--no-tui` | numbered prompts instead of dialog windows |
| `--auto` | everything recommended, no questions: packages + needed COPRs, Nerd Font, `~/.zshrc` (yours moved aside), zsh login shell, Bluetooth, SDDM when there is no login manager |

## 4. What the installer does

Each step is numbered, logged and resumable (an interrupted run continues where it stopped):

1. **Preflight** — Fedora release and edition, architecture, DNF5 vs DNF4, sudo, disk space and
   memory, GPUs and drivers, SELinux (reported, never changed), display manager (kept),
   conflicting bars/notification daemons, and every managed path of the selected components
   that already has something in it.
2. **Dependencies** — `packages.txt` (core) plus each selected component's packages
   (`packages/fedora/components.tsv`), each checked with `rpm -q` and `dnf repoquery` against
   your enabled repositories. For a GPU whose driver is already in use, optional userspace
   helpers are added; **drivers are never installed or replaced** (an NVIDIA GPU on nouveau gets
   a plan only: `aether graphics install-nvidia --dry-run`).
3. **Quickshell** (aether interface only) — from your repositories, else a source build after
   explicit yeses.
4. **Backup** — `scripts/backup.sh` archives everything at the managed paths to
   `~/.aetheros-backups/aetheros-backup-<time>.tar.gz`.
5. **Deploy** — AetherOS's commands (`~/.local/bin/aether*`) and user units, then each
   component: its configs are symlinked from this repository by `scripts/setup-symlinks.sh
   --only`. Anything in the way is **moved aside** to `<path>.bak.<time>` and recorded in
   `~/.local/state/aether/manifest.tsv`, never deleted. From a replaced Hyprland config, your
   keybinds are saved (commented out) to `~/.config/aether-shell/hypr/user.conf` — your own
   file, sourced last — and its `scripts/` folder to `~/.config/aether-shell/user/hypr-scripts`;
   replaced wallpapers are copied to `~/Pictures/Wallpapers`.
6. **Final configuration** — settings migration, Hyprland version-specific syntax and rules,
   GPU fragment, colours, hypridle timings, shaders compiled for your Qt.
7. **Services** — the AetherOS user units for your interface.
8. **Validation** — Hyprland config, Waybar layouts, Rofi themes, Quickshell, SwayNC, required
   programs, broken symlinks, programs started twice (exec-once, enabled units, running
   daemons), settings. Report: `~/.local/state/aether/reports/install-<time>.txt`.

Then log out and choose **Hyprland** at your login screen. Your display manager and other
desktops are untouched.

Logs: `~/.local/state/aether/logs/` (last ten kept).

## 5. Packages

| Set | File | Contents |
|---|---|---|
| core (always) | `packages/fedora/packages.txt` | python3, git, rsync, pciutils, jq, libnotify, ImageMagick, wl-clipboard, cliphist, UPower, NetworkManager… |
| per component | `packages/fedora/components.tsv` | e.g. `waybar` → waybar, network-manager-applet; `audio` → pipewire, wireplumber, pavucontrol… |
| recommended | `packages/fedora/recommended.txt` | qt6-qtshadertools, wf-recorder, nautilus, libsecret, sounds, plocate |
| complete | `optional.txt` + `advanced.txt` (+ `classic-extra.txt`) | nwg-displays, graphics diagnostics, mpvpaper, cava, satty, fzf, zoxide, btop… |

Not packaged by Fedora and therefore not installed: **Ollama** (local assistant — see
[docs/AI_ASSISTANT.md](docs/AI_ASSISTANT.md)). Every optional feature reports "unavailable" with
the reason when its package is missing. COPR candidates (`packages/fedora/repos.conf`) are only
offered when Fedora doesn't ship a package.

## 6. Update, restore, uninstall

```sh
./update.sh               # = ./install.sh --update: snapshot settings → git pull --ff-only →
                          #   re-link your components → regenerate → validate
./restore.sh              # menu: undo the installation, or restore a backup archive
./restore.sh FILE         # restore one archive from ~/.aetheros-backups
./install.sh --rollback   # uninstall, then move every recorded original back
./install.sh --uninstall  # remove links + user services; keep packages, settings, backups
```

Rollback lists the packages, any COPR and the SDDM theme drop-in the installer added, with the
exact commands to remove them — it doesn't remove packages itself (other software may depend on
them).

## 7. After installing

* `aether diagnostics` — full health report. `aether graphics verify` — GPU stack checks.
* Work through the hardware checklist in [docs/HARDWARE.md](docs/HARDWARE.md) and report what
  you find.
* `aether snapshot mark-good` once the desktop works the way you like: `aether recover` can
  return to it.
* Keys: `SUPER+H` lists every binding. Your own binds and settings:
  `~/.config/aether-shell/hypr/user.conf`.
