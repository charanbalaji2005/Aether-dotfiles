# Troubleshooting

## Run the doctor first

```
aether doctor
```

Reports which required/optional tools are missing and whether Hyprland/the shell are actually
running. Most "X isn't working" issues are a missing dependency this will catch.

## The shell didn't start / bar is missing

- Check the log: `aether logs` (tails `/tmp/aether-shell.log`)
- Confirm `qs` is on `PATH`: `command -v qs`
- Try running it in the foreground to see the actual error: `qs -c aether-shell`

## Blur isn't showing on the bar/launcher/dashboard

QML can't blur behind its own window — the blur comes from Hyprland's `layerrule`, matched by
layer namespace. Run `hyprctl layers` while the shell is running and check the actual namespace
Quickshell registered; if it's not `quickshell:aether-shell`, update the regex in
`config/hypr/rules.conf` to match what you see.

## Clipboard history is always empty

`cliphist` only records what's actively piped to it. Confirm this is running:
```
pgrep -af "wl-paste --watch cliphist"
```
If not, check that `exec-once = wl-paste --watch cliphist store` is present in
`config/hypr/hyprland.conf` and that you reloaded/relogged after adding it.

## Lock screen: password doesn't work / lock screen won't appear

- Confirm your compositor supports `ext-session-lock-v1` — Hyprland does; GNOME and current KWin
  don't. If you're not on Hyprland, this won't work regardless of config.
- The PAM integration in `shell/lockscreen/LockScreen.qml` is flagged in the shell's own
  PROGRESS.md as unverified against Quickshell's exact API (its docs site blocks automated
  fetching, so this wasn't tested against an authoritative source). If authentication silently
  doesn't work, that's the most likely cause — check Quickshell's actual `PamContext` docs for
  your installed version and adjust the property/method names in `LockScreen.qml` if they differ.
- **Keep a TTY accessible (Ctrl+Alt+F2) the first time you test locking**, so you're not stuck if
  something's wrong.

## Screenshots aren't captured / clipboard doesn't get the image

Requires `grim` (and `slurp` for region select) on `PATH`. Full-disk screenshots save to
`~/Pictures/Screenshots/`; check that directory exists and is writable.

## GTK apps look inconsistent with the rest of the theme

`theme/gtk/gtk-3.0/gtk.css` and `gtk-4.0/gtk.css` are an original AetherOS stylesheet (not stock
Adwaita), but they haven't been visually verified — no GTK/display server exists in the
environment they were written in. If something looks off, that's the most likely reason; check
the file's own header comments for what's and isn't covered (GTK4 in particular only styles a
small, conservative subset — see that file for why).

## Quickshell build fails

`install.sh` builds Quickshell from source since no official Fedora package exists as of this
writing. Its build dependencies can change — if the build fails, check
[quickshell.org](https://quickshell.org) for current instructions before assuming the repo's
`hyprland.conf`/shell config are at fault.
