import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../../ui"
import "../../theme"
import "Model.js" as Model
import "."
AureliaKeyboardPanel {
    id: root
    property var shell: null
    property string aureliaPath: ""
    property string backendRoot: ""
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    readonly property string sourceBinRoot: decodeURIComponent(
        String(Qt.resolvedUrl("../../bin")).replace(/^file:\/\//, "")
    )
    readonly property string resolvedBackendRoot: backendRoot !== ""
        ? backendRoot
        : (aureliaPath !== "" ? aureliaPath + "/bin" : sourceBinRoot)
    readonly property string statusBin: resolvedBackendRoot + "/aurelia-network-status"
    readonly property string bandBin: resolvedBackendRoot + "/aurelia-network-band"
    readonly property string dnsBin: resolvedBackendRoot + "/aurelia-network-dns"
    readonly property string dnsTerminalBin: resolvedBackendRoot + "/aurelia-network-dns-terminal"
    property var info: ({})
    property var wifiNetworks: []
    property bool scanning: false
    property bool wifiStationAvailable: false
    property string dnsProvider: "DHCP"
    property string dnsServers: "DHCP"
    property string pendingDnsProvider: ""
    property string dnsError: ""
    property string lastActionError: ""
    property int actionExitCode: -1
    property bool actionExitSeen: false
    property bool actionErrorStreamSeen: false
    property string bandCurrent: ""
    property string bandSelected: "auto"
    property var bandAvailable: []
    property string pendingBand: ""
    property string actionSsid: ""
    property string actionKind: ""
    property string failureSsid: ""
    property string failureReason: ""
    property string passwordSsid: ""
    property string passwordText: ""
    property string identityText: ""
    property real prevRxBytes: 0
    property real prevTxBytes: 0
    property real prevSampleTime: 0
    property string prevIface: ""
    property real downloadRate: 0
    property real uploadRate: 0
    property string pingIface: ""
    property var routerPingSamples: []
    property var internetPingSamples: []
    property real routerPingLatency: -1
    property real internetPingLatency: -1
    property int internetPingPacketLoss: 0
    property int selectedIndex: -1
    property bool wifiActionFocused: false
    property bool cursorActive: false
    property string focusSection: "dns"
    property int headerIndex: 0
    property int dnsIndex: 0
    property int bandIndex: 0
    property bool bandAutoFocused: true
    readonly property int pingHistoryWindow: 24
    readonly property int pingAverageWindow: 5
    readonly property bool hasInternetPing: internetPingSamples.length > 0
    readonly property bool hasTransferStats: info.rx_bytes !== undefined
    readonly property bool busy: actionKind !== ""
    readonly property var connectionFailReasons: ({
        NoSecrets: ConnectionFailReason.NoSecrets,
        WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
        WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
        WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
        WifiClientFailed: ConnectionFailReason.WifiClientFailed
    })
    readonly property bool networkManagerAvailable: Networking.backend === NetworkBackendType.NetworkManager
    readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDevice: findDevice(DeviceType.Wifi)
    readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks
        ? wifiDevice.networks.values : []
    readonly property var connectedWifiNetwork: findConnectedWifiNetwork()
    readonly property var wiredDevice: findDevice(DeviceType.Wired)
    readonly property string kind: {
        if (wiredDevice && wiredDevice.connected) return "ethernet"
        if (connectedWifiNetwork) return "wifi"
        return "disconnected"
    }
    readonly property int signalStrength: connectedWifiNetwork
        ? Math.round((connectedWifiNetwork.signalStrength || 0) * 100) : -1
    readonly property bool connectivityChecksEnabled: networkManagerAvailable &&
        Networking.canCheckConnectivity && Networking.connectivityCheckEnabled
    readonly property string connectivity: Model.connectivityState(kind, Networking.connectivity, {
        Portal: NetworkConnectivity.Portal,
        Limited: NetworkConnectivity.Limited,
        Full: NetworkConnectivity.Full,
        None: NetworkConnectivity.None
    }, connectivityChecksEnabled)
    readonly property bool hasCaptivePortal: connectivity === "portal"
    readonly property bool restricted: hasCaptivePortal || connectivity === "limited"
    readonly property string icon: Model.connectionIcon(kind, signalStrength, connectivity)
    readonly property string barLabel: {
        if (kind === "wifi") {
            if (connectedWifiNetwork && connectedWifiNetwork.name) return String(connectedWifiNetwork.name)
            if (info.ssid) return String(info.ssid)
            return "Wi-Fi"
        }
        if (kind === "ethernet") {
            var speed = parseInt(info.speed || "", 10)
            var speedLabel = speed > 0 ? Model.formatHeaderSpeed(speed) : ""
            return speedLabel !== "" ? "Ethernet " + speedLabel : "Ethernet"
        }
        return "Offline"
    }
    property int connectionPhraseIndex: 0
    readonly property var connectionPhrases: [
        "Wiring bits", "Handling packets", "Sorting frames", "Hauling bytes",
        "Routing crumbs", "Counting collisions", "Bending light"
    ]
    readonly property string connectionPhrase: connectionPhrases[connectionPhraseIndex % connectionPhrases.length]
    readonly property bool canToggleWifi: networkManagerAvailable && wifiStationAvailable
    readonly property bool canRunSpeedTest: !!info.iface
    readonly property bool canShareWifi: kind === "wifi" && canShareNetwork(connectedWifiNetwork)
    readonly property bool bandBusy: pendingBand !== ""
    readonly property string bandEffective: bandBusy ? pendingBand : bandSelected
    readonly property bool bandPinned: bandEffective !== "auto"
    readonly property bool canSelectBand: (kind === "wifi" || bandBusy) &&
        (bandAvailable.length > 1 || bandPinned)
    readonly property bool bandPillsVisible: canSelectBand && bandPinned
    readonly property string bandSectionTitle: Model.bandSectionTitle(bandEffective, bandCurrent)
    readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google", "Custom"]
    readonly property var headerActions: {
        var result = []
        if (canShareWifi) result.push({ id: "qr", label: "QR", icon: "󰐲" })
        if (canRunSpeedTest) result.push({ id: "speed", label: "Speed", icon: "󰓅" })
        if (canToggleWifi) result.push({ id: "wifi", label: "Wi-Fi", icon: "󰖩" })
        return result
    }
    readonly property int headerActionCount: headerActions.length
    readonly property bool headerHasCursor: cursorActive && focusSection === "header"
    readonly property bool canForgetSelected: selectedIndex >= 0 && selectedIndex < wifiNetworks.length &&
        canForgetNetwork(wifiNetworks[selectedIndex])
    onHeaderActionCountChanged: if (headerActionCount > 0) headerIndex = Math.min(headerIndex, headerActionCount - 1)
    ownerId: "aurelia.network"
    contentPadding: Theme.popupPadding
    popupWidth: 380
    popupHeight: Math.min(560, Math.max(220, column.implicitHeight + contentPadding * 2))
    fitHeightToContent: true
    contentSizingItem: column
    minPopupHeight: 220
    maxPopupHeight: 560
    focusTarget: keyCatcher
    shown: false
    function open(payloadJson) {
        dnsError = ""
        shown = true
        refresh(true)
        return "ok"
    }
    function close() {
        shown = false
        cancelPasswordPrompt()
        return "ok"
    }
    function closeForPopoutSwitch() { close() }
    function cancelPasswordPrompt() {
        passwordSsid = ""
        passwordText = ""
        identityText = ""
    }
    function findDevice(type) {
        var devices = networkDevices || []
        var fallback = null
        for (var i = 0; i < devices.length; i++) {
            var device = devices[i]
            if (!device || device.type !== type) continue
            if (device.connected) return device
            if (!fallback) fallback = device
        }
        return fallback
    }
    function findConnectedWifiNetwork() {
        var networks = wifiNetworkObjects || []
        for (var i = 0; i < networks.length; i++) {
            if (networks[i] && networks[i].connected) return networks[i]
        }
        return null
    }
    function canShareNetwork(network) {
        if (!network || !network.connected) return false
        return network.security !== WifiSecurityType.Wpa2Eap &&
            network.security !== WifiSecurityType.WpaEap
    }
    function setScannerEnabled(enabled) {
        var nextDevice = shown ? wifiDevice : null
        if (scannerDevice && scannerDevice !== nextDevice) scannerDevice.scannerEnabled = false
        scannerDevice = nextDevice
        if (scannerDevice) scannerDevice.scannerEnabled = enabled
    }
    function syncWifiNetworks() {
        var rows = []
        var networks = wifiNetworkObjects || []
        for (var i = 0; i < networks.length; i++) {
            var network = networks[i]
            if (!network) continue
            checkActionCompletion(network)
            var row = Model.wifiRow(network)
            if (row) rows.push(row)
        }
        wifiNetworks = Model.sortWifiRows(rows)
        wifiStationAvailable = !!wifiDevice
        scanning = false
    }
    function wifiSectionTitle(index) {
        return Model.wifiSectionTitle(wifiNetworks, index)
    }
    function syncBandIndex() {
        var index = bandAvailable.indexOf(bandSelected)
        bandIndex = index >= 0 ? index : 0
        bandAutoFocused = !bandPillsVisible
    }
    function refresh(scanWifi) {
        checkConnectivity()
        if (!detailsProc.running) detailsProc.running = true
        if (!dnsProc.running) {
            dnsProc.command = [dnsBin, "--servers"]
            dnsProc.running = true
        }
        if (!bandProc.running) {
            bandProc.command = [bandBin]
            bandProc.running = true
        }
        if (shown && wifiDevice) {
            if (scanWifi) {
                scanning = true
                setScannerEnabled(false)
                scanRestart.restart()
            } else {
                setScannerEnabled(true)
            }
        }
        syncWifiNetworks()
    }
    function toggleNetwork() {
        if (!networkManagerAvailable) return
        Networking.wifiEnabled = !Networking.wifiEnabled
        Qt.callLater(function() { refresh(true) })
    }
    function checkConnectivity() {
        if (connectivityChecksEnabled && kind !== "disconnected") Networking.checkConnectivity()
    }

    function copyToClipboard(value) {
        if (!value) return
        Quickshell.execDetached(["bash", "-c", "printf %s \"$1\" | wl-copy", "aurelia-network-copy", String(value)])
    }
    function openCaptivePortal() {
        if (!hasCaptivePortal) return
        Quickshell.execDetached(["xdg-open", Model.captivePortalUrl])
        close()
    }
    function summonWifiQr() {
        var payload = {}
        if (info.type === "wifi" && info.iface) {
            payload.iface = info.iface
            if (info.ssid) payload.ssid = info.ssid
        }
        close()
        if (shell && typeof shell.summon === "function")
            shell.summon("aurelia.wifiqr", JSON.stringify(payload))
    }
    function summonSpeedTest() {
        var connection = kind === "wifi" ? (info.ssid || "Wi-Fi")
            : (kind === "ethernet" ? "Ethernet" : "")
        close()
        if (shell && typeof shell.summon === "function")
            shell.summon("aurelia.speedtest", connection ? JSON.stringify({ connection: connection }) : "{}")
    }
    function activateHeader(id) {
        if (id === "qr") summonWifiQr()
        else if (id === "speed") summonSpeedTest()
        else if (id === "wifi") toggleNetwork()
    }
    function setHeaderCursor(index) {
        cursorActive = true
        focusSection = "header"
        headerIndex = Math.max(0, Math.min(Math.max(0, headerActionCount - 1), index))
    }
    function selectHeaderByDelta(delta) {
        if (headerActionCount === 0) return
        headerIndex = Math.max(0, Math.min(headerActionCount - 1, headerIndex + delta))
    }
    function selectDnsByDelta(delta) {
        dnsIndex = Math.max(0, Math.min(dnsProviders.length - 1, dnsIndex + delta))
    }
    function activateDns() {
        if (dnsIndex >= 0 && dnsIndex < dnsProviders.length) setDns(dnsProviders[dnsIndex])
    }
    function selectBandByDelta(delta) {
        bandIndex = Math.max(0, Math.min(bandAvailable.length - 1, bandIndex + delta))
    }
    function activateBand() {
        if (bandAutoFocused) {
            toggleBandAuto()
        } else if (bandIndex >= 0 && bandIndex < bandAvailable.length) {
            setBand(bandAvailable[bandIndex])
        }
    }
    function toggleBandAuto() {
        if (bandSelected !== "auto") setBand("auto")
        else if (bandCurrent !== "") setBand(bandCurrent)
    }
    function moveVertical(delta) {
        if (focusSection === "header") {
            if (delta > 0) focusSection = hasCaptivePortal ? "portal" : (canSelectBand ? "band" : "dns")
            else if (delta < 0) focusSection = "header"
            return
        }
        if (focusSection === "portal") {
            if (delta < 0 && headerActionCount > 0) focusSection = "header"
            else if (delta > 0) focusSection = canSelectBand ? "band" : "dns"
            return
        }
        if (focusSection === "band") {
            if (delta < 0) {
                if (!bandAutoFocused) bandAutoFocused = true
                else focusSection = hasCaptivePortal ? "portal" : (headerActionCount > 0 ? "header" : "dns")
            } else if (bandAutoFocused && bandPillsVisible) bandAutoFocused = false
            else focusSection = "dns"
            return
        }
        if (focusSection === "dns") {
            if (delta < 0) focusSection = canSelectBand ? "band" : (hasCaptivePortal ? "portal" : "header")
            else if (wifiNetworks.length > 0) {
                focusSection = "wifi"
                if (selectedIndex < 0) selectedIndex = 0
            }
            return
        }
        if (delta < 0 && selectedIndex <= 0) {
            focusSection = "dns"
            wifiActionFocused = false
        } else {
            selectByDelta(delta)
        }
    }
    function selectByDelta(delta) {
        if (wifiNetworks.length === 0) { selectedIndex = -1; return }
        if (selectedIndex < 0) selectedIndex = delta > 0 ? 0 : wifiNetworks.length - 1
        else selectedIndex = Math.max(0, Math.min(wifiNetworks.length - 1, selectedIndex + delta))
        wifiActionFocused = false
    }
    function selectWifiActionByDelta(delta) {
        if (selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
        if (!canForgetNetwork(wifiNetworks[selectedIndex])) {
            wifiActionFocused = false
            return
        }
        if (delta > 0) wifiActionFocused = true
        else if (delta < 0) wifiActionFocused = false
    }
    function activateSelected() {
        if (busy || selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
        var net = wifiNetworks[selectedIndex]
        if (!net) return
        if (wifiActionFocused && canForgetNetwork(net)) { forget(net); return }
        activateNetworkRow(net.ssid)
    }
    function activateNetworkRow(ssid) {
        var network = networkForSsid(ssid)
        if (!network || busy) return
        if (network.connected) disconnectRow(ssid)
        else if (requiresCredentials(network.security) && !network.known) openPasswordPrompt(ssid)
        else connectDirectly(ssid)
    }
    function networkForSsid(ssid) {
        var networks = wifiNetworkObjects || []
        for (var i = 0; i < networks.length; i++) {
            if (networks[i] && networks[i].name === ssid) return networks[i]
        }
        return null
    }
    function wifiIndexForSsid(ssid) {
        for (var i = 0; i < wifiNetworks.length; i++)
            if (wifiNetworks[i] && wifiNetworks[i].ssid === ssid) return i
        return -1
    }
    function canForgetNetwork(net) { return Model.canForgetNetwork(net) }
    function requiresCredentials(security) {
        return Model.requiresCredentials(security, WifiSecurityType.Open, WifiSecurityType.Owe)
    }
    function openPasswordPrompt(ssid) {
        if (passwordSsid !== ssid) {
            passwordText = ""
            identityText = ""
        }
        passwordSsid = ssid
    }
    function runNetworkAction(kindValue, network, callback) {
        if (actionKind !== "" || !network) return
        actionSsid = network.name || ""
        actionKind = kindValue
        failureSsid = ""
        failureReason = ""
        callback(network)
        actionTimeout.restart()
    }
    function clearNetworkAction() {
        actionTimeout.stop()
        if (actionKind === "connect") passwordSsid = ""
        failureSsid = ""
        failureReason = ""
        actionSsid = ""
        actionKind = ""
        refresh(false)
    }
    function failNetworkAction(network, reason) {
        if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
        actionTimeout.stop()
        failureSsid = actionSsid
        failureReason = Model.networkFailureReason(reason, requiresCredentials(network.security), connectionFailReasons)
        actionSsid = ""
        actionKind = ""
        refresh(false)
    }
    function checkActionCompletion(network) {
        if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
        if (actionKind === "connect" && network.connected) clearNetworkAction()
        else if (actionKind === "disconnect" && !network.connected && !network.stateChanging) clearNetworkAction()
        else if (actionKind === "forget" && !network.known && !network.stateChanging) clearNetworkAction()
    }
    function shouldRepromptPassphrase(reason, needsCredentials) {
        return Model.shouldRepromptPassphrase(reason, needsCredentials, connectionFailReasons)
    }
    function connectDirectly(ssid) {
        runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connect() })
    }
    function connectWithPassphrase(ssid, passphrase) {
        runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connectWithPsk(passphrase) })
    }
    function connectEnterprise(ssid, identity, passphrase) {
        runNetworkAction("connect", networkForSsid(ssid), function(network) {
            enterpriseConnect.secret = passphrase
            enterpriseConnect.command = ["/usr/bin/timeout", "--kill-after=1s", "30s", "bash", "-c", Model.enterpriseConnectScript, "nmcli-eap", ssid, identity]
            enterpriseConnect.running = true
        })
    }
    function disconnect(network) {
        runNetworkAction("disconnect", network || connectedWifiNetwork, function(net) { net.disconnect() })
    }
    function disconnectRow(ssid) {
        var network = networkForSsid(ssid)
        if (network) disconnect(network)
    }
    function forget(net) {
        runNetworkAction("forget", net ? networkForSsid(net.ssid) : null, function(network) { network.forget() })
    }
    function updateDetails(raw) {
        var next = Model.parseKeyValue(raw)
        if (bandBusy && !next.iface) return
        info = next
        var state = Model.throughputState({
            prevIface: prevIface, prevRxBytes: prevRxBytes, prevTxBytes: prevTxBytes,
            prevSampleTime: prevSampleTime, downloadRate: downloadRate, uploadRate: uploadRate
        }, next, Date.now() / 1000)
        prevIface = state.prevIface
        prevRxBytes = state.prevRxBytes
        prevTxBytes = state.prevTxBytes
        prevSampleTime = state.prevSampleTime
        downloadRate = state.downloadRate
        uploadRate = state.uploadRate
        var ping = Model.pingLatencyState({
            pingIface: pingIface, routerPingSamples: routerPingSamples,
            internetPingSamples: internetPingSamples
        }, next, pingHistoryWindow, pingAverageWindow)
        pingIface = ping.pingIface
        routerPingSamples = ping.routerPingSamples
        internetPingSamples = ping.internetPingSamples
        routerPingLatency = ping.routerPingLatency
        internetPingLatency = ping.internetPingLatency
        internetPingPacketLoss = ping.internetPingPacketLoss
    }
    function updateDns(raw) {
        var lines = String(raw || "").trim().split("\n")
        var provider = ""
        var servers = ""
        for (var i = 0; i < lines.length; i++) {
            var separator = lines[i].indexOf("\t")
            if (separator < 0) continue
            var key = lines[i].slice(0, separator)
            var value = lines[i].slice(separator + 1).trim()
            if (key === "provider") provider = value
            else if (key === "servers") servers = value
        }
        dnsProvider = provider || String(raw || "").trim() || "DHCP"
        dnsServers = servers || (dnsProvider === "DHCP" ? "DHCP" : "")
    }
    function updateBand(raw) {
        var status = Model.parseBandStatus(raw)
        if (bandBusy && status.available.length === 0) return
        bandCurrent = status.band
        bandSelected = status.selected
        bandAvailable = status.available
        syncBandIndex()
    }
    function setBand(band) {
        if (!band || actionProc.running) return
        pendingBand = band
        resetActionTracking()
        actionProc.command = ["/usr/bin/timeout", "--kill-after=1s", "20s", bandBin, band]
        actionProc.running = true
    }
    function setDns(provider) {
        if (!provider || actionProc.running) return
        dnsError = ""
        if (provider === "Custom") {
            close()
            openTerminalDns("Custom", "DNS configuration opened in a terminal for authentication.")
            return
        }
        pendingDnsProvider = provider
        // Match Omarchy: the helper owns authorization. On a provisioned
        // Fedora install this is an immediate passwordless sudo operation;
        // otherwise the helper can use polkit or its terminal fallback.
        startPendingDns()
        close()
    }
    function startPendingDns() {
        if (pendingDnsProvider === "" || actionProc.running) return
        resetActionTracking()
        actionProc.command = ["/usr/bin/timeout", "--kill-after=1s", "20s", dnsBin, pendingDnsProvider]
        actionProc.running = true
    }
    function openTerminalDns(provider, reason) {
        if (!provider) return
        pendingDnsProvider = ""
        dnsError = reason
        if (shown) close()
        Quickshell.execDetached([dnsTerminalBin, provider])
    }
    function resetActionTracking() {
        actionExitCode = -1
        actionExitSeen = false
        actionErrorStreamSeen = false
        lastActionError = ""
    }
    function finishAction() {
        if (!actionExitSeen || !actionErrorStreamSeen) return
        var code = actionExitCode
        var errorText = String(lastActionError || "").trim()
        if (code !== 0) console.warn("[NETWORK] action_failed code=" + code + " error=" + errorText)
        if (pendingDnsProvider !== "") {
            var provider = pendingDnsProvider
            if (code === 0) {
                dnsProvider = provider
                dnsError = ""
                pendingDnsProvider = ""
                close()
            } else if (code === 124 || code === 126 || code === 127 ||
                /authentication agent|controlling terminal/i.test(errorText)) {
                openTerminalDns(provider, code === 124
                    ? "Authorization timed out; opened a terminal for authentication."
                    : "Graphical authorization unavailable; opened a terminal for authentication.")
            } else {
                dnsError = errorText || ("DNS provider change failed (exit " + code + ").")
                pendingDnsProvider = ""
            }
        }
        if (pendingBand !== "") pendingBand = ""
        resetActionTracking()
        refresh(false)
    }
    function formatBytes(value) { return Model.formatBytes(value) }
    function formatRate(value) { return Model.formatRate(value) }
    function formatPing(value) { return Model.formatPingLatency(value, hasInternetPing) }
    function formatLoss(value) { return Model.formatPacketLoss(value, hasInternetPing) }
    onShownChanged: {
        if (shown) {
            refresh(true)
            selectedIndex = wifiNetworks.length > 0 ? 0 : -1
            wifiActionFocused = false
            focusSection = hasCaptivePortal ? "portal" : (wifiNetworks.length > 0 ? "wifi" : "dns")
            var dnsPosition = dnsProviders.indexOf(dnsProvider)
            dnsIndex = dnsPosition >= 0 ? dnsPosition : 0
            syncBandIndex()
            cursorActive = hasCaptivePortal
        } else {
            scanRestart.stop()
            prevSampleTime = 0
            downloadRate = 0
            uploadRate = 0
            pingIface = ""
            routerPingSamples = []
            internetPingSamples = []
            routerPingLatency = -1
            internetPingLatency = -1
            internetPingPacketLoss = 0
            setScannerEnabled(false)
        }
    }
    onPasswordSsidChanged: {
        if (passwordSsid === "" && shown) {
            passwordText = ""
            Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
        }
    }
    onWifiNetworksChanged: {
        if (wifiNetworks.length === 0) {
            selectedIndex = -1
            wifiActionFocused = false
            if (focusSection === "wifi") focusSection = "dns"
        } else if (passwordSsid !== "") {
            var index = wifiIndexForSsid(passwordSsid)
            if (index >= 0) {
                selectedIndex = index
                focusSection = "wifi"
            }
        } else if (selectedIndex >= wifiNetworks.length) {
            selectedIndex = wifiNetworks.length - 1
        } else if (selectedIndex < 0 && shown) {
            selectedIndex = 0
        }
        if (!canForgetSelected) wifiActionFocused = false
    }
    onWifiDeviceChanged: {
        setScannerEnabled(true)
        syncWifiNetworks()
    }
    onWifiNetworkObjectsChanged: syncWifiNetworks()
    onConnectionKeyChanged: Qt.callLater(checkConnectivity)
    onConnectivityChecksEnabledChanged: Qt.callLater(checkConnectivity)
    property string connectionKey: kind + ":" + (info.iface || "") + ":" + (connectedWifiNetwork ? connectedWifiNetwork.name : "")
    property var scannerDevice: null
    Component.onCompleted: refresh(false)
    Component.onDestruction: if (scannerDevice) scannerDevice.scannerEnabled = false
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.shown
        Keys.onPressed: function(event) {
            var key = event.key
            var text = String(event.text || "").toLowerCase()
            if (root.passwordSsid !== "") return
            if (key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
                return
            }
            var down = key === Qt.Key_Down || text === "j"
            var up = key === Qt.Key_Up || text === "k"
            var right = key === Qt.Key_Right || text === "l"
            var left = key === Qt.Key_Left || text === "h"
            if (down || up) {
                if (!root.cursorActive) root.cursorActive = true
                else root.moveVertical(down ? 1 : -1)
                event.accepted = true
            } else if (right || left) {
                if (!root.cursorActive) root.cursorActive = true
                else if (root.focusSection === "header") root.selectHeaderByDelta(right ? 1 : -1)
                else if (root.focusSection === "dns") root.selectDnsByDelta(right ? 1 : -1)
                else if (root.focusSection === "band" && !root.bandAutoFocused) root.selectBandByDelta(right ? 1 : -1)
                else if (root.focusSection === "wifi") root.selectWifiActionByDelta(right ? 1 : -1)
                event.accepted = true
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
                if (!root.cursorActive) return
                if (root.focusSection === "header") {
                    if (root.headerIndex >= 0 && root.headerIndex < root.headerActions.length)
                        root.activateHeader(root.headerActions[root.headerIndex].id)
                } else if (root.focusSection === "portal") root.openCaptivePortal()
                else if (root.focusSection === "band") root.activateBand()
                else if (root.focusSection === "dns") root.activateDns()
                else root.activateSelected()
                event.accepted = true
            } else if (text === "r") {
                root.refresh(true)
                event.accepted = true
            } else if (text === "w") {
                root.toggleNetwork()
                event.accepted = true
            }
        }
    }
    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: column.width; contentHeight: column.implicitHeight
        Column {
            id: column
            width: scroll.width
            spacing: Theme.spacingMd
            Item {
                width: parent.width
                height: 48
                Text {
                    id: heroIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.icon
                    color: root.restricted ? Theme.warning : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXl
                }
                Column {
                    anchors.left: heroIcon.right
                    anchors.leftMargin: Theme.spacingSm
                    anchors.right: heroActions.left
                    anchors.rightMargin: Theme.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: root.kind === "wifi" && root.connectedWifiNetwork
                            ? (root.connectedWifiNetwork.name || "Wi-Fi")
                            : (root.kind === "ethernet" ? "Ethernet" : "Disconnected")
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Theme.fontWeightBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.hasCaptivePortal ? "SIGN-IN REQUIRED"
                            : (root.restricted ? "LIMITED INTERNET ACCESS"
                                : (root.kind === "ethernet" || root.kind === "wifi"
                                    ? root.connectionPhrase.toUpperCase() : "NOT CONNECTED"))
                        color: root.restricted ? Theme.warning : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                        elide: Text.ElideRight
                    }
                }
                Row {
                    id: heroActions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXs
                    Repeater {
                        model: root.headerActions
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: modelData.id === "wifi" ? 60 : 34
                            height: 30
                            radius: Theme.radiusSm
                            color: root.headerHasCursor && root.headerIndex === index
                                ? Theme.selectionActive : Theme.surface
                            border.color: root.headerHasCursor && root.headerIndex === index
                                ? Theme.borderActive : Theme.border
                            border.width: Theme.borderWidthDefault
                            Row {
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: modelData.icon
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                }
                                Text {
                                    visible: modelData.id === "wifi"
                                    text: Networking.wifiEnabled ? "ON" : "OFF"
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: if (containsMouse) root.setHeaderCursor(index)
                                onClicked: root.activateHeader(modelData.id)
                            }
                        }
                    }
                }
            }
            Rectangle {
                visible: root.hasCaptivePortal
                width: parent.width
                height: 64
                radius: Theme.radiusSm
                color: Theme.surface
                border.color: Theme.warning
                border.width: Theme.borderWidthDefault
                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    spacing: Theme.spacingXs
                    Text {
                        text: "Open Captive Portal"
                        color: Theme.warning
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Theme.fontWeightMedium
                    }
                    Text {
                        width: parent.width
                        text: "Sign in or accept this network’s terms to access the internet."
                        color: Theme.textSecondary
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeXs
                        wrapMode: Text.WordWrap
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onContainsMouseChanged: if (containsMouse) {
                        root.cursorActive = true
                        root.focusSection = "portal"
                    }
                    onClicked: root.openCaptivePortal()
                }
            }
            NetworkDetails {
                width: parent.width
                panelRoot: root
            }
            Column {
                visible: root.canSelectBand
                width: parent.width
                spacing: Theme.spacingSm
                Item {
                    width: parent.width
                    height: 26
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.bandSectionTitle
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXs
                        Text { text: "AUTO"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                        Rectangle {
                            width: 34
                            height: 18
                            radius: 9
                            color: root.bandAutoFocused && root.cursorActive && root.focusSection === "band" ? Theme.selectionActive : Theme.surface
                            border.color: Theme.borderActive
                            Text { anchors.centerIn: parent; text: root.bandPinned ? "OFF" : "ON"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: 9 }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { root.cursorActive = true; root.focusSection = "band"; root.bandAutoFocused = true; root.toggleBandAuto() }
                            }
                        }
                    }
                }
                Row {
                    visible: root.bandPillsVisible
                    width: parent.width
                    spacing: Theme.spacingXs
                    Repeater {
                        model: root.bandAvailable
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            width: (parent.width - Theme.spacingXs * (root.bandAvailable.length - 1)) / Math.max(1, root.bandAvailable.length)
                            height: 32
                            radius: Theme.radiusSm
                            color: root.bandCurrent === modelData ? Theme.selection : Theme.surface
                            border.color: root.cursorActive && root.focusSection === "band" && !root.bandAutoFocused && root.bandIndex === index
                                ? Theme.borderActive : Theme.border
                            Text { anchors.centerIn: parent; text: Model.bandLabel(modelData); color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { root.cursorActive = true; root.focusSection = "band"; root.bandAutoFocused = false; root.bandIndex = index; root.setBand(modelData) }
                            }
                        }
                    }
                }
            }
            NetworkDnsControls {
                width: parent.width
                panelRoot: root
            }
            Text {
                visible: root.wifiStationAvailable && root.scanning
                text: "SCANNING WI-FI…"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                font.weight: Theme.fontWeightBold
            }
            ListView {
                id: networkList
                visible: root.wifiStationAvailable
                width: parent.width
                height: Math.min(contentHeight, 190)
                spacing: Theme.spacingXs
                clip: true
                interactive: contentHeight > height
                model: root.wifiStationAvailable ? root.wifiNetworks : []
                currentIndex: root.selectedIndex
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Column {
                    required property var modelData
                    required property int index
                    width: networkList.width
                    spacing: Theme.spacingXs
                    Text {
                        visible: root.wifiSectionTitle(index) !== ""
                        text: root.wifiSectionTitle(index)
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                    }
                    NetworkRow {
                        width: parent.width
                        net: modelData
                        index: parent.index
                        panelRoot: root
                    }
                }
            }
        }
    }
    Item {
        id: backendObjects
        width: 0
        height: 0
        visible: false
        Process {
            id: detailsProc
            command: ["/usr/bin/timeout", "--kill-after=1s", "6s", root.statusBin, "--verbose"]
            stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateDetails(text) }
            stderr: StdioCollector { id: detailsStderr; waitForEnd: true }
            onExited: function(code) {
                if (code !== 0) console.warn("[NETWORK] status_failed code=" + code + " error=" + detailsStderr.text.trim())
            }
        }
        Process {
            id: dnsProc
            command: ["/usr/bin/timeout", "--kill-after=1s", "15s", root.dnsBin, "--servers"]
            stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateDns(text) }
            stderr: StdioCollector { id: dnsStderr; waitForEnd: true }
            onExited: function(code) {
                if (code !== 0) console.warn("[NETWORK] dns_status_failed code=" + code)
            }
        }
        Process {
            id: bandProc
            command: ["/usr/bin/timeout", "--kill-after=1s", "15s", root.bandBin]
            stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateBand(text) }
            stderr: StdioCollector { id: bandStderr; waitForEnd: true }
            onExited: function(code) {
                if (code !== 0) console.warn("[NETWORK] band_status_failed code=" + code)
            }
        }
        Process {
            id: actionProc
            command: []
            stdout: StdioCollector { waitForEnd: true }
            stderr: StdioCollector {
                id: actionStderr
                waitForEnd: true
                onStreamFinished: {
                    root.lastActionError = String(text || "").trim()
                    root.actionErrorStreamSeen = true
                    root.finishAction()
                }
            }
            onExited: function(code) {
                root.actionExitCode = code
                root.actionExitSeen = true
                if (code === 124 && root.pendingDnsProvider !== "") {
                    root.openTerminalDns(root.pendingDnsProvider,
                        "Authorization timed out; opened a terminal for authentication.")
                    root.resetActionTracking()
                } else {
                    root.finishAction()
                }
            }
        }

        Process {
            id: enterpriseConnect
            property string secret: ""
            stdinEnabled: true
            onStarted: { write(secret + "\n"); secret = "" }
            onExited: function(code) {
                if (code !== 0 && root.actionKind === "connect")
                    root.failNetworkAction(root.networkForSsid(root.actionSsid), "enterprise")
            }
        }
        Timer {
            id: scanRestart
            interval: 100
            repeat: false
            onTriggered: {
                if (root.shown && root.wifiDevice) {
                    root.setScannerEnabled(true)
                    scanDone.restart()
                }
            }
        }
        Timer {
            id: scanDone
            interval: 1500
            repeat: false
            onTriggered: root.syncWifiNetworks()
        }
        Timer {
            id: detailsPoll
            interval: 1500
            repeat: true
            running: root.shown
            onTriggered: if (!detailsProc.running) detailsProc.running = true
        }
        Timer {
            id: connectionPhraseTimer
            interval: 2800
            repeat: true
            running: root.shown && !root.restricted &&
                (root.kind === "ethernet" || root.kind === "wifi")
            onTriggered: root.connectionPhraseIndex =
                (root.connectionPhraseIndex + 1) % root.connectionPhrases.length
        }
        Timer {
            id: bandPoll
            interval: 4000
            repeat: true
            running: root.shown
            onTriggered: if (!bandProc.running) { bandProc.command = ["/usr/bin/timeout", "--kill-after=1s", "15s", root.bandBin]; bandProc.running = true }
        }
        Timer {
            id: connectivityPoll
            interval: 10000
            repeat: true
            running: root.restricted && root.connectivityChecksEnabled
            onTriggered: root.checkConnectivity()
        }
        Timer {
            id: actionTimeout
            interval: 30000
            repeat: false
            onTriggered: {
                if (!root.actionKind) return
                root.failureSsid = root.actionSsid
                root.failureReason = root.actionKind === "connect" ? "Timed out connecting"
                    : (root.actionKind === "disconnect" ? "Timed out disconnecting" : "Timed out forgetting")
                root.actionSsid = ""
                root.actionKind = ""
                root.refresh(false)
            }
        }
    }
}
