import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../theme"
import "."

// Generic row renderer. Rows are projected by SettingsRows.js from the
// backend schema/status; this component only displays them and forwards
// user intent (changed / action) to the window, which owns all mutation.
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
                    implicitHeight: rowLoader.implicitHeight + (rowData.kind !== "heading" ? 10 : 0)

                    readonly property var rowData: modelData

                    Loader {
                        id: rowLoader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: Theme.spacingSm
                        anchors.rightMargin: Theme.spacingSm

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

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: Theme.spacingSm
                        anchors.rightMargin: Theme.spacingSm
                        height: 1
                        color: Theme.border
                        opacity: 0.3
                        visible: rowData.kind !== "heading"
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
