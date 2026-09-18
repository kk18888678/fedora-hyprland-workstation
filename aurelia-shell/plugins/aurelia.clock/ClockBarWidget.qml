import QtQuick
import Quickshell.Io
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

    // Date & Time preferences are owned by the desktop (gsettings) and written
    // by the settings hub. The clock treats the historical default format as
    // "auto" so the hub drives it without a migration.
    property bool clock24h: true
    property bool clockShowDate: true
    property bool clockShowSeconds: false
    property bool clockShowWeekday: false
    readonly property string configuredFormat: settings && typeof settings.format === "string"
        ? settings.format : ""
    readonly property bool autoFormat: configuredFormat === "" ||
        configuredFormat === "auto" || configuredFormat === "MMM d, dddd HH:mm"
    readonly property string derivedFormat: {
        var timeFormat = clock24h
            ? (clockShowSeconds ? "HH:mm:ss" : "HH:mm")
            : (clockShowSeconds ? "h:mm:ss AP" : "h:mm AP")
        if (clockShowDate && clockShowWeekday) return "MMM d, dddd " + timeFormat
        if (clockShowDate) return "MMM d " + timeFormat
        if (clockShowWeekday) return "dddd " + timeFormat
        return timeFormat
    }

    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text

    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    readonly property string displayFormat: root.vertical
        ? (settings && typeof settings.verticalFormat === "string" && settings.verticalFormat !== ""
            ? settings.verticalFormat : "HH\n—\nmm")
        : (root.autoFormat ? root.derivedFormat : root.configuredFormat)
    readonly property var verticalLines: displayText.split("\n")
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

    implicitWidth: root.vertical
        ? (bar ? bar.barSize : Theme.bar.sizeVertical)
        : clockLabel.implicitWidth + (root.bar && root.bar.barTextMargin
            ? root.bar.barTextMargin * 2
            : Theme.bar.textMargin * 2)
    implicitHeight: root.vertical
        ? root.verticalLines.length * (root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : Theme.bar.iconSlot)
        : (bar ? bar.barSize : Theme.bar.sizeHorizontal)

    // Read the desktop clock preferences (owned by gsettings) and re-read them
    // whenever the settings hub changes them, so widget and settings stay in
    // sync. Degrades to the built-in format when gsettings is unavailable.
    Process {
        id: clockPrefsProcess
        command: ["/usr/bin/sh", "-c",
            "command -v gsettings >/dev/null 2>&1 || exit 3; " +
            "gsettings get org.gnome.desktop.interface clock-format; " +
            "gsettings get org.gnome.desktop.interface clock-show-date; " +
            "gsettings get org.gnome.desktop.interface clock-show-seconds; " +
            "gsettings get org.gnome.desktop.interface clock-show-weekday"]
        stdout: StdioCollector { id: clockPrefsOut }
        onExited: function(code) {
            if (code !== 0) return
            var lines = String(clockPrefsOut.text || "").split("\n")
            root.clock24h = String(lines[0] || "").indexOf("24h") >= 0
            root.clockShowDate = String(lines[1] || "").indexOf("true") >= 0
            root.clockShowSeconds = String(lines[2] || "").indexOf("true") >= 0
            root.clockShowWeekday = String(lines[3] || "").indexOf("true") >= 0
        }
    }

    Process {
        id: clockPrefsMonitor
        command: ["/usr/bin/sh", "-c",
            "command -v gsettings >/dev/null 2>&1 && exec gsettings monitor org.gnome.desktop.interface"]
        stdout: SplitParser {
            onRead: function() { clockPrefsProcess.running = true }
        }
    }

    Component.onCompleted: clockPrefsProcess.running = true

    Timer {
        interval: 15000
        repeat: true
        running: !!(root.bar && root.bar.barVisible)
        onTriggered: root.refreshTick++
    }

    Text {
        id: clockLabel
        anchors.centerIn: parent
        visible: !root.vertical
        text: root.displayText
        color: root.barForeground
        font.family: Theme.fontFamily
        font.pixelSize: root.bar && root.bar.barTextSize ? root.bar.barTextSize : Theme.bar.text
        font.weight: Theme.fontWeightMedium
    }

    Column {
        visible: root.vertical
        anchors.fill: parent

        Repeater {
            model: root.verticalLines

            Text {
                required property string modelData
                width: parent.width
                height: root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : Theme.bar.iconSlot
                text: modelData
                color: root.barForeground
                font.family: Theme.fontFamily
                font.pixelSize: modelData.length > 3
                    ? (root.bar && root.bar.barIconFont ? root.bar.barIconFont * 0.9 : Theme.bar.iconFont * 0.9)
                    : (root.bar && root.bar.barIconFont ? root.bar.barIconFont : Theme.bar.iconFont)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
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
