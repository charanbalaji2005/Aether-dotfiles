# Hardware compatibility

AetherOS detects hardware from sysfs/procfs and adapts; nothing is assumed. This page says what
is expected to work, what depends on drivers, and how to verify it on **your** machine.

## Support matrix

| Hardware | Rendering | Telemetry | Notes |
|---|---|---|---|
| NVIDIA (proprietary driver, Turing or newer) | OpenGL/Vulkan via the NVIDIA driver | NVML in-process (usage, VRAM, temperature, power, power limit, clock, GPU processes); `nvidia-smi` fallback | Driver install: `aether graphics install-nvidia` (asks first; [NVIDIA_GUIDE](NVIDIA_GUIDE.md)) |
| NVIDIA on nouveau | limited | none | quality capped at *eco*; installing the proprietary driver is recommended |
| AMD (amdgpu) | Mesa radeonsi / RADV | sysfs: busy %, VRAM, temperature, power | |
| Intel (i915 / xe) | Mesa iris / ANV | sysfs: clock; no utilisation counter is exposed | |
| Hybrid laptops (Intel/AMD iGPU + NVIDIA/AMD dGPU) | desktop on the iGPU; apps on the dGPU via `aether gpu run` | dGPU queried **only while a detail view is open**, through a transient session | so the dGPU can runtime-suspend |
| Virtual machines (virtio-gpu, QXL, VMware) | Mesa / llvmpipe | none | quality capped at *eco* |
| No GPU / software rendering | Qt software backend | — | shaders and particles off |

**Displays:** any number, mixed refresh rates and scales; modes are restricted to what each
monitor reports. **Input:** any libinput device; XKB layouts from the system's rules.
**Battery/power:** UPower; health only where the firmware reports it.

## Your RTX 4050 Laptop (6 GB) specifically

* The desktop renders on the integrated GPU; the RTX 4050 sleeps until something uses it.
  Check: `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status` → `suspended` at idle.
* With the dashboard or System Centre open, AetherOS reads NVML once per tick and closes it,
  so the GPU can sleep again afterwards. Everything else never touches it.
* GPU pressure: effects step down after 3 consecutive samples above 88 % VRAM or 92 % load
  and come back after 10 samples below the threshold minus 8 points (Settings → GPU).
  With 6 GB, a game plus a browser can cross 88 % — that's the intended behaviour.
* Run games/apps on the dGPU: `aether gpu run <app>` (PRIME offload), or Steam's launch option
  `aether gpu run %command%`.

## Validation checklist (needed before calling a release "1.0.0")

Run these on real hardware and record the results in TEST_REPORT.md.

| # | Check | How |
|---|---|---|
| 1 | Session starts, no QML errors | log in; `journalctl --user -u aether-shell -b \| grep -i -E "error\|warn"` |
| 2 | NVIDIA acceleration | `aether render --probe` shows the NVIDIA renderer for `aether gpu run glxgears`-style apps; desktop renderer is the iGPU |
| 3 | dGPU sleeps at idle | `runtime_status` = `suspended` with dashboard closed for 30 s |
| 4 | NVML counters | dashboard shows usage/VRAM/temperature/power and GPU processes |
| 5 | VRAM under load | run a game/benchmark; Settings → GPU shows pressure entering and recovering without flapping |
| 6 | Frame pacing | System Centre → Performance: average animation frame time below the display's budget |
| 7 | PAM unlock | lock (`SUPER+L`), wrong password (shake, message), right password unlocks |
| 8 | Crash while locked | `pkill -f "qs -c aether-shell"` while locked → shell restarts, lock re-acquired, password field back |
| 9 | Multi-monitor + hotplug | connect/disconnect an external display; bars/wallpapers follow; display profile re-applies |
| 10 | Display revert | apply an odd mode in Settings → Displays, don't confirm → reverts after 15 s |
| 11 | Suspend/resume | close the lid / `systemctl suspend`; locks before sleep; resumes; video wallpaper resumes |
| 12 | Long session | 8 h of normal use: `systemctl --user status aether-shell` memory stays flat |
| 13 | Hyprland 0.53 rules | `aether hyprland` (runs `--verify-config`) reports no errors in rules-v2.conf |
| 14 | Mic/camera indicator | join a video call in a browser → island shows mic/camera with the app name |
| 15 | Widgets input | widgets clickable, empty desktop click-through |
