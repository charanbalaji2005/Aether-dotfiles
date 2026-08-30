import QtQuick
import QtQuick.Layouts
import "../theme"

ColumnLayout {
    id: root
    spacing: Metrics.spaceSm

    property var _today: new Date()
    property int viewYear: _today.getFullYear()
    property int viewMonth: _today.getMonth() // 0-11

    function _daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }
    function _firstWeekday(year, month) {
        return new Date(year, month, 1).getDay(); // 0 = Sunday
    }
    function _monthName(month) {
        return ["January", "February", "March", "April", "May", "June", "July",
                "August", "September", "October", "November", "December"][month];
    }

    function prevMonth() {
        if (viewMonth === 0) { viewMonth = 11; viewYear -= 1; } else { viewMonth -= 1; }
    }
    function nextMonth() {
        if (viewMonth === 11) { viewMonth = 0; viewYear += 1; } else { viewMonth += 1; }
    }

    RowLayout {
        Layout.fillWidth: true

        Text {
            text: "\u2039"
            color: Colors.textSecondary
            font.pixelSize: Typography.sizeMd
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: root.prevMonth()
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root._monthName(root.viewMonth) + " " + root.viewYear
            color: Colors.textPrimary
            font.family: Typography.family
            font.weight: Typography.weightSemibold
            font.pixelSize: Typography.sizeSm
        }

        Text {
            text: "\u203A"
            color: Colors.textSecondary
            font.pixelSize: Typography.sizeMd
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: root.nextMonth()
            }
        }
    }

    GridLayout {
        columns: 7
        columnSpacing: 4
        rowSpacing: 4
        Layout.fillWidth: true

        Repeater {
            model: ["S", "M", "T", "W", "T", "F", "S"]
            delegate: Text {
                required property string modelData
                Layout.preferredWidth: 28
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Colors.textMuted
                font.family: Typography.family
                font.pixelSize: Typography.sizeXs
            }
        }

        Repeater {
            model: root._firstWeekday(root.viewYear, root.viewMonth)
            delegate: Item {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
            }
        }

        Repeater {
            model: root._daysInMonth(root.viewYear, root.viewMonth)
            delegate: Rectangle {
                id: dayCell
                required property int index
                readonly property int dayNum: index + 1
                readonly property bool isToday: dayNum === root._today.getDate()
                    && root.viewMonth === root._today.getMonth()
                    && root.viewYear === root._today.getFullYear()

                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: Metrics.radiusPill
                color: isToday ? Colors.accent : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: dayCell.dayNum
                    color: dayCell.isToday ? Colors.bg0 : Colors.textSecondary
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeXs
                }
            }
        }
    }
}
