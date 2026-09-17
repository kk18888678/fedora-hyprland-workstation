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

    contentItem: Text {
        leftPadding: Theme.spacingMd - 2
        rightPadding: control.indicator.width + Theme.spacingSm
        text: control.currentIndex >= 0 ? String(control.displayText || "") : control.placeholderText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        color: control.currentIndex >= 0 ? Theme.controls.normalColor : Theme.textMuted
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
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
            font.family: Theme.fontFamily
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
        width: control.width - 8
        height: 32

        contentItem: Text {
            text: control.textRole
                ? (Array.isArray(control.model)
                    ? String(modelData[control.textRole])
                    : String(model[control.textRole]))
                : String(modelData)
            font.family: Theme.fontFamily
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
