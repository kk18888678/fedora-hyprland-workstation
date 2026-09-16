import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../../services/SourceUrl.js" as SourceUrl
import "../WallpapersModel.js" as WallpapersModel

// Wallpaper library panel. Keyboard-first, one grid, three sources (local
// library, wallhaven, and the pinned bjarneo catalog). This surface never
// mutates wallpaper or theme state itself: it only builds argv for the
// aurelia-wallpaper command and reports its result.
Item {
    id: root

    property bool opened: false
    property string mode: "local" // "local" | "wallhaven" | "catalog"
    property var entries: []
    property int selectedIndex: 0
    property string filterText: ""
    property bool loading: false
    property bool applying: false
    property bool themeFromWallpaper: false
    property string errorMessage: ""
    property int requestSerial: 0
    property string applyStage: "idle" // "idle" | "download" | "activate"

    readonly property string wallpaperBin: (aureliaPath !== ""
        ? aureliaPath + "/bin/aurelia-wallpaper"
        : "/usr/local/bin/aurelia-wallpaper")
    readonly property var filteredEntries: WallpapersModel.filteredRows(root.entries, root.filterText)
    readonly property var selectedEntry: root.filteredEntries.length > 0 &&
        root.selectedIndex >= 0 && root.selectedIndex < root.filteredEntries.length
        ? root.filteredEntries[root.selectedIndex]
        : null
    readonly property string modeLabel: root.mode === "wallhaven" ? "Wallhaven"
        : (root.mode === "catalog" ? "Wallpaper catalog" : "Local sources")
    readonly property bool remoteMode: root.mode === "wallhaven" || root.mode === "catalog"
    readonly property int gridColumns: 5
    readonly property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    function fileUrl(value) {
        return SourceUrl.fileUrl(value)
    }

    function focusSurface() {
        if (root.opened) surfaceFocus.forceActiveFocus()
    }

    function setMode(nextMode) {
        if (nextMode === "wallhaven" || nextMode === "catalog") root.mode = nextMode
        else root.mode = "local"
        root.entries = []
        root.selectedIndex = 0
        root.filterText = ""
        root.errorMessage = ""
        root.themeFromWallpaper = false
    }

    function open(payloadJson) {
        var payload = {}
        try {
            payload = JSON.parse(String(payloadJson || "{}")) || {}
        } catch (error) {
            console.warn("[WALLPAPERS] payload_invalid reason=invalid_json")
            payload = {}
        }
        root.setMode(payload.mode === "wallhaven" || payload.mode === "catalog"
            ? payload.mode : "local")
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
        root.errorMessage = ""
        if (dataProcess.running) dataProcess.running = false

        var query = String(root.filterText || "").trim()
        if (root.mode === "wallhaven") {
            if (query === "") {
                dataProcess.command = [root.wallpaperBin, "wallhaven", "search",
                    "--sorting", "toplist", "--rows", "--thumbs"]
            } else {
                dataProcess.command = [root.wallpaperBin, "wallhaven", "search",
                    "--query", query, "--rows", "--thumbs"]
            }
        } else if (root.mode === "catalog") {
            if (query === "") {
                dataProcess.command = [root.wallpaperBin, "catalog", "list",
                    "--rows", "--thumbs"]
            } else {
                dataProcess.command = [root.wallpaperBin, "catalog", "list",
                    "--query", query, "--rows", "--thumbs"]
            }
        } else {
            dataProcess.command = [root.wallpaperBin, "list", "--rows"]
        }
        dataProcess.serial = root.requestSerial
        dataProcess.running = true
    }

    function loadRows(raw, serial) {
        if (serial !== root.requestSerial) return
        var loaded
        if (root.mode === "wallhaven") loaded = WallpapersModel.loadWallhavenRows(raw)
        else if (root.mode === "catalog") loaded = WallpapersModel.loadCatalogRows(raw)
        else loaded = WallpapersModel.loadLocalRows(raw)
        root.entries = loaded
        root.selectedIndex = WallpapersModel.indexForCurrent(loaded)
        if (root.selectedIndex >= loaded.length) root.selectedIndex = Math.max(0, loaded.length - 1)
        root.loading = false
        Qt.callLater(root.focusSurface)
    }

    function select(index) {
        if (root.filteredEntries.length === 0) return
        var next = Math.max(0, Math.min(index, root.filteredEntries.length - 1))
        root.selectedIndex = next
        Qt.callLater(root.focusSurface)
    }

    function selectAdjacent(delta) {
        var count = root.filteredEntries.length
        if (count === 0) return
        root.select(root.selectedIndex + delta)
    }

    function updateFilter(nextText) {
        root.filterText = String(nextText || "")
        if (root.filteredEntries.length === 0) {
            root.selectedIndex = 0
            return
        }
        if (root.selectedIndex >= root.filteredEntries.length)
            root.selectedIndex = root.filteredEntries.length - 1
        // A changed remote query is a search, not a local filter.
        if (root.remoteMode) root.debouncedSearch.restart()
    }

    function applySelected() {
        var entry = root.selectedEntry
        if (!entry || root.applying) return

        if (root.remoteMode) {
            root.applyStage = "download"
            if (root.mode === "catalog") {
                applyProcess.command = [root.wallpaperBin, "catalog", "download", String(entry.id)]
            } else {
                applyProcess.command = [root.wallpaperBin, "wallhaven", "download", String(entry.id)]
            }
        } else if (root.themeFromWallpaper) {
            root.applyStage = "activate"
            applyProcess.command = [root.wallpaperBin, "theme", "apply", String(entry.filePath)]
        } else {
            root.applyStage = "activate"
            applyProcess.command = [root.wallpaperBin, "apply", String(entry.filePath)]
        }

        root.errorMessage = ""
        root.applying = true
        applyProcess.running = true
    }

    onOpenedChanged: {
        if (root.opened) Qt.callLater(root.focusSurface)
    }
    onFilterTextChanged: {
        if (root.selectedIndex >= root.filteredEntries.length)
            root.selectedIndex = Math.max(0, root.filteredEntries.length - 1)
    }

    Timer {
        id: debouncedSearch
        interval: 450
        repeat: false
        onTriggered: root.refresh()
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
                root.entries = []
                root.errorMessage = String(dataError.text || "").trim() ||
                    "Wallpaper sources are unavailable."
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
                root.applyStage = "idle"
                root.errorMessage = String(applyError.text || "").trim() ||
                    "The wallpaper change failed."
                Qt.callLater(root.focusSurface)
                return
            }

            if (root.applyStage === "download") {
                // The download commands print the published library path.
                var lines = String(applyOutput.text || "").trim().split("\n")
                var published = lines.length > 0 ? lines[lines.length - 1] : ""
                if (String(published).charAt(0) !== "/") {
                    root.applyStage = "idle"
                    root.errorMessage = "The download did not report a library path."
                    Qt.callLater(root.focusSurface)
                    return
                }
                root.applyStage = "activate"
                root.applying = true
                applyProcess.command = [root.wallpaperBin, "apply", String(published)]
                applyProcess.running = true
                return
            }

            root.applyStage = "idle"
            root.refresh()
        }
    }

    PanelWindow {
        id: overlay

        screen: root.targetScreen
        visible: root.opened && root.targetScreen !== null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "aurelia-wallpapers"
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
            width: Math.min(Math.max(640, parent.width - Theme.spacingXxl * 2), 1240)
            height: Math.min(Math.max(460, parent.height - Theme.spacingXxl * 2), 700)
            z: 1

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: function(mouse) { mouse.accepted = true }
            }

            FocusScope {
                id: surfaceFocus
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
                    if (event.key === Qt.Key_Tab) {
                        if (root.mode === "local") root.setMode("wallhaven")
                        else if (root.mode === "wallhaven") root.setMode("catalog")
                        else root.setMode("local")
                        root.refresh()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_T && root.mode === "local") {
                        root.themeFromWallpaper = !root.themeFromWallpaper
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Backspace) {
                        root.updateFilter(root.filterText.slice(0, -1))
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up ||
                        event.key === Qt.Key_Backtab) {
                        root.selectAdjacent(event.key === Qt.Key_Up ? -root.gridColumns : -1)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                        root.selectAdjacent(event.key === Qt.Key_Down ? root.gridColumns : 1)
                        event.accepted = true
                        return
                    }
                    if (event.text !== "" && event.text >= " " && event.text !== "\t") {
                        root.updateFilter(root.filterText + event.text)
                        event.accepted = true
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Theme.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30

                        Text {
                            Layout.fillWidth: true
                            text: "Wallpapers"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.weight: Theme.fontWeightBold
                        }

                        Text {
                            text: root.modeLabel + "  (Tab)"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightBold
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        text: root.errorMessage !== ""
                            ? root.errorMessage
                            : (root.applying
                                ? (root.applyStage === "download" ? "Downloading wallpaper…" : "Applying…")
                                : (root.loading ? "Loading…" :
                                    (root.remoteMode
                                        ? (root.filterText === ""
                                            ? root.modeLabel
                                            : "Search: " + root.filterText)
                                        : (root.filterText === ""
                                            ? root.modeLabel + ": " + root.filteredEntries.length
                                            : "Filter: " + root.filterText))))
                        color: root.errorMessage !== "" ? Theme.error : Theme.textSecondary
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeSm
                        elide: Text.ElideRight
                    }

                    GridView {
                        id: wallpaperGrid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cellWidth: Math.floor(wallpaperGrid.width / root.gridColumns)
                        cellHeight: Math.floor(wallpaperGrid.cellWidth * 0.62)
                        model: root.filteredEntries
                        currentIndex: root.selectedIndex
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            required property var modelData
                            required property int index

                            width: wallpaperGrid.cellWidth
                            height: wallpaperGrid.cellHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingXs
                                radius: Theme.radiusMd
                                color: index === root.selectedIndex
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                    : Qt.rgba(Theme.bgBase.r, Theme.bgBase.g, Theme.bgBase.b, 0.35)
                                border.color: index === root.selectedIndex ? Theme.accent : Theme.border
                                border.width: index === root.selectedIndex
                                    ? Theme.borderWidthFocus
                                    : Theme.borderWidthDefault

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingXs
                                    source: root.fileUrl(String(modelData.thumb || ""))
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    visible: String(modelData.thumb || "") !== ""
                                }

                                AureliaMark {
                                    anchors.centerIn: parent
                                    width: 40
                                    height: width
                                    visible: String(modelData.thumb || "") === ""
                                    color: Theme.accent
                                    coreColor: Theme.gold
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: Theme.spacingXs
                                    text: String(modelData.label || "")
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideMiddle
                                    style: Text.Outline
                                    styleColor: Theme.bgBase
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.applying
                                onClicked: function(mouse) {
                                    mouse.accepted = true
                                    if (index === root.selectedIndex) root.applySelected()
                                    else root.select(index)
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        text: root.remoteMode
                            ? "← → ↑ ↓ select   Enter download & apply   Tab next source   Esc close"
                            : "← → ↑ ↓ select   Enter apply   T theme from wallpaper   Tab next source   Esc close"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeSm
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
