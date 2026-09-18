import QtQuick
import "../../theme"
import "ClockFormat.js" as ClockFormat

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

    // The clock format is an Aurelia preference (written by the settings hub),
    // so the widget and Settings → Date & Time always agree. A per-bar
    // `format` value still wins when explicitly set to something custom.
    readonly property string configuredFormat: settings && typeof settings.format === "string"
        ? settings.format : ""
    readonly property bool autoFormat: configuredFormat === "" ||
        configuredFormat === "auto" || configuredFormat === "MMM d, dddd HH:mm"
    readonly property string derivedFormat: ClockFormat.buildFormat(
        Theme.clockFormat, Theme.clockHour24, Theme.clockSeconds)

    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text

    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    readonly property string displayFormat: root.vertical
        ? (settings && typeof settings.verticalFormat === "string" && settings.verticalFormat !== ""
            ? settings.verticalFormat : "HH\n—\nmm")
        : (root.autoFormat ? root.derivedFormat : root.configuredFormat)
    readonly property var verticalLines: displayText.split("\n")
    readonly property string displayText: {
        var tick = refreshTick
        return Qt.formatDateTime(new Date(), displayFormat)
    }

    implicitWidth: root.vertical
        ? (bar ? bar.barSize : Theme.bar.sizeVertical)
        : clockLabel.implicitWidth + (root.bar && root.bar.barTextMargin
            ? root.bar.barTextMargin * 2
            : Theme.bar.textMargin * 2)
    implicitHeight: root.vertical
        ? root.verticalLines.length * (root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : Theme.bar.iconSlot)
        : (bar ? bar.barSize : Theme.bar.sizeHorizontal)

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
