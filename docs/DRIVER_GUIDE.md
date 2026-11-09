# Graphics driver guide (Fedora)

`aether` detects the GPUs on the PCI bus and reports, per GPU, the kernel driver in use and what
(if anything) to install. It never installs anything without showing the command and asking.

```sh
aether graphics detect     # hardware + full stack: driver, Mesa, OpenGL, Vulkan, VA-API, CUDA
aether graphics drivers    # per-GPU recommendation, including video-codec packages
aether graphics verify     # PASS / WARN / FAIL checks
aether gpu [--watch]       # live usage, temperature, VRAM, power
```

The probe tools are optional; without them a check says *not checked* and names the package
instead of guessing:

| Tool | Package | Used for |
|---|---|---|
| `lspci` | `pciutils` | GPU model names (falls back to `hwdata`'s pci.ids) |
| `vulkaninfo` | `vulkan-tools` | Vulkan devices/drivers |
| `vainfo` | `libva-utils` | hardware video decode/encode profiles |
| `eglinfo` / `glxinfo` | `egl-utils` / `glx-utils` | OpenGL renderer (detects software rendering) |
| `nvidia-smi` | `xorg-x11-drv-nvidia-cuda` | NVIDIA telemetry, CUDA |

All of these are in `packages/fedora/optional.txt`.

## NVIDIA

See **[NVIDIA_GUIDE.md](NVIDIA_GUIDE.md)** — driver branch selection by chip generation, RPM
Fusion, akmods, Secure Boot key enrolment, hybrid graphics, rollback.

## AMD (Radeon)

**Nothing to install for the driver.** AMD GPUs use the in-kernel `amdgpu` driver plus Mesa:
RADV for Vulkan, radeonsi for OpenGL and VA-API. Fedora ships both by default.

`aether graphics verify` checks: `amdgpu` bound, render node present, RADV ICD installed
(`mesa-vulkan-drivers`), OpenGL renderer is not `llvmpipe`, VA-API profiles.

**Video decode:** Fedora's own `mesa-va-drivers` leaves out H.264/HEVC for patent reasons, so
`verify` warns *No H.264 hardware decode*. The full driver comes from RPM Fusion (free):

```sh
sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld
```

Older GCN 1.0/1.1 cards (HD 7000 / R9 200 era) may be bound to the legacy `radeon` driver;
`aether graphics drivers` explains the kernel parameters that move them to `amdgpu` (needed for
Vulkan) — change those only if you need to.

Telemetry: usage (`gpu_busy_percent`), VRAM, temperature and power come straight from sysfs —
no extra tools.

## Intel

**Nothing to install for the driver.** Intel GPUs use `i915` (or `xe` on newer generations)
plus Mesa: ANV for Vulkan (HASVK for Gen7/8), iris for OpenGL.

**Video decode:** Broadwell (5th gen) and newer use the iHD VA-API driver. For full codec
support install it from RPM Fusion (nonfree):

```sh
sudo dnf install intel-media-driver
```

Older GPUs use `libva-intel-driver` (i965).

Telemetry: GPU clock is shown; **utilisation is reported as unavailable**, because reading it
needs perf counters (`intel_gpu_top`) with elevated privileges, and the panel doesn't run
anything as root. Integrated GPUs share system RAM, so there is no separate VRAM figure.

## Hybrid graphics (iGPU + dGPU)

Detected automatically (`layout: hybrid`). The integrated GPU stays the default renderer — this
is preserved on purpose for battery life — and nothing vendor-specific is set globally.

* Run one program on the discrete GPU: `aether gpu run <command>` (PRIME offload; `DRI_PRIME`
  for Mesa dGPUs, the `__NV_PRIME_RENDER_OFFLOAD` variables for NVIDIA).
* Make the compositor itself use another GPU: `aether graphics configure --primary <PCI slot>`.
* A runtime-suspended dGPU is never queried by the panel, `detect` or `verify`, so it can stay
  asleep.

## Virtual machines

virtio-gpu, QXL, VMware and VirtualBox adapters are recognised as virtual. Hyprland needs 3D
acceleration (virtio-gpu with virgl) to render properly; `aether graphics configure` notes this.

## CPU

```sh
aether cpu [--watch]
```

Vendor and model, cores/threads/sockets, current and max frequency, scaling driver
(`intel_pstate`, `amd-pstate-epp`, `acpi-cpufreq`), governor, energy-performance preference,
boost state, package temperature (`coretemp` / `k10temp` / `zenpower`), virtualisation
extensions (VT-x / AMD-V) and whether KVM is usable. Reported only — AetherOS never changes
governors, frequencies, voltages or power limits. The only performance control it offers is the
system power profile (`aether performance set …`, see HYPRLAND_GUIDE.md §Performance), which
goes through power-profiles-daemon/tuned-ppd.
