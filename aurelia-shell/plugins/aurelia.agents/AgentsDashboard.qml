import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../theme"
import "../../ui"
import "AgentUsage.js" as AgentUsage

// Consolidated multi-account Usage dashboard surface.
//
// This is the panel body, extracted from the layer-shell wrapper so the same
// pixels can be rendered offscreen for a preview. The layout is deliberately
// pin-stable:
//
//   MATRIX  (pinned)  accounts in a fixed name/id order, columns
//                     ACCOUNT | 5H | WEEK | MONTH | TODAY [| BALANCE].
//                     Never reorders by severity; percentages are right-aligned
//                     and every window cell carries a non-colour severity glyph
//                     for warn/critical.
//   TABS    (pinned)  one tab per detected account, labelled with the provider
//                     name, hidden when there is exactly one account.
//   DETAIL  (scroll)  the selected account: state banner, full LIMITS list
//                     (including other/unknown windows and duplicates), today
//                     split, 7-day chart, model windows and subscription.
//   ACTIONS (pinned)  the compact Refresh action.
//
// A window's class comes from `windowMinutes` alone. A provider that reports
// no limits gets `—` and a single muted `no live limits` tag, never a
// fabricated `0%`.
Item {
    id: dashboard

    property var agentsWidget: null
    property real nowMs: Date.now()
    // The panel passes its body cap so only the detail pane ever scrolls.
    property real maxHeight: 620
    property int staleMs: 1800000
    // Focus regions: matrix -> tabs -> detail -> actions.
    property string focusRegion: "matrix"
    property int focusRow: 0
    property bool cursorActive: false
    property string selectedAccountId: ""
    property int selectedFallbackIndex: 0
    property var detailItems: []
    // Dedupes observed unmet conditions so a persistent condition is logged
    // once per session instead of on every 30 s tick.
    property var loggedDiagnostics: ({})
    // The panel wrapper installs a close handler here.
    property var dismissHook: null

    // Surface tokens exposed so the offscreen preview harness can reproduce the
    // panel card without importing the Theme singleton itself.
    readonly property color surfaceBackdrop: Theme.bgBase
    readonly property color surfaceBackground: Theme.popups.background
    readonly property color surfaceBorder: Theme.popups.border
    readonly property int surfacePadding: Theme.popupPadding
    readonly property int surfaceRadius: Theme.radiusLg

    anchors.fill: parent
    implicitHeight: body.implicitHeight

    readonly property var accounts: agentsWidget ? agentsWidget.visibleAgents : []
    readonly property var rows: AgentUsage.matrixRows(accounts, nowMs)
    readonly property bool showBalance: AgentUsage.anyBalance(accounts)
    readonly property int selectedIndex: AgentUsage.reconcileSelection(
        selectedAccountId, selectedFallbackIndex, rows)
    readonly property var selectedRow: selectedIndex >= 0 && selectedIndex < rows.length
        ? rows[selectedIndex] : null
    readonly property var selectedRecord: selectedRow ? selectedRow.record : null
    readonly property bool hasSelection: selectedRow !== null
    readonly property var stateInfo: AgentUsage.providerState(selectedRecord, nowMs, {
        loading: agentsWidget ? !agentsWidget.loaded : false,
        backendError: agentsWidget ? agentsWidget.lastError : "",
        staleMs: staleMs
    })
    readonly property var limitDetails: AgentUsage.limitDetailRows(selectedRecord, nowMs)
    readonly property var today: AgentUsage.todayUsage(selectedRecord)
    readonly property var freshness: AgentUsage.freshnessPill(selectedRecord, nowMs, staleMs)
    readonly property var todayModelRows: AgentUsage.todayModels(selectedRecord, 4)
    readonly property var allTimeModelRows: AgentUsage.modelRows(selectedRecord, 4)
    readonly property var weekBars: AgentUsage.dayChartBars(
        selectedRecord ? selectedRecord.recentDays : [], 56)
    readonly property bool hasSubscription: !!(selectedRecord && selectedRecord.subscription)
    readonly property bool bannerVisible: stateInfo.key === "unknown" ||
        stateInfo.key === "error" || stateInfo.key === "rate-limited"
    // The detail pane is capped so matrix + tabs + detail always fit the card.
    readonly property real maxDetailHeight: Math.max(0,
        maxHeight - matrixBlock.implicitHeight
        - (tabStrip.visible ? tabStrip.implicitHeight : 0)
        - actionsRow.implicitHeight - body.spacing * 3)

    function sectionColor(severity) {
        if (severity === "critical") return Theme.error
        if (severity === "warn") return Theme.warning
        return Theme.text
    }

    function visibleRegions() {
        var regions = []
        if (rows.length > 0) regions.push("matrix")
        if (rows.length > 1) regions.push("tabs")
        if (hasSelection) regions.push("detail")
        regions.push("actions")
        return regions
    }

    function clampFocus() {
        var regions = visibleRegions()
        if (regions.indexOf(focusRegion) < 0) {
            focusRegion = regions.length > 0 ? regions[0] : "matrix"
            focusRow = 0
        }
        if (focusRegion === "matrix") {
            focusRow = Math.max(0, Math.min(Math.max(0, rows.length - 1), focusRow))
        } else if (focusRegion === "tabs") {
            focusRow = Math.max(0, selectedIndex)
        } else if (focusRegion === "detail") {
            focusRow = Math.max(0, Math.min(Math.max(0, detailItems.length - 1), focusRow))
        } else {
            focusRow = 0
        }
    }

    function moveRegion(delta) {
        var regions = visibleRegions()
        if (regions.length === 0) return
        var index = regions.indexOf(focusRegion)
        if (index < 0) index = delta > 0 ? -1 : 0
        focusRegion = regions[(index + delta + regions.length) % regions.length]
        focusRow = (focusRegion === "tabs" && selectedIndex >= 0) ? selectedIndex : 0
        cursorActive = true
        Qt.callLater(ensureFocusVisible)
    }

    function selectAccount(index) {
        if (rows.length === 0) return
        var next = ((index % rows.length) + rows.length) % rows.length
        selectedFallbackIndex = next
        selectedAccountId = rows[next].id
        if (focusRegion === "matrix" || focusRegion === "tabs") focusRow = next
        cursorActive = true
        Qt.callLater(ensureFocusVisible)
    }

    function switchAccount(delta) {
        if (rows.length <= 1) return
        selectAccount((selectedIndex < 0 ? 0 : selectedIndex) + delta)
    }

    function moveRow(delta) {
        if (focusRegion === "tabs") {
            switchAccount(delta)
            return
        }
        if (focusRegion === "detail") {
            if (detailItems.length === 0) return
            focusRow = Math.max(0, Math.min(detailItems.length - 1, focusRow + delta))
            cursorActive = true
            Qt.callLater(ensureFocusVisible)
            return
        }
        if (focusRegion === "matrix") {
            if (rows.length === 0) return
            if (delta > 0) focusRow = focusRow >= rows.length - 1 ? 0 : focusRow + 1
            else focusRow = focusRow <= 0 ? rows.length - 1 : focusRow - 1
            cursorActive = true
        }
    }

    function activateFocus() {
        if (focusRegion === "matrix" || focusRegion === "tabs") {
            selectAccount(focusRow)
        } else if (focusRegion === "actions") {
            refreshNow(true)
        } else if (focusRegion === "detail") {
            var item = detailItems[focusRow]
            if (item && typeof item.activate === "function") item.activate()
        }
    }

    function refreshNow(force) {
        if (agentsWidget && typeof agentsWidget.refresh === "function")
            agentsWidget.refresh(force === true)
    }

    // Emit an observable diagnostic for every unmet condition. The visible
    // `—` / `no live limits` / `duration not reported` labels stay; this adds
    // the maintainer-facing record so a missing field is never silently
    // skipped. `console.warn` is the shell's standard observability channel
    // (read by `aurelia logs` from the Quickshell runtime log).
    function emitDiagnostics() {
        if (!agentsWidget) return
        var diagnostics = AgentUsage.diagnoseRecords(accounts)
        diagnostics = diagnostics.concat(AgentUsage.collectorDiagnostic(agentsWidget.lastError))
        var observed = {}
        for (var i = 0; i < diagnostics.length; i++) {
            var key = AgentUsage.diagnosticKey(diagnostics[i])
            observed[key] = true
            if (!loggedDiagnostics[key]) {
                console.warn(AgentUsage.diagnosticLine(diagnostics[i]))
            }
        }
        loggedDiagnostics = observed
    }

    function handleKey(event) {
        var key = event.key
        var text = String(event.text || "").toLowerCase()
        if (key === Qt.Key_Escape) {
            if (typeof dashboard.dismissHook === "function") dashboard.dismissHook()
            event.accepted = true
            return
        }
        if (key === Qt.Key_Tab) {
            moveRegion(event.modifiers & Qt.ShiftModifier ? -1 : 1)
            event.accepted = true
            return
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            activateFocus()
            event.accepted = true
            return
        }
        if (text === "r") {
            refreshNow(true)
            event.accepted = true
            return
        }
        if (key === Qt.Key_Down || key === Qt.Key_J) {
            moveRow(1)
            event.accepted = true
            return
        }
        if (key === Qt.Key_Up || key === Qt.Key_K) {
            moveRow(-1)
            event.accepted = true
            return
        }
        if (key === Qt.Key_Right || key === Qt.Key_L) {
            switchAccount(1)
            event.accepted = true
            return
        }
        if (key === Qt.Key_Left || key === Qt.Key_H) {
            switchAccount(-1)
            event.accepted = true
            return
        }
    }

    function registerDetailItem(item) {
        if (!item || detailItems.indexOf(item) >= 0) return
        detailItems = detailItems.concat([item])
    }

    function unregisterDetailItem(item) {
        var index = detailItems.indexOf(item)
        if (index < 0) return
        var copy = detailItems.slice()
        copy.splice(index, 1)
        detailItems = copy
    }

    function ensureFocusVisible() {
        if (focusRegion === "tabs") Qt.callLater(ensureTabVisible)
        if (focusRegion === "detail" && detailItems[focusRow])
            scrollItemIntoView(detailItems[focusRow])
    }

    function scrollItemIntoView(item) {
        if (!item) return
        var point = item.mapToItem(detailFlick, 0, 0)
        var maxY = Math.max(0, Number(detailFlick.contentHeight || 0) - Number(detailFlick.height || 0))
        if (point.y < detailFlick.contentY) {
            detailFlick.contentY = Math.max(0, point.y - Theme.spacingSm)
        } else if (point.y + item.height > detailFlick.contentY + detailFlick.height) {
            detailFlick.contentY = Math.min(maxY,
                point.y + item.height - detailFlick.height + Theme.spacingSm)
        }
    }

    function ensureTabVisible() {
        if (!tabStrip || selectedIndex < 0) return
        var child = tabRow.children[selectedIndex]
        if (!child) return
        var left = child.x
        var right = child.x + child.width
        if (left < tabStrip.contentX) {
            tabStrip.contentX = Math.max(0, left - Theme.spacingXs)
        } else if (right > tabStrip.contentX + tabStrip.width) {
            var maxX = Math.max(0, tabRow.width - tabStrip.width)
            tabStrip.contentX = Math.min(maxX, right - tabStrip.width + Theme.spacingXs)
        }
    }

    onRowsChanged: {
        var index = AgentUsage.reconcileSelection(selectedAccountId, selectedFallbackIndex, rows)
        if (index < 0) {
            selectedAccountId = ""
            selectedFallbackIndex = 0
        } else {
            selectedFallbackIndex = index
            if (String(selectedAccountId) !== rows[index].id) selectedAccountId = rows[index].id
        }
        clampFocus()
        emitDiagnostics()
    }
    onStateInfoChanged: emitDiagnostics()
    onSelectedIndexChanged: {
        detailItems = []
        if (focusRegion === "tabs") focusRow = Math.max(0, selectedIndex)
        Qt.callLater(ensureTabVisible)
    }
    onDetailItemsChanged: {
        if (focusRegion === "detail" && focusRow >= detailItems.length)
            focusRow = Math.max(0, detailItems.length - 1)
    }
    Component.onCompleted: emitDiagnostics()

    // ------------------------------------------------------------ primitives

    // The single font-family carrier. Every text node derives from this; the
    // repository test asserts raw_text_count <= 1, so no raw Text is added.
    component Label: Text {
        font.family: Theme.fontFamily
    }

    // Numeric cells right-align by default so percentages line up column-wise.
    component NumericLabel: Label {
        horizontalAlignment: Text.AlignRight
        font.weight: Theme.fontWeightMedium
    }

    component SectionHeader: Label {
        Layout.fillWidth: true
        topPadding: Theme.spacingXs
        color: Theme.textMuted
        font.pixelSize: Theme.fontSizeXs
        font.weight: Theme.fontWeightBold
        font.letterSpacing: 1
    }

    // A 1 px hairline is cheaper and cleaner than boxing every row.
    component Hairline: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.border
    }

    // A max(3, spacingXs) px meter on a translucent-safe track with a 1 px
    // outline and a 2 px pace marker at the elapsed fraction.
    component Meter: Item {
        id: meter
        property real value: -1
        property real marker: -1
        property bool alarming: false

        Layout.fillWidth: true
        implicitHeight: Math.max(3, Theme.spacingXs)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.controls.normalFill
            border.width: Theme.borderWidthDefault
            border.color: Theme.border
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

    // One canonical window cell: right-aligned percent, non-colour severity
    // glyph, meter with pace marker, muted relative countdown and the pace
    // word. The absolute reset time stays out of the grid and is exposed only
    // through the cell tooltip.
    component MatrixCell: ColumnLayout {
        id: matrixCell
        property var cell: null
        property string tooltipText: cell
            ? (String(cell.label) + " · " + cell.percentText +
                (cell.absoluteReset !== "" ? "\nResets " + cell.absoluteReset : ""))
            : ""

        Layout.fillWidth: true
        spacing: 1

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Label {
                text: matrixCell.cell ? matrixCell.cell.glyph : ""
                color: dashboard.sectionColor(matrixCell.cell ? matrixCell.cell.severity : "ok")
                font.pixelSize: Theme.fontSizeXs
                visible: text !== ""
            }

            Item { Layout.fillWidth: true }

            NumericLabel {
                text: matrixCell.cell ? matrixCell.cell.percentText : "—"
                color: matrixCell.cell
                    ? dashboard.sectionColor(matrixCell.cell.severity) : Theme.textMuted
                font.pixelSize: Theme.fontSizeSm
            }
        }

        Meter {
            visible: matrixCell.cell !== null
            value: matrixCell.cell ? matrixCell.cell.percent : -1
            marker: matrixCell.cell ? matrixCell.cell.elapsed : -1
            alarming: matrixCell.cell && matrixCell.cell.severity === "critical"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs
            visible: matrixCell.cell !== null

            Label {
                Layout.fillWidth: true
                text: matrixCell.cell ? matrixCell.cell.countdown : ""
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeXs
                elide: Text.ElideRight
            }

            Label {
                visible: matrixCell.cell && matrixCell.cell.paceWord !== ""
                text: matrixCell.cell ? matrixCell.cell.paceWord : ""
                color: matrixCell.cell && matrixCell.cell.paceWord === "behind"
                    ? Theme.warning : Theme.textMuted
                font.pixelSize: Theme.fontSizeXs
            }
        }

        HoverHandler { id: cellHover }

        ToolTip.visible: cellHover.hovered && matrixCell.tooltipText !== ""
        ToolTip.text: matrixCell.tooltipText
        ToolTip.delay: 400
    }

    // One limit row in the per-account tab. `unknown` durations render as a
    // full-width "duration not reported" row and never as a column.
    component LimitDetailRow: ColumnLayout {
        id: limitRow
        property var detail: null
        property int rowIndex: -1

        Layout.fillWidth: true
        spacing: Theme.spacingXs
        Component.onCompleted: dashboard.registerDetailItem(limitRow)
        Component.onDestruction: dashboard.unregisterDetailItem(limitRow)

        readonly property bool detailFocused: dashboard.cursorActive &&
            dashboard.focusRegion === "detail" && dashboard.detailItems[dashboard.focusRow] === limitRow
        readonly property string resetText: {
            if (!limitRow.detail) return ""
            var absolute = limitRow.detail.absoluteReset
            if (absolute === "") return limitRow.detail.countdown !== ""
                ? "in " + limitRow.detail.countdown : ""
            return limitRow.detail.countdown !== ""
                ? "Resets " + absolute + " · in " + limitRow.detail.countdown
                : "Resets " + absolute
        }

        function activate() { dashboard.refreshNow(true) }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: limitContent.implicitHeight + Theme.spacingSm
            radius: Theme.radiusSm
            color: "transparent"
            border.width: limitRow.detailFocused ? Theme.borderWidthFocus : 0
            border.color: Theme.controls.focusBorder

            ColumnLayout {
                id: limitContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingXs
                anchors.rightMargin: Theme.spacingXs
                spacing: Theme.spacingXs

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSm

                    Label {
                        Layout.fillWidth: true
                        text: limitRow.detail
                            ? (limitRow.detail.isUnknown ? "duration not reported" : limitRow.detail.title)
                            : ""
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Theme.fontWeightMedium
                        elide: Text.ElideRight
                    }

                    Label {
                        text: limitRow.detail ? limitRow.detail.glyph : ""
                        color: dashboard.sectionColor(limitRow.detail ? limitRow.detail.severity : "ok")
                        font.pixelSize: Theme.fontSizeSm
                        visible: text !== ""
                    }

                    NumericLabel {
                        text: limitRow.detail ? limitRow.detail.percentText : "—"
                        color: limitRow.detail
                            ? dashboard.sectionColor(limitRow.detail.severity) : Theme.textMuted
                        font.pixelSize: Theme.fontSizeSm
                    }
                }

                Meter {
                    visible: limitRow.detail ? !limitRow.detail.isUnknown : false
                    value: limitRow.detail ? limitRow.detail.percent : -1
                    marker: limitRow.detail ? limitRow.detail.elapsed : -1
                    alarming: limitRow.detail && limitRow.detail.severity === "critical"
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: limitRow.resetText !== "" || (limitRow.detail && limitRow.detail.paceWord !== "")
                    spacing: Theme.spacingSm

                    Label {
                        Layout.fillWidth: true
                        text: limitRow.resetText
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeXs
                        elide: Text.ElideRight
                    }

                    Label {
                        visible: limitRow.detail && limitRow.detail.paceWord !== ""
                        text: limitRow.detail ? limitRow.detail.paceWord : ""
                        color: limitRow.detail && limitRow.detail.paceWord === "behind"
                            ? Theme.warning : Theme.textMuted
                        font.pixelSize: Theme.fontSizeXs
                    }
                }
            }
        }
    }

    component ModelRow: RowLayout {
        id: modelRow
        property var row: null
        property real share: 0
        property int rowIndex: -1
        property string sectionName: ""

        Layout.fillWidth: true
        spacing: Theme.spacingSm

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

        NumericLabel {
            text: AgentUsage.formatTokens(modelRow.row ? modelRow.row.total : 0)
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSm
        }
    }

    component DayChart: Item {
        id: chart
        property var bars: []
        property string todayDate: ""

        Layout.fillWidth: true
        implicitHeight: 84

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

    // ---------------------------------------------------------------- layout

    ColumnLayout {
        id: body
        anchors.fill: parent
        spacing: Theme.spacingSm

        // MATRIX (pinned).
        ColumnLayout {
            id: matrixBlock
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spacingXs
                spacing: Theme.spacingXs

                Label {
                    Layout.preferredWidth: 108
                    text: "ACCOUNT"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightBold
                    font.letterSpacing: 1
                }

                Repeater {
                    model: AgentUsage.canonicalWindowOrder()

                    delegate: Label {
                        id: columnHeader
                        required property string modelData
                        Layout.fillWidth: true
                        text: AgentUsage.windowColumnLabel(modelData)
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                        font.letterSpacing: 1
                        horizontalAlignment: Text.AlignRight

                        HoverHandler { id: headerHover }
                        ToolTip.visible: headerHover.hovered && AgentUsage.windowDescription(columnHeader.modelData) !== ""
                        ToolTip.text: AgentUsage.windowDescription(columnHeader.modelData)
                        ToolTip.delay: 400
                    }
                }

                Label {
                    Layout.preferredWidth: 52
                    text: "TODAY"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightBold
                    font.letterSpacing: 1
                    horizontalAlignment: Text.AlignRight
                }

                Label {
                    Layout.preferredWidth: 66
                    visible: dashboard.showBalance
                    text: AgentUsage.balanceHeader(dashboard.accounts)
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightBold
                    font.letterSpacing: 1
                    horizontalAlignment: Text.AlignRight
                }
            }

            Hairline {}

            Repeater {
                model: dashboard.rows

                delegate: ColumnLayout {
                    id: matrixRow
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    spacing: 0

                    readonly property bool rowFocused: dashboard.cursorActive &&
                        dashboard.focusRegion === "matrix" && dashboard.focusRow === index

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: matrixRowContent.implicitHeight + Theme.spacingSm
                        radius: Theme.radiusSm
                        color: index === dashboard.selectedIndex ? Theme.controls.selectedFill : "transparent"
                        border.width: matrixRow.rowFocused ? Theme.borderWidthFocus : 0
                        border.color: Theme.controls.focusBorder

                        RowLayout {
                            id: matrixRowContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingXs
                            anchors.rightMargin: Theme.spacingXs
                            spacing: Theme.spacingXs

                            ColumnLayout {
                                Layout.preferredWidth: 108
                                spacing: 0

                                Label {
                                    Layout.fillWidth: true
                                    text: matrixRow.modelData.name
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Theme.fontWeightMedium
                                    elide: Text.ElideRight
                                }

                                Label {
                                    Layout.fillWidth: true
                                    visible: matrixRow.modelData.noLiveLimits
                                    text: "no live limits"
                                    color: Theme.textMuted
                                    font.pixelSize: Theme.fontSizeXs
                                    elide: Text.ElideRight
                                }
                            }

                            Repeater {
                                model: AgentUsage.canonicalWindowOrder()

                                delegate: MatrixCell {
                                    required property string modelData
                                    cell: matrixRow.modelData.windows[modelData]
                                }
                            }

                            NumericLabel {
                                Layout.preferredWidth: 52
                                text: matrixRow.modelData.todayTokens
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeSm
                            }

                            NumericLabel {
                                Layout.preferredWidth: 66
                                visible: dashboard.showBalance
                                text: matrixRow.modelData.balance !== ""
                                    ? matrixRow.modelData.balance : "—"
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeSm
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dashboard.selectAccount(matrixRow.index)
                        }
                    }

                    Hairline {
                        visible: matrixRow.index < dashboard.rows.length - 1
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingMd
                visible: dashboard.rows.length === 0
                text: "No AI coding subscriptions found."
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSm
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // TAB STRIP (pinned, hidden with a single account).
        Flickable {
            id: tabStrip
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? implicitHeight : 0
            visible: dashboard.rows.length > 1
            implicitHeight: 30
            contentWidth: tabRow.width
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width

            Row {
                id: tabRow
                spacing: Theme.spacingXs

                Repeater {
                    model: dashboard.rows

                    delegate: Rectangle {
                        id: tabButton
                        required property var modelData
                        required property int index

                        readonly property bool active: index === dashboard.selectedIndex
                        readonly property bool tabFocused: dashboard.cursorActive &&
                            dashboard.focusRegion === "tabs" && dashboard.focusRow === index

                        width: Math.max(72, tabLabel.implicitWidth + Theme.spacingMd * 2)
                        height: tabStrip.height
                        radius: Theme.radiusSm
                        color: active ? Theme.controls.selectedFill
                            : (tabHover.hovered ? Theme.controls.hoverFill : "transparent")
                        border.width: tabFocused ? Theme.borderWidthFocus
                            : (active ? Theme.borderWidthDefault : 0)
                        border.color: tabFocused ? Theme.controls.focusBorder
                            : Theme.controls.selectedBorder

                        Label {
                            id: tabLabel
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingSm
                            anchors.rightMargin: Theme.spacingSm
                            text: tabButton.modelData.name
                            color: tabButton.active ? Theme.accent : Theme.text
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        HoverHandler { id: tabHover }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dashboard.selectAccount(tabButton.index)
                        }
                    }
                }
            }
        }

        // DETAIL (the only scrolling region).
        Item {
            id: detailWrapper
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: detailFlick.implicitHeight

            Flickable {
                id: detailFlick
                anchors.fill: parent
                implicitHeight: Math.min(detailColumn.implicitHeight, dashboard.maxDetailHeight)
                contentWidth: width
                contentHeight: detailColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                opacity: dashboard.stateInfo.stale ? 0.6 : 1.0

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: detailColumn
                    width: detailFlick.width
                    spacing: Theme.spacingMd

                    Label {
                        Layout.fillWidth: true
                        visible: !dashboard.hasSelection
                        text: "No account selected."
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeSm
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // STATE BANNER: error / rate-limited / unknown only, with
                    // auth help and Retry. Error outranks stale.
                    Rectangle {
                        id: bannerItem
                        Layout.fillWidth: true
                        visible: dashboard.bannerVisible
                        implicitHeight: bannerColumn.implicitHeight + Theme.spacingMd * 2
                        radius: Theme.radiusSm
                        color: Theme.controls.normalFill
                        border.width: Theme.borderWidthDefault
                        border.color: dashboard.stateInfo.key === "error"
                            ? Theme.error
                            : (dashboard.stateInfo.key === "rate-limited" ? Theme.warning : Theme.border)
                        Component.onCompleted: dashboard.registerDetailItem(bannerItem)
                        Component.onDestruction: dashboard.unregisterDetailItem(bannerItem)

                        readonly property bool detailFocused: dashboard.cursorActive &&
                            dashboard.focusRegion === "detail" &&
                            dashboard.detailItems[dashboard.focusRow] === bannerItem

                        function activate() { if (dashboard.stateInfo.retry) dashboard.refreshNow(true) }

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
                                    text: dashboard.stateInfo.message
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Theme.fontWeightMedium
                                    wrapMode: Text.WordWrap
                                }

                                AureliaActionButton {
                                    visible: dashboard.stateInfo.retry
                                    label: "Retry"
                                    compact: true
                                    Layout.preferredWidth: 84
                                    onTriggered: dashboard.refreshNow(true)
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: dashboard.stateInfo.help !== ""
                                text: dashboard.stateInfo.help
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeXs
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // LIMITS: the FULL list for the selected account.
                    ColumnLayout {
                        id: limitsSection
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        visible: dashboard.limitDetails.length > 0

                        SectionHeader { text: "LIMITS" }

                        Repeater {
                            model: dashboard.limitDetails

                            delegate: LimitDetailRow {
                                required property var modelData
                                required property int index
                                detail: modelData
                                rowIndex: index
                            }
                        }
                    }

                    // USAGE TODAY.
                    ColumnLayout {
                        id: todaySection
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        visible: dashboard.today.billable + dashboard.today.cache > 0 ||
                            dashboard.today.count > 0 || dashboard.today.sessions > 0
                        Component.onCompleted: dashboard.registerDetailItem(todaySection)
                        Component.onDestruction: dashboard.unregisterDetailItem(todaySection)

                        readonly property bool detailFocused: dashboard.cursorActive &&
                            dashboard.focusRegion === "detail" &&
                            dashboard.detailItems[dashboard.focusRow] === todaySection

                        function activate() { dashboard.refreshNow(true) }

                        SectionHeader { text: "USAGE TODAY" }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingLg

                            Label {
                                text: "Billable " + AgentUsage.formatTokens(dashboard.today.billable)
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSm
                            }

                            Label {
                                text: "Cache " + AgentUsage.formatTokens(dashboard.today.cache)
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSizeSm
                            }

                            Item { Layout.fillWidth: true }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: {
                                var base = dashboard.today.count + " " + dashboard.today.noun
                                if (dashboard.today.noun !== "sessions" && dashboard.today.sessions > 0)
                                    base += " · " + dashboard.today.sessions + " sessions"
                                return base
                            }
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }

                    // LAST 7 DAYS.
                    ColumnLayout {
                        id: weekSection
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        visible: dashboard.weekBars.length > 0

                        SectionHeader { text: "LAST 7 DAYS" }

                        DayChart {
                            bars: dashboard.weekBars
                            todayDate: AgentUsage.todayDate(dashboard.nowMs)
                        }
                    }

                    // MODELS: today-first, then all-time.
                    ColumnLayout {
                        id: modelsTodaySection
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        visible: dashboard.todayModelRows.length > 0

                        SectionHeader { text: "MODELS · TODAY" }

                        Repeater {
                            model: dashboard.todayModelRows

                            delegate: ModelRow {
                                required property var modelData
                                required property int index
                                row: modelData
                                rowIndex: index
                                sectionName: "modelsToday"
                                share: modelData.total / Math.max(1, dashboard.todayModelRows[0].total)
                            }
                        }
                    }

                    ColumnLayout {
                        id: modelsAllSection
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        visible: dashboard.allTimeModelRows.length > 0

                        SectionHeader { text: "MODELS · ALL TIME" }

                        Repeater {
                            model: dashboard.allTimeModelRows

                            delegate: ModelRow {
                                required property var modelData
                                required property int index
                                row: modelData
                                rowIndex: index
                                sectionName: "modelsAll"
                                share: modelData.total / Math.max(1, dashboard.allTimeModelRows[0].total)
                            }
                        }
                    }

                    // SUBSCRIPTION rows (self-hiding).
                    ColumnLayout {
                        id: subscriptionSection
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        visible: dashboard.hasSubscription &&
                            AgentUsage.subscriptionRows(dashboard.selectedRecord).length > 0

                        SectionHeader { text: "SUBSCRIPTION" }

                        Repeater {
                            model: AgentUsage.subscriptionRows(dashboard.selectedRecord)

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

            // Focus border overlay for the detail region.
            Rectangle {
                anchors.fill: parent
                z: 5
                color: "transparent"
                radius: Theme.radiusSm
                border.width: dashboard.cursorActive && dashboard.focusRegion === "detail"
                    ? Theme.borderWidthFocus : 0
                border.color: Theme.controls.focusBorder
            }
        }

        // ACTIONS (pinned).
        RowLayout {
            id: actionsRow
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Label {
                Layout.fillWidth: true
                text: dashboard.freshness.text
                color: dashboard.freshness.stale ? Theme.warning : Theme.textMuted
                font.pixelSize: Theme.fontSizeXs
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: refreshButton.implicitWidth + Theme.spacingXs * 2
                Layout.preferredHeight: refreshButton.implicitHeight
                radius: Theme.radiusSm
                color: "transparent"
                border.width: dashboard.cursorActive && dashboard.focusRegion === "actions"
                    ? Theme.borderWidthFocus : 0
                border.color: Theme.controls.focusBorder

                AureliaActionButton {
                    id: refreshButton
                    anchors.centerIn: parent
                    label: "Refresh"
                    icon: "view-refresh"
                    compact: true
                    onTriggered: dashboard.refreshNow(true)
                }
            }
        }
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) { dashboard.handleKey(event) }
    }

    // Exposed so the panel wrapper can force focus on the dashboard cursor.
    readonly property Item keyTarget: keyScope

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: dashboard.nowMs = Date.now()
    }
}
