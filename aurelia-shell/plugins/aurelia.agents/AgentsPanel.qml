import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../ui"
import "../../theme"
import "AgentUsage.js" as AgentUsage

AureliaKeyboardPanel {
    id: panelRoot

    property var agentsWidget: null

    bar: agentsWidget ? agentsWidget.bar : null
    ownerId: "aurelia.agents"
    popupWidth: 460
    popupHeight: 320
    fitHeightToContent: true
    contentSizingItem: contentColumn
    minPopupHeight: 200
    maxPopupHeight: 640
    shown: false

    readonly property var agents: agentsWidget ? agentsWidget.readyAgents : []

    function open() {
        if (agentsWidget && agentsWidget.ready) shown = true
    }

    function close() {
        shown = false
    }

    function closeForPopoutSwitch() {
        close()
    }

    function dayLabel(date, index) {
        if (index === 6) return "Today"
        var parts = String(date || "").split("-")
        if (parts.length !== 3) return String(date || "")
        var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var parsed = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
        return names[parsed.getDay()]
    }

    ColumnLayout {
        id: contentColumn
        width: panelRoot.popupWidth - panelRoot.contentPadding * 2
        spacing: Theme.spacingSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: "Agents"
                color: Theme.text
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
                Layout.fillWidth: true
            }

            Text {
                text: "Refresh"
                color: refreshArea.containsMouse ? Theme.accent : Theme.textMuted
                font.pixelSize: Theme.fontSizeSm

                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    anchors.margins: -Theme.spacingXs
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (panelRoot.agentsWidget) panelRoot.agentsWidget.refresh()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: panelRoot.agents.length === 0
            wrapMode: Text.WordWrap
            text: "No agent usage recorded yet. Use a supported AI agent, then refresh."
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSm
        }

        Repeater {
            model: panelRoot.agents

            delegate: ColumnLayout {
                id: agentCard
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm

                    Text {
                        text: agentCard.modelData.name || agentCard.modelData.id || "Agent"
                        color: Theme.text
                        font.bold: true
                        font.pixelSize: Theme.fontSizeMd
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: text !== ""
                        text: AgentUsage.tierLabel(agentCard.modelData)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeSm
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: AgentUsage.formatTokens(agentCard.modelData.todayTotalTokens) +
                        " tokens today · " + (agentCard.modelData.todayPrompts || 0) + " prompts"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSm
                }

                Row {
                    spacing: Theme.spacingXs

                    Repeater {
                        model: AgentUsage.recentBars(agentCard.modelData.recentDays)

                        delegate: Item {
                            id: dayBar
                            required property var modelData
                            width: 28
                            height: 46

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.max(2, parent.height * dayBar.modelData.fraction)
                                radius: Theme.radiusSm
                                color: Theme.accent
                            }
                        }
                    }
                }

                Repeater {
                    model: AgentUsage.sortedModels(agentCard.modelData.modelUsage).slice(0, 4)

                    delegate: RowLayout {
                        id: modelRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm

                        Text {
                            text: modelRow.modelData.name
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeSm
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: AgentUsage.formatTokens(modelRow.modelData.total)
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingXs
                    height: 1
                    color: Theme.border
                    visible: agentCard.index < panelRoot.agents.length - 1
                }
            }
        }
    }
}
