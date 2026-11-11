# Desktop widgets — user and developer guide

## Using widgets

Settings → Widgets → enable, then `SUPER+SHIFT+Y` (or *Arrange widgets*) to add, drag (snaps to
the grid) and remove. Built-in: Clock, Calendar, System, GPU, Media, Battery, Network.

```sh
aether widget list                  # built-in + installed, with validation status
aether widget install ./my-widget   # a folder or .zip; shows its permissions and asks
aether widget remove my-widget
```

## Writing a widget (API 1)

```
my-widget/
├── widget.json
└── Widget.qml
```

```json
{ "aetherWidget": 1, "id": "my-widget", "name": "My widget", "version": "1.0.0", "api": 1,
  "entry": "Widget.qml", "description": "…", "author": "you", "license": "MIT",
  "size": { "w": 240, "h": 140 }, "permissions": ["time", "system"], "requires": [] }
```

```qml
import QtQuick
Item {
    property var api: null           // injected by the host
    Text {
        anchors.centerIn: parent
        text: api && api.system ? Math.round(api.system.cpu * 100) + "% CPU" : "—"
        color: api ? api.theme.text : "white"
        font.family: api ? api.theme.font : "sans-serif"
    }
}
```

**Permissions → `api` fields:** `time` → `api.time` (Date, updated every second) ·
`system` → `api.system {cpu, mem, disk, cpuTemp, uptime}` · `gpu` → `api.gpu {available, name,
usage, vramUsed, vramTotal, tempC, note}` (numbers are -1 when unavailable, never 0) · `media` → `api.media {available, title, artist,
playing, artUrl, playPause(), next(), previous()}` · `battery` → `api.battery {available, level,
charging, timeText}` · `network` → `api.network {connected, name, down, up}` · always:
`api.theme {accent, onAccent, text, textSecondary, textMuted, surface, border, danger, font,
radius}`, `api.use24Hour`, `api.version`. Fields you didn't declare are `undefined`.

**Rules enforced at install and at load (static check):** imports only `QtQuick`,
`QtQuick.Layouts`, `QtQuick.Shapes`, `QtQuick.Controls(.Basic)` and files inside the widget; no
Quickshell, `XMLHttpRequest`, `Qt.openUrlExternally/createQmlObject/createComponent/include`,
`eval`; no `file:`/`http(s):`/`qrc:`/`data:` URLs, absolute paths or `../`; ≤ 50 files,
≤ 256 KiB each, ≤ 2 MiB total, no symlinks; allowed file types `.qml .js .json .svg .png .jpg
.webp .md .txt`. `requires` lists commands the widget needs (reported if missing).

**This is not a sandbox.** QML runs inside the shell's process; Qt has no in-process isolation.
The static check blocks the obvious routes to files, programs and the network, but a hostile
widget could still, for example, busy-loop. Install widgets only from authors you trust.
Check yours before publishing: `aether widget inspect ./my-widget`.
