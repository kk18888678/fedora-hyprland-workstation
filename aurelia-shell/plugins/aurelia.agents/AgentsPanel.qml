import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../../ui"
import "../../theme"
import "AgentUsage.js" as AgentUsage

// AI subscription usage panel. The redesigned surface is ordered top-down:
// HERO (identity, plan, billing, freshness, Refresh) -> PROVIDERS switch (only
// when there is more than one provider) -> STATE BANNER (unknown/error/
// rate-limited only) -> LIMITS (every window, with a pace marker, an absolute
// reset time and an explicit on-pace state) -> USAGE TODAY (billable/cache
// split) -> LAST 7 DAYS (labelled window, numeric value per day) -> MODELS
// (today-first plus an explicit all-time list) -> SUBSCRIPTION (only when the
// user has recorded one). Every text node inherits the bar font through the
// local Label primitive so the panel can never drift to a fallback family.
AureliaKeyboardPanel {
    id: panelRoot

    property var agentsWidget: null
    property int selectedIndex: 0
    property real nowMs: Date.now()
    property string focusSection: "hero"
    property int focusRow: -1
    property bool cursorActive: false
    property var rowItems: ({})
    property var sectionItems: ({})

    bar: agentsWidget ? agentsWidget.bar : null
    ownerId: "aurelia.agents"
    popupWidth: 380
    popupHeight: 320
    fitHeightToContent: true
    contentSizingItem: scroller
    minPopupHeight: 220
    maxPopupHeight: 640
    focusTarget: keyScope
    shown: false

    readonly property var agents: agentsWidget ? agentsWidget.visibleAgents : []
    readonly property int safeIndex: agents.length > 0
        ? Math.max(0, Math.min(selectedIndex, agents.length - 1)) : 0
    readonly property var provider: agents.length > 0 ? agents[safeIndex] : null
    readonly property var limits: (provider && provider.limits) || []
    readonly property var todayModelRows: AgentUsage.todayModels(provider, 4)
    readonly property var allTimeModelRows: AgentUsage.modelRows(provider, 4)
    readonly property var weekBars: AgentUsage.dayChartBars(
        provider ? provider.recentDays : [], 64)
    readonly property var today: AgentUsage.todayUsage(provider)
    readonly property var freshness: AgentUsage.freshnessPill(provider, nowMs, staleMs)
    readonly property bool hasSubscription: !!(provider && provider.subscription)
    readonly property int staleMs: agentsWidget ? agentsWidget.staleMs : 1800000
    readonly property var providerStateInfo: AgentUsage.providerState(provider, nowMs, {
        loading: agentsWidget ? !agentsWidget.loaded : false,
        backendError: agentsWidget ? agentsWidget.lastError : "",
        staleMs: staleMs
    })
    // The body cap is DERIVED from the declared maximum, so the maximum is
    // actually reachable instead of being clamped again by the scroller.
    readonly property real maxBodyHeight: Math.max(0, maxPopupHeight - contentPadding * 2)

    function open(payloadJson) {
        if (!agentsWidget || !agentsWidget.hasAgents) return "not-ready"
        shown = true
        return "ok"
    }

    function close() {
        shown = false
        return "ok"
    }

    function toggle(payloadJson) {
        return shown ? close() : open(payloadJson || "{}")
    }

    function isVisible() { return shown === true }

    function closeForPopoutSwitch() { close() }

    function refreshNow(force) {
        if (agentsWidget) agentsWidget.refresh(force === true)
    }

    function selectProvider(index) {
        if (agents.length === 0) return
        selectedIndex = ((index % agents.length) + agents.length) % agents.length
        if (focusSection === "providers") {
            focusRow = safeIndex
            Qt.callLater(ensureCursorVisible)
        }
    }

    function bannerVisible() {
        var key = providerStateInfo.key
        return key === "unknown" || key === "error" || key === "rate-limited"
    }

    function hasToday() {
        return today.billable + today.cache > 0 || today.count > 0 || today.sessions > 0
    }

    function sectionHasRows(section) {
        if (section === "providers") return agents.length > 1
        if (section === "limits") return limits.length > 0
        if (section === "modelsToday") return todayModelRows.length > 0
        if (section === "modelsAll") return allTimeModelRows.length > 0
        return false
    }

    function sectionRowCount(section) {
        if (section === "providers") return agents.length
        if (section === "limits") return limits.length
        if (section === "modelsToday") return todayModelRows.length
        if (section === "modelsAll") return allTimeModelRows.length
        return 0
    }

    function visibleSections() {
        var sections = []
        if (agents.length > 1) sections.push("providers")
        sections.push("hero")
        if (bannerVisible()) sections.push("banner")
        if (limits.length > 0) sections.push("limits")
        if (hasToday()) sections.push("today")
        if (weekBars.length > 0) sections.push("week")
        if (todayModelRows.length > 0) sections.push("modelsToday")
        if (allTimeModelRows.length > 0) sections.push("modelsAll")
        if (hasSubscription) sections.push("subscription")
        return sections
    }

    function registerRow(section, index, item) {
        if (!rowItems[section]) rowItems[section] = []
        rowItems[section][index] = item
    }

    function registerSection(section, item) {
        sectionItems[section] = item
    }

    function clampFocus() {
        var sections = visibleSections()
        if (sections.length === 0) {
            focusSection = "hero"
            focusRow = -1
            return
        }
        if (sections.indexOf(focusSection) < 0) {
            focusSection = sections[0]
            focusRow = sectionHasRows(focusSection) ? 0 : -1
            return
        }
        if (!sectionHasRows(focusSection)) {
            focusRow = -1
            return
        }
        focusRow = Math.max(0, Math.min(sectionRowCount(focusSection) - 1, focusRow))
    }

    function moveSection(delta) {
        var sections = visibleSections()
        if (sections.length === 0) return
        var index = sections.indexOf(focusSection)
        if (index < 0) index = delta > 0 ? -1 : 0
        var next = (index + delta + sections.length) % sections.length
        focusSection = sections[next]
        focusRow = sectionHasRows(focusSection) ? 0 : -1
        cursorActive = true
        Qt.callLater(ensureCursorVisible)
    }

    function moveCursor(delta) {
        var sections = visibleSections()
        if (sections.length === 0) return
        if (!sectionHasRows(focusSection)) {
            moveSection(delta)
            return
        }
        var count = sectionRowCount(focusSection)
        if (delta > 0) {
            if (focusRow < count - 1) focusRow += 1
            else { moveSection(1); return }
        } else {
            if (focusRow > 0) focusRow -= 1
            else { moveSection(-1); return }
        }
        cursorActive = true
        Qt.callLater(ensureCursorVisible)
    }

    function switchProvider(delta) {
        if (agents.length <= 1) return
        selectProvider(safeIndex + delta)
        cursorActive = true
    }

    function activateCursor() {
        if (focusSection === "providers" && focusRow >= 0) {
            selectProvider(focusRow)
        } else if (focusSection === "banner" || focusSection === "hero") {
            refreshNow(true)
        }
    }

    function handleKey(event) {
        var key = event.key
        var text = String(event.text || "").toLowerCase()
        if (key === Qt.Key_Escape) {
            close()
            event.accepted = true
            return
        }
        if (key === Qt.Key_Tab) {
            moveSection(event.modifiers & Qt.ShiftModifier ? -1 : 1)
            event.accepted = true
            return
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            activateCursor()
            event.accepted = true
            return
        }
        if (text === "r") {
            refreshNow(true)
            event.accepted = true
            return
        }
        if (key === Qt.Key_Down || key === Qt.Key_J) {
            moveCursor(1)
            event.accepted = true
            return
        }
        if (key === Qt.Key_Up || key === Qt.Key_K) {
            moveCursor(-1)
            event.accepted = true
            return
        }
        if (key === Qt.Key_Right || key === Qt.Key_L) {
            switchProvider(1)
            event.accepted = true
            return
        }
        if (key === Qt.Key_Left || key === Qt.Key_H) {
            switchProvider(-1)
            event.accepted = true
            return
        }
    }

    function ensureCursorVisible() {
        if (!scroller || !scroller.contentItem) return
        var flick = scroller.contentItem
        var item = null
        var rows = rowItems[focusSection]
        if (rows && focusRow >= 0 && rows[focusRow]) item = rows[focusRow]
        if (!item) item = sectionItems[focusSection]
        if (!item || typeof item.mapToItem !== "function") return
        var point = item.mapToItem(flick, 0, 0)
        var maxY = Math.max(0, Number(flick.contentHeight || 0) - Number(flick.height || 0))
        if (point.y < flick.contentY) {
            flick.contentY = Math.max(0, point.y - Theme.spacingSm)
        } else if (point.y + item.height > flick.contentY + flick.height) {
            flick.contentY = Math.min(maxY,
                point.y + item.height - flick.height + Theme.spacingSm)
        }
    }

    onShownChanged: {
        if (shown) {
            nowMs = Date.now()
            cursorActive = false
            focusSection = agents.length > 1 ? "providers" : "hero"
            focusRow = -1
            clampFocus()
            if (agentsWidget && agentsWidget.maybeRefresh) agentsWidget.maybeRefresh(60000)
            Qt.callLater(ensureCursorVisible)
        }
    }
    onAgentsChanged: {
        if (selectedIndex >= agents.length) selectedIndex = 0
        clampFocus()
    }
    onProviderChanged: clampFocus()

    // ------------------------------------------------------------ primitives

    // Every text node in this panel derives from Label, so the bar font can
    // never silently regress to a fallback family.
    component Label: Text {
        font.family: Theme.fontFamily
    }

    component SectionHeader: Label {
        Layout.fillWidth: true
        topPadding: Theme.spacingXs
        color: Theme.textMuted
        font.pixelSize: Theme.fontSizeXs
        font.weight: Theme.fontWeightBold
        font.letterSpacing: 1
    }

    // Rounded track showing the fraction of an allowance used. The marker sits
    // at the pace position (where usage would be if the window drained evenly),
    // so a fill past the marker reads as "behind pace" at a glance. The track
    // is a shared control fill and the bar is at least 4 px thick.
    component Meter: Item {
        id: meter
        property real value: -1
        property real marker: -1
        property bool alarming: false

        Layout.fillWidth: true
        implicitHeight: Math.max(4, Theme.spacingXs)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.controls.normalFill
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

    // One live rate-limit window: label, used percentage, meter with a pace
    // marker, and the absolute reset time next to the relative countdown.
    component LimitRow: ColumnLayout {
        id: limitRow
        property var window: null
        property int rowIndex: -1

        readonly property real percent: Number(limitRow.window && limitRow.window.percent)
        readonly property bool alarming: AgentUsage.severityForLimit(limitRow.window) === "critical"
        readonly property real remainingMs: AgentUsage.resetMsFor(limitRow.window, panelRoot.nowMs)
        readonly property var pace: AgentUsage.paceInfo(limitRow.window, panelRoot.nowMs)
        readonly property string paceText: AgentUsage.paceLabel(limitRow.pace)
        readonly property string resetText: {
            var absolute = AgentUsage.formatResetAbsolute(limitRow.window && limitRow.window.resetsAt)
            if (absolute === "") return "No reset time reported"
            var relative = limitRow.remainingMs > 0
                ? AgentUsage.formatDuration(limitRow.remainingMs) : ""
            return relative !== ""
                ? "Resets " + absolute + " · in " + relative
                : "Resets " + absolute
        }

        Layout.fillWidth: true
        spacing: Theme.spacingXs
        Component.onCompleted: panelRoot.registerRow("limits", limitRow.rowIndex, limitRow)

        RowLayout {
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: limitRow.window ? String(limitRow.window.label || "Limit") : "Limit"
                color: Theme.text
                font.pixelSize: Theme.fontSizeMd
                font.weight: Theme.fontWeightMedium
                elide: Text.ElideRight
            }

            Label {
                text: isFinite(limitRow.percent)
                    ? Math.round(limitRow.percent * 100) + "% used" : "—"
                color: limitRow.alarming ? Theme.error : Theme.text
                font.pixelSize: Theme.fontSizeSm
                font.weight: Theme.fontWeightMedium
            }
        }

        Meter {
            value: limitRow.percent
            marker: limitRow.pace ? limitRow.pace.elapsed : -1
            alarming: limitRow.alarming
        }

        RowLayout {
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: limitRow.resetText
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeXs
                elide: Text.ElideRight
            }

            Label {
                visible: limitRow.paceText !== ""
                text: limitRow.paceText
                color: limitRow.pace && limitRow.pace.behind ? Theme.warning : Theme.textMuted
                font.pixelSize: Theme.fontSizeXs
            }
        }
    }

    // One model row: name, share bar scaled to the heaviest model, tokens.
    component ModelRow: RowLayout {
        id: modelRow
        property var row: null
        property real share: 0
        property int rowIndex: -1
        property string sectionName: ""

        Layout.fillWidth: true
        spacing: Theme.spacingSm
        Component.onCompleted: {
            if (modelRow.sectionName !== "")
                panelRoot.registerRow(modelRow.sectionName, modelRow.rowIndex, modelRow)
        }

        Label {
            Layout.fillWidth: true
            text: modelRow.row ? String(modelRow.row.name) : ""
            color: Theme.text
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideRight
        }

        Meter {
            Layout.fillWidth: false
            Layout.preferredWidth: 72
            value: modelRow.share
        }

        Label {
            text: AgentUsage.formatTokens(modelRow.row ? modelRow.row.total : 0)
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSm
        }
    }

    // Vertical tokens-by-day columns. Zero days emit no bar at all; every day
    // carries its numeric value and the window is labelled by its header.
    component DayChart: Item {
        id: chart
        property var bars: []
        property string todayDate: ""

        Layout.fillWidth: true
        implicitHeight: 94

        readonly property real columnWidth: bars.length > 0
            ? (width - (bars.length - 1) * Theme.spacingXs) / bars.length : 0

        Row {
            anchors.fill: parent
            spacing: Theme.spacingXs

            Repeater {
                model: chart.bars

                delegate: Column {
                    id: dayColumn
                    required property var modelData
                    required property int index
                    readonly property bool today: String(modelData.date || "") === chart.todayDate

                    width: chart.columnWidth
                    spacing: 2

                    Item {
                        width: parent.width
                        height: chart.implicitHeight - 30

                        Rectangle {
                            visible: dayColumn.modelData.hasUsage === true
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.max(3, parent.width * 0.6)
                            height: dayColumn.modelData.barHeight
                            radius: 2
                            color: dayColumn.today ? Theme.accent : Theme.textMuted
                            opacity: dayColumn.today ? 1 : 0.7

                            Behavior on height {
                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Label {
                        width: parent.width
                        text: AgentUsage.formatTokens(dayColumn.modelData.tokens)
                        color: dayColumn.today ? Theme.text : Theme.textMuted
                        font.pixelSize: Theme.fontSizeXs
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Label {
                        width: parent.width
                        text: AgentUsage.dayLabel(dayColumn.modelData.date, dayColumn.today)
                        color: dayColumn.today ? Theme.text : Theme.textMuted
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: dayColumn.today ? Theme.fontWeightBold : Theme.fontWeightNormal
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- content

    // The body scrolls instead of overflowing the card. `scroller` is the
    // content-sizing item so the card grows with the content up to the cap
    // derived from maxPopupHeight.
    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: panelRoot.shown
        Keys.onPressed: function(event) { panelRoot.handleKey(event) }

        Flickable {
            id: scroller
            anchors.fill: parent
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
                spacing: Theme.spacingLg

                Timer {
                    interval: 30000
                    repeat: true
                    running: panelRoot.shown
                    onTriggered: panelRoot.nowMs = Date.now()
                }

                Label {
                    Layout.fillWidth: true
                    visible: panelRoot.agents.length === 0
                    wrapMode: Text.WordWrap
                    text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSm
                    horizontalAlignment: Text.AlignHCenter
                }

                // PROVIDERS switch (only with more than one provider).
                ColumnLayout {
                    id: providersSection
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs
                    visible: panelRoot.agents.length > 1
                    Component.onCompleted: panelRoot.registerSection("providers", providersSection)

                    SectionHeader { text: "PROVIDERS" }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Repeater {
                            model: panelRoot.agents

                            delegate: Rectangle {
                                id: providerTab
                                required property var modelData
                                required property int index
                                readonly property string worst: AgentUsage.providerWorstLabel(modelData, panelRoot.nowMs)
                                readonly property bool active: index === panelRoot.safeIndex
                                readonly property bool focused: panelRoot.cursorActive &&
                                    panelRoot.focusSection === "providers" && panelRoot.focusRow === index

                                Layout.fillWidth: true
                                implicitHeight: tabColumn.implicitHeight + Theme.spacingSm
                                radius: Theme.radiusSm
                                color: active ? Theme.controls.selectedFill
                                    : (tabArea.containsMouse ? Theme.controls.hoverFill : "transparent")
                                border.width: focused ? Theme.borderWidthFocus
                                    : (active ? Theme.borderWidthDefault : 0)
                                border.color: focused ? Theme.controls.focusBorder : Theme.controls.selectedBorder
                                Component.onCompleted: panelRoot.registerRow("providers", index, providerTab)

                                ColumnLayout {
                                    id: tabColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Theme.spacingSm
                                    anchors.rightMargin: Theme.spacingSm
                                    spacing: 0

                                    Label {
                                        Layout.fillWidth: true
                                        text: String(providerTab.modelData.name || providerTab.modelData.id)
                                        color: providerTab.active ? Theme.accent : Theme.text
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: Theme.fontWeightMedium
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        visible: providerTab.worst !== ""
                                        text: providerTab.worst
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fontSizeXs
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: tabArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panelRoot.selectProvider(providerTab.index)
                                }
                            }
                        }
                    }
                }

                // HERO: identity, plan, billing, freshness and Refresh.
                ColumnLayout {
                    id: heroSection
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    Component.onCompleted: panelRoot.registerSection("hero", heroSection)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs

                            Label {
                                Layout.fillWidth: true
                                text: panelRoot.provider
                                    ? String(panelRoot.provider.name || panelRoot.provider.id) : "Agents"
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeLg
                                font.weight: Theme.fontWeightBold
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: AgentUsage.planLabel(panelRoot.provider)
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeSm
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: AgentUsage.billingSummary(panelRoot.provider)
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeXs
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.fillWidth: false
                                implicitWidth: freshnessLabel.implicitWidth + Theme.spacingSm * 2
                                implicitHeight: freshnessLabel.implicitHeight + Theme.spacingXs
                                radius: height / 2
                                color: "transparent"
                                border.width: Theme.borderWidthDefault
                                border.color: panelRoot.freshness.stale ? Theme.warning : Theme.border

                                Label {
                                    id: freshnessLabel
                                    anchors.centerIn: parent
                                    text: panelRoot.freshness.text
                                    color: panelRoot.freshness.stale ? Theme.warning : Theme.textMuted
                                    font.pixelSize: Theme.fontSizeXs
                                }
                            }
                        }

                        AureliaActionButton {
                            label: "Refresh"
                            icon: "view-refresh"
                            compact: true
                            Layout.preferredWidth: 96
                            Layout.alignment: Qt.AlignTop
                            onTriggered: panelRoot.refreshNow(true)
                        }
                    }
                }

                // STATE BANNER: unknown / error / rate-limited only. The
                // generic "Local usage only" string stays in the hero plan and
                // is never repeated here.
                Rectangle {
                    id: bannerItem
                    Layout.fillWidth: true
                    visible: panelRoot.bannerVisible()
                    implicitHeight: bannerColumn.implicitHeight + Theme.spacingMd * 2
                    radius: Theme.radiusSm
                    color: Theme.controls.normalFill
                    border.width: Theme.borderWidthDefault
                    border.color: panelRoot.providerStateInfo.key === "error"
                        ? Theme.error
                        : (panelRoot.providerStateInfo.key === "rate-limited" ? Theme.warning : Theme.border)
                    Component.onCompleted: panelRoot.registerSection("banner", bannerItem)

                    ColumnLayout {
                        id: bannerColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        spacing: Theme.spacingXs

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm

                            Label {
                                Layout.fillWidth: true
                                text: panelRoot.providerStateInfo.message
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: Theme.fontWeightMedium
                                wrapMode: Text.WordWrap
                            }

                            AureliaActionButton {
                                visible: panelRoot.providerStateInfo.retry
                                label: "Retry"
                                compact: true
                                Layout.preferredWidth: 84
                                onTriggered: panelRoot.refreshNow(true)
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: panelRoot.providerStateInfo.help !== ""
                            text: panelRoot.providerStateInfo.help
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeXs
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // LIMITS: every reported window, not just the binding one.
                ColumnLayout {
                    id: limitsSection
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    visible: panelRoot.limits.length > 0
                    opacity: panelRoot.providerStateInfo.stale ? 0.6 : 1.0
                    Component.onCompleted: panelRoot.registerSection("limits", limitsSection)

                    SectionHeader { text: "LIMITS" }

                    Repeater {
                        model: panelRoot.limits

                        delegate: LimitRow {
                            required property var modelData
                            required property int index
                            window: modelData
                            rowIndex: index
                        }
                    }
                }

                // USAGE TODAY: billable versus cache, the provider noun, and
                // sessions.
                ColumnLayout {
                    id: todaySection
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    visible: panelRoot.hasToday()
                    opacity: panelRoot.providerStateInfo.stale ? 0.6 : 1.0
                    Component.onCompleted: panelRoot.registerSection("today", todaySection)

                    SectionHeader { text: "USAGE TODAY" }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingLg

                        Label {
                            text: "Billable " + AgentUsage.formatTokens(panelRoot.today.billable)
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSm
                        }

                        Label {
                            text: "Cache " + AgentUsage.formatTokens(panelRoot.today.cache)
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeSm
                        }

                        Item { Layout.fillWidth: true }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: {
                            var base = panelRoot.today.count + " " + panelRoot.today.noun
                            if (panelRoot.today.noun !== "sessions" && panelRoot.today.sessions > 0)
                                base += " · " + panelRoot.today.sessions + " sessions"
                            return base
                        }
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeXs
                    }
                }

                // LAST 7 DAYS: labelled window with a numeric value per day.
                ColumnLayout {
                    id: weekSection
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    visible: panelRoot.weekBars.length > 0
                    opacity: panelRoot.providerStateInfo.stale ? 0.6 : 1.0
                    Component.onCompleted: panelRoot.registerSection("week", weekSection)

                    SectionHeader { text: "LAST 7 DAYS" }

                    DayChart {
                        bars: panelRoot.weekBars
                        todayDate: AgentUsage.todayDate(panelRoot.nowMs)
                    }
                }

                // MODELS: today-first, then an explicit all-time list.
                ColumnLayout {
                    id: modelsTodaySection
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    visible: panelRoot.todayModelRows.length > 0
                    opacity: panelRoot.providerStateInfo.stale ? 0.6 : 1.0
                    Component.onCompleted: panelRoot.registerSection("modelsToday", modelsTodaySection)

                    SectionHeader { text: "MODELS · TODAY" }

                    Repeater {
                        model: panelRoot.todayModelRows

                        delegate: ModelRow {
                            required property var modelData
                            required property int index
                            row: modelData
                            rowIndex: index
                            sectionName: "modelsToday"
                            share: modelData.total / Math.max(1, panelRoot.todayModelRows[0].total)
                        }
                    }
                }

                ColumnLayout {
                    id: modelsAllSection
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    visible: panelRoot.allTimeModelRows.length > 0
                    opacity: panelRoot.providerStateInfo.stale ? 0.6 : 1.0
                    Component.onCompleted: panelRoot.registerSection("modelsAll", modelsAllSection)

                    SectionHeader { text: "MODELS · ALL TIME" }

                    Repeater {
                        model: panelRoot.allTimeModelRows

                        delegate: ModelRow {
                            required property var modelData
                            required property int index
                            row: modelData
                            rowIndex: index
                            sectionName: "modelsAll"
                            share: modelData.total / Math.max(1, panelRoot.allTimeModelRows[0].total)
                        }
                    }
                }

                // SUBSCRIPTION: only when the user has recorded one.
                ColumnLayout {
                    id: subscriptionSection
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm
                    visible: panelRoot.hasSubscription
                    Component.onCompleted: panelRoot.registerSection("subscription", subscriptionSection)

                    SectionHeader { text: "SUBSCRIPTION" }

                    Repeater {
                        model: AgentUsage.subscriptionRows(panelRoot.provider)

                        delegate: Label {
                            required property string modelData
                            Layout.fillWidth: true
                            text: modelData
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }
                }
            }
        }
    }
}
