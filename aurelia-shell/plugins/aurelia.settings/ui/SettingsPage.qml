import QtQuick
import QtQuick.Controls
import "../../../theme"
import "."

// Generic row renderer. Rows are projected by SettingsRows.js from the
// backend schema/status; this component only displays them and forwards
// user intent (changed / action) to the window, which owns all mutation.
//
// A ListView (not a distributing Column+Repeater) renders rows at fixed
// delegate heights, so headings and cards stay compact instead of
// stretching apart.
Item {
    id: pageRoot

    property var rows: []
    property var windowRoot: null

    signal changed(string optionId, var value)
    signal action(string actionId)

    ListView {
        id: list
        anchors.fill: parent
        model: pageRoot.rows
        spacing: Theme.spacingSm
        clip: true
        topMargin: Theme.spacingMd
        bottomMargin: Theme.spacingLg

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        delegate: Item {
            required property var modelData
            width: list.width
            height: modelData.kind === "heading" ? 34 : 64
            clip: true // contain any stretched control within the row

            // Card surface for non-heading rows. clip keeps any stretched
            // control (e.g. full-width slider tracks) inside the rounded card.
            Rectangle {
                anchors.fill: parent
                visible: modelData.kind !== "heading"
                radius: Theme.radiusMd
                color: Theme.surface
                border.width: 1
                border.color: Theme.border
                clip: true
            }

            Loader {
                id: rowLoader
                anchors.fill: parent
                anchors.leftMargin: modelData.kind === "heading" ? Theme.spacingSm : Theme.spacingLg
                anchors.rightMargin: modelData.kind === "heading" ? Theme.spacingSm : Theme.spacingLg
                anchors.topMargin: modelData.kind === "heading" ? 0 : Theme.spacingSm
                anchors.bottomMargin: modelData.kind === "heading" ? 0 : Theme.spacingSm

                sourceComponent: {
                    switch (String(modelData.kind)) {
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
                    item.descriptor = modelData
                    // Pin the loaded row to the Loader's full size. The row
                    // components otherwise rely on parent width hints that
                    // do not propagate reliably through a generic Loader,
                    // leaving content right-shifted with an empty card body.
                    item.width = Qt.binding(function() { return rowLoader.width })
                    item.height = Qt.binding(function() { return rowLoader.height })
                    if (typeof item.changed === "function") {
                        item.changed.connect(function(value) {
                            pageRoot.changed(String(modelData.id || ""), value)
                        })
                    }
                    if (typeof item.action === "function") {
                        item.action.connect(function() {
                            pageRoot.action(String(modelData.actionId || ""))
                        })
                    }
                }
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
