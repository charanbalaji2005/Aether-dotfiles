import QtQuick
import QtQuick.Window
import "../components"
import "Assert.js" as A

// Every glyph in the icon kit draws visible pixels (catches typos and broken paths).
Window {
    id: win
    width: 416; height: 296; visible: true; color: "black"
    Rectangle { anchors.fill: parent; color: "#000000" }
    readonly property var names: ['volume-high', 'volume-low', 'volume-mute', 'wifi', 'wifi-off', 'ethernet', 'battery', 'battery-charging', 'cpu', 'memory', 'gpu', 'disk', 'thermometer', 'gauge', 'activity', 'mic', 'mic-off', 'bell', 'bell-off', 'bluetooth', 'moon', 'sun', 'contrast', 'bolt', 'leaf', 'display', 'search', 'star', 'star-filled', 'power', 'lock', 'clipboard', 'camera', 'keyboard', 'mouse', 'sparkle', 'widgets', 'shield', 'archive', 'code', 'logout', 'clock', 'grid', 'sliders', 'gear', 'image', 'music', 'play', 'pause', 'next', 'prev', 'arrow-up', 'arrow-down', 'chevron-left', 'chevron-right', 'chevron-down', 'check', 'close', 'plus', 'refresh', 'trash', 'globe']
    Repeater {
        model: win.names
        delegate: AetherIcon {
            required property int index
            required property string modelData
            x: (index % 10) * 40 + 8; y: Math.floor(index / 10) * 40 + 8
            width: 24; height: 24
            name: modelData
            color: "#ffffff"
        }
    }
    Timer {
        interval: 1200; running: true
        onTriggered: win.contentItem.grabToImage(function(r) {
            const p = "/tmp/aether-icons-" + Date.now() + ".png"; r.saveToFile(p);
            console.log("SHOT " + p);
            // Control: an empty cell past the last icon must have no ink.
            console.log("PIXMAX empty cell stays black|" + ((win.names.length % 10) * 40 + 20) + "|" + (Math.floor(win.names.length / 10) * 40 + 20) + "|r|5");
            for (let i = 0; i < win.names.length; i++)
                console.log("INK icon '" + win.names[i] + "' draws pixels|" + ((i % 10) * 40 + 8) + "|" + (Math.floor(i / 10) * 40 + 8) + "|24|24|25");
            Qt.exit(0);
        })
    }
}
