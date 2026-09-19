import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../ui"
import "../../theme"
import "AgentUsage.js" as AgentUsage

// AI subscription usage panel. Mirrors Omarchy's agents panel information
// architecture: a provider switch, a hero with the plan, live limit meters
// with reset countdowns, a tokens-by-day chart, and a tokens-by-model
// breakdown. Live rate limits come from each collector's own probe.
AureliaKeyboardPanel {
    id: panelRoot

    property var agentsWidget: null
    property int selectedIndex: 0
    property real nowMs: Date.now()

    bar: agentsWidget ? agentsWidget.bar : null
    ownerId: "aurelia.agents"
    popupWidth: 460
    popupHeight: 320
    fitHeightToContent: true
    contentSizingItem: contentColumn
    minPopupHeight: 200
    maxPopupHeight: 720
    shown: false

    readonly property var agents: agentsWidget ? agentsWidget.visibleAgents : []
    readonly property int safeIndex: agents.length > 0
        ? Math.max(0, Math.min(selectedIndex, agents.length - 1)) : 0
    readonly property var provider: agents.length > 0 ? agents[safeIndex] : null
    readonly property var limits: (provider && provider.limits) || []
    readonly property var models: AgentUsage.modelRows(provider, 4)
    readonly property real weekPeak: Math.max(1, AgentUsage.weekPeak(provider))

    function open() {
        if (!agentsWidget || !agentsWidget.hasAgents) return
        shown = true
    }

    function close() {
        shown = false
    }

    function closeForPopoutSwitch() {
        close()
    }

    function selectProvider(index) {
        if (agents.length === 0) return
        selectedIndex = ((index % agents.length) + agents.length) % agents.length
    }

    function refreshNow() {
        if (agentsWidget) agentsWidget.refresh()
    }

    onShownChanged: {
        if (!shown) return
        nowMs = Date.now()
        if (agentsWidget && agentsWidget.maybeRefresh) agentsWidget.maybeRefresh(60000)
    }
    onAgentsChanged: if (selectedIndex >= agents.length) selectedIndex = 0

    Timer {
        interval: 30000
        repeat: true
        running: panelRoot.shown
        onTriggered: panelRoot.nowMs = Date.now()
    }

    // ------------------------------------------------------------ components

    component SectionHeader: Text {
        Layout.fillWidth: true
        color: Theme.textMuted
        font.pixelSize: Theme.fontSizeSm
        font.bold: true
    }

    // Rounded track showing the fraction of an allowance used.
    component Meter: Item {
        id: meter
        property real value: -1
        property bool alarming: false

        Layout.fillWidth: true
        implicitHeight: 6

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.surface
        }

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            radius: height / 2
            width: Math.max(0, parent.width * AgentUsage.clamp(meter.value, 0, 1))
            color: meter.alarming ? Theme.error : Theme.accent

            Behavior on width {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
        }
    }

    // One live rate-limit window: used percentage, meter, remaining and reset.
    component LimitRow: ColumnLayout {
        id: limitRow
        property var window: null

        readonly property real percent: Number(limitRow.window && limitRow.window.percent)
        readonly property bool alarming: isFinite(limitRow.percent) && limitRow.percent >= 0.9
        readonly property real remainingMs: AgentUsage.resetMsFor(limitRow.window, panelRoot.nowMs)

        Layout.fillWidth: true
        spacing: Theme.spacingXs

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: limitRow.window ? String(limitRow.window.label || "Limit") : "Limit"
                color: Theme.text
                font.pixelSize: Theme.fontSizeMd
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                text: isFinite(limitRow.percent) ? Math.round(limitRow.percent * 100) + "% used" : "—"
                color: limitRow.alarming ? Theme.error : Theme.text
                font.pixelSize: Theme.fontSizeSm
            }
        }

        Meter {
            value: limitRow.percent
            alarming: limitRow.alarming
        }

        Text {
            Layout.fillWidth: true
            text: {
                var parts = []
                if (isFinite(limitRow.percent))
                    parts.push(Math.max(0, Math.round((1 - limitRow.percent) * 100)) + "% left")
                if (limitRow.remainingMs > 0)
                    parts.push("Resets in " + AgentUsage.formatDuration(limitRow.remainingMs))
                return parts.join(" · ")
            }
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSm
        }
    }

    // One row per day: label, bar, tokens. Today is picked out in full colour.
    component DayRow: Item {
        id: dayRow
        property var day: null
        property real ratio: 0
        property bool today: false

        Layout.fillWidth: true
        implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Theme.spacingXs

        Text {
            id: dayLabel
            text: AgentUsage.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
            color: dayRow.today ? Theme.text : Theme.textMuted
            font.pixelSize: Theme.fontSizeSm
            font.bold: dayRow.today
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 52
        }

        Rectangle {
            id: dayTrack
            anchors.left: dayLabel.right
            anchors.right: dayValue.left
            anchors.leftMargin: Theme.spacingSm
            anchors.rightMargin: Theme.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: height / 2
            color: Theme.surface

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                radius: parent.radius
                width: parent.width * AgentUsage.clamp(dayRow.ratio, 0, 1)
                color: dayRow.today ? Theme.accent : Theme.textMuted

                Behavior on width {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }
        }

        Text {
            id: dayValue
            text: AgentUsage.formatTokens(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
            color: dayRow.today ? Theme.text : Theme.textMuted
            font.pixelSize: Theme.fontSizeSm
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // One model row: name, share bar scaled to the heaviest model, tokens.
    component ModelRow: ColumnLayout {
        id: modelRow
        property var row: null
        property real share: 0

        Layout.fillWidth: true
        spacing: Theme.spacingXs

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: modelRow.row ? String(modelRow.row.name) : ""
                color: Theme.text
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                text: AgentUsage.formatTokens(modelRow.row ? modelRow.row.total : 0)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSm
            }
        }

        Meter {
            value: modelRow.share
        }
    }

    // ---------------------------------------------------------------- content

    ColumnLayout {
        id: contentColumn
        width: panelRoot.popupWidth - panelRoot.contentPadding * 2
        spacing: Theme.spacingMd

        // Hero: name · plan
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: panelRoot.provider ? String(panelRoot.provider.name || panelRoot.provider.id) : "Agents"
                color: Theme.text
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
                Layout.fillWidth: true
            }

            Text {
                text: AgentUsage.heroMeta(panelRoot.provider)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSm
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
                    onClicked: panelRoot.refreshNow()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: panelRoot.agents.length === 0
            wrapMode: Text.WordWrap
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSm
            horizontalAlignment: Text.AlignHCenter
        }

        // Provider switch
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            visible: panelRoot.agents.length > 1

            Repeater {
                model: panelRoot.agents

                delegate: Rectangle {
                    id: providerPill
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: pillLabel.implicitHeight + Theme.spacingSm
                    radius: Theme.radiusSm
                    color: index === panelRoot.safeIndex ? Theme.accent
                        : (pillArea.containsMouse ? Theme.hoverFill : Theme.surface)

                    Text {
                        id: pillLabel
                        anchors.centerIn: parent
                        text: String(providerPill.modelData.name || providerPill.modelData.id)
                        color: index === panelRoot.safeIndex ? Theme.background : Theme.text
                        font.pixelSize: Theme.fontSizeSm
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: pillArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panelRoot.selectProvider(index)
                    }
                }
            }
        }

        // Status / auth help
        Rectangle {
            Layout.fillWidth: true
            visible: !!panelRoot.provider && String(panelRoot.provider.usageStatusText || "") !== ""
            implicitHeight: statusText.implicitHeight + Theme.spacingMd * 2
            radius: Theme.radiusSm
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            Text {
                id: statusText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingMd
                anchors.rightMargin: Theme.spacingMd
                text: panelRoot.provider
                    ? String(panelRoot.provider.authHelpText || panelRoot.provider.usageStatusText || "")
                    : ""
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSm
                wrapMode: Text.WordWrap
            }
        }

        // Limits
        SectionHeader {
            text: "LIMITS"
            visible: panelRoot.limits.length > 0
        }

        Repeater {
            model: panelRoot.limits

            delegate: LimitRow {
                required property var modelData
                window: modelData
            }
        }

        // Tokens by day
        SectionHeader {
            text: "TOKENS BY DAY"
            visible: !!panelRoot.provider && (panelRoot.provider.recentDays || []).length > 0
        }

        Repeater {
            model: panelRoot.provider ? (panelRoot.provider.recentDays || []) : []

            delegate: DayRow {
                required property var modelData
                day: modelData
                ratio: Number(modelData.messageCount || 0) / panelRoot.weekPeak
                today: String(modelData.date || "") === AgentUsage.todayDate(panelRoot.nowMs)
            }
        }

        // Tokens by model
        SectionHeader {
            text: "TOKENS BY MODEL"
            visible: panelRoot.models.length > 0
        }

        Repeater {
            model: panelRoot.models

            delegate: ModelRow {
                required property var modelData
                row: modelData
                share: modelData.total / Math.max(1, panelRoot.models[0].total)
            }
        }

        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: panelRoot.provider
                ? AgentUsage.formatTokens(panelRoot.provider.todayTotalTokens) + " tokens today · "
                    + (panelRoot.provider.todayPrompts || 0) + " prompts"
                : ""
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSm
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
