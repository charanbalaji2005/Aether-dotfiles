# Troubleshooting

## Start here

```sh
aether diagnostics      # dependencies, Hyprland config, graphics, power, sensors — saved report
aether repair --dry-run # what it would fix; then `aether repair`
```

`aether diagnostics` writes `~/.local/state/aether/diagnostics-<timestamp>.txt` — attach it to
bug reports. The CLI's own log is `~/.local/state/aether/aether.log`.

## Hyprland doesn't start / black screen after login

1. **Ctrl+Alt+F3**, log in on the TTY.
2. `Hyprland -c ~/.config/hypr/recovery.conf` — minimal config with no GPU environment; a
   terminal opens. If this works, the problem is in the normal config or the GPU fragment.
3. `aether hyprland` — runs `Hyprland --verify-config` and shows the offending lines.
4. After a Hyprland upgrade: `aether hyprland compat` (rewrites version-specific syntax).
5. GPU fragment suspected: `mv ~/.config/aether-shell/hypr/hardware.conf{,.off} && aether repair`.
6. NVIDIA: `aether graphics verify` (module not loaded / unsigned under Secure Boot / modeset off).
   See [NVIDIA_GUIDE.md](NVIDIA_GUIDE.md) §3 and §7.

## The bar / shell is missing

- `aether logs` (journal of `aether-shell.service`, or `$XDG_RUNTIME_DIR/aether-shell.log`).
- `command -v qs` — Quickshell built from source installs to `/usr/local/bin`.
- Run in the foreground to see QML errors: `qs -c aether-shell`.
- `systemctl --user status aether-shell.service`. After 5 crashes in 30 s systemd stops
  restarting it (to avoid a CPU-burning loop); `aether shell-reload` starts it again.
- Invalid `~/.config/aether-shell/config.json`: `aether repair` moves it aside and the shell
  recreates defaults.

## Panel shows "Unavailable" for a metric

That's deliberate — the panel never invents numbers. Settings → About shows which backends work.

| Metric | Needs |
|---|---|
| Any temperature / GPU / network / process list | the `aether` backend: `python3`; check `aether telemetry` prints JSON |
| CPU temperature | a `coretemp` (Intel) / `k10temp` (AMD) hwmon sensor — `aether cpu` shows it |
| NVIDIA usage/temp/VRAM | `nvidia-smi` (`xorg-x11-drv-nvidia-cuda`) and the proprietary driver |
| NVIDIA on a hybrid laptop shows "asleep" | normal: the dGPU is runtime-suspended and isn't woken just to read it |
| Intel GPU usage | not readable without root (`intel_gpu_top`); clock is shown instead |
| VRAM on Intel | integrated GPUs share system RAM |

If the dashboard says **"Basic mode — AetherOS backend unavailable"**, the shell fell back to
reading `/proc` directly: CPU/RAM/disk still work; fix `python3`/the repo path for the rest.

## Control centre tiles are greyed out

Each tile names what's missing in its subtitle:

- Night Light → `sudo dnf install hyprsunset`
- Battery Saver / Performance → `power-profiles-daemon` (or `tuned-ppd`) must be running;
  *"Not offered by this CPU"* means the platform has no performance profile.
- Wi-Fi → NetworkManager not running, or no Wi-Fi adapter.
- Brightness slider missing → no backlight device (desktops). External monitors over DDC/CI
  are not controlled.

## Wi-Fi: "Secrets were required, but not provided"

The password was wrong or empty. Click the network again to re-enter it. Saved networks show
*Saved* and can be forgotten with the bin icon.

## Blur isn't showing on the bar/panels

QML can't blur behind itself; Hyprland does it via `layerrule`s in `config/hypr/rules.conf`,
matched by the explicit namespaces the shell sets (`aether-bar`, `aether-launcher`, …).
`hyprctl layers` lists the namespaces. Also check Settings → Appearance → Background blur isn't
*Off*, and that the Hyprland profile isn't `battery`/`low-latency` (both disable blur).

## Accent from wallpaper does nothing

Needs ImageMagick (`magick` or `convert`). Test: `aether theme accent ~/Pictures/x.jpg`. The
error, if any, is shown under the setting.

## Clipboard history is always empty

```sh
systemctl --user status aether-clipboard.service
pgrep -af "wl-paste --watch cliphist"
```
Enable it with `systemctl --user enable --now aether-clipboard.service`.

## Screenshots aren't captured

Requires `grim` (and `slurp` for region select). Files go to `~/Pictures/Screenshots/`. Under
systemd the shell finds `aether-screenshot` because `aether-shell.service` adds `~/.local/bin`
to PATH — if you start `qs` some other way, make sure `~/.local/bin` is on your PATH.

## Lock screen: password doesn't work

- `ext-session-lock-v1` is needed (Hyprland has it).
- The PAM integration is flagged unverified against Quickshell's exact API (see the shell's
  PROGRESS.md) and fails safe (won't unlock without auth). **Keep a TTY available the first time
  you lock.**

## Suspend / resume problems on NVIDIA

`aether graphics verify` checks `PreserveVideoMemoryAllocations` and `nvidia-suspend.service`.
RPM Fusion's `xorg-x11-drv-nvidia-power` package enables both.

## GTK apps look inconsistent

`theme/gtk/*/gtk.css` is an original dark stylesheet; light mode switches libadwaita/GTK4 apps via
`gsettings color-scheme` (Settings → Appearance → Sync GTK apps), but the custom GTK3 stylesheet
itself is dark-only.

## Quickshell build fails

Check [quickshell.org](https://quickshell.org) for current build dependencies; they change.
