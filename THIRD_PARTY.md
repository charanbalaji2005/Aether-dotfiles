# Third-Party Dependencies & Provenance (dotfiles layer)

For the Quickshell UI's own dependencies (Quickshell itself, PipeWire, UPower, NetworkManager,
BlueZ, MPRIS, cliphist, grim/slurp), see
[`config/quickshell/aether-shell/THIRD_PARTY.md`](./config/quickshell/aether-shell/THIRD_PARTY.md).
This file covers the surrounding dotfiles layer.

## Runtime dependencies

Nothing here is vendored — these are system packages/binaries this repo's config files configure
or invoke, same as any dotfiles repo.

| Dependency | License | How it's used |
|---|---|---|
| [Hyprland](https://hyprland.org) | BSD-3-Clause | The compositor. `config/hypr/*.conf` is original configuration written for this project — Hyprland's own config format, not copied from any other dotfiles repo. |
| [hyprpolkitagent](https://github.com/hyprwm/hyprpolkitagent) | BSD-3-Clause | Polkit authentication agent, autostarted for GUI privilege prompts. |
| [hyprpaper](https://github.com/hyprwm/hyprpaper) | BSD-3-Clause | Wallpaper daemon (see `theme/wallpapers/README.md`). |
| [kitty](https://sw.kovidgoyal.net/kitty/) | GPL-3.0 | Terminal emulator. `config/kitty/kitty.conf` is original configuration. |
| [Zsh](https://www.zsh.org) | MIT-like (zsh license) | Shell. `config/zsh/.zshrc` is original configuration. |
| zsh-autosuggestions / zsh-syntax-highlighting | MIT / BSD | Optional zsh plugins, sourced if installed — not bundled. |
| [eza](https://github.com/eza-community/eza) | MIT | Optional `ls` replacement, aliased if installed. |
| [bat](https://github.com/sharkdp/bat) | MIT/Apache-2.0 | Optional `cat` replacement, aliased if installed. |
| [playerctl](https://github.com/altdesktop/playerctl) | LGPL-2.1 | MPRIS media key bindings in `keybinds.conf`. |
| [brightnessctl](https://github.com/Hummer12007/brightnessctl) | MIT | Brightness key bindings. |
| GTK (Adwaita theme) | LGPL-2.1 | Referenced by `theme/gtk/*.ini` for app theming consistency — not modified or redistributed. |
| [JetBrains Mono](https://www.jetbrains.com/lp/mono/) | SIL OFL-1.1 | Terminal/monospace font, referenced not bundled. |
| [Manrope](https://github.com/sharanda/manrope) | SIL OFL-1.1 | GTK app font, referenced not bundled. |

## Provenance

All `.conf`/`.ini`/`.sh` files in this repo were authored for AetherOS specifically — none were
copied from `end-4/dots-hyprland` or any other existing dotfiles repository. Where a config format
is dictated by the tool itself (Hyprland's `bind = `/`windowrule = ` syntax, kitty's
`key value` format), that structure is the tool's own documented format, not something copyrightable
in itself — the actual keybind choices, window rules, color values, and scripts here are original.
