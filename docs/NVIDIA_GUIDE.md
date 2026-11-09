# NVIDIA on AetherOS (Fedora + Hyprland)

This guide covers what `aether graphics install-nvidia` does, why, and how to do or undo
each step by hand. For AMD and Intel see [DRIVER_GUIDE.md](DRIVER_GUIDE.md).

> **Honesty note.** The detection and planning logic is unit-tested against captured sysfs
> layouts of NVIDIA desktops, hybrid laptops, Secure Boot machines and machines without the
> driver (`tests/python/`). It has **not** been run end-to-end on physical NVIDIA hardware by
> the author of this upgrade. Every command it runs is printed first and needs confirmation, so
> you can always see — and stop — what it is about to do.

## TL;DR

```sh
aether graphics detect            # what GPU, which driver, Secure Boot, Vulkan, CUDA...
aether graphics drivers           # which driver package fits this GPU (installs nothing)
aether graphics install-nvidia    # shows the plan, asks you to type "install", then runs it
sudo reboot                       # (enrol the MOK key on the blue screen if Secure Boot is on)
aether graphics verify            # PASS/WARN/FAIL checks of the running stack
aether graphics configure         # write Hyprland's GPU settings for this machine
```

`--dry-run` shows the plan without running anything. `--json` prints the plan for scripts.

## 1. Choosing the driver branch

The installer never assumes a branch. It reads the GPU's **chip code name** from `lspci`/the
`pci.ids` database (`GA104`, `TU117M`, `GP106`, …) and maps the generation:

| Generation (code name prefix) | Package proposed | Hyprland |
|---|---|---|
| Blackwell `GB`, Hopper `GH`, Ada `AD`, Ampere `GA`, Turing `TU` | `akmod-nvidia` | yes |
| Volta `GV`, Pascal `GP`, Maxwell `GM` | `akmod-nvidia-580xx` if your repos have it, otherwise `akmod-nvidia` **with a warning** — the 580 series is the last that supports these chips | yes |
| Kepler `GK` | **nothing** — the 470xx legacy driver has no GBM support, so it can't run Hyprland; stay on nouveau | no |
| Fermi `GF` and older | **nothing** — no maintained driver; stay on nouveau | no |
| Code name not recognised | **nothing** — pass `--package akmod-nvidia[-NNNxx]` yourself after checking nvidia.com | — |

`xorg-x11-drv-nvidia-cuda` is added by default because it provides `nvidia-smi` (used by the
panel for GPU usage/temperature/VRAM) and `libcuda`. It does **not** install the CUDA toolkit.
Skip it with `--no-cuda`. Add `--vaapi` for `libva-nvidia-driver` (hardware video decode through
NVDEC in browsers/mpv).

## 2. What the plan contains

Shown in this order, each with the exact command:

1. **Enable RPM Fusion** (only if `dnf repolist` shows it isn't): installs RPM Fusion's own
   `rpmfusion-{free,nonfree}-release-<fedora>.noarch.rpm` from `mirrors.rpmfusion.org`. dnf asks
   you to confirm and to import the repository's GPG key.
2. **Secure Boot preparation** (only if Secure Boot is enabled and the akmods key isn't already
   enrolled) — see §3.
3. **Install the driver**: `sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda`. dnf shows its
   own transaction summary and asks again (unless you passed `--yes`).
4. **Build the module now** (optional): `sudo akmods --force --kernels $(uname -r)` so the installer
   can confirm the module exists before you reboot.

Before planning anything it checks:

* the machine runs Fedora and actually has an NVIDIA GPU;
* the driver isn't already installed and loaded (then it stops: nothing to do);
* the running kernel is the newest installed one. akmods builds for the newest kernel, so if you
  haven't rebooted after an update you'd end up without a module for the kernel you're on. Fix:
  `sudo dnf upgrade --refresh`, reboot, then install.

A JSON record of every command run, its exit code, and the NVIDIA packages before/after is saved
to `~/.local/state/aether/nvidia-install-<timestamp>.json`.

## 3. Secure Boot

**AetherOS never disables Secure Boot.** With Secure Boot on, the firmware only loads kernel
modules signed by a key it trusts. The NVIDIA module is built on your machine, so it has to be
signed with a local key that you enrol once:

```sh
sudo dnf install kmodtool akmods mokutil openssl
sudo kmodgenca -a                                      # creates /etc/pki/akmods/certs/public_key.der
sudo mokutil --import /etc/pki/akmods/certs/public_key.der   # choose a one-time password
sudo reboot
```

On the next boot a blue **MOK management** screen appears: *Enroll MOK* → *Continue* → *Yes* →
type the one-time password → *Reboot*. From then on akmods signs every module it builds.

Check it worked:

```sh
mokutil --sb-state                                          # SecureBoot enabled
mokutil --test-key /etc/pki/akmods/certs/public_key.der     # ... is already enrolled
modinfo -F signer nvidia                                    # shows the akmods key
aether graphics verify
```

If you missed the blue screen, run the `mokutil --import` command again and reboot.

## 4. After rebooting

`aether graphics verify` checks, among other things:

| Check | Why it matters |
|---|---|
| `nvidia` module loaded, `nouveau` not loaded | the proprietary driver is actually in use |
| module built for the running kernel / no akmods `.failed.log` | after kernel updates |
| `nvidia_drm modeset = Y` | **required** for any Wayland compositor |
| `nvidia_drm fbdev = Y` | proper VT console on 545+ |
| GBM backend (`nvidia-drm_gbm.so`) present | Hyprland renders through GBM |
| driver ≥ 555 and Hyprland ≥ 0.42 | explicit sync → no XWayland flicker |
| `PreserveVideoMemoryAllocations=1` + `nvidia-suspend.service` | session survives suspend |
| `nvidia-smi`, `libcuda.so.1` | panel telemetry, CUDA apps |
| persistence daemon state | informational — only useful for compute/headless |

## 5. Hyprland settings (`aether graphics configure`)

Writes `~/.config/aether-shell/hypr/hardware.conf` (sourced by `hyprland.conf`), showing a diff
and asking before it replaces anything. The previous version is kept as `hardware.conf.bak-*`.

**NVIDIA drives the desktop** (desktop PC, or you chose it with `--primary`):

```ini
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = LIBVA_DRIVER_NAME,nvidia       # only if libva-nvidia-driver is installed
env = NVD_BACKEND,direct             # same
```

and, only for drivers older than 555, `cursor { no_hardware_cursors = true }`.

**Deliberately never written:** `GBM_BACKEND=nvidia-drm` (breaks some apps, not needed on
current drivers), `WLR_NO_HARDWARE_CURSORS` (obsolete), `render:explicit_sync` (removed from
Hyprland — explicit sync is automatic with 555+).

**Hybrid laptops (Intel/AMD iGPU + NVIDIA dGPU):** nothing is forced globally. The desktop stays
on the integrated GPU (best battery life; the dGPU sleeps). Run individual programs on the dGPU:

```sh
aether gpu run steam
aether gpu run --gpu 0000:01:00.0 blender
```

which sets `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia
__VK_LAYER_NV_optimus=NVIDIA_only` for that program only. To make Hyprland itself render on the
dGPU (e.g. a desktop with monitors on the NVIDIA card while the iGPU is enabled):

```sh
aether graphics configure --primary 0000:01:00.0
```

This writes `AQ_DRM_DEVICES` (Hyprland ≥ 0.42; `WLR_DRM_DEVICES` before) using symlinks to
`/dev/dri/by-path/…`, because the `:` in PCI paths would break the colon-separated list.
Log out and back in for `env =` changes to apply.

The panel never wakes a sleeping dGPU: telemetry and `aether graphics detect/verify` skip GPUs
whose PCI runtime status is `suspended` and report them as asleep.

## 6. Rollback

```sh
sudo dnf history list                 # find the driver transaction
sudo dnf history undo <id>
# or remove everything NVIDIA except firmware:
sudo dnf remove '*nvidia*' --exclude=nvidia-gpu-firmware
rm ~/.config/aether-shell/hypr/hardware.conf && aether repair   # back to an empty GPU fragment
```

After removing the driver, nouveau takes over on the next boot.

## 7. If the desktop doesn't come back after installing

1. Switch to a TTY: **Ctrl+Alt+F3**, log in.
2. `aether graphics verify` — usually tells you exactly what's wrong (module not signed, not built,
   modeset off).
3. Start a minimal session that sets no GPU environment at all:
   `Hyprland -c ~/.config/hypr/recovery.conf`
4. Or roll back as in §6.
