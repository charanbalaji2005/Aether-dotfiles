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
- **Wallpaper path injection (fixed in this release).** `WallpaperService` previously built a
  `bash -c` string containing the wallpaper's file path, so a file named e.g. `$(cmd).jpg` in a
  wallpaper folder would have executed `cmd`. Paths are now passed as positional arguments.
  All shell → helper calls go through `Paths.helper()`, which never interpolates values.
- **Wi-Fi passwords.** NetworkManager's CLI takes a new network's passphrase as an argument
  (`nmcli device wifi connect <ssid> password <psk>`), so for the second or two that `nmcli` runs,
  the passphrase is visible in `/proc/<pid>/cmdline` to other local users (Fedora doesn't mount
  /proc with `hidepid`). It is never logged or written to disk by AetherOS. On a shared
  multi-user machine, add networks with `nmtui` or `nm-connection-editor` instead. Known
  networks reconnect with `nmcli connection up` (no secret on the command line).
- **Driver installation** (`aether graphics install-nvidia`) runs `sudo dnf install …` and, with
  Secure Boot on, `sudo kmodgenca -a` and `sudo mokutil --import …`. Each command is printed
  before the user types a confirmation word; non-interactive runs decline by default. It never
  disables Secure Boot, never edits the bootloader, and never runs downloaded scripts — RPM
  Fusion is enabled with its own signed release RPMs, whose GPG key dnf asks you to accept.
- **The `aether` CLI** runs with `python3 -I` (isolated: ignores PYTHONPATH, user site-packages
  and the current directory), never uses `shell=True`, and never needs to run as root.
  `AETHER_SYSROOT` / `AETHER_COMMAND_FIXTURES` exist only for tests; they make the CLI read
  fixture files instead of the live system and can't make it execute anything.
- **Logs** (`$XDG_RUNTIME_DIR/aether-shell.log`, previously `/tmp/aether-shell.log`) moved out
  of the world-writable /tmp to avoid symlink attacks on a predictable path.
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
