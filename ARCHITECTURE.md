# Architecture (dotfiles layer)

This document covers the repo as a whole. For the shell's internal architecture (its QML layering
rules, service pattern, etc.), see `config/quickshell/aether-shell/ARCHITECTURE.md` — that one is
more detailed and is the one to read if you're modifying the shell itself.

## Layering

```
This repo (config/, theme/, scripts/)
        ↓  scripts/setup-symlinks.sh
~/.config/*, ~/.zshrc, ~/.local/bin/aether  (symlinks, not copies)
        ↓  read by
Hyprland, Quickshell, kitty, zsh, GTK  (the actual running system)
```

Everything under `config/` and `theme/` is **symlinked**, not copied, into place. This is a
deliberate choice: editing a file in your live config edits the file in this repo directly (since
they're the same inode via the symlink), so `git status` in the repo shows your actual changes —
no separate "sync my dotfiles" step.

## Why scripts are split the way they are

- `install.sh` — thin wrapper, exists only so `./install.sh` at the repo root is the obvious
  first command. All real logic is in `scripts/bootstrap.sh`.
- `scripts/bootstrap.sh` — distro detection + package installation + Quickshell build/check. The
  only script that runs `sudo`.
- `scripts/setup-symlinks.sh` — purely the symlinking step, no package installation, no `sudo`.
  Callable on its own if you've already got dependencies installed some other way.
- `scripts/backup.sh` / `restore.sh` / `uninstall.sh` — the safety net. `uninstall.sh` and
  `restore.sh` both call `backup.sh` before doing anything destructive, so there's always a
  backup of "what was there right before this ran."
- `scripts/doctor.sh` — read-only, checks the live system against what the shell/config actually
  need, independent of whether install/setup ever ran.

## Why symlink targets are an explicit list, not a loop over `config/*`

`scripts/setup-symlinks.sh` lists each target path explicitly (`config/hypr` →
`~/.config/hypr`, etc.) rather than symlinking every subdirectory of `config/` generically. This
is intentional: it means adding a new config directory requires a deliberate one-line addition to
the script, so nothing gets symlinked into a live location by accident.

## Distro abstraction

Only Fedora and Arch have automated package installation (`packages/fedora/`,
`packages/arch/`), because those are the two distros this was actually tested against (Fedora
being AetherOS's own base). `packages/generic/README.md` documents what's needed for anything
else without pretending to automate it — see that file for why.

## Testing philosophy

See `tests/run-all.sh` and each suite under `tests/`. The short version: everything in `tests/` is
either (a) a real static check that runs a real tool (shellcheck, brace-balance, import
resolution) or (b) a real integration test executed against an isolated fake `$HOME`, never fake
tests that print PASS unconditionally. Where a real test isn't possible in this development
environment — anything needing live Quickshell/Qt6/Hyprland/D-Bus — that gap is documented
(`tests/services/README.md`) instead of papered over.
