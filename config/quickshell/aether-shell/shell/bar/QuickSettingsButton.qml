import QtQuick
import "../../theme"
import "../../core"
import "../../components"

// Opens the control centre (Wi-Fi, Bluetooth, audio, brightness, night
// light, theme, power modes...). Also reachable with SUPER+A.
Capsule {
    id: root
    implicitWidth: implicitHeight + Metrics.spaceXs
    onClicked: EventBus.controlCenterRequested()

    AetherIcon {
        anchors.centerIn: parent
        width: Metrics.iconMd; height: Metrics.iconMd
        name: "sliders"
        color: root.hovered ? Colors.accent : Colors.textPrimary
        rotation: root.hovered && !Motion.reducedMotion ? 90 : 0
        Behavior on rotation { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.normal; easing.type: Motion.easeStandard } }
        Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }
    }
}
