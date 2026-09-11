import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../ui"
import "../../../theme"

AureliaKeyboardPanel {
    id: panelRoot

    // Minimal Aurelia calendar: one rule, one navigation row, and an unboxed
    // equal-cell ledger. All visual density is controlled by Theme.qml and
    // theme.conf so the surface can be tuned without editing this component.
    property date displayedMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property date today: new Date()

    readonly property int year: displayedMonth.getFullYear()
    readonly property int month: displayedMonth.getMonth()
    readonly property string todayKey: dateKey(today)
    readonly property bool viewingCurrentMonth: year === today.getFullYear() && month === today.getMonth()
    readonly property var dayCells: buildDayCells()
    readonly property var weekdays: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    // Explicit geometry prevents GridLayout from stretching or collapsing
    // cells. The required delegate index below is essential for positioning
    // each date; without it every delegate is placed at the same origin.
    readonly property int gridGap: Theme.calendarCellGap
    readonly property int gridCellSize: Math.max(24, Math.min(
        Theme.calendarCellSize,
        Math.floor((popupWidth - contentPadding * 2 - gridGap * 6) / 7)
    ))
    readonly property int gridWidth: gridCellSize * 7 + gridGap * 6
    readonly property int gridHeight: gridCellSize * 6 + gridGap * 5

    ownerId: "aurelia.clock"
    centerOnBar: true
    contentPadding: Theme.calendarPadding
    popupWidth: Theme.calendarPopupWidth
    popupHeight: Theme.calendarPopupHeight
    shown: false

    function pad(value) {
        return value < 10 ? "0" + value : String(value)
    }

    function dateKey(value) {
        return value.getFullYear() + "-" + pad(value.getMonth() + 1) + "-" + pad(value.getDate())
    }

    function open(payloadJson) {
        today = new Date()
        displayedMonth = new Date(today.getFullYear(), today.getMonth(), 1)
        shown = true
    }

    function close() {
        shown = false
    }

    function closeForPopoutSwitch() { close() }

    function goToToday() {
        displayedMonth = new Date(today.getFullYear(), today.getMonth(), 1)
    }

    function previousMonth() {
        displayedMonth = new Date(year, month - 1, 1)
    }

    function nextMonth() {
        displayedMonth = new Date(year, month + 1, 1)
    }

    function buildDayCells() {
        var result = []
        var firstDay = new Date(year, month, 1)
        var firstWeekday = firstDay.getDay()

        // Keep six rows so the popup height never jumps between months.
        for (var index = 0; index < 42; index++) {
            var current = new Date(year, month, 1 - firstWeekday + index)
            result.push({
                day: current.getDate(),
                dateKey: dateKey(current),
                inMonth: current.getMonth() === month,
                weekend: current.getDay() === 0 || current.getDay() === 6,
                isToday: dateKey(current) === todayKey
            })
        }
        return result
    }

    function monthTitle() {
        return Qt.formatDate(displayedMonth, "MMMM")
    }

    Item {
        anchors.fill: parent

        Timer {
            interval: 30000
            repeat: true
            running: panelRoot.shown
            onTriggered: {
                var followToday = panelRoot.viewingCurrentMonth
                panelRoot.today = new Date()
                if (followToday) panelRoot.goToToday()
            }
        }

        Column {
            id: calendarColumn
            anchors.fill: parent
            spacing: Theme.spacingSm
            focus: panelRoot.shown

            Item {
                width: parent.width
                height: Theme.calendarHeaderHeight

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AURELIA / CALENDAR"
                    color: Theme.calendarAccent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightBold
                    font.letterSpacing: 1
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "TODAY  " + Qt.formatDate(panelRoot.today, "ddd, d MMM")
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightMedium
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.calendarRule
                    opacity: 0.72
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: 22
                    height: 1
                    color: Theme.calendarAccent
                }
            }

            Item {
                width: parent.width
                height: Theme.calendarToolbarHeight

                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.spacingXs

                    Rectangle {
                        Layout.preferredWidth: 26
                        Layout.fillHeight: true
                        radius: Theme.radiusSm
                        color: previousMouse.containsMouse
                            ? Qt.rgba(Theme.calendarHover.r, Theme.calendarHover.g, Theme.calendarHover.b, 0.32)
                            : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "‹"
                            color: previousMouse.containsMouse ? Theme.calendarAccent : Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.weight: Theme.fontWeightMedium
                        }

                        MouseArea {
                            id: previousMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panelRoot.previousMonth()
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingSm

                            Text {
                                id: monthTitleLabel
                                text: panelRoot.monthTitle()
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeLg
                                font.weight: Theme.fontWeightBold
                            }

                            Text {
                                anchors.baseline: monthTitleLabel.baseline
                                text: String(panelRoot.year)
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: Theme.fontWeightMedium
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !panelRoot.viewingCurrentMonth
                            text: "TODAY"
                            color: todayMouse.containsMouse ? Theme.calendarAccent : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 0.7

                            MouseArea {
                                id: todayMouse
                                anchors.fill: parent
                                anchors.margins: -Theme.spacingXs
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panelRoot.goToToday()
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 26
                        Layout.fillHeight: true
                        radius: Theme.radiusSm
                        color: nextMouse.containsMouse
                            ? Qt.rgba(Theme.calendarHover.r, Theme.calendarHover.g, Theme.calendarHover.b, 0.32)
                            : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "›"
                            color: nextMouse.containsMouse ? Theme.calendarAccent : Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.weight: Theme.fontWeightMedium
                        }

                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panelRoot.nextMonth()
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.calendarWeekdayHeight

                Row {
                    anchors.centerIn: parent
                    spacing: panelRoot.gridGap

                    Repeater {
                        model: panelRoot.weekdays

                        Text {
                            required property string modelData
                            width: panelRoot.gridCellSize
                            height: parent.height
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 0.5
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: panelRoot.gridHeight

                Item {
                    id: calendarGrid
                    anchors.centerIn: parent
                    width: panelRoot.gridWidth
                    height: panelRoot.gridHeight

                    Repeater {
                        model: panelRoot.dayCells

                        Rectangle {
                            required property var modelData
                            required property int index
                            x: (index % 7) * (panelRoot.gridCellSize + panelRoot.gridGap)
                            y: Math.floor(index / 7) * (panelRoot.gridCellSize + panelRoot.gridGap)
                            width: panelRoot.gridCellSize
                            height: panelRoot.gridCellSize
                            radius: Theme.radiusSm
                            color: modelData.isToday
                                ? Theme.calendarAccent
                                : (dayHover.hovered
                                    ? Qt.rgba(Theme.calendarHover.r, Theme.calendarHover.g, Theme.calendarHover.b, 0.32)
                                    : "transparent")
                            border.color: modelData.isToday
                                ? Theme.calendarAccent
                                : (dayHover.hovered ? Theme.calendarAccent : "transparent")
                            border.width: modelData.isToday || dayHover.hovered ? Theme.borderWidthDefault : 0
                            opacity: modelData.inMonth ? 1.0 : 0.42

                            HoverHandler { id: dayHover }

                            Text {
                                anchors.centerIn: parent
                                text: String(modelData.day)
                                color: modelData.isToday
                                    ? Theme.bgBase
                                    : (modelData.inMonth
                                        ? (modelData.weekend ? Theme.calendarWeekend : Theme.text)
                                        : Theme.calendarAdjacent)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: modelData.isToday ? Theme.fontWeightBold : Theme.fontWeightMedium
                            }

                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.calendarFooterHeight

                Text {
                    anchors.centerIn: parent
                    text: "← →  MONTHS    T  TODAY"
                    color: Theme.textSubtle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightMedium
                    font.letterSpacing: 0.3
                }
            }

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Left) {
                    panelRoot.previousMonth()
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    panelRoot.nextMonth()
                    event.accepted = true
                } else if (event.key === Qt.Key_T) {
                    panelRoot.goToToday()
                    event.accepted = true
                }
            }
        }
    }
}
