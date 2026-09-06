import QtQuick
import Quickshell
import Quickshell.Io
import "ui"

Item {
    id: pluginRoot

    property string aureliaPath: ""
    property var shell: null
    property var manifest: ({})
    property var pluginRegistry: null

    function open(payloadJson) {
        calendarPanel.open(payloadJson || "{}")
        return "ok"
    }

    function close() {
        calendarPanel.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (calendarPanel.visible) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return calendarPanel.visible
    }

    IpcHandler {
        target: "aurelia.calendar"

        function ping(): bool { return true }
        function open(): void { pluginRoot.open("{}") }
        function close(): void { pluginRoot.close() }
        function toggle(): void { pluginRoot.toggle("{}") }
        function isVisible(): bool { return pluginRoot.isVisible() }
    }

    CalendarPanel {
        id: calendarPanel
    }
}
