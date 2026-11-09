import QtQuick
import "../../theme"
import "../../core"
import "../../components"

// Opens the application launcher. Right-click opens Settings.
Capsule {
    id: root
    visible: Config.bar.showLauncher
    implicitWidth: implicitHeight + Metrics.spaceXs
    onClicked: EventBus.launcherRequested()
    onRightClicked: EventBus.settingsRequested("")

    AetherIcon {
        anchors.centerIn: parent
        width: Metrics.iconMd; height: Metrics.iconMd
        name: "grid"
        color: root.hovered ? Colors.accent : Colors.textPrimary
        Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }
    }
}
