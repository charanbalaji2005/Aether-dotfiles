# `aether` command reference

Generated from the CLI's own argument parser by `tools/gen_cli_reference.py` (AetherOS 1.0.0).
Every command supports `--json` where it reports data, never needs root, and logs to
`~/.local/state/aether/aether.log` (secrets redacted).

| Command | Purpose |
|---|---|
| [`ai`](#aether-ai) | assistant: status \| ask \| actions \| set-key \| clear-key \| history |
| [`automation`](#aether-automation) | automation rules: list \| validate \| import \| export |
| [`autostart`](#aether-autostart) | startup applications (XDG autostart): list \| enable \| disable \| add \| remove \| run |
| [`capabilities`](#aether-capabilities) | what visual quality this machine is comfortable with (never wakes a sleeping GPU) |
| [`config`](#aether-config) | shell settings file: validate \| migrate \| reset \| export \| import \| get \| set |
| [`cpu`](#aether-cpu) | CPU model, topology, frequency, governor, temperature and live usage |
| [`diagnostics`](#aether-diagnostics) | full health report (dependencies, Hyprland config, graphics, power) |
| [`display`](#aether-display) | monitors: list \| apply (auto-reverts unless confirmed) \| confirm \| revert \| save-profile \| auto |
| [`gpu`](#aether-gpu) | GPU list with live usage, temperature, VRAM and power; `gpu run` offloads a program |
| [`graphics`](#aether-graphics) | graphics drivers: detect \| drivers \| verify \| install-nvidia \| configure |
| [`hardware`](#aether-hardware) | CPU, GPUs, memory, storage and battery overview |
| [`hyprland`](#aether-hyprland) | validate the Hyprland configuration; `hyprland compat` writes version-specific syntax |
| [`idle`](#aether-idle) | idle locking: write hypridle settings from the lock-screen configuration |
| [`input`](#aether-input) | keyboard/mouse/touchpad: show \| apply \| layouts |
| [`island`](#aether-island) | post a message to the Dynamic Island from your own scripts |
| [`layout`](#aether-layout) | window layouts: list \| preview \| apply \| undo \| save |
| [`logs`](#aether-logs) | recent AetherOS log lines (redacted); --audit for the action audit trail |
| [`performance`](#aether-performance) | power profiles and Hyprland visual profiles |
| [`profile`](#aether-profile) | desktop profiles: list \| show \| apply \| save \| import \| export |
| [`recover`](#aether-recover) | fix a broken desktop: safe mode, repair fragments, optional last-known-good restore |
| [`render`](#aether-render) | rendering diagnostics: Qt Quick backend, EGL/Vulkan/VA-API drivers, PRIME (files only unless --probe) |
| [`repair`](#aether-repair) | fix common problems (missing fragments, broken symlinks, invalid config, units) |
| [`reset-section`](#aether-reset-section) | reset one settings section to its defaults (snapshot first) |
| [`safe-mode`](#aether-safe-mode) | start the shell with every optional effect disabled |
| [`security`](#aether-security) | SELinux, firewall, Secure Boot and disk-encryption status (read-only) |
| [`services`](#aether-services) | systemd user services: list \| start \| stop \| restart \| log |
| [`snapshot`](#aether-snapshot) | configuration snapshots: create \| list \| verify \| preview \| restore \| mark-good |
| [`system`](#aether-system) | OS, kernel, session, Secure Boot and Hyprland version |
| [`telemetry`](#aether-telemetry) | live metrics as JSON (used by the shell) |
| [`theme`](#aether-theme) | accent colour from a wallpaper; dark/light mode |
| [`themes`](#aether-themes) | custom colour themes: list \| create \| import \| export \| delete |
| [`updates`](#aether-updates) | list available Fedora updates (installs nothing) |
| [`widget`](#aether-widget) | desktop widgets: list \| inspect \| install \| remove |
| [`workspace`](#aether-workspace) | workspaces: rules (write app→workspace rules) \| save \| restore (session) |

## aether ai

assistant: status | ask | actions | set-key | clear-key | history

```
aether ai [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether ai status` — status [-h] [--probe] [--json]
- `aether ai ask` — question as arguments, or {"messages": [...]} on stdin
- `aether ai actions` — actions [-h] [--json]
- `aether ai set-key` — stored in the desktop keyring; read from stdin
- `aether ai clear-key` — clear-key [-h] [--provider PROVIDER] [--json]
- `aether ai history` — history [-h] [--clear]
- `aether ai log-action` — log-action [-h] [--ran] data

## aether automation

automation rules: list | validate | import | export

```
aether automation [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether automation list` — list [-h] [--json]
- `aether automation validate` — validate [-h] [--json] [file]
- `aether automation import` — import [-h] file
- `aether automation export` — export [-h] file

## aether autostart

startup applications (XDG autostart): list | enable | disable | add | remove | run

```
aether autostart [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether autostart list` — list [-h] [--json]
- `aether autostart run` — start entries for this session (used at login)
- `aether autostart enable` — enable [-h] [--json] id
- `aether autostart disable` — disable [-h] [--json] id
- `aether autostart add` — add [-h] [--json] id
- `aether autostart remove` — remove [-h] [--json] id

## aether capabilities

what visual quality this machine is comfortable with (never wakes a sleeping GPU)

```
aether capabilities [-h] [--json]
  --json                       machine-readable output
```

## aether config

shell settings file: validate | migrate | reset | export | import | get | set

```
aether config [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether config validate` — check config.json against the schema
- `aether config migrate` — upgrade an older config.json
- `aether config reset` — back up and reset all settings
- `aether config export` — write a validated copy
- `aether config import` — replace settings from a file (validated; nothing in it is executed)
- `aether config get` — print one setting
- `aether config set` — change one setting (validated)

## aether cpu

CPU model, topology, frequency, governor, temperature and live usage

```
aether cpu [-h] [--json] [--watch] [--interval INTERVAL]
  --json                       machine-readable output
  --watch                      refresh continuously (Ctrl+C to stop)
  --interval                   
```

## aether diagnostics

full health report (dependencies, Hyprland config, graphics, power)

```
aether diagnostics [-h] [--json]
  --json                       machine-readable output
```

## aether display

monitors: list | apply (auto-reverts unless confirmed) | confirm | revert | save-profile | auto

```
aether display [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether display list` — list [-h] [--json]
- `aether display apply` — apply [-h] [--position POSITION] [--scale SCALE]
                            [--confirm-within CONFIRM_WITHIN] [--json]
                            monitor mode
- `aether display confirm` — confirm [-h] [--json]
- `aether display revert` — revert [-h] [--json]
- `aether display auto` — auto [-h] [--json]
- `aether display save-profile` — save-profile [-h] [--json] name

## aether gpu

GPU list with live usage, temperature, VRAM and power; `gpu run` offloads a program

```
aether gpu [-h] [--json] [--watch] [--interval INTERVAL] [run] ...
  --json                       machine-readable output
  --watch                      refresh continuously (Ctrl+C to stop)
  --interval                   
```

- `aether gpu run` — run a program on the discrete GPU (PRIME offload)

## aether graphics

graphics drivers: detect | drivers | verify | install-nvidia | configure

```
aether graphics [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether graphics detect` — detect GPUs and the full graphics stack
- `aether graphics drivers` — recommend drivers and codec packages per GPU (installs nothing)
- `aether graphics verify` — PASS/WARN/FAIL checks of the running graphics stack
- `aether graphics install-nvidia` — install the matching RPM Fusion NVIDIA driver (Fedora)
- `aether graphics configure` — write Hyprland GPU settings for this machine

## aether hardware

CPU, GPUs, memory, storage and battery overview

```
aether hardware [-h] [--json]
  --json                       machine-readable output
```

## aether hyprland

validate the Hyprland configuration; `hyprland compat` writes version-specific syntax

```
aether hyprland [-h] [--json] [verify|compat] ...
  --json                       machine-readable output
```

- `aether hyprland verify` — check the config with Hyprland itself
- `aether hyprland compat` — write settings whose syntax depends on the Hyprland version

## aether idle

idle locking: write hypridle settings from the lock-screen configuration

```
aether idle [-h] [--json] [--dry-run] [apply|show] ...
  --json                       machine-readable output
  --dry-run                    
```

- `aether idle apply` — apply [-h]
- `aether idle show` — show [-h]

## aether input

keyboard/mouse/touchpad: show | apply | layouts

```
aether input [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether input show` — show [-h] [--json]
- `aether input layouts` — layouts [-h] [--json]
- `aether input apply` — write input.conf from settings and apply live

## aether island

post a message to the Dynamic Island from your own scripts

```
aether island [-h] [--json] title [body]
  --json                       machine-readable output
```

## aether layout

window layouts: list | preview | apply | undo | save

```
aether layout [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether layout list` — list [-h] [--json]
- `aether layout preview` — preview [-h] [--monitor MONITOR] [--json] name
- `aether layout apply` — apply [-h] [--monitor MONITOR] [--json] [--no-launch] name
- `aether layout undo` — undo [-h] [--json]
- `aether layout save` — save the focused workspace's arrangement

## aether logs

recent AetherOS log lines (redacted); --audit for the action audit trail

```
aether logs [-h] [--json] [--audit] [--shell] [--lines LINES]
  --json                       machine-readable output
  --audit                      
  --shell                      also the aether-shell journal
  --lines                      
```

## aether performance

power profiles and Hyprland visual profiles

```
aether performance [-h] [--json] [status|list|set|hyprland] ...
  --json                       machine-readable output
```

- `aether performance status` — show current profiles
- `aether performance list` — list available profiles
- `aether performance set` — set the system power profile
- `aether performance hyprland` — set the Hyprland visual profile

## aether profile

desktop profiles: list | show | apply | save | import | export

```
aether profile [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether profile list` — list [-h] [--json]
- `aether profile show` — show [-h] name
- `aether profile apply` — apply [-h] [--dry-run] [--no-hyprland] [--json] name
- `aether profile save` — save the current look as a profile
- `aether profile import` — import [-h] [--json] file name
- `aether profile export` — export [-h] [--json] name file

## aether recover

fix a broken desktop: safe mode, repair fragments, optional last-known-good restore

```
aether recover [-h] [--json] [--restore] [--yes]
  --json                       machine-readable output
  --restore                    also offer to restore the last-known-good configuration
  --yes                        
```

## aether render

rendering diagnostics: Qt Quick backend, EGL/Vulkan/VA-API drivers, PRIME (files only unless --probe)

```
aether render [-h] [--json] [--probe]
  --json                       machine-readable output
  --probe                      also run eglinfo/vulkaninfo (may wake a discrete GPU)
```

## aether repair

fix common problems (missing fragments, broken symlinks, invalid config, units)

```
aether repair [-h] [--json] [--dry-run] [--yes]
  --json                       machine-readable output
  --dry-run                    
  --yes                        
```

## aether reset-section

reset one settings section to its defaults (snapshot first)

```
aether reset-section [-h] [--json] section
  --json                       machine-readable output
```

## aether safe-mode

start the shell with every optional effect disabled

```
aether safe-mode [-h] [--json] [on|off|status] ...
  --json                       machine-readable output
```

- `aether safe-mode on` — on [-h]
- `aether safe-mode off` — off [-h]
- `aether safe-mode status` — status [-h] [--json]

## aether security

SELinux, firewall, Secure Boot and disk-encryption status (read-only)

```
aether security [-h] [--json]
  --json                       machine-readable output
```

## aether services

systemd user services: list | start | stop | restart | log

```
aether services [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether services list` — list [-h] [--json]
- `aether services start` — start [-h] [--json] unit
- `aether services stop` — stop [-h] [--json] unit
- `aether services restart` — restart [-h] [--json] unit
- `aether services log` — log [-h] [--json] [--lines LINES] unit

## aether snapshot

configuration snapshots: create | list | verify | preview | restore | mark-good

```
aether snapshot [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether snapshot create` — snapshot the current settings
- `aether snapshot list` — list [-h] [--json]
- `aether snapshot mark-good` — record the current settings as last-known-good
- `aether snapshot verify` — verify [-h] [--json] name
- `aether snapshot preview` — preview [-h] [--json] [--only ONLY] name
- `aether snapshot restore` — restore [-h] [--json] [--only ONLY] [--yes] name

## aether system

OS, kernel, session, Secure Boot and Hyprland version

```
aether system [-h] [--json]
  --json                       machine-readable output
```

## aether telemetry

live metrics as JSON (used by the shell)

```
aether telemetry [-h] [--json] [--stream] [--interval INTERVAL] [--processes]
                        [--count COUNT]
  --json                       machine-readable output
  --stream                     one JSON line per interval until stdout closes
  --interval                   
  --processes                  emit the top-processes table instead of system metrics
  --count                      stop after N lines (testing)
```

## aether theme

accent colour from a wallpaper; dark/light mode

```
aether theme [-h] [--json] <accent|mode> ...
  --json                       machine-readable output
```

- `aether theme accent` — derive an accent colour from an image
- `aether theme mode` — set the shell theme
- `aether theme palettes` — list colour palettes
- `aether theme terminals` — list detected terminals
- `aether theme palette` — select a palette and theme terminals/Hyprland to match
- `aether theme icons` — list installed icon themes, or --set one
- `aether theme cursor` — list installed cursor themes, or --set one
- `aether theme apply` — re-write terminal/Hyprland theme files for the current palette

## aether themes

custom colour themes: list | create | import | export | delete

```
aether themes [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether themes list` — list [-h] [--json]
- `aether themes create` — new theme from a palette with overrides
- `aether themes import` — import [-h] [--json] file id
- `aether themes export` — export [-h] [--json] id file
- `aether themes delete` — delete [-h] [--yes] [--json] id

## aether updates

list available Fedora updates (installs nothing)

```
aether updates [-h] [--json]
  --json                       machine-readable output
```

## aether widget

desktop widgets: list | inspect | install | remove

```
aether widget [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether widget list` — list [-h] [--json]
- `aether widget inspect` — inspect [-h] [--json] path
- `aether widget install` — a widget directory or .zip (validated; asks to confirm its permissions)
- `aether widget trust` — trust a user-installed widget (pinned to its current files)
- `aether widget untrust` — untrust [-h] [--json] id
- `aether widget disable-third-party` — recovery: stop loading all non-built-in widgets
- `aether widget remove` — remove [-h] [--json] id

## aether workspace

workspaces: rules (write app→workspace rules) | save | restore (session)

```
aether workspace [-h] [--json] <subcommand> ...
  --json                       machine-readable output
```

- `aether workspace rules` — rules [-h] [--json]
- `aether workspace save` — remember open apps and their workspaces
- `aether workspace restore` — reopen saved apps on their workspaces
