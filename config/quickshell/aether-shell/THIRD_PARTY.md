# Third-Party Dependencies & Provenance

## Runtime dependencies

AetherOS Shell doesn't vendor or copy code from any of these — it talks to them at runtime through
their own public interfaces (QML bindings, IPC sockets, or CLI tools).

| Dependency | License | How it's used |
|---|---|---|
| [Quickshell](https://quickshell.org) by outfoxxed | LGPL-3.0 | The shell framework itself. AetherOS Shell is QML configuration that runs inside it. |
| [Hyprland](https://hyprland.org) | BSD-3-Clause | Compositor. Accessed via Quickshell's `Quickshell.Hyprland` IPC bindings and the public `hyprctl` CLI. |
| [PipeWire](https://pipewire.org) / WirePlumber | MIT / LGPL-2.1+ | Audio. Accessed via Quickshell's `Quickshell.Services.Pipewire` binding. |
| [UPower](https://upower.freedesktop.org) | GPL-2.0 | Battery/power state. Accessed via Quickshell's `Quickshell.Services.UPower` binding (D-Bus under the hood). |
| [NetworkManager](https://networkmanager.dev) | GPL-2.0 | Network state. Accessed by shelling out to its `nmcli` CLI — an intentionally stable public interface — not by linking or parsing its internals. |
| [BlueZ](http://www.bluez.org) | GPL-2.0 | Bluetooth. Accessed via Quickshell's `Quickshell.Bluetooth` binding (BlueZ's D-Bus interface under the hood). |
| MPRIS-compatible media players (Spotify, browsers, mpv, etc.) | N/A — spec, not code | Media control via the freedesktop MPRIS D-Bus spec, through Quickshell's `Quickshell.Services.Mpris` binding. |
| [cliphist](https://github.com/sentriz/cliphist) by sentriz | MIT | Clipboard history storage. Invoked as a CLI tool (`cliphist list/decode/delete/wipe`) — not vendored. |
| [wl-clipboard](https://github.com/bugaevc/wl-clipboard) | MIT | `wl-copy`, used to write clipboard/screenshot content. Invoked as a CLI tool. |
| [grim](https://sr.ht/~emersion/grim/) / [slurp](https://github.com/emersion/slurp) by emersion | MIT | Screenshot capture and region selection. Invoked as CLI tools. |
| [Qt6 / QML](https://www.qt.io) | LGPL-3.0 / GPL-3.0 (dual) | UI toolkit Quickshell itself is built on. |

## Fonts

Default typography references "Manrope" (SIL OFL) with a system sans-serif fallback, and
"JetBrains Mono" (SIL OFL) for future monospace/diagnostic surfaces. Neither is bundled in this
repo yet; document the actual bundled files here once assets are added.

## Provenance note

While designing this project, the GPLv3-licensed `end-4/dots-hyprland` ("illogical-impulse") shell
was consulted to understand what functionality a Hyprland/Quickshell desktop shell needs to cover
(panel modules, system integrations, typical UX patterns). No source files, QML implementations,
directory structure, or assets from that project were copied, transcribed, or mechanically
translated into this repository — every file here was authored independently against Quickshell's
own public API, verified against Quickshell's official documentation rather than the reference
project's code.
