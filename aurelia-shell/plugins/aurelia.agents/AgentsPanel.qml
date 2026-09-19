import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../../ui"
import "../../theme"
import "AgentUsage.js" as AgentUsage

// AI subscription usage panel. Mirrors the reference agents panels: a provider
// switch, an all-accounts snapshot, live limit meters with a pace marker and
// reset countdown, a vertical tokens-by-day chart, and a compact
// tokens-by-model breakdown. The body scrolls when it is taller than the card.
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
    contentSizingItem: scroller
    minPopupHeight: 200
    maxPopupHeight: 640
    shown: false

    readonly property var agents: agentsWidget ? agentsWidget.visibleAgents : []
    readonly property int safeIndex: agents.length > 0
        ? Math.max(0, Math.min(selectedIndex, agents.length - 1)) : 0
    readonly property var provider: agents.length > 0 ? agents[safeIndex] : null
    readonly property var limits: (provider && provider.limits) || []
    readonly property var models: AgentUsage.modelRows(provider, 5)
    readonly property real weekPeak: Math.max(1, AgentUsage.weekPeak(provider))
    readonly property real contentWidth: popupWidth - contentPadding * 2
    readonly property real maxBodyHeight: 460

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

    // ------------------------------------------------------------ components

    component SectionHeader: Text {
        Layout.fillWidth: true
        color: Theme.textMuted
        font.pixelSize: Theme.fontSizeSm
        font.bold: true
    }

    // Rounded track showing the fraction of an allowance used. The marker sits
    // at the pace position (where usage would be if the window drained evenly),
    // so a fill past the marker reads as "behind pace" at a glance.
    component Meter: Item {
        id: meter
        property real value: -1
        property real marker: -1
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

        Rectangle {
            visible: meter.marker >= 0
            x: Math.round(parent.width * AgentUsage.clamp(meter.marker, 0, 1)) - width / 2
            width: 2
            height: parent.height + 4
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            opacity: 0.75
        }
    }

    // One live rate-limit window: used percentage, meter, remaining and reset.
    component LimitRow: ColumnLayout {
        id: limitRow
        property var window: null

        readonly property real percent: Number(limitRow.window && limitRow.window.percent)
        readonly property bool alarming: AgentUsage.severityForLimit(limitRow.window) === "critical"
        readonly property real remainingMs: AgentUsage.resetMsFor(limitRow.window, panelRoot.nowMs)
        readonly property var pace: AgentUsage.paceInfo(limitRow.window, panelRoot.nowMs)

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
            marker: limitRow.pace ? limitRow.pace.elapsed : -1
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
                if (limitRow.pace)
                    parts.push(limitRow.pace.behind ? "behind pace" : "ahead of pace")
                return parts.join(" · ")
            }
            color: limitRow.pace && limitRow.pace.behind ? Theme.warning : Theme.textMuted
            font.pixelSize: Theme.fontSizeSm
        }
    }

    // Vertical tokens-by-day columns. Today is picked out in accent.
    component DayChart: Item {
        id: chart
        property var days: []
        property real peak: 1
        property string todayDate: ""

        Layout.fillWidth: true
        implicitHeight: 96

        readonly property real columnWidth: days.length > 0
            ? (width - (days.length - 1) * Theme.spacingXs) / days.length : 0

        Row {
            anchors.fill: parent
            spacing: Theme.spacingXs

            Repeater {
                model: chart.days

                delegate: Column {
                    id: dayColumn
                    required property var modelData
                    required property int index
                    readonly property bool today: String(modelData.date || "") === chart.todayDate
                    readonly property real fraction: AgentUsage.clamp(
                        Number(modelData.messageCount || 0) / Math.max(1, chart.peak), 0, 1)

                    width: chart.columnWidth
                    spacing: 2

                    Item {
                        width: parent.width
                        height: chart.implicitHeight - 16

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.max(3, parent.width * 0.6)
                            height: Math.max(2, parent.height * dayColumn.fraction)
                            radius: 2
                            color: dayColumn.today ? Theme.accent : Theme.textMuted
                            opacity: dayColumn.today ? 1 : 0.7

                            Behavior on height {
                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: AgentUsage.dayLabel(dayColumn.modelData.date, dayColumn.today)
                        color: dayColumn.today ? Theme.text : Theme.textMuted
                        font.pixelSize: Theme.fontSizeSm - 2
                        font.bold: dayColumn.today
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // One model row: name, share bar scaled to the heaviest model, tokens.
    component ModelRow: RowLayout {
        id: modelRow
        property var row: null
        property real share: 0

        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Text {
            Layout.fillWidth: true
            text: modelRow.row ? String(modelRow.row.name) : ""
            color: Theme.text
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideRight
        }

        Meter {
            Layout.fillWidth: false
            Layout.preferredWidth: 84
            value: modelRow.share
        }

        Text {
            text: AgentUsage.formatTokens(modelRow.row ? modelRow.row.total : 0)
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSm
        }
    }

    // ---------------------------------------------------------------- content

    // The body scrolls instead of overflowing the card. `scroller` is the
    // content-sizing item so the card grows with the content up to a cap.
    Flickable {
        id: scroller
        width: panelRoot.contentWidth
        implicitHeight: Math.min(contentColumn.implicitHeight, panelRoot.maxBodyHeight)
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: contentColumn
            width: scroller.width
            spacing: Theme.spacingMd

            Timer {
                interval: 30000
                repeat: true
                running: panelRoot.shown
                onTriggered: panelRoot.nowMs = Date.now()
            }

            // Hero: name · plan · refresh
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

            // Plan · billing line
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: AgentUsage.billingText(panelRoot.provider)
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSm
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

            // All-accounts snapshot: every agent's headline at a glance.
            SectionHeader {
                text: "ALL ACCOUNTS"
                visible: panelRoot.agents.length > 1
            }

            Repeater {
                model: panelRoot.agents

                delegate: Rectangle {
                    id: snapshotRow
                    required property var modelData
                    required property int index
                    readonly property var snapshotLimit: AgentUsage.bindingWindow(snapshotRow.modelData)

                    Layout.fillWidth: true
                    implicitHeight: snapshotLayout.implicitHeight + Theme.spacingSm
                    radius: Theme.radiusSm
                    color: snapshotArea.containsMouse ? Theme.controls.hoverFill
                        : (index === panelRoot.safeIndex ? Theme.controls.selectedFill : "transparent")

                    RowLayout {
                        id: snapshotLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingXs
                        anchors.rightMargin: Theme.spacingXs
                        spacing: Theme.spacingSm

                        Text {
                            Layout.fillWidth: true
                            text: String(snapshotRow.modelData.name || snapshotRow.modelData.id)
                            color: snapshotRow.index === panelRoot.safeIndex ? Theme.accent : Theme.text
                            font.pixelSize: Theme.fontSizeSm
                            elide: Text.ElideRight
                        }

                        Meter {
                            Layout.fillWidth: false
                            Layout.preferredWidth: 84
                            visible: snapshotRow.snapshotLimit !== null
                            value: snapshotRow.snapshotLimit ? Number(snapshotRow.snapshotLimit.percent) : -1
                            marker: snapshotRow.snapshotLimit
                                ? AgentUsage.elapsedFraction(snapshotRow.snapshotLimit, panelRoot.nowMs) : -1
                            alarming: AgentUsage.severityForLimit(snapshotRow.snapshotLimit) === "critical"
                        }

                        Text {
                            text: {
                                if (!snapshotRow.snapshotLimit) {
                                    return AgentUsage.formatTokens(snapshotRow.modelData.todayTotalTokens) + " today"
                                }
                                var percent = Math.round(Number(snapshotRow.snapshotLimit.percent) * 100) + "%"
                                var remaining = AgentUsage.resetMsFor(snapshotRow.snapshotLimit, panelRoot.nowMs)
                                return remaining > 0 ? percent + " · " + AgentUsage.formatDuration(remaining) : percent
                            }
                            color: {
                                var severity = AgentUsage.severityForLimit(snapshotRow.snapshotLimit)
                                if (severity === "critical") return Theme.error
                                if (severity === "warn") return Theme.warning
                                return Theme.textMuted
                            }
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }

                    MouseArea {
                        id: snapshotArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panelRoot.selectProvider(snapshotRow.index)
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

            DayChart {
                visible: !!panelRoot.provider && (panelRoot.provider.recentDays || []).length > 0
                days: panelRoot.provider ? (panelRoot.provider.recentDays || []) : []
                peak: panelRoot.weekPeak
                todayDate: AgentUsage.todayDate(panelRoot.nowMs)
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
}
