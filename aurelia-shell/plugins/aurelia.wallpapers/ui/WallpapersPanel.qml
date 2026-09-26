import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../../ui"
import "../../../theme"
import "../../../services/SourceUrl.js" as SourceUrl
import "../WallpapersModel.js" as WallpapersModel

// Wallpaper library GUI. Three sources (local library, wallhaven, and the
// pinned bjarneo catalog) with a thumbnail grid, a live preview pane, and
// click/keyboard apply. This surface never mutates wallpaper or theme state
// itself: it only builds argv for the aurelia-wallpaper command and reports
// its result.
Item {
    id: root

    property bool opened: false
    property string aureliaPath: ""
    property string mode: "local" // "local" | "wallhaven" | "catalog"
    property var entries: []
    property int selectedIndex: 0
    property string filterText: ""
    property bool loading: false
    property bool applying: false
    property bool editorOpen: false
    property string editorImage: ""
    property string errorMessage: ""
    property int requestSerial: 0
    property string applyStage: "idle" // "idle" | "download" | "activate"
    property bool appending: false
    property int wallhavenPage: 1
    property int wallhavenLastPage: 1
    property int wallhavenTotal: 0

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
    readonly property string searchPlaceholder: root.mode === "wallhaven"
        ? "Search wallhaven…"
        : (root.mode === "catalog" ? "Search catalog…" : "Filter wallpapers…")
    readonly property string applyLabel: root.remoteMode ? "Download & apply" : "Set wallpaper"
    readonly property bool canLoadMore: root.mode === "wallhaven" &&
        root.wallhavenPage < root.wallhavenLastPage && !root.appending
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
        root.wallhavenPage = 1
        root.wallhavenLastPage = 1
        root.wallhavenTotal = 0
        root.appending = false
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

    function wallhavenSearchCommand(page) {
        var query = String(root.filterText || "").trim()
        var args = [root.wallpaperBin, "wallhaven", "search"]
        if (query === "") args.push("--sorting", "toplist")
        else args.push("--query", query)
        args.push("--page", String(page), "--rows", "--thumbs", "--paging")
        return args
    }

    function catalogCommand() {
        var query = String(root.filterText || "").trim()
        var args = [root.wallpaperBin, "catalog", "list"]
        if (query !== "") args.push("--query", query)
        args.push("--rows", "--thumbs")
        return args
    }

    function refresh() {
        if (root.applying) return
        root.requestSerial++
        root.loading = true
        root.errorMessage = ""
        root.appending = false
        if (dataProcess.running) dataProcess.running = false

        if (root.mode === "wallhaven") {
            root.wallhavenPage = 1
            root.wallhavenLastPage = 1
            root.wallhavenTotal = 0
            dataProcess.command = root.wallhavenSearchCommand(1)
        } else if (root.mode === "catalog") {
            dataProcess.command = root.catalogCommand()
        } else {
            dataProcess.command = [root.wallpaperBin, "list", "--rows"]
        }
        dataProcess.serial = root.requestSerial
        dataProcess.running = true
    }

    function loadMoreWallhaven() {
        if (root.applying || root.loading || root.mode !== "wallhaven") return
        if (root.wallhavenPage >= root.wallhavenLastPage) return
        root.requestSerial++
        root.loading = true
        root.appending = true
        root.errorMessage = ""
        if (dataProcess.running) dataProcess.running = false
        dataProcess.command = root.wallhavenSearchCommand(root.wallhavenPage + 1)
        dataProcess.serial = root.requestSerial
        dataProcess.running = true
    }

    function loadRows(raw, serial) {
        if (serial !== root.requestSerial) return
        var loaded
        var append = root.appending && root.mode === "wallhaven"
        if (root.mode === "wallhaven") {
            var meta = WallpapersModel.parseMeta(raw)
            if (meta) {
                root.wallhavenPage = meta.page
                root.wallhavenLastPage = meta.lastPage
                root.wallhavenTotal = meta.total
            }
            loaded = WallpapersModel.loadWallhavenRows(raw)
            if (append) loaded = WallpapersModel.mergeRows(root.entries, loaded)
        } else if (root.mode === "catalog") {
            loaded = WallpapersModel.loadCatalogRows(raw)
        } else {
            loaded = WallpapersModel.loadLocalRows(raw)
        }
        root.entries = loaded
        if (!append) {
            root.selectedIndex = WallpapersModel.indexForCurrent(loaded)
            if (root.selectedIndex >= loaded.length) root.selectedIndex = Math.max(0, loaded.length - 1)
        }
        root.appending = false
        root.loading = false
        Qt.callLater(root.focusSurface)
    }

    function openEditor() {
        var entry = root.selectedEntry
        if (!entry || root.remoteMode || String(entry.filePath || "") === "") return
        root.editorImage = String(entry.filePath)
        root.editorOpen = true
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
        } else {
            root.applyStage = "activate"
            applyProcess.command = [root.wallpaperBin, "apply", String(entry.filePath)]
        }

        root.errorMessage = ""
        root.applying = true
        applyProcess.running = true
    }

    function applyRandom() {
        if (root.applying || root.remoteMode) return
        root.applyStage = "activate"
        root.errorMessage = ""
        root.applying = true
        applyProcess.command = [root.wallpaperBin, "random"]
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
                if (!root.appending) root.entries = []
                root.appending = false
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

    // The editor is created only while it is open. Instantiating its layer
    // window eagerly would make the panel depend on a window backend just to
    // load, which offscreen and headless sessions cannot provide.
    Loader {
        id: paletteEditorLoader
        active: root.editorOpen
        source: Qt.resolvedUrl("PaletteEditor.qml")
        onLoaded: {
            item.aureliaPath = root.aureliaPath
            item.imagePath = root.editorImage
            item.opened = root.editorOpen
            item.closed.connect(function() {
                Qt.callLater(function() { root.editorOpen = false })
            })
            item.applied.connect(function() {
                Qt.callLater(function() {
                    root.editorOpen = false
                    root.refresh()
                })
            })
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
            width: Math.min(Math.max(760, parent.width - Theme.spacingXxl * 2), 1280)
            height: Math.min(Math.max(520, parent.height - Theme.spacingXxl * 2), 760)
            z: 1

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: function(mouse) { mouse.accepted = true }
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusLg
                color: Theme.bgBase
                border.color: Theme.border
                border.width: Theme.borderWidthDefault
            }

            FocusScope {
                id: surfaceFocus
                anchors.fill: parent
                anchors.margins: Theme.spacingMd
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
                        root.openEditor()
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
                        root.selectAdjacent(event.key === Qt.Key_Up ? -wallpaperGrid.columns : -1)
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                        root.selectAdjacent(event.key === Qt.Key_Down ? wallpaperGrid.columns : 1)
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
                        Layout.preferredHeight: 36
                        spacing: Theme.spacingSm

                        Text {
                            text: "Wallpapers"
                            color: Theme.text
                            font.family: Theme.fontFamilyResolved
                            font.pixelSize: Theme.fontSizeLg
                            font.weight: Theme.fontWeightBold
                        }

                        Repeater {
                            model: ["Local", "Wallhaven", "Catalog"]

                            delegate: Rectangle {
                                required property int index
                                required property string modelData
                                readonly property bool active: (index === 0 && root.mode === "local") ||
                                    (index === 1 && root.mode === "wallhaven") ||
                                    (index === 2 && root.mode === "catalog")

                                width: tabLabel.width + Theme.spacingMd * 2
                                height: 28
                                radius: Theme.radiusSm
                                color: active
                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                    : Theme.controls.normalFill
                                border.color: active ? Theme.accent : Theme.controls.normalBorder
                                border.width: active
                                    ? Theme.borderWidthFocus
                                    : Theme.borderWidthDefault

                                Text {
                                    id: tabLabel
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: active ? Theme.accent : Theme.textSecondary
                                    font.family: Theme.fontFamilyResolved
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: active
                                        ? Theme.fontWeightBold
                                        : Theme.fontWeightMedium
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.applying
                                    onClicked: function(mouse) {
                                        mouse.accepted = true
                                        var next = index === 0 ? "local"
                                            : (index === 1 ? "wallhaven" : "catalog")
                                        if (next !== root.mode) {
                                            root.setMode(next)
                                            root.refresh()
                                        }
                                        surfaceFocus.forceActiveFocus()
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        TextField {
                            id: searchField
                            property bool syncing: false

                            Layout.preferredWidth: 240
                            Layout.preferredHeight: 32
                            placeholderText: root.searchPlaceholder
                            text: root.filterText
                            font.family: Theme.fontFamilyResolved
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.inputText
                            placeholderTextColor: Theme.inputPlaceholder
                            selectionColor: Theme.inputSelection
                            background: Rectangle {
                                color: Theme.inputBg
                                border.color: searchField.activeFocus
                                    ? Theme.inputBorderFocused
                                    : Theme.inputBorder
                                border.width: Theme.borderWidthDefault
                                radius: Theme.radiusSm
                            }
                            onTextChanged: {
                                if (!searchField.syncing && text !== root.filterText)
                                    root.updateFilter(text)
                            }
                            onAccepted: root.applySelected()
                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Escape) {
                                    if (root.filterText !== "") root.updateFilter("")
                                    else root.close()
                                    event.accepted = true
                                    return
                                }
                                if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                    surfaceFocus.forceActiveFocus()
                                    event.accepted = true
                                }
                            }
                        }

                        Connections {
                            target: root
                            function onFilterTextChanged() {
                                if (searchField.text !== root.filterText) {
                                    searchField.syncing = true
                                    searchField.text = root.filterText
                                    searchField.syncing = false
                                }
                            }
                            function onModeChanged() {
                                searchField.syncing = true
                                searchField.text = root.filterText
                                searchField.syncing = false
                            }
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

                    WallhavenKeyRow {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        visible: root.mode === "wallhaven"
                        wallpaperBin: root.wallpaperBin
                        onChanged: root.refresh()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Theme.spacingMd

                        GridView {
                            id: wallpaperGrid
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            readonly property int columns: Math.max(2,
                                Math.floor(wallpaperGrid.width / 220))
                            cellWidth: Math.floor(wallpaperGrid.width / wallpaperGrid.columns)
                            cellHeight: Math.floor(wallpaperGrid.cellWidth * 0.64)
                            model: root.filteredEntries
                            currentIndex: root.selectedIndex
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Item {
                                required property var modelData
                                required property int index

                                width: wallpaperGrid.cellWidth
                                height: wallpaperGrid.cellHeight

                                Rectangle {
                                    id: card
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingXs
                                    radius: Theme.radiusMd
                                    color: index === root.selectedIndex
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                        : cardHover.hovered
                                            ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                                            : Theme.controls.normalFill
                                    border.color: index === root.selectedIndex
                                        ? Theme.accent
                                        : (cardHover.hovered ? Theme.controls.hoverBorder : Theme.border)
                                    border.width: index === root.selectedIndex
                                        ? Theme.borderWidthFocus
                                        : Theme.borderWidthDefault

                                    HoverHandler { id: cardHover }

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

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: Theme.spacingXs
                                        width: currentBadge.width + Theme.spacingXs * 2
                                        height: 18
                                        radius: Theme.radiusSm
                                        visible: modelData.current === true
                                        color: Qt.rgba(Theme.accent.r, Theme.accent.g,
                                            Theme.accent.b, 0.85)

                                        Text {
                                            id: currentBadge
                                            anchors.centerIn: parent
                                            text: "ACTIVE"
                                            color: Theme.bgBase
                                            font.family: Theme.fontFamilyResolved
                                            font.pixelSize: Theme.fontSizeXs - 1
                                            font.weight: Theme.fontWeightBold
                                        }
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: Theme.spacingXs
                                        text: String(modelData.label || "")
                                        color: Theme.text
                                        font.family: Theme.fontFamilyResolved
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
                                        surfaceFocus.forceActiveFocus()
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            id: previewPane
                            // A nested layout item otherwise stretches to the
                            // whole row in QtQuick Layouts, which collapses the
                            // sibling GridView to a few pixels and hides the
                            // thumbnail grid. Pin the preview column instead.
                            Layout.preferredWidth: 300
                            Layout.fillWidth: false
                            Layout.maximumWidth: 300
                            Layout.fillHeight: true
                            spacing: Theme.spacingSm

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 190
                                radius: Theme.radiusMd
                                color: Theme.controls.normalFill
                                border.color: previewHover.hovered && root.mode === "local"
                                    ? Theme.accent : Theme.controls.normalBorder
                                border.width: Theme.borderWidthDefault
                                clip: true

                                HoverHandler { id: previewHover }

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingXs
                                    source: root.selectedEntry
                                        ? root.fileUrl(String(root.selectedEntry.thumb || ""))
                                        : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    visible: root.selectedEntry !== null &&
                                        String(root.selectedEntry.thumb || "") !== ""
                                }

                                AureliaMark {
                                    anchors.centerIn: parent
                                    width: 64
                                    height: width
                                    visible: root.selectedEntry === null ||
                                        String(root.selectedEntry.thumb || "") === ""
                                    color: Theme.accent
                                    coreColor: Theme.gold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: root.mode === "local" && root.selectedEntry !== null
                                        ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: root.mode === "local" && root.selectedEntry !== null &&
                                        !root.applying
                                    onClicked: root.openEditor()
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.selectedEntry
                                    ? String(root.selectedEntry.label || "")
                                    : "Nothing selected"
                                color: Theme.text
                                font.family: Theme.fontFamilyResolved
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: Theme.fontWeightBold
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: {
                                    if (root.selectedEntry === null) return "Select a wallpaper."
                                    if (root.remoteMode) {
                                        var bits = []
                                        if (String(root.selectedEntry.resolution || "") !== "")
                                            bits.push(String(root.selectedEntry.resolution))
                                        if (String(root.selectedEntry.purity || "") !== "")
                                            bits.push(String(root.selectedEntry.purity).toUpperCase())
                                        return bits.length > 0 ? bits.join("  •  ")
                                            : "Remote wallpaper"
                                    }
                                    var localBits = [String(root.selectedEntry.source || "local")]
                                    if (root.selectedEntry.current === true)
                                        localBits.push("active wallpaper")
                                    return localBits.join("  •  ")
                                }
                                color: Theme.textMuted
                                font.family: Theme.fontFamilyProse
                                font.pixelSize: Theme.fontSizeXs
                                wrapMode: Text.Wrap
                            }

                            Item { Layout.fillHeight: true }

                            AureliaActionButton {
                                Layout.fillWidth: true
                                primary: true
                                compact: true
                                centerLabel: true
                                label: root.applyLabel
                                detail: root.remoteMode ? "into the library" : ""
                                enabled: root.selectedEntry !== null && !root.applying && !root.loading
                                onTriggered: root.applySelected()
                            }

                            AureliaActionButton {
                                Layout.fillWidth: true
                                compact: true
                                centerLabel: true
                                label: "Extract colors…"
                                detail: "preview, tune, apply"
                                visible: root.mode === "local"
                                enabled: root.selectedEntry !== null && !root.applying && !root.loading
                                onTriggered: root.openEditor()
                            }

                            AureliaActionButton {
                                Layout.fillWidth: true
                                compact: true
                                centerLabel: true
                                label: root.appending ? "Loading more…" : "Load more"
                                detail: root.wallhavenTotal > 0
                                    ? (root.wallhavenTotal + " results") : "next page"
                                visible: root.canLoadMore || root.appending
                                enabled: !root.applying && !root.loading
                                onTriggered: root.loadMoreWallhaven()
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSm

                                AureliaActionButton {
                                    Layout.fillWidth: true
                                    compact: true
                                    centerLabel: true
                                    label: "Random"
                                    visible: root.mode === "local"
                                    enabled: !root.applying && !root.loading
                                    onTriggered: root.applyRandom()
                                }

                                AureliaActionButton {
                                    Layout.fillWidth: true
                                    compact: true
                                    centerLabel: true
                                    label: "Refresh"
                                    enabled: !root.applying
                                    onTriggered: root.refresh()
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        text: root.remoteMode
                            ? (root.mode === "wallhaven" && root.wallhavenTotal > 0
                                ? ("Page " + root.wallhavenPage + " of " + root.wallhavenLastPage +
                                    "  •  " + root.entries.length + " of " + root.wallhavenTotal +
                                    "   •   Load more for the next page   •   Tab next source   •   Esc close")
                                : "Click a thumbnail to select, again or Enter to download & apply   •   Tab next source   •   Esc close")
                            : "Click a thumbnail to select, again or Enter to apply   •   click the preview or press T to extract colors   •   Tab next source   •   Esc close"
                        color: Theme.textMuted
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeXs
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
