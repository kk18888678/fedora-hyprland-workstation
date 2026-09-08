import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../ui"
import "../../../theme"

AureliaKeyboardPanel {
    id: panelRoot

    // Aurelia calendar language: a compact instrument panel rather than a
    // large hero card. The date rail establishes hierarchy, the month strip
    // establishes navigation, and the grid stays quiet until it needs to
    // communicate today or a hover target.
    property date displayedMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property date today: new Date()

    readonly property int year: displayedMonth.getFullYear()
    readonly property int month: displayedMonth.getMonth()
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
    readonly property string todayKey: dateKey(today)
    readonly property bool viewingCurrentMonth: year === today.getFullYear() && month === today.getMonth()
    readonly property var dayCells: buildDayCells()

    // The content area is fixed by AureliaKeyboardPanel's popup insets. The
    // grid uses explicit geometry so it cannot stretch one row or column
    // differently when the number of weeks changes.
    readonly property int gridGap: 5
    readonly property int gridCellSize: Math.max(32, Math.floor((popupWidth - Theme.popupPadding * 2 - gridGap * 6) / 7))
    readonly property int gridWidth: gridCellSize * 7 + gridGap * 6
    readonly property int gridHeight: gridCellSize * 6 + gridGap * 5
    readonly property var weekdays: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    ownerId: "aurelia.clock"
    centerOnBar: true
    popupWidth: 388
    popupHeight: 486
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

        // Always render six complete rows. This makes the popup stable while
        // browsing and gives adjacent-month dates enough context to scan.
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

    function monthName() {
        return Qt.formatDate(displayedMonth, "MMMM").toUpperCase()
    }

    // Keep the non-visual clock object below an Item. The keyboard panel's
    // direct-child alias is intentionally restricted to visual content.
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
            anchors.fill: parent
            spacing: Theme.spacingSm
            focus: panelRoot.shown

        Item {
            width: parent.width
            height: 48

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusMd
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.62)
                border.color: Theme.border
                border.width: Theme.borderWidthDefault
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3
                radius: width / 2
                color: Theme.accent
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingLg
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: "AURELIA / CALENDAR"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightBold
                    font.letterSpacing: 1.2
                }

                Row {
                    spacing: Theme.spacingSm

                    Text {
                        id: monthLabel
                        text: panelRoot.monthName()
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXl + 2
                        font.weight: Theme.fontWeightBold
                    }

                    Text {
                        text: String(panelRoot.year)
                        anchors.baseline: monthLabel.baseline
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Theme.fontWeightMedium
                    }
                }
            }

            Column {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingMd
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    anchors.right: parent.right
                    text: "TODAY"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightBold
                    font.letterSpacing: 1
                }

                Text {
                    anchors.right: parent.right
                    text: Qt.formatDate(panelRoot.today, "ddd, d MMM")
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }
            }
        }

        Rectangle {
            id: monthToolbar
            width: parent.width
            height: 38
            radius: Theme.radiusMd
            color: Theme.surface
            border.color: Theme.border
            border.width: Theme.borderWidthDefault

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 4

                Rectangle {
                    id: previousButton
                    Layout.preferredWidth: 36
                    Layout.fillHeight: true
                    radius: Theme.radiusSm
                    color: previousMouse.containsMouse ? Theme.selection : "transparent"
                    border.color: previousMouse.containsMouse ? Theme.borderActive : "transparent"
                    border.width: Theme.borderWidthDefault

                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        color: previousMouse.containsMouse ? Theme.accent : Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Theme.fontWeightBold
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

                    Column {
                        anchors.centerIn: parent
                        spacing: 0

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "VIEWING"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 1
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDate(panelRoot.displayedMonth, "MMMM yyyy")
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 62
                        height: 26
                        radius: Theme.radiusSm
                        visible: !panelRoot.viewingCurrentMonth
                        color: todayMouse.containsMouse ? Theme.accent : "transparent"
                        border.color: todayMouse.containsMouse ? Theme.accent : Theme.border
                        border.width: Theme.borderWidthDefault

                        Text {
                            anchors.centerIn: parent
                            text: "TODAY"
                            color: todayMouse.containsMouse ? Theme.bgBase : Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 0.8
                        }

                        MouseArea {
                            id: todayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panelRoot.goToToday()
                        }
                    }
                }

                Rectangle {
                    id: nextButton
                    Layout.preferredWidth: 36
                    Layout.fillHeight: true
                    radius: Theme.radiusSm
                    color: nextMouse.containsMouse ? Theme.selection : "transparent"
                    border.color: nextMouse.containsMouse ? Theme.borderActive : "transparent"
                    border.width: Theme.borderWidthDefault

                    Text {
                        anchors.centerIn: parent
                        text: "→"
                        color: nextMouse.containsMouse ? Theme.accent : Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Theme.fontWeightBold
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
            height: 16

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
                        font.letterSpacing: 0.8
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: panelRoot.gridHeight

            Rectangle {
                anchors.centerIn: parent
                width: panelRoot.gridWidth
                height: panelRoot.gridHeight
                radius: Theme.radiusMd
                color: Qt.rgba(Theme.surfaceElevated.r, Theme.surfaceElevated.g, Theme.surfaceElevated.b, 0.22)
                border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.78)
                border.width: Theme.borderWidthDefault
            }

            Item {
                id: calendarGrid
                anchors.centerIn: parent
                width: panelRoot.gridWidth
                height: panelRoot.gridHeight

                Repeater {
                    model: panelRoot.dayCells

                    Rectangle {
                        required property var modelData
                        x: (index % 7) * (panelRoot.gridCellSize + panelRoot.gridGap)
                        y: Math.floor(index / 7) * (panelRoot.gridCellSize + panelRoot.gridGap)
                        width: panelRoot.gridCellSize
                        height: panelRoot.gridCellSize
                        radius: Theme.radiusSm
                        color: modelData.isToday
                            ? Theme.accent
                            : (dayHover.hovered
                                ? Theme.selection
                                : (modelData.inMonth
                                    ? (modelData.weekend
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                                        : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.62))
                                    : "transparent"))
                        border.color: modelData.isToday
                            ? Theme.accent
                            : (dayHover.hovered ? Theme.borderActive : "transparent")
                        border.width: modelData.isToday || dayHover.hovered ? Theme.borderWidthDefault : 0
                        opacity: modelData.inMonth ? 1.0 : 0.45

                        HoverHandler {
                            id: dayHover
                            enabled: !modelData.isToday
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.topMargin: 6
                            width: 10
                            height: 2
                            radius: 1
                            color: Theme.bgBase
                            visible: modelData.isToday
                        }

                        Text {
                            anchors.centerIn: parent
                            text: String(modelData.day)
                            color: modelData.isToday
                                ? Theme.bgBase
                                : (modelData.inMonth
                                    ? (modelData.weekend ? Theme.textSecondary : Theme.text)
                                    : Theme.textSubtle)
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
            height: 12

            Text {
                anchors.centerIn: parent
                text: "← →  MONTHS     T  TODAY"
                color: Theme.textSubtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                font.weight: Theme.fontWeightMedium
                font.letterSpacing: 0.4
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
