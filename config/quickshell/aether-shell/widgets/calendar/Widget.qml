import QtQuick

// AetherOS built-in widget "Calendar" (widget API 1). Data arrives only through
// `api`, which the host fills according to widget.json's permissions.
Item {
    id: root
    property var api: null
    function c(token) { return api && api.theme ? api.theme[token] : "#EDEFF7"; }
    function f() { return api && api.theme ? api.theme.font : "sans-serif"; }

    readonly property var t: api && api.time ? api.time : new Date()
    readonly property int first: new Date(t.getFullYear(), t.getMonth(), 1).getDay()
    readonly property int days: new Date(t.getFullYear(), t.getMonth() + 1, 0).getDate()
    Column {
        anchors.fill: parent; anchors.margins: 14
        spacing: 6
        Text { text: Qt.formatDate(root.t, "MMMM yyyy"); color: root.c("text"); font.family: root.f(); font.pixelSize: 15; font.weight: Font.DemiBold }
        Grid {
            columns: 7; spacing: 4
            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]
                delegate: Text { required property string modelData; width: 28; horizontalAlignment: Text.AlignHCenter; text: modelData; color: root.c("textMuted"); font.family: root.f(); font.pixelSize: 11 }
            }
            Repeater {
                model: root.first + root.days
                delegate: Rectangle {
                    required property int index
                    readonly property int day: index - root.first + 1
                    width: 28; height: 22; radius: 11
                    color: day === root.t.getDate() ? root.c("accent") : "transparent"
                    Text { anchors.centerIn: parent; visible: parent.day > 0; text: parent.day; color: parent.day === root.t.getDate() ? root.c("onAccent") : root.c("textSecondary"); font.family: root.f(); font.pixelSize: 12 }
                }
            }
        }
    }
}
