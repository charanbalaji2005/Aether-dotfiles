# AetherOS Shell — architecture

```
shell/        surfaces (windows): bar, dock, island, overview, launcher, panels, lock, settings…
  ↓
components/   reusable, theme-aware UI (no system access)
graphics/     shader materials + WallpaperStage (pure Qt Quick, runtime-tested)
animation/    SpringValue, SpringBehavior, Reveal, GestureTracker
  ↓
services/     one system concern each; the only files importing Quickshell system modules
  ↓
Quickshell (Hyprland, Pipewire, UPower, Bluetooth, Mpris, Notifications, Pam, Wayland, Io)
```

`theme/` (tokens) and `core/` (Config, EventBus, AnimationCoordinator, Logger, Paths,
ShellState) are available to every layer. **theme/, core/, components/, animation/ and
graphics/ never import services/** — `shell.qml` is the only bridge: it binds Colors, Materials,
Metrics, Typography, Motion, Effects and FocusState from Config and PerformanceService. That is
what lets `tests/shell/runtime` load those layers in plain Qt and test them for real.

## Design system

| Token singleton | Role | Inputs (bound in shell.qml) |
|---|---|---|
| `Colors` | every colour, resolved from `Palettes.js`; high-contrast and Okabe–Ito variants | preferDark, palette, accentInput, glassOpacity, highContrast, colorBlind |
| `Materials` | glass presets → panel opacity, frost, specular | glassStyle, custom opacity, battery |
| `Metrics` / `Typography` | spacing, radii, sizes, elevation; type scale | uiScale, cornerScale |
| `Motion` | durations (speed-scaled, zero under reduced motion), stagger, spring presets | reducedMotion, speed, springs |
| `Effects` | what graphics work is allowed right now | PerformanceService |

## Animation engine

* **SpringValue** — damped harmonic oscillator (stiffness/damping/mass presets in `Motion`),
  semi-implicit Euler at a fixed 1/240 s sub-step, driven by a `FrameAnimation` that runs only
  while moving. Retargeting mid-flight keeps velocity (interruptible, continuous motion);
  `impulse()` feeds gesture velocity. Reduced motion → snap.
* **SpringBehavior** — Qt's native `SpringAnimation` as a drop-in `Behavior`.
* **Reveal / MotionCard** — staggered entrances; hover lift; press dip.
* **GestureTracker** — least-squares pointer velocity over 100 ms.
* **AnimationCoordinator** — counts running springs, measures frame times *only while
  animating*, publishes `struggling` → PerformanceService steps quality down (adaptive).

## Graphics

Shaders (`graphics/shaders/*.frag`, Vulkan-style GLSL 440, compiled to `.qsb` with Qt 6.7's
`qsb`; `scripts/build-shaders.sh` rebuilds for the installed Qt): **glass** (rounded SDF, film
grain, pointer-following specular, lit rim), **glow** (travelling conic highlight on the edge),
**aurora** (domain-warped animated gradient), **transition** (fade/wipe/circle/dissolve/
blinds/zoom), **parallax** (depth-map displacement with refinement taps). `ShaderLibrary`
resolves URLs, records load failures once, and every wrapper falls back to plain Qt Quick.
Particles use Qt Quick Particles (GPU instanced), paused whenever hidden.

## Services added in 0.3

| Service | Concern |
|---|---|
| PerformanceService | effective quality + reasons (settings, `aether capabilities`, safe mode, power, frame pacing, fullscreen) |
| WindowService | `hyprctl -j clients` on IPC events (debounced); open/close diffs; focus/close/move |
| ActionService | the allowlisted actions gestures/edges/rules may trigger |
| AutomationService | rules engine (events from existing services; debounce, re-entry guard, circuit breaker) |
| TimerService · RecordingService · VisualizerService · IslandService | island providers (timers/focus, `aether-record`, cava on the output monitor, event queue) |
| VideoWallpaperService | mpvpaper lifecycle (lock, fullscreen, battery, failures) |
| CliService | queued `aether … --json` calls; ProfileService, LayoutService, SystemService, IdleService build on it |
| MediaService (rewritten) | player selection (playing first), art, seek, position refresh on demand |
| PowerService (extended) | battery level state machine + edge-triggered alerts with hysteresis |

## Conventions

* Every service exposes `available`; UI hides or explains unavailable features.
* Helpers run through `Paths.helper(name, args)` — arguments positional, never interpolated.
* Windows use explicit layer namespaces `aether-*` (Hyprland rules match them).
* Version-sensitive Quickshell types live in their own file loaded via `Loader.source`
  (e.g. `shell/overview/WindowPreview.qml`).
* Settings sections are separate files under `shell/settings/sections/`, loaded on demand.
