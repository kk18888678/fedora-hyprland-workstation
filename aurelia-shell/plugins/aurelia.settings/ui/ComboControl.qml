import QtQuick
import QtQuick.Controls
import "../../../theme"

// Themed combo box: compact surface fill, accent chevron. The popup inherits
// the control palette, so it stays dark and consistent with the shell.
ComboBox {
    id: control

    property int controlHeight: 34
    // Shown when nothing matches the current value (never display 'undefined').
    property string placeholderText: ""

    

    implicitWidth: 200
    implicitHeight: controlHeight

    // Editable combos use a real text field; read-only combos keep a plain
    // Text so they never steal keyboard focus from popup navigation.
    contentItem: Loader {
        sourceComponent: control.editable ? editableContent : readonlyContent
    }

    Component {
        id: editableContent
        TextField {
            leftPadding: Theme.spacingMd - 2
            rightPadding: control.indicator.width + Theme.spacingSm
            text: String(control.editText || "")
            font.family: Theme.fontFamilyResolved
            font.pixelSize: Theme.fontSizeSm
            color: Theme.controls.normalColor
            verticalAlignment: Text.AlignVCenter
            background: null
            selectByMouse: true
            onTextEdited: control.editText = text
            onAccepted: control.accepted()
        }
    }

    Component {
        id: readonlyContent
        Text {
            leftPadding: Theme.spacingMd - 2
            rightPadding: control.indicator.width + Theme.spacingSm
            text: control.currentIndex >= 0
                ? String(control.displayText || "")
                : String(control.placeholderText || "")
            font.family: Theme.fontFamilyResolved
            font.pixelSize: Theme.fontSizeSm
            // Any shown value is real text; use the normal foreground. The
            // muted tone is reserved for a genuinely empty control (no value,
            // no placeholder), so selected values stay legible under every
            // theme.
            color: (control.currentIndex >= 0 || String(control.placeholderText || "") !== "")
                ? Theme.controls.normalColor
                : Theme.textMuted
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    indicator: Rectangle {
        width: 24
        height: control.implicitHeight
        x: control.width - width
        color: "transparent"

        Text {
            anchors.centerIn: parent
            text: "\u2304"
            color: Theme.accent
            font.family: Theme.fontFamilyResolved
            font.pixelSize: Theme.fontSizeLg
        }
    }

    background: Rectangle {
        implicitWidth: control.implicitWidth
        implicitHeight: control.implicitHeight
        radius: Theme.radiusMd
        color: Theme.surface
        border.width: 1
        border.color: control.visualFocus
            ? Theme.controls.focusBorder
            : (control.hovered ? Theme.controls.hoverBorder : Theme.controls.normalBorder)
    }

    popup: Popup {
        y: control.height + 4
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 280)
        padding: 4

        background: Rectangle {
            radius: Theme.radiusMd
            color: Theme.popups.background
            border.width: Theme.borderWidthDefault
            border.color: Theme.popups.border
        }

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }

    // Themed popup rows (explicit visuals; no palette dependency).
    delegate: ItemDelegate {
        required property int index
        required property var modelData
        width: control.width - 8
        height: 32

        // Robust text lookup: javascript object rows (textRole), string rows,
        // or plain value rows. Never render 'undefined'.
        readonly property string _label: {
            var raw = modelData
            if (control.textRole && typeof raw === "object" && raw !== null && raw !== undefined) {
                return String(raw[control.textRole] ?? "")
            }
            if (raw === null || raw === undefined) return ""
            if (typeof raw === "object") {
                // string-only models surface as objects with the value; fall back
                // to displayText content via currentIndex on activate
                return String(raw.value ?? "")
            }
            return String(raw)
        }

        contentItem: Text {
            text: parent._label
            font.family: Theme.fontFamilyResolved
            font.pixelSize: Theme.fontSizeSm
            color: highlighted ? Theme.bgBase : Theme.text
            verticalAlignment: Text.AlignVCenter
            leftPadding: Theme.spacingSm
        }

        background: Rectangle {
            radius: Theme.radiusSm
            color: highlighted ? Theme.accent : "transparent"
        }
    }
}
