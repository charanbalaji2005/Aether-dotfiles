import QtQuick

// AetherOS built-in widget "System" (widget API 1). Data arrives only through
// `api`, which the host fills according to widget.json's permissions.
Item {
    id: root
    property var api: null
    function c(token) { return api && api.theme ? api.theme[token] : "#EDEFF7"; }
    function f() { return api && api.theme ? api.theme.font : "sans-serif"; }

    readonly property var s: api && api.system ? api.system : null
    Column {
        anchors.fill: parent; anchors.margins: 14
        spacing: 10
        Repeater {
            model: [{ l: "CPU", v: root.s ? root.s.cpu : -1 }, { l: "Memory", v: root.s ? root.s.mem : -1 }, { l: "Disk", v: root.s ? root.s.disk : -1 }]
            delegate: Column {
                required property var modelData
                width: parent.width; spacing: 3
                Row {
                    width: parent.width
                    Text { width: parent.width / 2; text: modelData.l; color: root.c("textSecondary"); font.family: root.f(); font.pixelSize: 12 }
                    Text { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: modelData.v >= 0 ? Math.round(modelData.v * 100) + "%" : "—"; color: root.c("text"); font.family: root.f(); font.pixelSize: 12 }
                }
                Rectangle {
                    width: parent.width; height: 4; radius: 2; color: root.c("border")
                    Rectangle { width: parent.width * Math.max(0, modelData.v); height: 4; radius: 2; color: modelData.v > 0.9 ? root.c("danger") : root.c("accent"); Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } }
                }
            }
        }
    }
}
