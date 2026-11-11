import QtQuick
import "../../theme"
import "../../animation"
import "../../services"
import "../../core"
import "../../components"

// Workspace indicators. The focused workspace is a wide accent pill that
// slides/grows into place; others are dots that reveal their number on
// hover. Scroll over the module to move between workspaces. Special
// (scratchpad) workspaces are not listed.
Rectangle {
    id: root
    visible: HyprlandService.available
    implicitWidth: row.implicitWidth + Metrics.spaceSm * 2
    implicitHeight: 24
    radius: Metrics.radiusPill
    color: Colors.withAlpha(Colors.textMuted, 0.10)

    readonly property var items: {
        const ws = HyprlandService.workspaces;
        const list = ws && ws.values ? ws.values : [];
        return list.filter(function(w) { return w && w.id > 0; })
                   .sort(function(a, b) { return a.id - b.id; });
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            HyprlandService.dispatch("workspace " + (wheel.angleDelta.y > 0 ? "e-1" : "e+1"));
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceXs

        Repeater {
            model: root.items

            delegate: Rectangle {
                id: dot
                required property var modelData
                readonly property bool focused: HyprlandService.focusedWorkspace
                    && HyprlandService.focusedWorkspace.id === modelData.id
                readonly property bool hovered: area.containsMouse

                // Names and icons from Settings → Workspaces. The focused pill
                // grows to show them; others stay compact dots.
                readonly property string wsName: (Config.workspaces.names || {})[String(modelData.id)] || ""
                readonly property string wsIcon: (Config.workspaces.icons || {})[String(modelData.id)] || ""
                readonly property bool labelled: focused && (wsName.length > 0 || wsIcon.length > 0)
                width: labelled ? labelRow.implicitWidth + 16 : focused ? 26 : (hovered ? 18 : (wsIcon ? 14 : 10))
                height: labelled ? 16 : hovered && !focused ? 16 : (wsIcon && !focused ? 14 : 10)
                radius: Metrics.radiusPill
                anchors.verticalCenter: parent.verticalCenter
                color: focused ? Colors.accent
                    : hovered ? Colors.withAlpha(Colors.textPrimary, 0.35)
                    : Colors.withAlpha(Colors.textMuted, 0.55)

                SpringBehavior on width { preset: "snappy" }
                Behavior on height { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast } }
                Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }

                Row {
                    id: labelRow
                    anchors.centerIn: parent
                    spacing: 4
                    visible: dot.labelled
                    AetherIcon { visible: dot.wsIcon.length > 0; width: 10; height: 10; anchors.verticalCenter: parent.verticalCenter; name: dot.wsIcon; color: Colors.onAccent }
                    Text { visible: dot.wsName.length > 0; text: dot.wsName; color: Colors.onAccent; font.family: Typography.family; font.pixelSize: 10; font.weight: Typography.weightBold; anchors.verticalCenter: parent.verticalCenter }
                }
                AetherIcon {
                    anchors.centerIn: parent
                    visible: !dot.focused && !dot.hovered && dot.wsIcon.length > 0
                    width: 8; height: 8; name: dot.wsIcon; color: Colors.bg0
                }
                Text {
                    anchors.centerIn: parent
                    visible: dot.hovered && !dot.focused
                    text: dot.wsName || dot.modelData.id
                    color: Colors.textPrimary
                    font.family: Typography.family
                    font.pixelSize: 9
                    font.weight: Typography.weightBold
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: HyprlandService.switchToWorkspace(dot.modelData.id)
                }
            }
        }
    }
}
