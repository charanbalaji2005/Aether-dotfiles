# Recovery

AetherOS is designed so a bad setting, a broken shell or a Hyprland upgrade never leaves you
without a desktop. In order of severity:

## The shell misbehaves (panel glitchy, effects slow, something stuck)

```sh
aether recover             # safe mode on, missing fragments recreated, invalid settings reported, shell restarted
aether recover --restore   # …and offers to restore the last-known-good settings
```

Safe mode turns off shaders, particles, parallax, video wallpaper and automation. When things
work again: `aether safe-mode off && aether shell-reload`. Record a good state any time with
`aether snapshot mark-good`.

## The shell crashes repeatedly

`aether-shell.service` gives up after 4 failed starts in 40 s and **automatically starts
`aether-shell-safe.service`** (same shell, safe mode), with a notification. Then:

```sh
journalctl --user -u aether-shell -n 80     # why it crashed
aether config validate                      # bad settings? (`aether config reset` backs up and resets)
aether shell-reload                         # back to the normal shell
```

No panel at all? `SUPER+Return` still opens a terminal (Hyprland keybinds don't depend on the shell).

## Settings got into a bad state

```sh
aether snapshot list
aether snapshot preview <name>     # shows the diff
aether snapshot restore <name>     # verified (checksums), snapshots the current state first
aether config reset                # everything to defaults; previous file kept as config.json.bak-<time>
```

Applying a profile or importing settings always snapshots first — Settings → Profiles → Undo.

## Hyprland doesn't start

From a TTY (**Ctrl+Alt+F3**, log in):

```sh
Hyprland -c ~/.config/hypr/recovery.conf    # minimal config: no shell, no GPU fragment, no effects
# in the terminal it opens:
aether diagnostics
aether repair                               # recreates fragments, fixes broken links, resets an invalid config
aether hyprland                             # Hyprland --verify-config with readable results
```

Common causes: a Hyprland upgrade changed syntax (`aether hyprland compat` regenerates
version-specific rules and gestures — it also runs automatically at every login), or a GPU
fragment that no longer fits (`aether graphics configure`). NVIDIA specifics:
[docs/NVIDIA_GUIDE.md](docs/NVIDIA_GUIDE.md).

## The lock screen won't accept your password

Authentication is PAM (`/etc/pam.d/login`); AetherOS never checks passwords itself, and only a
PAM success can unlock. After 3 failures it reminds you about Caps Lock/keyboard layout; PAM
errors and a 30 s timeout re-enable the field instead of leaving it stuck.

**"Lock client died" / red screen:** the shell crashed while locked. The session stays locked —
that is the secure outcome. systemd restarts the shell within seconds and it re-acquires the
lock (it left a marker in `$XDG_RUNTIME_DIR`), so the password field comes back. If it doesn't
(e.g. the shell keeps crashing), switch to a TTY (Ctrl+Alt+F3), log in, and either:

```sh
systemctl --user start aether-shell-safe.service   # safe-mode shell; it re-locks and shows the password field
# or, with hyprlock installed (an independent PAM locker):
hyprctl --instance 0 'dispatch exec hyprlock'
```

As a last resort, `loginctl terminate-user $USER` ends the session (unsaved work is lost).

## Undo AetherOS entirely

```sh
cd ~/aetheros-dotfiles
./install.sh --rollback        # removes links and services, moves your original files back
```

Your display manager and other desktop sessions were never changed, so the previous desktop is
one logout away. Older full backups: `~/.aetheros-backups/` (`scripts/restore.sh <archive>`).

## Collecting information for a bug report

```sh
aether diagnostics            # saved to ~/.local/state/aether/diagnostics-*.txt
journalctl --user -u aether-shell -b > shell.log
```

Nothing is uploaded anywhere; review the files before sharing (they contain hardware details).
