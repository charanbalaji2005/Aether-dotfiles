# Hyprland on AetherOS

## File layout

```
config/hypr/                    (in the repo, symlinked to ~/.config/hypr)
  hyprland.conf                 entry point — sources everything below
  env.conf                      toolkit/session environment (Wayland-native Qt/GTK/Electron)
  monitors.conf                 monitor layout (edit for multi-monitor)
  workspaces.conf               workspace definitions
  keybinds.conf                 key bindings (docs/KEYBINDS.md)
  rules.conf                    layer rules (shell blur), window rules, smart gaps
  recovery.conf                 standalone minimal config — NOT sourced (see Recovery)

~/.config/aether-shell/hypr/    (per machine, generated, not in the repo)
  hardware.conf                 GPU environment         ← aether graphics configure
  compat.conf                   version-specific syntax ← aether hyprland compat
  profile.conf                  visual/perf profile     ← aether performance hyprland <name>
```

Source order in `hyprland.conf`: `env.conf` → `hardware.conf` → monitors/workspaces/keybinds/
rules → `compat.conf` → main settings → **`profile.conf` last**, so a profile overrides the
defaults. `setup-symlinks.sh` creates the three fragments (comment-only) before Hyprland first
starts, and `aether repair` recreates them if deleted, so a `source =` line never points at a
missing file. They live outside the repo because they describe *this* machine; generating them
inside the symlinked repo would show up as uncommitted changes.

## Version compatibility

Hyprland's config syntax changes between releases. AetherOS handles that in three ways:

1. **Generated, version-aware syntax.** Settings whose syntax changed are written by
   `aether hyprland compat` for the installed version. Currently: touchpad workspace gestures
   (`gesture = 3, horizontal, workspace` on ≥ 0.51, the old `gestures { workspace_swipe }` block
   before). Re-run after upgrading Hyprland.
2. **Real validation.** `aether hyprland` runs `Hyprland --verify-config` against your config and,
   inside a session, `hyprctl configerrors`. Run it after every Hyprland upgrade.
3. **No obsolete workarounds.** The shared config contains no NVIDIA-era hacks; a repo test
   (`tests/hyprland/test_config_syntax.sh`) fails if any creep back in.

The shared files target the syntax used throughout this repo (`windowrule = <rule>, class:…`,
the `shadow { }` block — Hyprland 0.45+). If a future release changes window-rule syntax,
`aether hyprland` will report the exact lines.

## Visual design

* Rounded corners (14 px), 5/10 px gaps, gradient active border in the AetherOS accent pair.
* Soft offset shadows, lighter on inactive windows.
* Blur tuned for cost: 2 passes by default, `new_optimizations`, `ignore_opacity`, blur on popups.
* **Smart gaps:** a lone tiled window gets no gaps, border or rounding (`rules.conf`).
* Animation curves: an expressive deceleration for things appearing, a quicker curve for things
  leaving, popin for windows, slide-fade for workspaces, vertical slide for the scratchpad.
* Shell surfaces animate themselves (with reduced-motion support), so `rules.conf` disables
  Hyprland's own layer animation for them to avoid double animation.

## Performance profiles

```sh
aether performance hyprland quality       # stronger blur, softer shadows, full animations
aether performance hyprland balanced      # the defaults
aether performance hyprland low-latency   # no blur/shadows, short animations, tearing allowed
aether performance hyprland battery       # no blur/shadows/animations, opaque windows
aether performance                        # show current profiles
```

Also in Settings → Performance. Hyprland reloads the changed file automatically — this is a
config reload, never a compositor restart.

*Low latency* sets `general:allow_tearing = true`; tearing only applies to windows with the
`immediate` rule, which the profile adds for Steam games (`class:^(steam_app_.*)$`). Add your own
the same way.

The **system** power profile is separate:

```sh
aether performance set power-saver|balanced|performance
```

This goes through `powerprofilesctl` (power-profiles-daemon, or tuned-ppd on Fedora 41+). The
control centre's Battery Saver and Performance tiles use the same interface.

`misc:vfr = true` is on in every profile: Hyprland doesn't redraw unchanged frames, which is the
biggest single idle-power saving.

## Blur and the shell

Every AetherOS surface sets an explicit layer-shell namespace (`aether-bar`, `aether-launcher`,
`aether-controlcenter`, …), so `rules.conf` matches them exactly:

```ini
layerrule = blur, ^(aether-(bar|launcher|controlcenter|dashboard|notifications|toasts|settings|clipboard|bluetooth|wallpicker|osd))$
layerrule = ignorezero, ^(aether-(…))$
```

`ignorezero` means fully transparent pixels (the invisible click-catcher around popups) are not
blurred, so only the visible cards pay for blur. Settings → Appearance → *Background blur* can
force blur on/off at runtime (`hyprctl keyword decoration:blur:enabled`); the shell re-applies it
after a config reload.

## GPUs

`aether graphics configure` writes `hardware.conf`. See NVIDIA_GUIDE.md §5 for what it writes on
NVIDIA, hybrid and Mesa systems, and how to pick the compositor's GPU with `--primary`.

## Multiple monitors

`monitors.conf` ships with a catch-all `monitor = , preferred, auto, 1`. For fixed layouts add one
line per output (`hyprctl monitors` lists names). The control centre's Displays page changes scale
at runtime and opens `nwg-displays` (if installed), which writes `monitors.conf` for you.
Bar: one per monitor. Popups and toasts open on the focused monitor. Wallpapers can be set per
display (right-click in the wallpaper picker).

Keybinds: `SUPER+ALT+←/→` focus monitor, `SUPER+ALT+SHIFT+←/→` move the workspace there.

## Screenshots and clipboard

* `Print` full screen, `SHIFT+Print` / `SUPER+SHIFT+S` region — saved to
  `~/Pictures/Screenshots` and copied to the clipboard (`aether-screenshot`, grim + slurp).
* `SUPER+V` clipboard history (cliphist, recorded by `aether-clipboard.service`).

## Recovery

If Hyprland won't start (bad GPU fragment, config error after an upgrade):

1. **Ctrl+Alt+F3**, log in.
2. `Hyprland -c ~/.config/hypr/recovery.conf` — no GPU environment, no shell, no effects, a
   terminal opens automatically.
3. In that terminal: `aether diagnostics`, then `aether repair`.
4. To reset just the GPU settings: `rm ~/.config/aether-shell/hypr/hardware.conf && aether repair`.
