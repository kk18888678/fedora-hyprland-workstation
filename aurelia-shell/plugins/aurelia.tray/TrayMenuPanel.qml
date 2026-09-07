import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../ui"
import "../../theme"

// Render tray menus inside Aurelia. QsMenuEntry.display() and QsMenuAnchor
// are platform-menu APIs and require QApplication mode; Aurelia intentionally
// runs as a resident Wayland shell instead. QsMenuOpener gives us the live
// D-Bus menu model without creating a second application surface.
AureliaKeyboardPanel {
    id: panelRoot

    property var trayItem: null
    property var rootMenuOpener: null
    property var submenuStack: []

    readonly property var currentOpener: submenuStack.length > 0 ? submenuStack[submenuStack.length - 1].opener : rootMenuOpener
    readonly property var currentChildren: currentOpener ? currentOpener.children : null
    readonly property var currentValues: currentChildren ? currentChildren.values : []
    readonly property string currentTitle: submenuStack.length > 0 ? submenuStack[submenuStack.length - 1].title : panelRoot.displayName(panelRoot.trayItem)
    readonly property int menuHeight: Math.min(520, Math.max(112, Number(currentValues.length) * 38 + headerRow.implicitHeight + Theme.spacingXl * 2 + Theme.spacingSm))

    ownerId: "aurelia.tray"
    popupWidth: 340
    popupHeight: menuHeight
    shown: false
    dismissHandler: function() { panelRoot.close() }

    function displayName(item) {
        if (!item) return "Tray"
        var title = String(item.title || "").trim()
        if (title !== "") return title
        var tooltipTitle = String(item.tooltipTitle || "").trim()
        if (tooltipTitle !== "") return tooltipTitle
        var description = String(item.tooltipDescription || "").trim()
        if (description !== "") return description
        var id = String(item.id || "")
        var slash = id.lastIndexOf("/")
        if (slash >= 0) id = id.substring(slash + 1)
        if (id.toLowerCase().indexOf("statusnotifieritem") >= 0 || id === "") return "Tray"
        return id
    }

    Item {
        width: 0
        height: 0
        visible: false

        Component {
            id: submenuOpenerComponent
            QsMenuOpener {}
        }

        Timer {
            id: submenuCleanupTimer
            interval: 150
            repeat: false
            onTriggered: panelRoot.finalizeClose()
        }
    }

    function openForItem(item, opener, itemAnchor) {
        if (!item || !item.menu || !opener || !itemAnchor) return
        submenuCleanupTimer.stop()
        resetSubmenus()
        trayItem = item
        rootMenuOpener = opener
        anchorItem = itemAnchor
        shown = true
    }

    function close() {
        shown = false
        submenuCleanupTimer.restart()
    }

    function closeForPopoutSwitch() { close() }

    function finalizeClose() {
        resetSubmenus()
        trayItem = null
        rootMenuOpener = null
    }

    function resetSubmenus() {
        var oldStack = submenuStack
        submenuStack = []
        for (var i = oldStack.length - 1; i >= 0; i--) {
            if (oldStack[i] && oldStack[i].opener) oldStack[i].opener.destroy()
        }
    }

    function enterSubmenu(entry) {
        if (!entry || !entry.hasChildren) return
        console.info("[TRAY] submenu_open text=" + String(entry.text || ""))
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

    function triggerEntry(entry) {
        if (!entry || !entry.enabled) return
        console.info("[TRAY] menu_trigger text=" + String(entry.text || ""))
        // Keep the submenu opener alive until the D-Bus action has had an
        // event-loop turn to dispatch. Omarchy retains its opener through the
        // popup fade for the same reason.
        entry.triggered()
        close()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingSm
        focus: panelRoot.shown

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
                        // Keep the live ObjectModel, not a copied JavaScript
                        // array. QsMenuEntry activation and submenu updates
                        // are owned by this live model.
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
                                    else panelRoot.triggerEntry(modelData)
                                }
                            }
                        }
                    }
                }
            }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Back) {
                panelRoot.close()
                event.accepted = true
            } else if (event.key === Qt.Key_Left && panelRoot.submenuStack.length > 0) {
                panelRoot.leaveSubmenu()
                event.accepted = true
            }
        }
    }
}
