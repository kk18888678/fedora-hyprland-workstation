import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../../ui"
import "ImagePickerModel.js" as ImagePickerModel

// Resident Omarchy-style image selector. Theme/background policy stays in the
// aurelia-theme* commands; this overlay owns only discovery, preview, focus,
// and selection. Applying a choice always goes back through those commands.
Item {
    id: root

    property string aureliaPath: ""
    property var shell: null
    property var manifest: ({})
    property var pluginRegistry: null
    property bool opened: false
    property string mode: "theme"
    property var entries: []
    property int selectedIndex: 0
    property string filterText: ""
    property bool imagesLoaded: false
    property bool loading: false
    property bool applying: false
    readonly property bool filterable: true
    property string errorMessage: ""
    property int requestSerial: 0

    readonly property string themeBin: aureliaPath !== ""
        ? aureliaPath + "/bin/aurelia-theme"
        : "/usr/local/bin/aurelia-theme"
    readonly property string backgroundBin: aureliaPath !== ""
        ? aureliaPath + "/bin/aurelia-theme-bg"
        : "/usr/local/bin/aurelia-theme-bg"
    readonly property string previewBin: aureliaPath !== ""
        ? aureliaPath + "/bin/aurelia-theme-preview"
        : "/usr/local/bin/aurelia-theme-preview"
    readonly property var filteredEntries: ImagePickerModel.filteredRows(root.entries, root.filterText)
    readonly property var selectedEntry: root.filteredEntries.length > 0 &&
        root.selectedIndex >= 0 && root.selectedIndex < root.filteredEntries.length
        ? root.filteredEntries[root.selectedIndex]
        : null
    readonly property string modeLabel: root.mode === "background" ? "Backgrounds" : "Themes"
    readonly property string screenName: Quickshell.screens.length > 0
        ? String(Quickshell.screens[0].name || "")
        : ""

    function fileUrl(value) {
        var parts = String(value || "").split("/")
        for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
        return "file://" + parts.join("/")
    }

    function isVideo(value) {
        return /\.(mp4|m4v|mov|webm|mkv|avi)$/i.test(String(value || ""))
    }

    function validThemeId(value) {
        return /^[A-Za-z0-9][A-Za-z0-9_.+-]*$/.test(String(value || ""))
    }

    function validMediaPath(value) {
        var path = String(value || "")
        return path.charAt(0) === "/" && path !== "/" &&
            path.indexOf("\n") === -1 && path.indexOf("\r") === -1 &&
            /\.(jpg|jpeg|png|gif|bmp|webp|mp4|m4v|mov|webm|mkv|avi)$/i.test(path)
    }

    function focusSurface() {
        if (root.opened && root.imagesLoaded) pickerFocus.forceActiveFocus()
    }

    function setMode(nextMode) {
        root.mode = nextMode === "background" ? "background" : "theme"
        root.entries = []
        root.selectedIndex = 0
        root.filterText = ""
        root.imagesLoaded = false
    }

    function open(payloadJson) {
        var payload = {}
        try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (error) { payload = {} }
        root.setMode(payload.mode)
        root.errorMessage = ""
        root.opened = true
        root.refresh()
        return "ok"
    }

    function close() {
        if (root.applying) return "busy"
        root.opened = false
        root.filterText = ""
        root.errorMessage = ""
        return "closed"
    }

    function isVisible() {
        return root.opened
    }

    function refresh() {
        if (root.applying) return
        root.requestSerial++
        root.loading = true
        root.imagesLoaded = false
        root.errorMessage = ""
        if (dataProcess.running) dataProcess.running = false
        dataProcess.command = [root.previewBin, root.mode === "background" ? "backgrounds" : "themes"]
        dataProcess.serial = root.requestSerial
        dataProcess.running = true
    }

    function loadRows(raw, serial) {
        if (serial !== root.requestSerial) return
        var loaded = ImagePickerModel.loadRows(raw, root.mode)
        root.entries = loaded
        root.selectedIndex = ImagePickerModel.indexForCurrent(loaded)
        if (root.selectedIndex >= loaded.length) root.selectedIndex = Math.max(0, loaded.length - 1)
        root.imagesLoaded = true
        root.loading = false
        Qt.callLater(root.focusSurface)
    }

    function select(index) {
        if (root.filteredEntries.length === 0) return
        var next = Math.max(0, Math.min(index, root.filteredEntries.length - 1))
        root.selectedIndex = next
        Qt.callLater(root.focusSurface)
    }

    function selectAdjacent(direction) {
        var count = root.filteredEntries.length
        if (count === 0) return
        root.select((root.selectedIndex + direction + count) % count)
    }

    function updateFilter(nextText) {
        root.filterText = String(nextText || "")
        if (root.filteredEntries.length === 0) {
            root.selectedIndex = 0
            return
        }
        if (root.selectedIndex >= root.filteredEntries.length)
            root.selectedIndex = root.filteredEntries.length - 1
    }

    function applySelected() {
        var entry = root.selectedEntry
        if (!entry || root.applyProcessRunning || root.filteredEntries.length === 0) return

        if (root.mode === "theme") {
            if (!root.validThemeId(entry.id)) {
                root.errorMessage = "The selected theme identifier is invalid."
                return
            }
            applyProcess.command = [root.themeBin, "set", String(entry.id)]
        } else {
            if (!root.validMediaPath(entry.filePath)) {
                root.errorMessage = "The selected background path is invalid."
                return
            }
            applyProcess.command = [root.backgroundBin, "set", String(entry.filePath)]
        }

        root.errorMessage = ""
        root.applying = true
        applyProcess.running = true
    }

    readonly property bool applyProcessRunning: applyProcess.running

    onOpenedChanged: {
        if (root.opened) Qt.callLater(root.focusSurface)
    }
    onFilterTextChanged: {
        if (root.selectedIndex >= root.filteredEntries.length)
            root.selectedIndex = Math.max(0, root.filteredEntries.length - 1)
    }

    Process {
        id: dataProcess
        property int serial: 0
        command: []
        stdout: StdioCollector { id: dataOutput }
        stderr: StdioCollector { id: dataError }

        onExited: function(code) {
            if (serial !== root.requestSerial) return
            root.loading = false
            if (code !== 0) {
                root.imagesLoaded = true
                root.errorMessage = String(dataError.text || "").trim() || "Image preview data is unavailable."
                Qt.callLater(root.focusSurface)
                return
            }
            root.loadRows(dataOutput.text || "", serial)
        }
    }

    Process {
        id: applyProcess
        command: []
        stdout: StdioCollector { id: applyOutput }
        stderr: StdioCollector { id: applyError }

        onExited: function(code) {
            root.applying = false
            if (code !== 0) {
                root.errorMessage = String(applyError.text || "").trim() || "Theme or background change failed."
                Qt.callLater(root.focusSurface)
                return
            }
            root.opened = false
            root.refresh()
        }
    }

    PanelWindow {
        id: overlay

        readonly property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        screen: targetScreen
        visible: root.opened && targetScreen !== null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "aurelia-image-picker"
        WlrLayershell.keyboardFocus: root.opened
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.OnDemand

        Rectangle {
            anchors.fill: parent
            color: Theme.imagePicker.scrim
        }

        MouseArea {
            anchors.fill: parent
            z: 0
            enabled: root.opened && !root.applying
            onClicked: root.close()
        }

        Item {
            id: selectorSurface
            anchors.centerIn: parent
            width: Math.min(Math.max(560, parent.width - Theme.spacingXxl * 2), 1180)
            height: Math.min(Math.max(430, parent.height - Theme.spacingXxl * 2), 620)
            z: 1

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: function(mouse) { mouse.accepted = true }
            }

            FocusScope {
                id: pickerFocus
                anchors.fill: parent
                focus: root.opened
                Keys.priority: Keys.BeforeItem

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        if (root.filterText !== "") root.updateFilter("")
                        else root.close()
                        event.accepted = true
                        return
                    }
                    if (root.applying) {
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.applySelected()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up ||
                        event.key === Qt.Key_Backtab ||
                        (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier)) {
                        root.selectAdjacent(-1)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                        root.selectAdjacent(1)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Backspace) {
                        if (root.filterText.length > 0)
                            root.updateFilter(root.filterText.slice(0, -1))
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_U && event.modifiers & Qt.ControlModifier) {
                        root.updateFilter("")
                        event.accepted = true
                        return
                    }

                    var printable = event.text && event.text.length === 1 &&
                        event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                    var plainText = event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier
                    if (root.filterable && printable && plainText) {
                        root.updateFilter(root.filterText + event.text)
                        event.accepted = true
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Theme.spacingSm

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            text: root.modeLabel.toUpperCase()
                            color: Theme.imagePicker.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.weight: Theme.fontWeightBold
                        }

                        Text {
                            text: root.applying ? "Applying…" :
                                (root.loading ? "Loading previews…" :
                                    (root.filteredEntries.length + " available"))
                            color: root.errorMessage !== "" ? Theme.error : Theme.imagePicker.text
                            font.family: Theme.fontFamilyProse
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.errorMessage !== "" ? root.errorMessage
                            : (root.filterText !== "" ? "Filter: " + root.filterText
                                : "← → select   Enter apply   Esc close   Type to filter")
                        color: root.errorMessage !== "" ? Theme.error : Theme.textSecondary
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeSm
                        elide: Text.ElideRight
                    }

                    Item {
                        id: carousel
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: false

                        Text {
                            anchors.centerIn: parent
                            visible: root.imagesLoaded && root.filteredEntries.length === 0
                            text: root.filterText !== "" ? "No matching previews" : "No previews available"
                            color: Theme.textMuted
                            font.family: Theme.fontFamilyProse
                            font.pixelSize: Theme.fontSizeMd
                        }

                        Repeater {
                            model: root.filteredEntries

                            delegate: Item {
                                id: carouselItem
                                required property var modelData
                                required property int index

                                readonly property bool selected: index === root.selectedIndex
                                readonly property int relativeIndex: index - root.selectedIndex
                                readonly property bool nearby: Math.abs(relativeIndex) <= 8
                                property bool sourceActivated: nearby
                                readonly property real expandedWidth: Math.min(560, carousel.width * 0.52)
                                readonly property real collapsedWidth: 116

                                onNearbyChanged: if (nearby) sourceActivated = true
                                visible: nearby
                                width: selected ? expandedWidth : collapsedWidth
                                height: selected ? 340 : 286
                                x: {
                                    var center = (carousel.width - expandedWidth) / 2
                                    if (selected) return center
                                    if (relativeIndex < 0)
                                        return center - collapsedWidth + relativeIndex * 88
                                    return center + expandedWidth + (relativeIndex - 1) * 88
                                }
                                y: selected ? 0 : 27
                                z: selected ? 100 : 50 - Math.abs(relativeIndex)
                                rotation: selected ? 0 : (relativeIndex < 0 ? -4 : 4)
                                transformOrigin: Item.Center

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radiusMd
                                    color: Theme.surface
                                    border.color: carouselItem.selected
                                        ? Theme.imagePicker.selectedBorder
                                        : Theme.imagePicker.unselectedBorder
                                    border.width: carouselItem.selected ? 3 : 1
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        visible: carouselItem.sourceActivated &&
                                            String(carouselItem.modelData.thumbnailPath || "") !== ""
                                        source: visible ? root.fileUrl(carouselItem.modelData.thumbnailPath) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        smooth: true
                                        mipmap: true
                                    }

                                    AureliaMark {
                                        anchors.centerIn: parent
                                        width: carouselItem.selected ? 96 : 48
                                        height: width
                                        visible: String(carouselItem.modelData.thumbnailPath || "") === ""
                                        color: Theme.accent
                                        coreColor: Theme.gold
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: Qt.rgba(Theme.bgBase.r, Theme.bgBase.g, Theme.bgBase.b,
                                            carouselItem.selected ? 0.02 : 0.58)
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: Theme.spacingSm
                                        visible: !carouselItem.selected
                                        text: String(carouselItem.modelData.label || "")
                                        color: Theme.imagePicker.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideMiddle
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !root.applying
                                        onClicked: {
                                            mouse.accepted = true
                                            if (carouselItem.selected) root.applySelected()
                                            else root.select(carouselItem.index)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        text: root.selectedEntry
                            ? String(root.selectedEntry.label || root.selectedEntry.id || "")
                            : ""
                        color: Theme.imagePicker.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Theme.fontWeightBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
