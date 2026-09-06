import QtQuick
import QtQuick.Layouts
import "."
import "../../theme"

// Contextual help is presentation-only. It consumes the same model and
// controller state as the interactive surfaces without owning navigation or
// mutation.
Item {
    id: footerRoot

    required property var modelController
    required property var windowController

    Layout.fillWidth: true
    Layout.preferredHeight: Theme.footerHeight
    Layout.leftMargin: Theme.spacingXl
    Layout.rightMargin: Theme.spacingXl
    Layout.bottomMargin: Theme.spacingSm

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spacingLg

        RowLayout {
            spacing: Theme.spacingSm
            visible: windowController.captureState === "conflict"
            Text { text: "↵"; color: Theme.warning; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Reassign Shortcut"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingSm
            visible: windowController.captureState === "capture_armed" || windowController.captureState === "entering_capture" || windowController.captureState === "validating"
            Text { text: "ESC"; color: Theme.rose; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Cancel"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
            Text { text: "BACKSPACE"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Unset"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingSm
            visible: !windowController.isRecording && modelController.activeView === "add_exec"
            Text { text: "↵"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Add Action"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
            Text { text: "TAB"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Next Field"; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
        }

        RowLayout {
            spacing: Theme.spacingSm
            visible: !windowController.isRecording && modelController.activeView === "add_action_type"
            Text { text: "↵"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Select Type"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingXs
            visible: !windowController.isRecording && modelController.operationState === "idle" && (modelController.activeView === "add_app" || (modelController.selectedItem && modelController.selectedItem.runnable === true))
            Text { text: "↵"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: modelController.activeView === "add_app" ? "Add to Unbound" : "Run"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingXs
            visible: !windowController.isRecording && modelController.operationState === "idle" && (modelController.activeView === "bound" || modelController.activeView === "unbound") && modelController.selectedItem && modelController.selectedItem.editable === true
            Text { text: Theme.shortcutSet; color: Theme.gold; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: modelController.activeView === "unbound" ? "Assign" : "Set"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingXs
            visible: !windowController.isRecording && modelController.operationState === "idle" && modelController.activeView === "bound" && modelController.selectedItem && modelController.selectedItem.editable === true && modelController.selectedItem.display_key && modelController.selectedItem.display_key !== "None (Unbound)"
            Text { text: Theme.shortcutUnset; color: Theme.love; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Unset"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingXs
            visible: !windowController.isRecording && modelController.operationState === "idle" && modelController.activeView.indexOf("add_") !== 0 && modelController.activeView !== "settings"
            Text { text: Theme.shortcutAddAction; color: Theme.foam; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Add Action"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingXs
            visible: !windowController.isRecording && modelController.operationState === "idle" && (modelController.activeView.indexOf("add_") === 0 || modelController.activeView === "settings")
            Text { text: Theme.shortcutBack; color: Theme.foam; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Back"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingSm
            visible: !windowController.isRecording && modelController.activeView === "settings"
            Text { text: "↵ / Space"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Edit / Toggle"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingXs
            visible: !windowController.isRecording && modelController.operationState === "idle" && modelController.activeView !== "settings" && modelController.activeView !== "add_exec"
            Text { text: "TAB"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Header Nav"; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingSm
            visible: !windowController.isRecording && modelController.activeView === "bound" && modelController.selectedItem && (modelController.selectedItem.category === "Mouse Controls" || modelController.selectedItem.mouse === true)
            Text { text: "🖱 Mouse Action"; color: Theme.foam; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Compositor window gesture"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        RowLayout {
            spacing: Theme.spacingSm
            visible: !windowController.isRecording && modelController.activeView === "bound" && modelController.selectedItem && modelController.selectedItem.editable === false && modelController.selectedItem.category !== "Mouse Controls" && !modelController.selectedItem.mouse
            Text { text: "• System Binding"; color: Theme.foam; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: "Compositor managed"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            spacing: Theme.spacingSm
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            Text { text: "ESC"; color: Theme.rose; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
            Text { text: windowController.isRecording ? "Cancel" : ((modelController.activeView.indexOf("add_") === 0 || modelController.activeView === "settings") ? "Back" : "Close"); color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
        }
    }
}
