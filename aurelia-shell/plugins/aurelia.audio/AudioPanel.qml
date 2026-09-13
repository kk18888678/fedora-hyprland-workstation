import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../../ui"
import "../../theme"
import "Model.js" as Model

// Omarchy-aligned Audio panel. PipeWire owns live nodes; this panel snapshots
// the current lists before delegates are rebuilt so a node disappearing during
// discovery cannot leave a delegate holding a stale QObject wrapper.
AureliaKeyboardPanel {
    id: root

    property var audioWidget: null
    property var shell: null

    readonly property var sink: audioWidget && audioWidget.sink
        ? audioWidget.sink : Pipewire.defaultAudioSink
    readonly property var source: audioWidget && audioWidget.source
        ? audioWidget.source : Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []

    readonly property var candidateSinks: {
        var list = []
        for (var i = 0; i < root.nodes.length; i++) {
            var node = root.nodes[i]
            if (node && node.isSink && !node.isStream) list.push(node)
        }
        return list
    }
    readonly property var candidateSources: {
        var list = []
        for (var i = 0; i < root.nodes.length; i++) {
            var node = root.nodes[i]
            if (node && !node.isSink && !node.isStream && Model.isAudioSource(node) &&
                String(node.name || "") !== "quickshell") list.push(node)
        }
        return list
    }
    readonly property var candidateStreams: {
        var list = []
        for (var i = 0; i < root.nodes.length; i++) {
            var node = root.nodes[i]
            if (node && node.isStream && Model.isPlaybackStream(node)) list.push(node)
        }
        return list
    }

    readonly property var rawAudioSinks: {
        var list = root.candidateSinks.slice()
        if (root.sink && list.indexOf(root.sink) < 0) list.unshift(root.sink)
        return list
    }
    readonly property var rawAudioSources: {
        var list = root.candidateSources.slice()
        if (root.source && list.indexOf(root.source) < 0) list.unshift(root.source)
        return list
    }
    readonly property var audioStreams: {
        var list = []
        for (var i = 0; i < root.candidateStreams.length; i++) {
            var node = root.candidateStreams[i]
            if (node && node.audio) list.push(node)
        }
        return list
    }
    property var cachedAudioSinks: []
    property var cachedAudioSources: []
    readonly property var audioSinks: root.rawAudioSinks.length > 0
        ? root.rawAudioSinks : root.cachedAudioSinks
    readonly property var audioSources: root.rawAudioSources.length > 0
        ? root.rawAudioSources : root.cachedAudioSources

    // Repeater data is detached from the live list container and refreshed
    // after a short settle interval. Actions still target the current default
    // or node object and are checked again immediately before mutation.
    property var displayAudioSinks: []
    property var displayAudioSources: []
    property var displayAudioStreams: []

    readonly property real outputVolume: root.sink && root.sink.audio
        ? Number(root.sink.audio.volume || 0) : 0
    readonly property real inputVolume: root.source && root.source.audio
        ? Number(root.source.audio.volume || 0) : 0
    readonly property bool outputMuted: !!(root.sink && root.sink.audio && root.sink.audio.muted)
    readonly property bool inputMuted: !!(root.source && root.source.audio && root.source.audio.muted)
    readonly property bool hasOutput: !!(root.sink && root.sink.audio)
    readonly property bool hasInput: !!(root.source && root.source.audio)
    readonly property bool anyAudible: (root.hasOutput && !root.outputMuted) ||
        (root.hasInput && !root.inputMuted)
    readonly property string toggleHint: root.anyAudible ? "Mute" : "Unmute"

    property string focusSection: "output"
    property int selectedIndex: -1
    property bool cursorActive: false
    property real wheelAccumulator: 0

    ownerId: "aurelia.audio"
    popupWidth: 380
    popupHeight: 560
    fitHeightToContent: true
    minPopupHeight: 220
    maxPopupHeight: 560
    contentSizingItem: panelColumn
    focusTarget: keyScope
    shown: false

    function open(payloadJson) {
        root.shown = true
        return "ok"
    }

    function close() {
        root.shown = false
        return "ok"
    }

    function toggle(payloadJson) {
        return root.shown ? root.close() : root.open(payloadJson || "{}")
    }

    function isVisible() { return root.shown === true }

    function listSnapshot(list) { return Model.listSnapshot(list) }

    function refreshDisplayAudioModels() {
        if (!root.shown) return
        root.displayAudioSinks = root.listSnapshot(root.audioSinks)
        root.displayAudioSources = root.listSnapshot(root.audioSources)
        root.displayAudioStreams = root.listSnapshot(root.audioStreams)
        root.clampCursor()
    }

    function scheduleDisplayAudioModelRefresh() {
        if (root.shown) audioModelRefreshTimer.restart()
    }

    function clearDisplayAudioModels() {
        audioModelRefreshTimer.stop()
        root.displayAudioSinks = []
        root.displayAudioSources = []
        root.displayAudioStreams = []
    }

    function sectionCount(section) {
        if (section === "output") return root.displayAudioSinks.length
        if (section === "input") return root.displayAudioSources.length
        if (section === "streams") return root.displayAudioStreams.length
        return 0
    }

    function sectionHasSlider(section) {
        if (section === "output") return true
        if (section === "input") return root.hasInput
        return false
    }

    function sectionVisible(section) {
        if (section === "output") return true
        if (section === "input") return root.displayAudioSources.length > 0 || root.hasInput
        if (section === "streams") return root.displayAudioStreams.length > 0
        return false
    }

    readonly property var visibleSections: {
        var sections = []
        if (root.sectionVisible("output")) sections.push("output")
        if (root.sectionVisible("input")) sections.push("input")
        if (root.sectionVisible("streams")) sections.push("streams")
        return sections
    }

    function moveCursor(delta) {
        var sections = root.visibleSections
        if (sections.length === 0) return
        if (root.focusSection === "header") {
            if (delta > 0) {
                root.focusSection = sections[0]
                root.selectedIndex = root.sectionHasSlider(sections[0]) ? -1 : 0
            }
            return
        }

        var sectionIndex = sections.indexOf(root.focusSection)
        if (sectionIndex < 0) {
            root.focusSection = sections[0]
            root.selectedIndex = root.sectionHasSlider(root.focusSection) ? -1 : 0
            return
        }

        var floor = root.sectionHasSlider(root.focusSection) ? -1 : 0
        var max = root.sectionCount(root.focusSection) - 1
        if (delta > 0) {
            if (root.selectedIndex < max) {
                root.selectedIndex++
                return
            }
            if (sectionIndex < sections.length - 1) {
                root.focusSection = sections[sectionIndex + 1]
                root.selectedIndex = root.sectionHasSlider(root.focusSection) ? -1 : 0
            }
        } else {
            if (root.selectedIndex > floor) {
                root.selectedIndex--
                return
            }
            if (sectionIndex > 0) {
                root.focusSection = sections[sectionIndex - 1]
                var previousMax = root.sectionCount(root.focusSection) - 1
                root.selectedIndex = previousMax >= 0
                    ? previousMax : (root.sectionHasSlider(root.focusSection) ? -1 : 0)
            } else {
                root.focusSection = "header"
                root.selectedIndex = -1
            }
        }
    }

    function moveSection(delta) {
        var sections = root.visibleSections
        if (sections.length === 0) return
        var index = sections.indexOf(root.focusSection)
        if (index < 0) index = delta > 0 ? -1 : 0
        var next = (index + delta + sections.length) % sections.length
        root.focusSection = sections[next]
        root.selectedIndex = root.sectionHasSlider(root.focusSection) ? -1 : 0
        root.cursorActive = true
    }

    function adjustVolume(delta) {
        if (root.focusSection === "output" && root.selectedIndex === -1) {
            root.setOutputVolume(root.outputVolume + delta)
            return
        }
        if (root.focusSection === "input" && root.selectedIndex === -1) {
            root.setInputVolume(root.inputVolume + delta)
            return
        }
        if (root.focusSection === "streams" && root.selectedIndex >= 0 &&
            root.selectedIndex < root.displayAudioStreams.length) {
            var stream = root.displayAudioStreams[root.selectedIndex]
            if (stream && stream.audio)
                stream.audio.volume = Model.steppedVolume(stream.audio.volume, delta, 1.5)
        }
    }

    function setOutputVolume(value) {
        if (!root.sink || !root.sink.audio) return root.outputVolume
        var bounded = Model.clampVolume(value, 1)
        root.sink.audio.volume = bounded
        return bounded
    }

    function setInputVolume(value) {
        if (!root.source || !root.source.audio) return root.inputVolume
        var bounded = Model.clampVolume(value, 1)
        root.source.audio.volume = bounded
        return bounded
    }

    function toggleOutputMute() {
        if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
    }

    function toggleInputMute() {
        if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
    }

    function toggleAllMuted() {
        var mute = root.anyAudible
        if (root.hasOutput) root.sink.audio.muted = mute
        if (root.hasInput) root.source.audio.muted = mute
    }

    function setDefaultSink(node) {
        if (!node) return
        Pipewire.preferredDefaultAudioSink = node
    }

    function setDefaultSource(node) {
        if (!node) return
        Pipewire.preferredDefaultAudioSource = node
    }

    function deviceAt(section, index) {
        var list = section === "output" ? root.displayAudioSinks
            : (section === "input" ? root.displayAudioSources : root.displayAudioStreams)
        return index >= 0 && index < list.length ? list[index] : null
    }

    function clampCursor() {
        if (root.focusSection === "header") return
        var sections = root.visibleSections
        if (sections.length === 0) {
            root.focusSection = "header"
            root.selectedIndex = -1
            return
        }
        if (sections.indexOf(root.focusSection) < 0) {
            root.focusSection = sections[0]
            root.selectedIndex = root.sectionHasSlider(root.focusSection) ? -1 : 0
            return
        }
        var floor = root.sectionHasSlider(root.focusSection) ? -1 : 0
        var count = root.sectionCount(root.focusSection)
        root.selectedIndex = Math.max(floor, Math.min(count - 1, root.selectedIndex))
    }

    function resetScroll() {
        if (scrollArea && scrollArea.contentItem && scrollArea.contentItem.contentY !== undefined)
            scrollArea.contentItem.contentY = 0
    }

    function ensureCursorVisible(item) {
        if (!item || !scrollArea || !scrollArea.contentItem) return
        var flick = scrollArea.contentItem
        if (flick.contentY === undefined || typeof item.mapToItem !== "function") return
        var point = item.mapToItem(flick, 0, 0)
        var maxY = Math.max(0, Number(flick.contentHeight || 0) - Number(flick.height || 0))
        if (point.y < flick.contentY) flick.contentY = Math.max(0, point.y - Theme.spacingSm)
        else if (point.y + item.height > flick.contentY + flick.height)
            flick.contentY = Math.min(maxY, point.y + item.height - flick.height + Theme.spacingSm)
    }

    function activateCursor() {
        if (root.focusSection === "header") {
            root.toggleAllMuted()
            return
        }
        if (root.focusSection === "output") {
            if (root.selectedIndex === -1) root.toggleOutputMute()
            else root.setDefaultSink(root.displayAudioSinks[root.selectedIndex])
            return
        }
        if (root.focusSection === "input") {
            if (root.selectedIndex === -1) root.toggleInputMute()
            else root.setDefaultSource(root.displayAudioSources[root.selectedIndex])
            return
        }
        var stream = root.displayAudioStreams[root.selectedIndex]
        if (stream && stream.audio) stream.audio.muted = !stream.audio.muted
    }

    function handleKey(event) {
        var key = event.key
        var text = String(event.text || "").toLowerCase()
        if (key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
            return
        }
        if (key === Qt.Key_Tab) {
            root.moveSection(event.modifiers & Qt.ShiftModifier ? -1 : 1)
            event.accepted = true
            return
        }
        if (text === "m") {
            if (root.focusSection === "input") root.toggleInputMute()
            else if (root.focusSection === "streams") root.activateCursor()
            else root.toggleOutputMute()
            event.accepted = true
            return
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            if (root.cursorActive) root.activateCursor()
            event.accepted = true
            return
        }
        if (key === Qt.Key_Up || key === Qt.Key_K) root.moveCursor(-1)
        else if (key === Qt.Key_Down || key === Qt.Key_J) root.moveCursor(1)
        else if (key === Qt.Key_Left || key === Qt.Key_H) root.adjustVolume(-0.05)
        else if (key === Qt.Key_Right || key === Qt.Key_L) root.adjustVolume(0.05)
        else return
        root.cursorActive = true
        event.accepted = true
    }

    onShownChanged: {
        if (root.shown) {
            root.refreshDisplayAudioModels()
            root.focusSection = "output"
            root.selectedIndex = -1
            root.cursorActive = false
            Qt.callLater(root.resetScroll)
        } else {
            root.clearDisplayAudioModels()
        }
    }
    onRawAudioSinksChanged: {
        if (root.rawAudioSinks.length > 0) root.cachedAudioSinks = root.rawAudioSinks
        root.scheduleDisplayAudioModelRefresh()
    }
    onRawAudioSourcesChanged: {
        if (root.rawAudioSources.length > 0) root.cachedAudioSources = root.rawAudioSources
        root.scheduleDisplayAudioModelRefresh()
    }
    onCandidateStreamsChanged: root.scheduleDisplayAudioModelRefresh()
    onDisplayAudioSinksChanged: root.clampCursor()
    onDisplayAudioSourcesChanged: root.clampCursor()
    onDisplayAudioStreamsChanged: root.clampCursor()
    onVisibleSectionsChanged: root.clampCursor()

    Item {
        width: 0
        height: 0
        visible: false

        PwObjectTracker { objects: root.candidateSinks }
        PwObjectTracker { objects: root.candidateSources }
        PwObjectTracker { objects: root.candidateStreams }

        Timer {
            id: audioModelRefreshTimer
            interval: 75
            repeat: false
            onTriggered: root.refreshDisplayAudioModels()
        }
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: root.shown
        Keys.onPressed: function(event) { root.handleKey(event) }

        ScrollView {
            id: scrollArea
            anchors.fill: parent
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: panelColumn.implicitHeight > height
                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

            Column {
                id: panelColumn
                width: scrollArea.availableWidth
                spacing: Theme.spacingLg

                Item {
                    width: parent.width
                    implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, masterMute.implicitHeight)

                    AureliaIcon {
                        id: heroIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        iconSize: 34
                        glyph: root.outputMuted ? "󰝟" : Model.sinkGlyph(root.sink)
                        tint: Theme.text
                    }

                    Column {
                        id: heroLabels
                        anchors.left: heroIcon.right
                        anchors.leftMargin: Theme.spacingSm
                        anchors.right: masterMute.left
                        anchors.rightMargin: Theme.spacingSm
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            text: "Audio"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.weight: Theme.fontWeightBold
                        }
                        Text {
                            text: Model.outputVolumeName(root.outputVolume, root.outputMuted).toUpperCase()
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 0.8
                        }
                    }

                    Rectangle {
                        id: masterMute
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        radius: height / 2
                        color: root.anyAudible ? Theme.accent : Theme.surface
                        border.color: root.focusSection === "header" && root.cursorActive
                            ? Theme.borderActive : Theme.border
                        border.width: root.focusSection === "header" && root.cursorActive
                            ? Theme.borderWidthFocus : Theme.borderWidthDefault

                        Rectangle {
                            width: 18
                            height: 18
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.anyAudible ? parent.width - width - 3 : 3
                            color: root.anyAudible ? Theme.bgBase : Theme.textMuted
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.toggleAllMuted()
                            onEntered: {
                                root.cursorActive = true
                                root.focusSection = "header"
                                root.selectedIndex = -1
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.65 }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXs

                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: "OUTPUT"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 1
                        }
                        Text {
                            text: Math.round(root.outputVolume * 100) + "%"
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                        }
                    }

                    Rectangle {
                        id: outputSliderRow
                        width: parent.width
                        height: 38
                        radius: Theme.radiusSm
                        color: root.cursorActive && root.focusSection === "output" && root.selectedIndex === -1
                            ? Theme.selectionActive : Theme.surface
                        border.color: root.cursorActive && root.focusSection === "output" && root.selectedIndex === -1
                            ? Theme.borderActive : Theme.border
                        border.width: Theme.borderWidthDefault

                        Slider {
                            id: outputSlider
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSm
                            anchors.rightMargin: Theme.spacingSm
                            from: 0
                            to: 1
                            stepSize: 0.05
                            value: root.outputVolume
                            enabled: root.hasOutput
                            opacity: root.outputMuted ? 0.5 : 1.0
                            onMoved: root.setOutputVolume(value)
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: root.toggleOutputMute()
                            onEntered: {
                                root.cursorActive = true
                                root.focusSection = "output"
                                root.selectedIndex = -1
                            }
                        }
                    }

                    Repeater {
                        model: root.displayAudioSinks
                        delegate: SinkRow {
                            required property var modelData
                            required property int index
                            node: modelData
                            rowIndex: index
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXs
                    visible: root.sectionVisible("input")

                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: "INPUT"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 1
                        }
                        Text {
                            text: Math.round(root.inputVolume * 100) + "%"
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 38
                        radius: Theme.radiusSm
                        color: root.cursorActive && root.focusSection === "input" && root.selectedIndex === -1
                            ? Theme.selectionActive : Theme.surface
                        border.color: root.cursorActive && root.focusSection === "input" && root.selectedIndex === -1
                            ? Theme.borderActive : Theme.border
                        border.width: Theme.borderWidthDefault

                        Slider {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSm
                            anchors.rightMargin: Theme.spacingSm
                            from: 0
                            to: 1
                            stepSize: 0.05
                            value: root.inputVolume
                            enabled: root.hasInput
                            opacity: root.inputMuted ? 0.5 : 1.0
                            onMoved: root.setInputVolume(value)
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: root.toggleInputMute()
                            onEntered: {
                                root.cursorActive = true
                                root.focusSection = "input"
                                root.selectedIndex = -1
                            }
                        }
                    }

                    Repeater {
                        model: root.displayAudioSources
                        delegate: SourceRow {
                            required property var modelData
                            required property int index
                            node: modelData
                            rowIndex: index
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXs
                    visible: root.sectionVisible("streams")

                    Text {
                        width: parent.width
                        text: "SOURCES"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                        font.letterSpacing: 1
                    }

                    Repeater {
                        model: root.displayAudioStreams
                        delegate: StreamRow {
                            required property var modelData
                            required property int index
                            node: modelData
                            rowIndex: index
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: !root.hasOutput && !root.hasInput && root.displayAudioStreams.length === 0
                    text: "No audio devices available"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    component SinkRow: Rectangle {
        id: sinkRow
        required property var node
        required property int rowIndex
        width: parent ? parent.width : 0
        height: 42
        radius: Theme.radiusSm
        color: root.cursorActive && root.focusSection === "output" && root.selectedIndex === rowIndex
            ? Theme.selectionActive : (sinkHover.hovered ? Theme.selectionHover : Theme.surface)
        border.color: root.sink && node && root.sink.id === node.id ? Theme.borderActive : Theme.border
        border.width: Theme.borderWidthDefault

        HoverHandler {
            id: sinkHover
            onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "output"
                root.selectedIndex = sinkRow.rowIndex
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingSm
            anchors.rightMargin: Theme.spacingSm
            spacing: Theme.spacingSm

            AureliaIcon {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                iconSize: 20
                glyph: Model.sinkGlyph(sinkRow.node)
                tint: Theme.text
            }
            Text {
                Layout.fillWidth: true
                text: Model.nodeLabel(sinkRow.node)
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: root.sink && sinkRow.node && root.sink.id === sinkRow.node.id
                    ? Theme.fontWeightMedium : Font.Normal
                elide: Text.ElideRight
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setDefaultSink(sinkRow.node)
        }
    }

    component SourceRow: Rectangle {
        id: sourceRow
        required property var node
        required property int rowIndex
        width: parent ? parent.width : 0
        height: 42
        radius: Theme.radiusSm
        color: root.cursorActive && root.focusSection === "input" && root.selectedIndex === rowIndex
            ? Theme.selectionActive : (sourceHover.hovered ? Theme.selectionHover : Theme.surface)
        border.color: root.source && node && root.source.id === node.id ? Theme.borderActive : Theme.border
        border.width: Theme.borderWidthDefault

        HoverHandler {
            id: sourceHover
            onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "input"
                root.selectedIndex = sourceRow.rowIndex
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingSm
            anchors.rightMargin: Theme.spacingSm
            spacing: Theme.spacingSm

            AureliaIcon {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                iconSize: 20
                glyph: Model.sourceGlyph(sourceRow.node)
                tint: Theme.text
            }
            Text {
                Layout.fillWidth: true
                text: Model.nodeLabel(sourceRow.node)
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: root.source && sourceRow.node && root.source.id === sourceRow.node.id
                    ? Theme.fontWeightMedium : Font.Normal
                elide: Text.ElideRight
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setDefaultSource(sourceRow.node)
        }
    }

    component StreamRow: Rectangle {
        id: streamRow
        required property var node
        required property int rowIndex
        readonly property real streamVolume: node && node.audio ? Number(node.audio.volume || 0) : 0
        readonly property bool streamMuted: !!(node && node.audio && node.audio.muted)
        width: parent ? parent.width : 0
        height: 62
        radius: Theme.radiusSm
        color: root.cursorActive && root.focusSection === "streams" && root.selectedIndex === rowIndex
            ? Theme.selectionActive : (streamHover.hovered ? Theme.selectionHover : Theme.surface)
        border.color: Theme.border
        border.width: Theme.borderWidthDefault

        HoverHandler {
            id: streamHover
            onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "streams"
                root.selectedIndex = streamRow.rowIndex
            }
        }

        RowLayout {
            id: streamHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 30
            anchors.leftMargin: Theme.spacingSm
            anchors.rightMargin: Theme.spacingSm
            spacing: Theme.spacingSm

            AureliaIcon {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                iconSize: 20
                glyph: streamRow.streamMuted ? "󰝟" : "󰕾"
                tint: streamRow.streamMuted ? Theme.textMuted : Theme.text
            }
            Text {
                Layout.fillWidth: true
                text: Model.streamLabel(streamRow.node, root.mprisPlayers, root.displayAudioStreams)
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideRight
            }
            Text {
                text: Math.round(streamRow.streamVolume * 100) + "%"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
        }

        Slider {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Theme.spacingSm
            anchors.rightMargin: Theme.spacingSm
            anchors.bottomMargin: Theme.spacingXs
            from: 0
            to: 1.5
            stepSize: 0.05
            value: streamRow.streamVolume
            enabled: !!(streamRow.node && streamRow.node.audio)
            opacity: streamRow.streamMuted ? 0.5 : 1.0
            onMoved: if (streamRow.node && streamRow.node.audio)
                streamRow.node.audio.volume = Model.clampVolume(value, 1.5)
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: if (streamRow.node && streamRow.node.audio)
                streamRow.node.audio.muted = !streamRow.node.audio.muted
        }
    }
}
