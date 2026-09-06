import QtQuick
import "../../theme"

// Deliberately small bar-only clock. A future calendar panel can be added as
// another entry point without making the status widget responsible for it.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.clock"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property int refreshTick: 0

    readonly property string displayFormat: settings && typeof settings.format === "string" && settings.format !== ""
        ? settings.format
        : "MMM d, dddd HH:mm"
    readonly property var displayLocale: Qt.locale("en_US")
    readonly property string displayText: {
        var tick = refreshTick
        var date = new Date()
        if (displayFormat === "MMM d, dddd HH:mm") {
            var month = displayLocale.monthName(date.getMonth(), Locale.ShortFormat)
            var weekday = displayLocale.dayName(date.getDay(), Locale.LongFormat)
            return month + " " + date.getDate() + ", " + weekday + " " + Qt.formatTime(date, "HH:mm")
        }
        return Qt.formatDateTime(date, displayFormat)
    }

    implicitWidth: clockLabel.implicitWidth + Theme.spacingMd * 2
    implicitHeight: bar ? bar.barSize : 40

    Timer {
        interval: 15000
        repeat: true
        running: !!(root.bar && root.bar.visible)
        onTriggered: root.refreshTick++
    }

    Text {
        id: clockLabel
        anchors.centerIn: parent
        text: root.displayText
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.weight: Theme.fontWeightMedium
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            mouse.accepted = true
            if (root.shell && typeof root.shell.summon === "function") {
                root.shell.summon("aurelia.calendar", "{}")
            }
        }
    }
}
