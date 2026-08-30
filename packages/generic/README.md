# Generic / other distributions

No package manager automation is provided for distributions outside Fedora and Arch — every
other distro's package names and repo layout vary too much to script safely without testing on
each one, and I'm not going to pretend that's been done when it hasn't. `scripts/bootstrap.sh`
detects Fedora and Arch specifically; on anything else it stops and points here rather than
guessing.

## What you need, distro-agnostic

Install these however your distribution does it (native package manager, Flatpak, or from
source), then run `scripts/setup-symlinks.sh` directly — that part isn't distro-specific.

**Required:**
- Hyprland
- Quickshell ≥ 0.2 ([quickshell.org](https://quickshell.org) — check there first for a packaged
  build before building from source)
- Qt6 (Core, Declarative/QML, Wayland)

**Needed for individual shell features to work (each degrades gracefully if missing — see the
shell's own README for exactly which module needs which):**
- PipeWire + WirePlumber (audio)
- UPower (battery)
- NetworkManager with `nmcli` on `PATH` (network)
- BlueZ (Bluetooth)
- `cliphist` + `wl-clipboard` (clipboard history)
- `grim` + `slurp` (screenshots)
- `playerctl` (media keys)
- `brightnessctl` (brightness keys)
- A polkit agent (`hyprpolkitagent` or your desktop's own)
- kitty, zsh (or adjust `config/kitty`/`config/zsh` for your preferred terminal/shell)

## After installing dependencies manually

```sh
./scripts/setup-symlinks.sh
./scripts/doctor.sh   # confirms what's actually detected on your system
```
