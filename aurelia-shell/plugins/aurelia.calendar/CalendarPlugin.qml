import QtQuick
import Quickshell
import Quickshell.Io
import "ui"

Item {
    id: pluginRoot

    property string aureliaPath: ""
    property var shell: null
    property var bar: null
    property var manifest: ({})
    property var pluginRegistry: null

    function resolveClockAnchor() {
        if (!pluginRoot.bar || typeof pluginRoot.bar.anchorItemFor !== "function") return
        var clockItem = pluginRoot.bar.anchorItemFor("aurelia.clock")
        if (clockItem) calendarPanel.anchorItem = clockItem
        else if (typeof pluginRoot.bar.barAnchorItem === "function") calendarPanel.anchorItem = pluginRoot.bar.barAnchorItem()
    }

    function open(payloadJson) {
        resolveClockAnchor()
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
        bar: pluginRoot.bar
        anchorItem: pluginRoot.bar && pluginRoot.bar.widgetRevision >= 0 && typeof pluginRoot.bar.anchorItemFor === "function"
            ? pluginRoot.bar.anchorItemFor("aurelia.clock")
            : null
    }
}
