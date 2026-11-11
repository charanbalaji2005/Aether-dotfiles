# GPU-aware rendering

Everything visual is decided in one place, `services/PerformanceService.qml`, and explained
live in Settings → Effects and System Centre → Performance.

## Quality tiers

| Tier | What you get |
|---|---|
| **eco** | flat translucent surfaces, no shaders, no ambient work; fastest and lightest |
| **performance** | glass shader and quick motion; no glow, particles, aurora, parallax or pointer light — for games or a busy GPU |
| **balanced** | everything except particles |
| **ultra** | particles and the richest lighting |

*Automatic* picks a tier from `aether capabilities` (sysfs only — discrete desktop GPU → ultra,
hybrid → balanced, VM/nouveau/low memory → eco), then:

1. **Power** — on battery: at most balanced; power-saver profile: eco.
2. **GPU pressure** — VRAM ≥ 88 % or load ≥ 92 % for 3 samples → one tier down until 10 samples
   are below threshold − 8 points (hysteresis: no flapping). Thresholds in Settings → GPU.
3. **Frame pacing** — measured only while the shell animates; if more than a fifth of frames
   miss 1.5× the display's budget, one tier down until three smooth windows in a row.
4. **Fullscreen** — ambient work (particles, parallax, video wallpaper) pauses.
5. **Safe mode** — eco, nothing optional.

A manual tier is respected except in safe mode. Every automatic change is logged with its reason.

## What costs what

| Effect | Cost at rest | Notes |
|---|---|---|
| Glass frost (shader) | none (static) | redrawn only when the pointer moves over a panel |
| Glow edge | per frame while active | only on focused/active surfaces |
| Aurora | per frame | lock screen / aurora wallpaper only; still frame when not allowed |
| Particles | per frame | Qt Quick Particles (GPU instanced), paused when hidden |
| Springs | none at rest | frame callback only while moving |
| Wallpaper transition | during the transition only | one decode per image |
| Video wallpaper | continuous | mpvpaper with hardware decoding where mpv deems it safe |
| Window thumbnails | one capture per open | not live streams |

## Shaders

Five fragment shaders (`graphics/shaders`): glass, glow, aurora, transition, parallax. The
bundled `.qsb` files are built with Qt 6.7's `qsb`; `scripts/build-shaders.sh` rebuilds them for
your Qt into `~/.cache/aether-shell/shaders`. A shader that fails to load is recorded once and
its effect falls back to plain Qt Quick for the session.

## Diagnostics

```sh
aether capabilities          # recommended tier and why (never wakes a dGPU)
aether render                # Qt backend, EGL/Vulkan/VA-API drivers, PRIME env (files only)
aether render --probe        # + eglinfo / vulkaninfo (wakes the dGPU briefly)
aether gpu                   # live counters
aether graphics verify       # driver stack checks
```
