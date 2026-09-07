import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"

// Render tray menus inside Aurelia. QsMenuEntry.display() and QsMenuAnchor
// are platform-menu APIs and require QApplication mode; Aurelia intentionally
// runs as a resident Wayland shell instead. QsMenuOpener gives us the live
// D-Bus menu model without creating a second application surface.
PanelWindow {
    id: panelRoot

    property var anchorWindow: null
    property int barSize: 26
    property var trayItem: null
    property var submenuStack: []

    readonly property bool barAtBottom: anchorWindow && anchorWindow.position === "bottom"
    readonly property var currentOpener: submenuStack.length > 0 ? submenuStack[submenuStack.length - 1].opener : rootMenuOpener
    readonly property var currentChildren: currentOpener ? currentOpener.children : null
    readonly property string currentTitle: submenuStack.length > 0 ? submenuStack[submenuStack.length - 1].title : (trayItem ? String(trayItem.title || trayItem.id || "Tray") : "Tray")
    readonly property int menuHeight: Math.min(520, Math.max(112, Number(currentChildren ? currentChildren.count : 0) * 38 + headerRow.implicitHeight + Theme.spacingXl * 2 + Theme.spacingSm))

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-tray-menu"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitWidth: 0
    implicitHeight: 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    QsMenuOpener {
        id: rootMenuOpener
        menu: panelRoot.trayItem ? panelRoot.trayItem.menu : null
    }

    Component {
        id: submenuOpenerComponent
        QsMenuOpener {}
    }

    function openForItem(item) {
        if (!item || !item.menu) return
        if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot)
        resetSubmenus()
        trayItem = item
        visible = true
        Qt.callLater(function() { card.forceActiveFocus() })
    }

    function close() {
        resetSubmenus()
        trayItem = null
        visible = false
        if (anchorWindow && typeof anchorWindow.releasePopout === "function") anchorWindow.releasePopout(panelRoot)
    }

    function closeForPopoutSwitch() { close() }

    function resetSubmenus() {
        var oldStack = submenuStack
        submenuStack = []
        for (var i = oldStack.length - 1; i >= 0; i--) {
            if (oldStack[i] && oldStack[i].opener) oldStack[i].opener.destroy()
        }
    }

    function enterSubmenu(entry) {
        if (!entry || !entry.hasChildren) return
        var opener = submenuOpenerComponent.createObject(panelRoot, { menu: entry })
        if (!opener) return
        var next = submenuStack.slice()
        next.push({ opener: opener, title: String(entry.text || "Menu") })
        submenuStack = next
    }

    function leaveSubmenu() {
        if (submenuStack.length === 0) {
            close()
            return
        }
        var next = submenuStack.slice()
        var last = next.pop()
        submenuStack = next
        if (last && last.opener) last.opener.destroy()
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton
        onClicked: function(mouse) {
            mouse.accepted = true
            panelRoot.close()
        }
    }

    Rectangle {
        id: card
        width: 340
        height: panelRoot.menuHeight
        anchors.right: parent.right
        anchors.top: barAtBottom ? undefined : parent.top
        anchors.bottom: barAtBottom ? parent.bottom : undefined
        anchors.topMargin: barAtBottom ? 0 : panelRoot.barSize + Theme.spacingLg
        anchors.bottomMargin: barAtBottom ? panelRoot.barSize + Theme.spacingLg : 0
        anchors.rightMargin: Theme.spacingLg
        z: 1
        radius: Theme.radiusLg
        color: Theme.bgBase
        border.color: Theme.border
        border.width: Theme.borderWidthDefault
        focus: panelRoot.visible

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { mouse.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingXl
            spacing: Theme.spacingSm

            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: panelRoot.currentTitle
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    font.weight: Theme.fontWeightBold
                    elide: Text.ElideRight
                }
                Text {
                    text: "ESC"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }
            }

            RowLayout {
                visible: panelRoot.submenuStack.length > 0
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "‹ Back"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Theme.spacingSm
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            panelRoot.leaveSubmenu()
                        }
                    }
                }
            }

            Flickable {
                id: menuFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: menuColumn.implicitHeight
                interactive: contentHeight > height

                Column {
                    id: menuColumn
                    width: menuFlick.width
                    spacing: Theme.spacingXs

                    Repeater {
                        model: panelRoot.currentChildren

                        delegate: Item {
                            required property var modelData
                            width: menuColumn.width
                            height: modelData.isSeparator ? 10 : 38
                            opacity: modelData.enabled ? 1.0 : 0.45

                            Rectangle {
                                visible: modelData.isSeparator
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 1
                                color: Theme.border
                            }

                            Rectangle {
                                visible: !modelData.isSeparator
                                anchors.fill: parent
                                radius: Theme.radiusSm
                                color: menuHover.hovered && modelData.enabled ? Theme.selection : "transparent"
                                HoverHandler { id: menuHover }
                            }

                            RowLayout {
                                visible: !modelData.isSeparator
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingSm
                                anchors.rightMargin: Theme.spacingSm
                                spacing: Theme.spacingSm

                                Text {
                                    Layout.preferredWidth: 18
                                    text: modelData.buttonType !== QsMenuButtonType.None && modelData.checkState === Qt.Checked ? "✓" : ""
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Image {
                                    visible: String(modelData.icon || "") !== ""
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    source: modelData.icon
                                    sourceSize: Qt.size(18, 18)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.text || ""
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: modelData.hasChildren
                                    text: "›"
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeLg
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !modelData.isSeparator && modelData.enabled
                                onClicked: function(mouse) {
                                    mouse.accepted = true
                                    if (modelData.hasChildren) panelRoot.enterSubmenu(modelData)
                                    else {
                                        modelData.triggered()
                                        panelRoot.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
                panelRoot.close()
                event.accepted = true
            } else if (event.key === Qt.Key_Left && panelRoot.submenuStack.length > 0) {
                panelRoot.leaveSubmenu()
                event.accepted = true
            }
        }
    }
}
