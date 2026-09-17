import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "."

// Generic row renderer. Rows are projected by SettingsRows.js from the
// backend schema/status; this component only displays them and forwards
// user intent (changed / action) to the window, which owns all mutation.
//
// Layout: headings are section titles; every other row is a rounded card
// (surfaceElevated) so the page reads as a real settings sheet rather than
// a sparse dark slab.
Item {
    id: pageRoot

    property var rows: []
    property var windowRoot: null

    signal changed(string optionId, var value)
    signal action(string actionId)

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: column
            width: parent.width
            spacing: Theme.spacingSm

            Item {
                Layout.preferredHeight: Theme.spacingMd
            }

            Repeater {
                id: repeater
                model: pageRoot.rows

                delegate: Item {
                    id: rowWrap
                    Layout.fillWidth: true
                    // cards get breathing room; headings sit flush
                    implicitHeight: rowLoader.implicitHeight
                                     + (rowData.kind !== "heading" ? 2 * Theme.spacingSm : 0)

                    readonly property var rowData: modelData

                    Rectangle {
                        anchors.fill: parent
                        anchors.bottomMargin: rowData.kind !== "heading" ? Theme.spacingSm : 0
                        radius: Theme.radiusMd
                        color: rowData.kind !== "heading" ? Theme.surfaceElevated : "transparent"
                        border.width: rowData.kind !== "heading" ? 1 : 0
                        border.color: Theme.border
                        opacity: rowData.kind !== "heading" ? 1 : 0
                    }

                    Loader {
                        id: rowLoader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: rowData.kind !== "heading" ? Theme.spacingLg : Theme.spacingSm
                        anchors.rightMargin: rowData.kind !== "heading" ? Theme.spacingLg : Theme.spacingSm
                        anchors.topMargin: rowData.kind !== "heading" ? Theme.spacingSm : 0

                        sourceComponent: {
                            switch (String(rowData.kind)) {
                            case "toggle": return toggleComp
                            case "slider": return sliderComp
                            case "combo": return comboComp
                            case "color": return colorComp
                            case "text": return textComp
                            case "heading": return headingComp
                            case "action": return actionComp
                            case "info":
                            default: return infoComp
                            }
                        }

                        onLoaded: {
                            item.descriptor = rowData
                            if (typeof item.changed === "function") {
                                item.changed.connect(function(value) {
                                    pageRoot.changed(String(rowData.id || ""), value)
                                })
                            }
                            if (typeof item.action === "function") {
                                item.action.connect(function() {
                                    pageRoot.action(String(rowData.actionId || ""))
                                })
                            }
                        }
                    }
                }
            }

            Item {
                Layout.preferredHeight: Theme.spacingLg
            }
        }
    }

    Component {
        id: toggleComp
        SettingToggle {}
    }
    Component {
        id: sliderComp
        SettingSlider {}
    }
    Component {
        id: comboComp
        SettingCombo {}
    }
    Component {
        id: colorComp
        SettingColor {}
    }
    Component {
        id: textComp
        SettingText {}
    }
    Component {
        id: headingComp
        SettingHeading {}
    }
    Component {
        id: infoComp
        SettingInfo {}
    }
    Component {
        id: actionComp
        SettingAction {}
    }
}
