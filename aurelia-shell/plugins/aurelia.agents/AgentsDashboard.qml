import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import "../../theme"
import "../../ui"
import "AgentUsage.js" as AgentUsage

// Consolidated multi-account AI Usage dashboard surface.
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
//   DETAIL  (scroll)  the selected account: state banner, full LIMITS list
//                     (including other/unknown windows and duplicates), today
//                     split, 7-day chart, model windows, subscription and a
//                     collapsed ACCOUNT DETAILS disclosure.
//   ACTIONS (pinned)  the icon-only Refresh and Close controls.
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
    // Focus regions: matrix -> detail -> actions.
    property string focusRegion: "matrix"
    property int focusRow: 0
    property bool cursorActive: false
    property string selectedAccountId: ""
    // -1 means deliberately no selection (the resting consolidated matrix).
    property int selectedFallbackIndex: -1
    property var detailItems: []
    // Dedupes observed unmet conditions so a persistent condition is logged
    // once per session instead of on every 30 s tick.
    property var loggedDiagnostics: ({})
    // The panel wrapper installs a close handler here.
    property var dismissHook: null
    // Tooltip hover state. `hoverRow`/`hoverColumn` drive both the footer hint
    // legend and the single shared inline tooltip.
    property int hoverRow: -1
    property string hoverColumn: ""
    // The panel wrapper binds this from `panelRoot.shown`. The false default
    // makes an unwired fixture (or the offscreen preview) fail safe: the
    // rotation timer can never run when nothing is shown.
    property bool panelShown: false
    // Index into the idle footer rotation. Reset to 0 whenever the panel opens.
    property int rotationIndex: 0
    onPanelShownChanged: if (panelShown) rotationIndex = 0

    // Surface tokens exposed so the offscreen preview harness can reproduce the
    // panel card without importing the Theme singleton itself.
    readonly property color surfaceBackdrop: Theme.bgBase
    readonly property color surfaceBackground: Theme.popups.background
    readonly property color surfaceBorder: Theme.popups.border
    readonly property int surfacePadding: Theme.popupPadding
    readonly property int surfaceRadius: Theme.radiusLg
    // Role tokens exposed for the offscreen probes so they can assert a colour
    // equality without importing the Theme singleton.
    readonly property color tokenTextSecondary: Theme.textSecondary
    readonly property color tokenWarning: Theme.warning

    anchors.fill: parent
    implicitHeight: body.implicitHeight

    readonly property var accounts: agentsWidget ? agentsWidget.visibleAgents : []
    // Fail-closed: a missing/unknown widget mode resolves to the remaining
    // default. AgentUsage is the one normalization point, so the rendered
    // number and the meter fill can never disagree.
    readonly property string percentMode: AgentUsage.normalizePercentMode(
        agentsWidget ? agentsWidget.percentMode : "remaining")
    readonly property var rows: AgentUsage.matrixRows(accounts, nowMs, percentMode)
    readonly property bool showBalance: AgentUsage.anyBalance(accounts)
    readonly property bool refreshing: !!(agentsWidget && agentsWidget.refreshing === true)

    // Single source of truth for the matrix column geometry. The header and
    // every account row use these exact widths, so no row can compute its own
    // column boundaries from its own (varying) cell content.
    readonly property int matrixAccountRequestedWidth: 160
    readonly property int matrixAccountMinWidth: 56
    readonly property int matrixTodayWidth: 56
    readonly property int matrixBalanceWidth: 66
    readonly property int matrixMinWindowWidth: 44
    readonly property int matrixRowMargin: Theme.spacingSm
    readonly property int matrixColumnSpacing: Theme.spacingSm
    readonly property int matrixWindowCount: AgentUsage.canonicalWindowOrder().length
    readonly property real matrixContentWidth: Math.max(0, matrixBlock.width - matrixRowMargin * 2)
    // The action cluster belongs to the detail card; Refresh lives in the
    // always-present header so it is reachable in every state, while Close
    // collapses the detail and is offered only while an account is expanded.
    // Targets are ordered top-to-bottom so entering the region lands on
    // Refresh rather than on an absent Close.
    readonly property var actionTargets: hasSelection ? ["refresh", "close"] : ["refresh"]

    // Windows get the shared width that remains after the fixed columns and
    // spacing. When even the minimum window width cannot fit, the ACCOUNT
    // column shrinks first; the window width never varies per row.
    function matrixWindowWidthForAccountWidth(accountWidth) {
        if (matrixWindowCount <= 0) return 0
        var items = 2 + matrixWindowCount + (showBalance ? 1 : 0)
        var spacingCount = Math.max(0, items - 1)
        var fixed = accountWidth + matrixTodayWidth +
            (showBalance ? matrixBalanceWidth : 0) +
            matrixColumnSpacing * spacingCount
        var available = matrixContentWidth - fixed
        if (available <= 0) return 0
        return Math.floor(available / matrixWindowCount)
    }

    readonly property int matrixAccountWidth: {
        if (matrixWindowWidthForAccountWidth(matrixAccountRequestedWidth) >= matrixMinWindowWidth)
            return matrixAccountRequestedWidth
        var items = 2 + matrixWindowCount + (showBalance ? 1 : 0)
        var spacingCount = Math.max(0, items - 1)
        var fixedWithoutAccount = matrixTodayWidth +
            (showBalance ? matrixBalanceWidth : 0) +
            matrixColumnSpacing * spacingCount
        var roomForAccount = matrixContentWidth - fixedWithoutAccount -
            matrixMinWindowWidth * matrixWindowCount
        return Math.max(matrixAccountMinWidth,
            Math.min(matrixAccountRequestedWidth, Math.floor(roomForAccount)))
    }

    readonly property int matrixWindowColumnWidth:
        matrixWindowWidthForAccountWidth(matrixAccountWidth)
    readonly property int selectedIndex: {
        // The -1 fallback index is the explicit "nothing selected" sentinel;
        // reconcileSelection() would otherwise clamp it to the first row.
        if (String(selectedAccountId) === "" && selectedFallbackIndex < 0) return -1
        return AgentUsage.reconcileSelection(selectedAccountId, selectedFallbackIndex, rows)
    }
    readonly property var selectedRow: selectedIndex >= 0 && selectedIndex < rows.length
        ? rows[selectedIndex] : null
    readonly property var selectedRecord: selectedRow ? selectedRow.record : null
    readonly property bool hasSelection: selectedRow !== null
    readonly property var stateInfo: AgentUsage.providerState(selectedRecord, nowMs, {
        loading: agentsWidget ? !agentsWidget.loaded : false,
        backendError: agentsWidget ? agentsWidget.lastError : "",
        staleMs: staleMs
    })
    // The number of accounts whose headline severity is critical. The header
    // chip is shown only when it is greater than zero.
    readonly property int blockedCount: AgentUsage.blockedCount(rows)
    // Header freshness spans every account, not just the selected one, so the
    // resting consolidated matrix never says "Freshness unknown".
    readonly property var overallFreshness: AgentUsage.overallFreshnessPill(accounts, nowMs, staleMs)
    // The single footer hint. Its priority decides what the action row shows;
    // the idle rotation is the only case the timer advances.
    readonly property var footerHint: AgentUsage.footerHint({
        stale: overallFreshness.stale,
        ageText: overallFreshness.stale ? overallFreshness.ageText : "",
        keyboard: cursorActive,
        hoverColumn: hoverColumn,
        hoverRow: hoverRow,
        hoverAccount: hoverRow >= 0 && hoverRow < rows.length ? rows[hoverRow].name : "",
        rowSelected: selectedIndex === hoverRow,
        idleIndex: rotationIndex
    })
    readonly property var limitDetails: AgentUsage.limitDetailRows(selectedRecord, nowMs, percentMode)
    readonly property var today: AgentUsage.todayUsage(selectedRecord)
    readonly property var freshness: AgentUsage.freshnessPill(selectedRecord, nowMs, staleMs)
    readonly property var todayModelRows: AgentUsage.todayModels(selectedRecord, 4)
    readonly property var allTimeModelRows: AgentUsage.modelRows(selectedRecord, 4)
    readonly property var weekBars: AgentUsage.dayChartBars(
        selectedRecord ? selectedRecord.recentDays : [], 56)
    readonly property bool hasSubscription: !!(selectedRecord && selectedRecord.subscription)
    // ACCOUNT DETAILS disclosure state. It is held in memory per shell session,
    // keyed by account id, and deliberately NOT persisted: an absent key means
    // COLLAPSED, and a persisted "expanded" flag would make sensitive identity
    // reappear after a restart without a deliberate action. It would also be
    // the plugin's first persisted UI state for no concrete need (YAGNI).
    property var accountDetailsExpanded: ({})
    readonly property string accountDetailsKey: String(
        (selectedRecord && selectedRecord.id) || "")
    readonly property bool accountExpanded:
        accountDetailsExpanded[accountDetailsKey] === true
    readonly property var accountDetailState: AgentUsage.accountDetails(selectedRecord)
    readonly property var accountDetailRows: accountDetailState.rows
    readonly property bool bannerVisible: stateInfo.key === "unknown" ||
        stateInfo.key === "error" || stateInfo.key === "rate-limited"
    // The detail pane is capped so the pinned header, matrix and action row
    // plus the detail always fit the card.
    readonly property real maxDetailHeight: Math.max(0,
        maxHeight - headerRow.implicitHeight - matrixBlock.implicitHeight
        - actionRow.implicitHeight - body.spacing * 3)

    function sectionColor(severity) {
        if (severity === "critical") return Theme.error
        if (severity === "warn") return Theme.warning
        return Theme.text
    }

    // Map an AgentUsage status/dot tone role to a Theme token. It never invents
    // a colour: "neutral" is the secondary text token, never a dimmed text.
    function toneColor(tone) {
        if (tone === "error") return Theme.error
        if (tone === "warning") return Theme.warning
        if (tone === "success") return Theme.success
        return Theme.textSecondary
    }

    function visibleRegions() {
        var regions = []
        if (rows.length > 0) regions.push("matrix")
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
        } else if (focusRegion === "actions") {
            focusRow = Math.max(0, Math.min(Math.max(0, actionTargets.length - 1), focusRow))
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
        focusRow = focusRegion === "actions"
            ? Math.max(0, actionTargets.indexOf("refresh")) : 0
        cursorActive = true
        Qt.callLater(ensureFocusVisible)
    }

    // True when the named action in the always-present action row owns the
    // keyboard cursor.
    function actionFocus(name) {
        return dashboard.cursorActive && dashboard.focusRegion === "actions" &&
            dashboard.actionTargets[dashboard.focusRow] === name
    }

    // Pointer interaction never creates, moves or retains the keyboard cursor.
    // Every pointer entry point clears it so the focus ring disappears the
    // moment the user reaches for the mouse; only real key handlers set it. It
    // also clears the hover state and dismisses the shared inline tooltip.
    function notePointerInteraction() {
        cursorActive = false
        hoverRow = -1
        hoverColumn = ""
        if (panelToolTip) panelToolTip.dismiss()
    }

    function selectAccountByPointer(index) {
        notePointerInteraction()
        selectAccount(index)
    }

    function clearSelectionByPointer() {
        notePointerInteraction()
        clearSelection()
    }

    function refreshByPointer() {
        notePointerInteraction()
        refreshNow(true)
    }

    function selectAccount(index) {
        if (rows.length === 0) return
        var next = ((index % rows.length) + rows.length) % rows.length
        if (hasSelection && selectedIndex === next) {
            clearSelection()
            return
        }
        selectedFallbackIndex = next
        selectedAccountId = rows[next].id
        if (focusRegion === "matrix") focusRow = next
        Qt.callLater(ensureFocusVisible)
    }

    // Collapse the extended detail back to the consolidated matrix. This is
    // the sole behaviour shared by the close control and re-clicking the
    // selected row; it never closes the panel.
    function clearSelection() {
        if (!hasSelection) return
        selectedAccountId = ""
        selectedFallbackIndex = -1
        detailItems = []
        if (focusRegion === "detail") focusRegion = "matrix"
        clampFocus()
    }

    // Toggle the per-account disclosure. The expanded map is replaced (never
    // mutated in place) so QML re-evaluates the binding, and only the selected
    // account's key is touched, so switching accounts keeps each disclosure's
    // own state for the rest of the shell session.
    function toggleAccountDetails() {
        var key = accountDetailsKey
        if (key === "") return
        var next = {}
        for (var existing in accountDetailsExpanded) {
            next[existing] = accountDetailsExpanded[existing]
        }
        next[key] = !accountExpanded
        accountDetailsExpanded = next
    }

    function toggleAccountDetailsByPointer() {
        notePointerInteraction()
        toggleAccountDetails()
    }

    function switchAccount(delta) {
        if (focusRegion === "actions") {
            moveRow(delta)
            return
        }
        if (rows.length <= 1) return
        cursorActive = true
        selectAccount((selectedIndex < 0 ? 0 : selectedIndex) + delta)
    }

    function moveRow(delta) {
        if (focusRegion === "actions") {
            focusRow = Math.max(0, Math.min(actionTargets.length - 1, focusRow + delta))
            cursorActive = true
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
        // Enter/Space is a real key handler: the keyboard cursor is established
        // here exactly as it is for the motion keys.
        cursorActive = true
        if (focusRegion === "matrix") {
            selectAccount(focusRow)
        } else if (focusRegion === "actions") {
            if (actionTargets[focusRow] === "close") clearSelection()
            else refreshNow(true)
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
        // Any key hides the shared inline tooltip as well as moving the cursor.
        if (panelToolTip) panelToolTip.dismiss()
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

    onRowsChanged: {
        if (selectedAccountId === "" && selectedFallbackIndex < 0) {
            clampFocus()
            emitDiagnostics()
            return
        }
        var index = AgentUsage.reconcileSelection(selectedAccountId, selectedFallbackIndex, rows)
        if (index < 0) {
            selectedAccountId = ""
            selectedFallbackIndex = -1
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
        // The ACCOUNT DETAILS disclosure is a persistent static child (unlike
        // the Repeater's limit rows, which re-register when they are
        // recreated), so re-register it after the selection reset keeps it
        // reachable through the existing Enter/Space focus path.
        if (accountDetailsHeader) registerDetailItem(accountDetailsHeader)
        if (!hasSelection && focusRegion === "detail") focusRegion = "matrix"
        clampFocus()
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
        font.family: Theme.fontFamilyResolved
    }

    // Numeric cells right-align by default so percentages line up column-wise.
    component NumericLabel: Label {
        horizontalAlignment: Text.AlignRight
        font.weight: Theme.fontWeightMedium
    }

    component SectionHeader: Label {
        Layout.fillWidth: true
        topPadding: Theme.spacingXs
        color: Theme.textSecondary
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

    // max(6, spacingXs + 2) px meter on a translucent-safe track with a 1 px
    // outline, a full-opacity 2 px pace marker and a 4 px halo backing it.
    component Meter: Item {
        id: meter
        property real value: -1
        property real marker: -1
        property bool alarming: false
        property bool deEmphasised: false
        property color markerColor: Theme.text

        Layout.fillWidth: true
        implicitHeight: Math.max(6, Theme.spacingXs + 2)

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
            color: meter.deEmphasised ? Theme.textMuted
                : (meter.alarming ? Theme.error : Theme.accent)
            objectName: "meterFill"

            Behavior on width {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
        }

        // A 4 px halo behind the marker keeps it legible over the fill and the
        // track. The marker itself is full opacity in every state.
        Rectangle {
            visible: meter.marker >= 0
            x: Math.round(parent.width * AgentUsage.clamp(meter.marker, 0, 1)) - width / 2
            width: 4
            height: parent.height + 6
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.popups.background
        }

        Rectangle {
            visible: meter.marker >= 0
            x: Math.round(parent.width * AgentUsage.clamp(meter.marker, 0, 1)) - width / 2
            width: 2
            height: parent.height + 6
            anchors.verticalCenter: parent.verticalCenter
            color: meter.markerColor
        }
    }

    // One canonical window cell: right-aligned percent, non-colour severity
    // glyph, meter with pace marker, muted relative countdown and the pace
    // word. The absolute reset time stays out of the grid and is exposed only
    // through the cell tooltip.
    component MatrixCell: ColumnLayout {
        id: matrixCell
        property var cell: null
        property var record: null
        property string columnClass: ""
        property int rowIndex: -1
        // True when the provider declared that it does not offer this canonical
        // window. That is a non-problem: it renders a distinct muted marker and
        // a "not offered" tooltip, and never emits an unmet-condition
        // diagnostic. A supported window that was not reported keeps the plain
        // `—` and does emit one.
        property bool notOffered: false
        readonly property bool isBinding: cell ? cell.isBinding === true : false
        readonly property bool muted: cell ? cell.muted === true : false
        readonly property bool alertCell: cell
            ? AgentUsage.isAlertSeverity(cell.severity) : false
        readonly property string markerText: AgentUsage.matrixCellMarker(cell, notOffered)
        // De-emphasis is a TOKEN choice, never an opacity: the percentage and
        // meta use Theme.textSecondary and the meter fill uses Theme.textMuted.
        readonly property bool deEmphasised: cell === null || notOffered || muted
        readonly property string metaText: {
            if (notOffered) return "Not offered"
            if (cell === null) return " "
            if (muted) return "not limiting"
            return cell.countdown !== "" ? cell.countdown : " "
        }

        objectName: "matrixCell-" + rowIndex + "-" + columnClass
        Layout.preferredWidth: dashboard.matrixWindowColumnWidth
        Layout.minimumWidth: dashboard.matrixWindowColumnWidth
        Layout.maximumWidth: dashboard.matrixWindowColumnWidth
        Layout.fillWidth: false
        spacing: 1
        // Opacity is 1.0 in EVERY state: no text in the dashboard is ever
        // dimmed. The token choice above carries the de-emphasis instead.
        opacity: 1.0
        Accessible.role: Accessible.StaticText
        Accessible.name: AgentUsage.matrixCellAccessibility(
            cell, columnClass, notOffered, dashboard.percentMode, record,
            dashboard.nowMs, -new Date().getTimezoneOffset())

        function percentColor() {
            if (matrixCell.deEmphasised) return Theme.textSecondary
            return dashboard.sectionColor(matrixCell.cell.severity)
        }

        // Percentage line: the severity glyph sits immediately left of the
        // number, right-aligned so the number's right edge is exactly the
        // shared column boundary. A plain Row anchored right (rather than a
        // layout-managed RowLayout) lets the row overflow to the LEFT when the
        // glyph does not fit at a narrow width, so the number's right edge can
        // never move and the number can never elide.
        Item {
            Layout.fillWidth: true
            implicitHeight: percentRow.implicitHeight

            Row {
                id: percentRow
                anchors.right: parent.right
                spacing: Theme.spacingXs

                Label {
                    text: matrixCell.cell ? matrixCell.cell.glyph : ""
                    color: dashboard.sectionColor(matrixCell.cell ? matrixCell.cell.severity : "ok")
                    font.pixelSize: Theme.fontSizeXs
                    visible: text !== ""
                }

                NumericLabel {
                    objectName: "matrixPercent-" + matrixCell.rowIndex + "-" + matrixCell.columnClass
                    text: matrixCell.markerText
                    color: matrixCell.percentColor()
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Theme.fontWeightMedium
                }
            }
        }

        // The meter slot is always present so every row keeps the same height.
        // A not-offered column shows a 1 px dashed border line instead of a
        // track; a no-live-limit cell leaves the track empty (value -1) rather
        // than fabricating a 0% fill.
        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(6, Theme.spacingXs + 2)

            Meter {
                objectName: "matrixMeter-" + matrixCell.rowIndex + "-" + matrixCell.columnClass
                anchors.fill: parent
                visible: !matrixCell.notOffered
                value: matrixCell.cell ? matrixCell.cell.percent : -1
                marker: matrixCell.cell && !matrixCell.muted ? matrixCell.cell.elapsed : -1
                alarming: matrixCell.cell && matrixCell.cell.severity === "critical"
                deEmphasised: matrixCell.muted
                markerColor: matrixCell.cell && matrixCell.cell.meaningfullyFast === true
                    ? Theme.warning : Theme.text
            }

            Shape {
                id: notOfferedLine
                visible: matrixCell.notOffered
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1

                ShapePath {
                    strokeColor: Theme.border
                    strokeWidth: 1
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [1, 3]
                    startX: 0
                    startY: 0.5
                    PathLine { x: notOfferedLine.width; y: 0.5 }
                }
            }
        }

        // Meta line: the countdown only (or `not limiting` / `Not offered`).
        // The matrix no longer prints pace words.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXs
            visible: true

            Label {
                Layout.fillWidth: true
                text: matrixCell.metaText
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSm
                elide: Text.ElideRight
                horizontalAlignment: matrixCell.notOffered ? Text.AlignRight : Text.AlignLeft
            }
        }

        HoverHandler {
            id: cellHover
            onHoveredChanged: {
                if (hovered) {
                    dashboard.hoverColumn = matrixCell.columnClass
                    dashboard.hoverRow = matrixCell.rowIndex
                    panelToolTip.triggerItem = matrixCell
                    panelToolTip.lines = AgentUsage.cellTooltipLines(
                        matrixCell.cell, matrixCell.columnClass, matrixCell.notOffered,
                        dashboard.percentMode, matrixCell.record, dashboard.nowMs,
                        -new Date().getTimezoneOffset())
                    panelToolTip.hovered = true
                } else {
                    if (dashboard.hoverColumn === matrixCell.columnClass)
                        dashboard.hoverColumn = ""
                    panelToolTip.hovered = false
                    panelToolTip.triggerItem = null
                    panelToolTip.lines = []
                }
            }
        }
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
        // The row's own severity, exposed for the measured alignment probe so a
        // test can assert that alert rows keep effective opacity 1.0.
        readonly property string rowSeverity: limitRow.detail
            ? String(limitRow.detail.severity) : "unknown"
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
            objectName: "limitDetailRow-" + limitRow.rowIndex
            property string severity: limitRow.rowSeverity
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
                        objectName: "limitBindingTag"
                        visible: limitRow.detail && limitRow.detail.isBinding === true
                        text: "Binding"
                        color: dashboard.sectionColor(limitRow.detail ? limitRow.detail.severity : "ok")
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                    }

                    Label {
                        objectName: "limitDetailGlyph-" + limitRow.rowIndex
                        text: limitRow.detail ? limitRow.detail.glyph : ""
                        color: dashboard.sectionColor(limitRow.detail ? limitRow.detail.severity : "ok")
                        font.pixelSize: Theme.fontSizeSm
                        visible: text !== ""
                    }

                    NumericLabel {
                        objectName: "limitDetailPercent-" + limitRow.rowIndex
                        text: limitRow.detail ? limitRow.detail.percentText : "—"
                        color: limitRow.detail
                            ? dashboard.sectionColor(limitRow.detail.severity) : Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSm
                    }
                }

                Meter {
                    objectName: "limitDetailMeter-" + limitRow.rowIndex
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
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeXs
                        elide: Text.ElideRight
                    }

                    Label {
                        visible: limitRow.detail && limitRow.detail.paceWord !== ""
                        text: limitRow.detail ? limitRow.detail.paceWord : ""
                        color: limitRow.detail && limitRow.detail.paceWord === "faster than pace"
                            ? Theme.warning : Theme.textSecondary
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
            color: Theme.textSecondary
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
                        color: dayColumn.today ? Theme.text : Theme.textSecondary
                        font.pixelSize: Theme.fontSizeXs
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Label {
                        width: parent.width
                        text: AgentUsage.dayLabel(dayColumn.modelData.date, dayColumn.today)
                        color: dayColumn.today ? Theme.text : Theme.textSecondary
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

        // HEADER (pinned): icon tile, title, quota legend + account-wide
        // freshness, a blocked count chip and Refresh. Refresh lives here so it
        // is reachable in EVERY state; Close stays in the action row below.
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            // Icon tile: 32x32, never changes with usage.
            Rectangle {
                objectName: "agentsHeaderTile"
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: Theme.radiusMd
                color: Theme.controls.normalFill
                border.width: Theme.borderWidthDefault
                border.color: Theme.border

                AureliaIcon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    glyph: "󰚩"
                    iconSize: Theme.fontSizeLg + 3
                    tint: Theme.text
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    text: "AI Usage"
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Theme.fontWeightBold
                }

                RowLayout {
                    spacing: Theme.spacingXs

                    // The single legend that makes a bare percentage unambiguous.
                    Label {
                        objectName: "agentsModeChip"
                        text: dashboard.percentMode === "used"
                            ? "Quota used ·" : "Quota remaining ·"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSm
                    }

                    // Freshness is signalled here, in the warning colour when
                    // stale. It is never signalled by dimming any text.
                    Label {
                        objectName: "agentsFreshnessLabel"
                        Layout.fillWidth: true
                        text: dashboard.overallFreshness.text
                        color: dashboard.overallFreshness.stale
                            ? Theme.warning : Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSm
                        elide: Text.ElideRight
                    }
                }
            }

            // Blocked chip: shown only when at least one account is blocked.
            Rectangle {
                objectName: "agentsBlockedChip"
                visible: dashboard.blockedCount > 0
                Layout.preferredWidth: blockedChipRow.implicitWidth + Theme.spacingSm * 2
                Layout.preferredHeight: blockedChipRow.implicitHeight + Theme.spacingXs
                radius: height / 2
                color: "transparent"
                border.width: Theme.borderWidthDefault
                border.color: Theme.border

                RowLayout {
                    id: blockedChipRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXs

                    Rectangle {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: Theme.error
                    }

                    Label {
                        text: dashboard.blockedCount + " blocked"
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSm
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: headerRefreshButton.implicitWidth
                Layout.preferredHeight: headerRefreshButton.implicitHeight
                radius: Theme.radiusSm
                color: "transparent"

                AureliaIconButton {
                    id: headerRefreshButton
                    objectName: "agentsRefreshButton"
                    anchors.centerIn: parent
                    icon: "view-refresh"
                    tooltip: dashboard.refreshing ? "Refreshing usage…" : "Refresh usage"
                    active: dashboard.refreshing
                    enabled: !dashboard.refreshing
                    // The ring is the dashboard's keyboard cursor, not Qt focus.
                    keyboardFocus: dashboard.actionFocus("refresh")
                    onTriggered: dashboard.refreshByPointer()
                }
            }
        }

        // MATRIX (pinned).
        ColumnLayout {
            id: matrixBlock
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                id: matrixHeader
                Layout.fillWidth: true
                Layout.leftMargin: dashboard.matrixRowMargin
                Layout.rightMargin: dashboard.matrixRowMargin
                Layout.bottomMargin: Theme.spacingXs
                spacing: dashboard.matrixColumnSpacing

                Label {
                    objectName: "matrixAccountHeader"
                    Layout.preferredWidth: dashboard.matrixAccountWidth
                    Layout.minimumWidth: dashboard.matrixAccountWidth
                    Layout.maximumWidth: dashboard.matrixAccountWidth
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignBottom
                    text: "ACCOUNT"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightBold
                    font.letterSpacing: 1
                }

                Repeater {
                    model: AgentUsage.canonicalWindowOrder()

                    delegate: Label {
                        id: columnHeader
                        required property string modelData
                        objectName: "matrixHeader-" + modelData
                        Layout.preferredWidth: dashboard.matrixWindowColumnWidth
                        Layout.minimumWidth: dashboard.matrixWindowColumnWidth
                        Layout.maximumWidth: dashboard.matrixWindowColumnWidth
                        Layout.fillWidth: false
                        Layout.alignment: Qt.AlignBottom
                        text: AgentUsage.windowColumnLabel(modelData)
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                        font.letterSpacing: 1
                        // Right edge matches the right-aligned percentage and
                        // the right end of the meter it labels.
                        horizontalAlignment: Text.AlignRight

                        HoverHandler {
                            id: headerHover
                            onHoveredChanged: {
                                if (hovered) {
                                    dashboard.hoverColumn = columnHeader.modelData
                                    panelToolTip.triggerItem = columnHeader
                                    panelToolTip.lines = [{
                                        text: AgentUsage.windowDescription(columnHeader.modelData),
                                        tone: "default",
                                        strong: false
                                    }]
                                    panelToolTip.hovered = true
                                } else {
                                    if (dashboard.hoverColumn === columnHeader.modelData)
                                        dashboard.hoverColumn = ""
                                    panelToolTip.hovered = false
                                    panelToolTip.triggerItem = null
                                    panelToolTip.lines = []
                                }
                            }
                        }
                    }
                }

                // TODAY becomes two lines: the label and its unit. The unit
                // lives in the header, so no per-row cell repeats it.
                ColumnLayout {
                    Layout.preferredWidth: dashboard.matrixTodayWidth
                    Layout.minimumWidth: dashboard.matrixTodayWidth
                    Layout.maximumWidth: dashboard.matrixTodayWidth
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignBottom
                    spacing: 0

                    Label {
                        Layout.fillWidth: true
                        text: "TODAY"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                        font.letterSpacing: 1
                        horizontalAlignment: Text.AlignRight
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "tokens"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightNormal
                        horizontalAlignment: Text.AlignRight
                    }
                }

                Label {
                    Layout.preferredWidth: dashboard.matrixBalanceWidth
                    Layout.minimumWidth: dashboard.matrixBalanceWidth
                    Layout.maximumWidth: dashboard.matrixBalanceWidth
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignBottom
                    visible: dashboard.showBalance
                    text: AgentUsage.balanceHeader(dashboard.accounts)
                    color: Theme.textSecondary
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
                    Layout.bottomMargin: matrixRow.index < dashboard.rows.length - 1 ? 2 : 0
                    spacing: 0

                    readonly property bool rowFocused: dashboard.cursorActive &&
                        dashboard.focusRegion === "matrix" && dashboard.focusRow === index

                    Rectangle {
                        id: matrixRowRect
                        objectName: "matrixRowRect-" + matrixRow.index
                        Layout.fillWidth: true
                        implicitHeight: matrixRowContent.implicitHeight + Theme.spacingSm * 2
                        radius: Theme.radiusMd
                        // Fill priority: selected, then hovered, then transparent.
                        color: index === dashboard.selectedIndex
                            ? Theme.controls.selectedFill
                            : (rowHover.hovered ? Theme.controls.hoverFill : "transparent")
                        border.width: matrixRow.rowFocused ? Theme.borderWidthFocus : 0
                        border.color: Theme.controls.focusBorder

                        HoverHandler {
                            id: rowHover
                            onHoveredChanged: {
                                if (hovered) dashboard.hoverRow = matrixRow.index
                                else if (dashboard.hoverRow === matrixRow.index)
                                    dashboard.hoverRow = -1
                            }
                        }

                        // Blocked stripe: a 3 px error bar inset from the row's
                        // top and bottom. No background tint.
                        Rectangle {
                            objectName: "matrixBlockedStripe-" + matrixRow.index
                            visible: matrixRow.modelData.headlineSeverity === "critical"
                            width: 3
                            radius: 1.5
                            color: Theme.error
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.topMargin: Theme.spacingMd
                            anchors.bottomMargin: Theme.spacingMd
                        }

                        RowLayout {
                            id: matrixRowContent
                            // Match the header's layout box exactly so the
                            // shared column boundary is pixel-identical.
                            x: matrixHeader.x
                            width: matrixHeader.width
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: dashboard.matrixColumnSpacing

                            ColumnLayout {
                                id: matrixAccountCell
                                objectName: "matrixAccountCell-" + matrixRow.index
                                Layout.preferredWidth: dashboard.matrixAccountWidth
                                Layout.minimumWidth: dashboard.matrixAccountWidth
                                Layout.maximumWidth: dashboard.matrixAccountWidth
                                Layout.fillWidth: false
                                spacing: 0

                                readonly property var status: AgentUsage.accountStatus(
                                    matrixRow.modelData, dashboard.nowMs)

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSm

                                    Rectangle {
                                        Layout.preferredWidth: 8
                                        Layout.preferredHeight: 8
                                        radius: 4
                                        Layout.alignment: Qt.AlignVCenter
                                        color: dashboard.toneColor(matrixAccountCell.status.dotTone)
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: matrixRow.modelData.name
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: Theme.fontWeightMedium
                                        elide: Text.ElideRight
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    // Indent the status to the name's x.
                                    Layout.leftMargin: 8 + Theme.spacingSm
                                    objectName: "matrixHeadline-" + matrixRow.index
                                    // Always present with a space fallback so
                                    // the status never changes the row height.
                                    text: matrixAccountCell.status.text !== ""
                                        ? matrixAccountCell.status.text : " "
                                    color: dashboard.toneColor(matrixAccountCell.status.tone)
                                    font.pixelSize: Theme.fontSizeSm
                                    elide: Text.ElideRight
                                }
                            }

                            Repeater {
                                model: AgentUsage.canonicalWindowOrder()

                                delegate: MatrixCell {
                                    required property string modelData
                                    required property int index
                                    columnClass: modelData
                                    rowIndex: matrixRow.index
                                    cell: matrixRow.modelData.windows[modelData]
                                    notOffered: matrixRow.modelData.notOffered[modelData] === true
                                    record: matrixRow.modelData.record
                                }
                            }

                            NumericLabel {
                                Layout.preferredWidth: dashboard.matrixTodayWidth
                                Layout.minimumWidth: dashboard.matrixTodayWidth
                                Layout.maximumWidth: dashboard.matrixTodayWidth
                                Layout.fillWidth: false
                                text: matrixRow.modelData.todayTokens
                                color: matrixRow.modelData.todayTokens === "0"
                                    ? Theme.textSecondary : Theme.text
                                font.pixelSize: Theme.fontSizeMd
                                font.weight: matrixRow.modelData.todayTokens === "0"
                                    ? Theme.fontWeightNormal : Theme.fontWeightMedium
                            }

                            NumericLabel {
                                Layout.preferredWidth: dashboard.matrixBalanceWidth
                                Layout.minimumWidth: dashboard.matrixBalanceWidth
                                Layout.maximumWidth: dashboard.matrixBalanceWidth
                                Layout.fillWidth: false
                                visible: dashboard.showBalance
                                text: matrixRow.modelData.balance !== ""
                                    ? matrixRow.modelData.balance : "—"
                                color: matrixRow.modelData.balance === ""
                                    ? Theme.textSecondary : Theme.text
                                font.pixelSize: Theme.fontSizeMd
                                font.weight: matrixRow.modelData.balance === ""
                                    ? Theme.fontWeightNormal : Theme.fontWeightMedium
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: dashboard.notePointerInteraction()
                            onClicked: dashboard.selectAccountByPointer(matrixRow.index)
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingMd
                visible: dashboard.rows.length === 0
                text: "No AI coding subscriptions found."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSm
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // ACTIONS (pinned): the footer hint line, its pager and the Close
        // control. Refresh is in the header above and is always reachable.
        // Close is offered only while an account is expanded.
        RowLayout {
            id: actionRow
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            // Hovering the footer pauses the idle rotation.
            HoverHandler { id: footerHover }

            // The hint's resting opacity is 1.0. Only the idle rotation
            // cross-fades it (200 ms, ending at 1.0).
            RowLayout {
                id: footerHintRow
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                opacity: 1.0

                Label {
                    objectName: "agentsFooterHint"
                    visible: dashboard.footerHint.kind === "text"
                    Layout.fillWidth: true
                    text: dashboard.footerHint.kind === "text" ? dashboard.footerHint.text : ""
                    color: dashboard.footerHint.tone === "warning"
                        ? Theme.warning : Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSm
                    elide: Text.ElideRight
                }

                // Key-cap renderer.
                Row {
                    visible: dashboard.footerHint.kind === "keys"
                    spacing: Theme.spacingSm

                    Repeater {
                        model: ["↑↓ select", "↵ details", "R refresh", "Esc close"]

                        delegate: Rectangle {
                            required property string modelData
                            implicitWidth: keyCap.implicitWidth + Theme.spacingSm * 2
                            implicitHeight: keyCap.implicitHeight + 2
                            radius: Theme.radiusSm
                            color: "transparent"
                            border.width: Theme.borderWidthDefault
                            border.color: Theme.border

                            Label {
                                id: keyCap
                                anchors.centerIn: parent
                                text: modelData
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeXs
                            }
                        }
                    }
                }

                // Pace legend renderer, built from the real Meter component.
                Row {
                    visible: dashboard.footerHint.kind === "legend"
                    spacing: Theme.spacingLg

                    Row {
                        spacing: Theme.spacingXs

                        Meter {
                            width: 22
                            height: 4
                            value: 0.5
                            marker: 0.5
                        }

                        Label {
                            text: "even pace"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }

                    Row {
                        spacing: Theme.spacingXs

                        Meter {
                            width: 22
                            height: 4
                            value: 0.5
                            marker: 0.5
                            markerColor: Theme.warning
                        }

                        Label {
                            text: "using faster than pace"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeXs
                        }
                    }
                }
            }

            // Pager: three dots, the active one a 14 x 5 pill. Only the idle
            // rotation shows it; clicking steps through the tips.
            Row {
                objectName: "agentsFooterPager"
                visible: dashboard.footerHint.priority === 5
                spacing: Theme.spacingXs

                Repeater {
                    model: 3

                    delegate: Rectangle {
                        required property int index
                        width: index === dashboard.rotationIndex ? 14 : 5
                        height: 5
                        radius: height / 2
                        color: index === dashboard.rotationIndex
                            ? Theme.textSecondary : Theme.border
                    }
                }

                TapHandler {
                    onTapped: dashboard.rotationIndex = (dashboard.rotationIndex + 1) % 3
                }
            }

            Rectangle {
                Layout.preferredWidth: closeButton.implicitWidth
                Layout.preferredHeight: closeButton.implicitHeight
                visible: dashboard.hasSelection
                radius: Theme.radiusSm
                color: "transparent"

                AureliaIconButton {
                    id: closeButton
                    objectName: "agentsCloseButton"
                    anchors.centerIn: parent
                    icon: "window-close"
                    tooltip: "Collapse account details"
                    // The ring is the dashboard's keyboard cursor, not Qt focus.
                    keyboardFocus: dashboard.actionFocus("close")
                    onTriggered: dashboard.clearSelectionByPointer()
                }
            }
        }

        // DETAIL (the only scrolling region), present only once an account is
        // expanded so the consolidated matrix is the clean default state.
        Item {
            id: detailWrapper
            objectName: "agentsDetailPane"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: detailFlick.implicitHeight
            visible: dashboard.hasSelection

            Flickable {
                id: detailFlick
                anchors.fill: parent
                implicitHeight: Math.min(detailColumn.implicitHeight, dashboard.maxDetailHeight)
                contentWidth: width
                contentHeight: detailColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: detailColumn
                    width: detailFlick.width
                    spacing: Theme.spacingMd

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
                                    onTriggered: dashboard.refreshByPointer()
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: dashboard.stateInfo.help !== ""
                                text: dashboard.stateInfo.help
                                color: Theme.textSecondary
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
                        // A stale account in an alert state keeps the whole
                        // detail pane at full strength; a stale non-alert
                        // account de-emphasises its informational sections.
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
                                color: Theme.textSecondary
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
                            color: Theme.textSecondary
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
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSm
                            }
                        }
                    }

                    // ACCOUNT DETAILS: the LAST child of the scrolling detail
                    // column (after SUBSCRIPTION), so it can never become a
                    // pinned region. Collapsed by default; it shows nothing
                    // but the disclosure header until the user expands it.
                    // Identity is private: it is displayed only here, never in
                    // the runtime log, a diagnostic, the bar tooltip or a
                    // notification.
                    ColumnLayout {
                        id: accountDetailsSection
                        objectName: "accountDetailsSection"
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm

                        Rectangle {
                            id: accountDetailsHeader
                            objectName: "accountDetailsHeader"
                            Layout.fillWidth: true
                            implicitHeight: Math.max(Theme.spacingXxl,
                                accountHeaderRow.implicitHeight + Theme.spacingSm)
                            radius: Theme.radiusSm
                            color: "transparent"
                            border.width: dashboard.cursorActive &&
                                dashboard.focusRegion === "detail" &&
                                dashboard.detailItems[dashboard.focusRow] === accountDetailsHeader
                                ? Theme.borderWidthFocus : 0
                            border.color: Theme.controls.focusBorder

                            Accessible.role: Accessible.Button
                            // Never interpolate a value here: the accessible
                            // name and description must stay non-sensitive.
                            Accessible.name: "Account details"
                            Accessible.description: "Shows account email, name and subscription information. Collapsed by default."
                            Accessible.checkable: true
                            Accessible.checked: dashboard.accountExpanded

                            function activate() { dashboard.toggleAccountDetails() }

                            Component.onCompleted: dashboard.registerDetailItem(accountDetailsHeader)
                            Component.onDestruction: dashboard.unregisterDetailItem(accountDetailsHeader)

                            RowLayout {
                                id: accountHeaderRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingXs
                                anchors.rightMargin: Theme.spacingXs
                                spacing: Theme.spacingXs

                                SectionHeader { text: "ACCOUNT DETAILS" }

                                // A Label, not raw Text, so the dashboard's
                                // raw_text_count <= 1 invariant holds.
                                Label {
                                    objectName: "accountDetailsChevron"
                                    text: dashboard.accountExpanded ? "⌃" : "⌄"
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSm
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: dashboard.toggleAccountDetailsByPointer()
                            }
                        }

                        // The body renders only when expanded; while collapsed
                        // the header is the whole section, with no value
                        // summary that could leak the protected identity.
                        ColumnLayout {
                            id: accountDetailsBody
                            objectName: "accountDetailsBody"
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs
                            visible: dashboard.accountExpanded

                            Repeater {
                                model: dashboard.accountDetailRows

                                delegate: RowLayout {
                                    required property var modelData
                                    required property int index
                                    objectName: "accountDetailsRow-" + index
                                    // Exposed for the offscreen probe so the
                                    // displayed rows can be measured without
                                    // walking the text nodes.
                                    property string rowLabel: modelData.label
                                    property string rowValue: modelData.value
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSm

                                    Label {
                                        text: modelData.label
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeXs
                                    }

                                    // No wrap and no tooltip: a long email
                                    // elides in the middle so the domain stays
                                    // visible, a long name elides on the right.
                                    // fillWidth (not a parent-width maximumWidth)
                                    // avoids a recursive Layout rearrange.
                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.value
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: modelData.label === "Email" ||
                                            modelData.label === "Name"
                                            ? Theme.fontWeightMedium : Theme.fontWeightNormal
                                        horizontalAlignment: Text.AlignRight
                                        elide: modelData.elide === "middle"
                                            ? Text.ElideMiddle : Text.ElideRight
                                        wrapMode: Text.NoWrap
                                    }
                                }
                            }

                            // Partial data must not look broken: when nothing
                            // is known we show one honest muted line, never
                            // three rows of "Unknown".
                            Label {
                                objectName: "accountDetailsEmpty"
                                Layout.fillWidth: true
                                visible: dashboard.accountDetailRows.length === 0
                                text: "No account details available for this provider."
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeXs
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
    }

    // Any real pointer movement over the panel drops the keyboard cursor, so a
    // ring never lingers while the user is working with the mouse. The handler
    // is passive and does not consume events or steal hover from the children.
    HoverHandler {
        id: pointerHover
        onPointChanged: if (pointerHover.hovered) dashboard.notePointerInteraction()
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

    // Idle footer rotation. The timer runs only while the panel is actually
    // shown (`panelShown`), the hint is idle (priority 5) and the footer is not
    // hovered. `panelShown` defaults to false, so an unwired fixture never
    // rotates. Any higher-priority hint takes over immediately.
    Timer {
        interval: 8000
        repeat: true
        running: dashboard.panelShown && dashboard.footerHint.priority === 5 && !footerHover.hovered
        onTriggered: footerRotateAnimation.start()
    }

    // 200 ms cross-fade: out, swap, in. It always ends at opacity 1.0.
    SequentialAnimation {
        id: footerRotateAnimation
        NumberAnimation { target: footerHintRow; property: "opacity"; to: 0; duration: 100 }
        ScriptAction { script: dashboard.rotationIndex = (dashboard.rotationIndex + 1) % 3 }
        NumberAnimation { target: footerHintRow; property: "opacity"; to: 1; duration: 100 }
    }

    // The ONE shared in-scene tooltip for the whole dashboard. It is the last
    // child so it has the highest z. There is deliberately no PopupWindow and
    // no attached ToolTip anywhere in this file.
    AureliaInlineToolTip {
        id: panelToolTip
        objectName: "panelToolTip"
    }
}
