# Security

## Scope

This repo configures a desktop environment (Hyprland) and a Quickshell-based UI that has access
to session-level things: your clipboard, notifications, PAM authentication (lock screen), and
whatever binaries it shells out to (`nmcli`, `bluetoothctl`, `systemctl`, etc.).

## Known, documented risk areas

- **Lock screen PAM authentication** (`config/quickshell/aether-shell/shell/lockscreen/LockScreen.qml`)
  — the PAM integration's exact API usage could not be verified against Quickshell's authoritative
  documentation (see that file's comments and the shell's `PROGRESS.md`). It's written to fail
  safe — unlock only happens on an explicit PAM-success signal — but it hasn't been
  security-audited beyond that. **Do not treat this as your only authentication mechanism without
  testing it yourself first.**
- **Clipboard history** (`cliphist`) stores clipboard content, including anything sensitive you
  copy (passwords, tokens) unless your password manager excludes itself from clipboard history
  (most do, via the clipboard manager exclusion mechanisms they implement — check yours).
- **Scripts that shell out** (`ApplicationService.launch()`, `ClipboardService`, screenshot
  scripts) pass user/system-derived strings as separate argv elements (never string-interpolated
  into a shell command string) specifically to avoid injection — see the comments in those files
  for the reasoning if you're auditing this.
- **Installer scripts** (`bootstrap.sh`, `setup-symlinks.sh`, `uninstall.sh`) never delete a file
  that isn't a symlink pointing into this repo, and back up before any destructive operation. If
  you find a path where that's not true, that's a bug — report it.

## Reporting a vulnerability

Open an issue (or, for something you don't want public immediately, contact the maintainer
directly through whatever channel the repo's README links). Include reproduction steps. There's
no bug bounty — this is a personal/community dotfiles project, not a funded security program.

## What this is not

This has not been through a formal security audit. Treat it the way you'd treat any dotfiles
repo you found on GitHub: read the scripts before running them, especially `bootstrap.sh` (it
runs `sudo`).
