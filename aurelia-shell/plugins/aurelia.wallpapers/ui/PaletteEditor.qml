import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../../ui"
import "../../../theme"
import "../../../services/SourceUrl.js" as SourceUrl
import "PalettePreview.js" as PalettePreview

// Full-screen palette editor for one local wallpaper. The editor renders a
// live palette preview through `aurelia-wallpaper theme preview` and commits
// through `theme apply` / `apply`. It never touches wallpaper or theme state
// itself, and it performs no network access.
Item {
    id: editor

    property string aureliaPath: ""
    property string imagePath: ""
    property bool opened: false

    signal closed()
    signal applied()

    readonly property string wallpaperBin: aureliaPath !== ""
        ? aureliaPath + "/bin/aurelia-wallpaper"
        : "/usr/local/bin/aurelia-wallpaper"
    readonly property var targetScreen: Quickshell.screens.length > 0
        ? Quickshell.screens[0] : null

    property string mode: "normal"
    property string themeMode: "" // "", "light", "dark"
    property var adjustments: editor.defaultAdjustments()
    property var colors: ({})
    property bool loading: false
    property bool applying: false
    property bool previewPending: false
    property string errorMessage: ""
    property int requestSerial: 0

    readonly property var modeOptions: [
        ["normal", "Normal"], ["monochromatic", "Mono"], ["analogous", "Analogous"],
        ["pastel", "Pastel"], ["material", "Material"], ["colorful", "Colorful"],
        ["muted", "Muted"], ["bright", "Bright"]
    ]
    readonly property var swatchRoles: [
        "background", "foreground", "accent", "selection", "muted",
        "red", "yellow", "green", "cyan", "blue", "magenta",
        "bright_red", "bright_yellow", "bright_green",
        "bright_cyan", "bright_blue", "bright_magenta"
    ]

    function defaultAdjustments() {
        return ({
            "vibrance": 0, "saturation": 0, "contrast": 0, "brightness": 0,
            "shadows": 0, "highlights": 0, "gamma": 1, "black-point": 0,
            "white-point": 0, "hue-shift": 0, "temperature": 0, "tint": 0
        })
    }

    function fileUrl(value) {
        return SourceUrl.fileUrl(value)
    }

    function adjustmentValue(key) {
        var value = editor.adjustments[key]
        return value === undefined ? 0 : value
    }

    function setAdjustment(key, value) {
        var next = {}
        for (var existing in editor.adjustments) next[existing] = editor.adjustments[existing]
        next[key] = value
        editor.adjustments = next
        previewDebounce.restart()
    }

    function resetAdjustments() {
        editor.adjustments = editor.defaultAdjustments()
        editor.themeMode = ""
        editor.mode = "normal"
        previewDebounce.restart()
    }

    function recipeArgs() {
        var keys = ["vibrance", "saturation", "contrast", "brightness", "shadows",
            "highlights", "gamma", "black-point", "white-point", "hue-shift",
            "temperature", "tint"]
        var args = ["--mode", editor.mode]
        if (editor.themeMode === "light") args.push("--light")
        else if (editor.themeMode === "dark") args.push("--dark")
        for (var i = 0; i < keys.length; i++) {
            args.push("--" + keys[i])
            args.push(String(editor.adjustmentValue(keys[i])))
        }
        return args
    }

    function close() {
        if (editor.applying) return
        editor.opened = false
        editor.closed()
    }

    function requestPreview() {
        if (!editor.opened || editor.imagePath === "") return
        var action = PalettePreview.requestAction(previewProcess.running, editor.applying)
        if (action === "ignore") return
        // Never interrupt a preview already in flight: the SIGTERM exit raced
        // the serial guard and surfaced a spurious "Color extraction failed"
        // error. The newest request is serialized behind the running one.
        if (action === "defer") {
            editor.previewPending = true
            return
        }
        editor.requestSerial++
        editor.loading = true
        editor.errorMessage = ""
        previewProcess.serial = editor.requestSerial
        previewProcess.command = [editor.wallpaperBin, "theme", "preview", editor.imagePath]
            .concat(editor.recipeArgs()).concat(["--json"])
        previewProcess.running = true
    }

    function applyTheme() {
        if (editor.applying || editor.imagePath === "") return
        editor.applying = true
        editor.errorMessage = ""
        applyProcess.command = [editor.wallpaperBin, "theme", "apply", editor.imagePath]
            .concat(editor.recipeArgs())
        applyProcess.running = true
    }

    function applyWallpaperOnly() {
        if (editor.applying || editor.imagePath === "") return
        editor.applying = true
        editor.errorMessage = ""
        applyProcess.command = [editor.wallpaperBin, "apply", editor.imagePath]
        applyProcess.running = true
    }

    onOpenedChanged: {
        if (editor.opened) {
            editor.resetAdjustments()
        } else {
            editor.colors = ({})
            editor.errorMessage = ""
            editor.previewPending = false
            editor.applying = false
        }
    }

    onImagePathChanged: {
        if (editor.opened) {
            editor.resetAdjustments()
        }
    }

    Component.onCompleted: {
        if (editor.opened) {
            editor.resetAdjustments()
        }
    }

    Timer {
        id: previewDebounce
        interval: 250
        repeat: false
        onTriggered: editor.requestPreview()
    }

    Process {
        id: previewProcess
        property int serial: 0
        command: []
        stdout: StdioCollector { id: previewOutput }
        stderr: StdioCollector { id: previewError }

        onExited: function(code) {
            if (serial !== editor.requestSerial) return
            editor.loading = false
            editor.errorMessage = PalettePreview.previewError(code, previewError.text)
            if (code !== 0) {
                editor.colors = ({})
            } else {
                try {
                    var parsed = JSON.parse(String(previewOutput.text || "{}"))
                    editor.colors = parsed.colors || ({})
                } catch (error) {
                    editor.colors = ({})
                    editor.errorMessage = "Color extraction returned invalid data."
                }
            }
            if (PalettePreview.shouldReplay(editor.previewPending)) {
                editor.previewPending = false
                editor.requestPreview()
            }
        }
    }

    Process {
        id: applyProcess
        command: []
        stdout: StdioCollector { id: applyOutput }
        stderr: StdioCollector { id: applyError }

        onExited: function(code) {
            editor.applying = false
            if (code !== 0) {
                editor.errorMessage = String(applyError.text || "").trim() ||
                    "Applying the palette failed."
                return
            }
            editor.opened = false
            editor.applied()
        }
    }

    ListModel {
        id: sliderModel
        ListElement { key: "vibrance"; label: "Vibrance"; minV: -50; maxV: 50; stepV: 1 }
        ListElement { key: "saturation"; label: "Saturation"; minV: -100; maxV: 100; stepV: 1 }
        ListElement { key: "contrast"; label: "Contrast"; minV: -30; maxV: 30; stepV: 1 }
        ListElement { key: "brightness"; label: "Brightness"; minV: -30; maxV: 30; stepV: 1 }
        ListElement { key: "shadows"; label: "Shadows"; minV: -50; maxV: 50; stepV: 1 }
        ListElement { key: "highlights"; label: "Highlights"; minV: -50; maxV: 50; stepV: 1 }
        ListElement { key: "gamma"; label: "Gamma"; minV: 0.5; maxV: 2.0; stepV: 0.05 }
        ListElement { key: "black-point"; label: "Black point"; minV: -30; maxV: 30; stepV: 1 }
        ListElement { key: "white-point"; label: "White point"; minV: -30; maxV: 30; stepV: 1 }
        ListElement { key: "hue-shift"; label: "Hue shift"; minV: -180; maxV: 180; stepV: 1 }
        ListElement { key: "temperature"; label: "Temperature"; minV: -50; maxV: 50; stepV: 1 }
        ListElement { key: "tint"; label: "Tint"; minV: -50; maxV: 50; stepV: 1 }
    }

    PanelWindow {
        id: editorWindow

        screen: editor.targetScreen
        visible: editor.opened && editor.targetScreen !== null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "aurelia-wallpaper-editor"
        WlrLayershell.keyboardFocus: editor.opened
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.OnDemand

        Rectangle {
            anchors.fill: parent
            color: Theme.imagePicker.scrim
        }

        FocusScope {
            id: editorFocus
            anchors.centerIn: parent
            focus: editor.opened
            Keys.priority: Keys.BeforeItem
            width: Math.min(Math.max(900, parent.width - Theme.spacingXxl * 2), 1500)
            height: Math.min(Math.max(600, parent.height - Theme.spacingXxl * 2), 900)

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    editor.close()
                    event.accepted = true
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusLg
                color: Theme.bgBase
                border.color: Theme.border
                border.width: Theme.borderWidthDefault
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingMd
                spacing: Theme.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm

                    Text {
                        text: "Palette editor"
                        color: Theme.text
                        font.family: Theme.fontFamilyResolved
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Theme.fontWeightBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: editor.imagePath
                        color: Theme.textMuted
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeXs
                        elide: Text.ElideMiddle
                    }

                    Repeater {
                        model: [["", "Auto"], ["light", "Light"], ["dark", "Dark"]]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: editor.themeMode === modelData[0]
                            width: 56
                            height: 26
                            radius: Theme.radiusSm
                            color: active
                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                : Theme.controls.normalFill
                            border.color: active ? Theme.accent : Theme.controls.normalBorder
                            border.width: active ? Theme.borderWidthFocus : Theme.borderWidthDefault
                            Text {
                                anchors.centerIn: parent
                                text: modelData[1]
                                color: active ? Theme.accent : Theme.textSecondary
                                font.family: Theme.fontFamilyResolved
                                font.pixelSize: Theme.fontSizeXs
                                font.weight: Theme.fontWeightMedium
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: !editor.applying
                                onClicked: {
                                    editor.themeMode = modelData[0]
                                    previewDebounce.restart()
                                }
                            }
                        }
                    }

                    AureliaActionButton {
                        compact: true
                        label: "Close"
                        enabled: !editor.applying
                        onTriggered: editor.close()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.spacingMd

                    ColumnLayout {
                        Layout.preferredWidth: Math.max(320, Math.round(editorWindow.width * 0.40))
                        Layout.fillHeight: true
                        spacing: Theme.spacingSm

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusMd
                            color: Theme.controls.normalFill
                            border.color: Theme.controls.normalBorder
                            border.width: Theme.borderWidthDefault
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingXs
                                source: editor.fileUrl(editor.imagePath)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                smooth: true
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs

                            Repeater {
                                model: editor.swatchRoles
                                delegate: Rectangle {
                                    required property string modelData
                                    width: 28
                                    height: 28
                                    radius: Theme.radiusSm
                                    color: String(editor.colors[modelData] || "")
                                    border.color: Theme.border
                                    border.width: Theme.borderWidthDefault
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: editor.errorMessage !== ""
                                ? editor.errorMessage
                                : (editor.loading
                                    ? "Extracting colors…"
                                    : (editor.colors.extraction_mode
                                        ? ("Mode: " + editor.colors.extraction_mode +
                                            "  •  " + String(editor.colors.mode || ""))
                                        : "Adjust the palette to preview it here."))
                            color: editor.errorMessage !== "" ? Theme.error : Theme.textSecondary
                            font.family: Theme.fontFamilyProse
                            font.pixelSize: Theme.fontSizeSm
                            elide: Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Theme.spacingSm

                        Text {
                            text: "Extraction mode"
                            color: Theme.text
                            font.family: Theme.fontFamilyResolved
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightBold
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs

                            Repeater {
                                model: editor.modeOptions
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool active: editor.mode === modelData[0]
                                    width: modeLabel.width + Theme.spacingMd * 2
                                    height: 26
                                    radius: Theme.radiusSm
                                    color: active
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                        : Theme.controls.normalFill
                                    border.color: active ? Theme.accent : Theme.controls.normalBorder
                                    border.width: active ? Theme.borderWidthFocus : Theme.borderWidthDefault
                                    Text {
                                        id: modeLabel
                                        anchors.centerIn: parent
                                        text: modelData[1]
                                        color: active ? Theme.accent : Theme.textSecondary
                                        font.family: Theme.fontFamilyResolved
                                        font.pixelSize: Theme.fontSizeXs
                                        font.weight: active ? Theme.fontWeightBold : Theme.fontWeightMedium
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !editor.applying
                                        onClicked: {
                                            editor.mode = modelData[0]
                                            previewDebounce.restart()
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            text: "Fine-tuning"
                            color: Theme.text
                            font.family: Theme.fontFamilyResolved
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightBold
                        }

                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: width
                            contentHeight: sliderColumn.implicitHeight

                            ColumnLayout {
                                id: sliderColumn
                                width: parent.width
                                spacing: Theme.spacingXs

                                Repeater {
                                    model: sliderModel
                                    delegate: ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                Layout.fillWidth: true
                                                text: model.label
                                                color: Theme.text
                                                font.family: Theme.fontFamilyResolved
                                                font.pixelSize: Theme.fontSizeXs
                                            }
                                            Text {
                                                text: model.stepV < 1
                                                    ? Number(editor.adjustmentValue(model.key)).toFixed(2)
                                                    : String(Math.round(editor.adjustmentValue(model.key)))
                                                color: Theme.textMuted
                                                font.family: Theme.fontFamilyProse
                                                font.pixelSize: Theme.fontSizeXs
                                            }
                                        }

                                        Slider {
                                            Layout.fillWidth: true
                                            from: model.minV
                                            to: model.maxV
                                            stepSize: model.stepV
                                            value: editor.adjustmentValue(model.key)
                                            enabled: !editor.applying
                                            onMoved: editor.setAdjustment(model.key, value)
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm

                            AureliaActionButton {
                                Layout.fillWidth: true
                                compact: true
                                centerLabel: true
                                label: "Reset"
                                enabled: !editor.applying
                                onTriggered: editor.resetAdjustments()
                            }
                            AureliaActionButton {
                                Layout.fillWidth: true
                                compact: true
                                centerLabel: true
                                label: "Set wallpaper only"
                                enabled: !editor.applying && editor.imagePath !== ""
                                onTriggered: editor.applyWallpaperOnly()
                            }
                            AureliaActionButton {
                                Layout.fillWidth: true
                                compact: true
                                centerLabel: true
                                primary: true
                                label: editor.applying ? "Applying…" : "Apply theme"
                                enabled: !editor.applying && editor.imagePath !== ""
                                onTriggered: editor.applyTheme()
                            }
                        }
                    }
                }
            }
        }
    }
}
