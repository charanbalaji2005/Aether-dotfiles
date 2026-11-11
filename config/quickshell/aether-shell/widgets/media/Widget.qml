import QtQuick

// AetherOS built-in widget "Media" (widget API 1). Data arrives only through
// `api`, which the host fills according to widget.json's permissions.
Item {
    id: root
    property var api: null
    function c(token) { return api && api.theme ? api.theme[token] : "#EDEFF7"; }
    function f() { return api && api.theme ? api.theme.font : "sans-serif"; }

    readonly property var m: api && api.media ? api.media : null
    Row {
        anchors.fill: parent; anchors.margins: 12
        spacing: 12
        Rectangle {
            width: 86; height: 86; radius: 10; color: root.c("surface"); clip: true
            Image { anchors.fill: parent; source: root.m && root.m.artUrl ? root.m.artUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
        }
        Column {
            width: parent.width - 98; spacing: 4
            anchors.verticalCenter: parent.verticalCenter
            Text { width: parent.width; elide: Text.ElideRight; text: root.m && root.m.available ? root.m.title : "Nothing playing"; color: root.c("text"); font.family: root.f(); font.pixelSize: 14; font.weight: Font.DemiBold }
            Text { width: parent.width; elide: Text.ElideRight; text: root.m && root.m.available ? root.m.artist : ""; color: root.c("textSecondary"); font.family: root.f(); font.pixelSize: 12 }
            Row {
                spacing: 18
                visible: root.m && root.m.available
                Repeater {
                    model: [{ s: "⏮", a: "previous" }, { s: root.m && root.m.playing ? "⏸" : "▶", a: "playPause" }, { s: "⏭", a: "next" }]
                    delegate: Text {
                        required property var modelData
                        text: modelData.s; color: root.c("text"); font.pixelSize: 20
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.api.media[modelData.a]() }
                    }
                }
            }
        }
    }
}
