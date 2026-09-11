import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import "../../theme"
import "Model.js" as Model

// NetworkManager objects are intentionally resolved only for actions and
// signal connections. The row itself receives the primitive snapshot made by
// Model.wifiRow(), matching Omarchy's protection against AP churn while a
// ListView delegate is being recycled.
Item {
    id: row

    required property var net
    required property int index
    property var panelRoot: null

    readonly property bool isConnected: !!(net && net.connected)
    readonly property bool isKnown: !!(net && net.known)
    readonly property bool requiresCredentials: panelRoot && net
        ? panelRoot.requiresCredentials(net.security) : false
    readonly property bool isEnterprise: !!(net &&
        (net.security === WifiSecurityType.Wpa2Eap || net.security === WifiSecurityType.WpaEap))
    readonly property bool canForget: panelRoot && net
        ? panelRoot.canForgetNetwork(net) : false
    readonly property bool isSelected: panelRoot && panelRoot.focusSection === "wifi" &&
        panelRoot.selectedIndex === index
    readonly property bool forgetFocused: isSelected && panelRoot.wifiActionFocused && canForget
    readonly property bool forgetVisible: canForget &&
        (!requiresCredentials || forgetFocused || forgetMouse.containsMouse)
    readonly property bool isBusy: panelRoot && net && panelRoot.actionKind !== "" &&
        panelRoot.actionSsid === net.ssid
    readonly property bool isFailed: panelRoot && net && panelRoot.failureReason !== "" &&
        panelRoot.failureSsid === net.ssid
    readonly property bool isPasswordOpen: panelRoot && net && panelRoot.passwordSsid !== "" &&
        panelRoot.passwordSsid === net.ssid
    readonly property string statusText: {
        if (!net || !panelRoot || isPasswordOpen) return ""
        if (isBusy && panelRoot.actionKind === "connect") return "Connecting…"
        if (isBusy && panelRoot.actionKind === "disconnect") return "Disconnecting…"
        if (isBusy && panelRoot.actionKind === "forget") return "Forgetting…"
        if (isFailed) return panelRoot.failureReason || "Connection failed"
        if (isConnected && panelRoot.kind === "wifi" && panelRoot.hasCaptivePortal)
            return "Sign-in required"
        if (isConnected) return "Connected"
        return ""
    }
    readonly property color statusColor: isFailed ? Theme.error
        : (isConnected && panelRoot && panelRoot.hasCaptivePortal ? Theme.warning
            : (isConnected ? Theme.success : Theme.textMuted))

    implicitHeight: baseRow.implicitHeight + (isPasswordOpen ? prompt.implicitHeight + Theme.spacingXs : 0)

    function submitCredentials() {
        if (!panelRoot || !net || isBusy || panelRoot.passwordText.length === 0) return
        if (isEnterprise) {
            if (panelRoot.identityText.length > 0)
                panelRoot.connectEnterprise(net.ssid, panelRoot.identityText, panelRoot.passwordText)
        } else {
            panelRoot.connectWithPassphrase(net.ssid, panelRoot.passwordText)
        }
    }

    Rectangle {
        id: baseRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: Math.max(44, networkInfo.implicitHeight + Theme.spacingSm * 2)
        height: implicitHeight
        radius: Theme.radiusSm
        color: row.panelRoot && row.panelRoot.cursorActive && row.isSelected && !row.forgetFocused
            ? Theme.selectionActive
            : (rowHover.hovered ? Theme.selectionHover
                : (row.isConnected ? Theme.selection : Theme.surface))
        border.color: row.isConnected ? Theme.borderActive : Theme.border
        border.width: Theme.borderWidthDefault

        HoverHandler { id: rowHover }

        Text {
            id: networkIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            text: row.panelRoot && row.net
                ? Model.connectionIcon("wifi", row.net.signal,
                    row.isConnected && row.panelRoot.kind === "wifi" ? row.panelRoot.connectivity : "")
                : Model.wifiIconFor(-1)
            color: row.statusColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXl
        }

        Column {
            id: networkInfo
            anchors.left: networkIcon.right
            anchors.leftMargin: Theme.spacingSm
            anchors.right: rightAction.left
            anchors.rightMargin: Theme.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: row.net && row.net.ssid !== "" ? row.net.ssid : "Hidden network"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Theme.fontWeightMedium
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: row.statusText !== ""
                text: row.statusText
                color: row.statusColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                elide: Text.ElideRight
            }
        }

        Item {
            id: rightAction
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            visible: row.requiresCredentials || row.canForget

            Text {
                anchors.fill: parent
                visible: row.requiresCredentials || row.forgetVisible
                text: row.forgetVisible ? "󰅙" : "󰌾"
                color: row.forgetVisible ? Theme.error : Theme.textSubtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Rectangle {
                anchors.fill: parent
                visible: row.forgetFocused
                color: Theme.selection
                border.color: Theme.error
                border.width: Theme.borderWidthDefault
                radius: Theme.radiusSm
                z: -1
            }

            MouseArea {
                id: forgetMouse
                anchors.fill: parent
                enabled: row.canForget && row.panelRoot && !row.panelRoot.busy
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onContainsMouseChanged: if (containsMouse) row.selectForget()
                onClicked: if (row.panelRoot && row.net) row.panelRoot.forget(row.net)
            }

            ToolTip.visible: forgetMouse.containsMouse || row.forgetFocused
            ToolTip.text: "Forget network"
            ToolTip.delay: 400
        }

        MouseArea {
            anchors.fill: parent
            anchors.rightMargin: rightAction.visible ? rightAction.width + Theme.spacingSm : 0
            enabled: !!row.panelRoot && !row.panelRoot.busy
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onContainsMouseChanged: if (containsMouse) row.selectRow()
            onClicked: {
                mouse.accepted = true
                if (row.panelRoot && row.net) row.panelRoot.activateNetworkRow(row.net.ssid)
            }
        }
    }

    function selectRow() {
        if (!panelRoot) return
        panelRoot.cursorActive = true
        panelRoot.focusSection = "wifi"
        panelRoot.selectedIndex = index
        panelRoot.wifiActionFocused = false
    }

    function selectForget() {
        if (!panelRoot) return
        panelRoot.cursorActive = true
        panelRoot.focusSection = "wifi"
        panelRoot.selectedIndex = index
        panelRoot.wifiActionFocused = true
    }

    Item {
        id: prompt
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: baseRow.bottom
        anchors.topMargin: Theme.spacingXs
        height: isPasswordOpen ? (isBusy || isFailed ? 32 : (isEnterprise ? 76 : 42)) : 0
        visible: isPasswordOpen

        TextField {
            id: identityField
            visible: row.isEnterprise && !row.isBusy && !row.isFailed
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 32
            placeholderText: "Identity (user@domain)"
            text: row.isPasswordOpen && row.panelRoot ? row.panelRoot.identityText : ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            color: Theme.inputText
            placeholderTextColor: Theme.inputPlaceholder
            selectionColor: Theme.inputSelection
            background: Rectangle {
                color: Theme.inputBg
                border.color: identityField.activeFocus ? Theme.inputBorderFocused : Theme.inputBorder
                border.width: Theme.borderWidthDefault
                radius: Theme.radiusSm
            }
            onTextChanged: if (row.panelRoot && row.isPasswordOpen && text !== row.panelRoot.identityText)
                row.panelRoot.identityText = text
            onAccepted: passwordField.forceActiveFocus()
            Keys.onEscapePressed: if (row.panelRoot) row.panelRoot.cancelPasswordPrompt()
            onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
        }

        TextField {
            id: passwordField
            visible: !row.isBusy && !row.isFailed
            anchors.left: parent.left
            anchors.right: submitButton.left
            anchors.rightMargin: Theme.spacingXs
            anchors.bottom: parent.bottom
            height: 32
            placeholderText: "Passphrase"
            echoMode: TextInput.Password
            text: row.isPasswordOpen && row.panelRoot ? row.panelRoot.passwordText : ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            color: Theme.inputText
            placeholderTextColor: Theme.inputPlaceholder
            selectionColor: Theme.inputSelection
            background: Rectangle {
                color: Theme.inputBg
                border.color: passwordField.activeFocus ? Theme.inputBorderFocused : Theme.inputBorder
                border.width: Theme.borderWidthDefault
                radius: Theme.radiusSm
            }
            onTextChanged: if (row.panelRoot && row.isPasswordOpen && text !== row.panelRoot.passwordText)
                row.panelRoot.passwordText = text
            onAccepted: row.submitCredentials()
            Keys.onEscapePressed: if (row.panelRoot) row.panelRoot.cancelPasswordPrompt()
            onVisibleChanged: if (visible && !row.isEnterprise) Qt.callLater(forceActiveFocus)
        }

        Rectangle {
            visible: row.isBusy || row.isFailed
            anchors.fill: parent
            height: 32
            color: Theme.surface
            border.color: row.isFailed ? Theme.error : Theme.borderActive
            border.width: Theme.borderWidthDefault
            radius: Theme.radiusSm

            Text {
                anchors.fill: parent
                text: row.isFailed ? "Wrong password" : "Connecting…"
                color: row.isFailed ? Theme.error : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Rectangle {
            id: submitButton
            visible: !row.isBusy && !row.isFailed
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 32
            height: 32
            radius: Theme.radiusSm
            color: submitHover.hovered ? Theme.selection : Theme.surfaceElevated
            border.color: Theme.borderActive
            border.width: Theme.borderWidthDefault

            HoverHandler { id: submitHover }

            Text {
                anchors.centerIn: parent
                text: "✓"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMd
            }

            MouseArea {
                id: submitMouse
                anchors.fill: parent
                enabled: !!row.panelRoot && row.passwordText.length > 0 &&
                    (!row.isEnterprise || row.panelRoot.identityText.length > 0)
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: row.submitCredentials()
            }

            ToolTip.visible: submitMouse.containsMouse && submitMouse.enabled
            ToolTip.text: "Connect"
            ToolTip.delay: 400
        }
    }

    Connections {
        target: row.panelRoot && row.net ? row.panelRoot.networkForSsid(row.net.ssid) : null

        function onConnectionFailed(reason) {
            if (!row.panelRoot || !row.net) return
            var ours = row.panelRoot.actionKind === "connect" &&
                row.panelRoot.actionSsid === row.net.ssid
            row.panelRoot.failNetworkAction(row.panelRoot.networkForSsid(row.net.ssid), reason)
            if (ours && row.panelRoot.shouldRepromptPassphrase(reason, row.requiresCredentials))
                row.panelRoot.openPasswordPrompt(row.net.ssid)
        }

        function onConnectedChanged() {
            if (row.panelRoot && row.net)
                row.panelRoot.checkActionCompletion(row.panelRoot.networkForSsid(row.net.ssid))
        }

        function onKnownChanged() {
            if (row.panelRoot && row.net)
                row.panelRoot.checkActionCompletion(row.panelRoot.networkForSsid(row.net.ssid))
        }

        function onStateChangingChanged() {
            if (row.panelRoot && row.net)
                row.panelRoot.checkActionCompletion(row.panelRoot.networkForSsid(row.net.ssid))
        }
    }
}
