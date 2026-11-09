import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../core"

// Shared popup surface for every AetherOS panel (launcher, control centre,
// dashboard, notification centre, settings, ...).
//
// It stays mapped while its close animation runs (visible = open OR still
// animating), dismisses on click-outside and Escape, and closes itself
// when another popup opens (EventBus.closePopups), so two panels never
// fight for the same corner. Under reduced motion Motion.panel is 0 and
// everything is instant.
//
// Usage:
//   PopupPanel {
//       id: panel
//       layerNamespace: "aether-dashboard"
//       placement: "top-right"            // or "center", "top-left", "top"
//       cardWidth: 420; cardHeight: body.implicitHeight + 32
//       ColumnLayout { id: body; ... }    // becomes the card's content
//   }
PanelWindow {
    id: root

    property bool open: false
    property string layerNamespace: "aether-popup"
    property string placement: "center"
    property bool showScrim: false
    property bool closeOnBackdrop: true
    property int cardWidth: 400
    property int cardHeight: 300
    property int edgeMargin: Metrics.spaceLg
    // Distance from the bar edge for top-anchored panels.
    property int topOffset: Config.bar.height + (Config.bar.style === "full" ? 0 : Metrics.barMargin) + Metrics.spaceSm
    property bool barAtBottom: Config.bar.position === "bottom"
    property real cardRadius: Metrics.radiusXl

    // 0 = closed, 1 = open. Animated; drives every transition below.
    property real progress: open ? 1 : 0
    Behavior on progress {
        NumberAnimation { duration: Motion.panel; easing.type: root.open ? Motion.easeSpring : Motion.easeExit }
    }

    default property alias content: body.data
    readonly property alias card: card

    signal opened()
    signal dismissed()

    // Latched when opening so the panel doesn't jump monitors mid-animation.
    property var targetScreen: null

    function show() {
        EventBus.closePopups(root.layerNamespace);
        if (ShellState.activeScreen) targetScreen = ShellState.activeScreen;
        open = true;
    }
    function hide() { open = false; }
    function toggle() { if (open) hide(); else show(); }

    onOpenChanged: {
        if (open) {
            // Default focus first, so a panel's onOpened can move it into
            // its own input (e.g. the launcher's search field).
            focusCatcher.forceActiveFocus();
            opened();
        } else {
            dismissed();
        }
    }

    Connections {
        target: EventBus
        function onClosePopups(except) {
            if (except !== root.layerNamespace && root.open) root.open = false;
        }
    }

    // Keyboard focus while open (Escape to close, typing in inputs).
    property bool wantsKeyboard: true
    focusable: wantsKeyboard && open

    visible: open || progress > 0.001
    screen: targetScreen ? targetScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Colors.scrim
        opacity: root.showScrim ? root.progress : 0
        visible: root.showScrim
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: if (root.closeOnBackdrop) root.hide()
    }

    Item {
        id: focusCatcher
        focus: true
        Keys.onEscapePressed: root.hide()
    }

    GlassPanel {
        id: card
        width: root.cardWidth
        height: root.cardHeight
        radius: root.cardRadius
        opacity: root.progress
        scale: 0.965 + 0.035 * root.progress
        transformOrigin: {
            switch (root.placement) {
            case "top-right": return root.barAtBottom ? Item.BottomRight : Item.TopRight;
            case "top-left": return root.barAtBottom ? Item.BottomLeft : Item.TopLeft;
            case "top": return root.barAtBottom ? Item.Bottom : Item.Top;
            default: return Item.Center;
            }
        }
        transform: Translate {
            y: (1 - root.progress) * (root.placement === "center" ? Motion.travel : (root.barAtBottom ? Motion.travel : -Motion.travel))
        }

        x: {
            switch (root.placement) {
            case "top-right": return root.width - width - root.edgeMargin;
            case "top-left": return root.edgeMargin;
            default: return (root.width - width) / 2;
            }
        }
        y: {
            if (root.placement === "center") return (root.height - height) / 2;
            return root.barAtBottom ? root.height - height - root.topOffset : root.topOffset;
        }

        // Swallow clicks so the backdrop MouseArea doesn't close the card.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Item {
            id: body
            anchors.fill: parent
            // Escape from anywhere inside the card (e.g. a focused text field)
            // propagates up to here.
            Keys.onEscapePressed: root.hide()
        }
    }
}
