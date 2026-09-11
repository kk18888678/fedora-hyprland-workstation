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
    readonly property int menuTextInset: Theme.trayMenuTextInset
    // Size the card from the live menu column instead of treating separators
    // as full menu rows. This keeps the surface close to its last action.
    readonly property int menuHeight: {
        var backHeight = backRow.visible ? backRow.implicitHeight : 0
        var layoutGaps = backRow.visible ? Theme.trayMenuGap : 0
        var contentHeight = Theme.trayMenuPadding * 2 + backHeight + layoutGaps + menuColumn.implicitHeight
        return Math.min(520, Math.max(112, Math.ceil(contentHeight)))
    }

    ownerId: "aurelia.tray"
    popupWidth: 232
    popupHeight: menuHeight
    contentSizingItem: menuColumn
    fitHeightToContent: true
    contentPadding: Theme.trayMenuPadding
    minPopupHeight: 112
    maxPopupHeight: 520
    shown: false
    dismissHandler: function() { panelRoot.close() }

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
        spacing: Theme.trayMenuGap
        focus: panelRoot.shown

            RowLayout {
                id: backRow
                visible: panelRoot.submenuStack.length > 0
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "‹ Back"
                    color: Theme.accent
                    font.family: Theme.fontFamilyProse
                    font.pixelSize: Theme.trayMenuTextSize
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
                    spacing: Theme.trayMenuGap

                    Repeater {
                        // Keep the live ObjectModel, not a copied JavaScript
                        // array. QsMenuEntry activation and submenu updates
                        // are owned by this live model.
                        model: panelRoot.currentChildren

                        delegate: Item {
                            required property var modelData
                            readonly property bool hasCheck: modelData.buttonType !== QsMenuButtonType.None
                            readonly property bool hasIcon: String(modelData.icon || "") !== ""
                            readonly property bool sectionLabel: !modelData.isSeparator &&
                                !modelData.enabled && !modelData.hasChildren &&
                                !hasIcon && String(modelData.text || "") !== ""
                            width: menuColumn.width
                            height: modelData.isSeparator
                                ? Theme.trayMenuSeparatorHeight
                                : (sectionLabel ? Theme.trayMenuSectionHeight : Theme.trayMenuRowHeight)
                            opacity: sectionLabel ? 1.0 : (modelData.enabled ? 1.0 : 0.45)

                            Rectangle {
                                visible: modelData.isSeparator
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 1
                                color: Theme.border
                            }

                            Rectangle {
                                visible: !modelData.isSeparator && !sectionLabel
                                anchors.fill: parent
                                radius: Theme.radiusSm
                                color: menuHover.hovered && modelData.enabled ? Theme.selectionHover : "transparent"
                                HoverHandler { id: menuHover }
                            }

                            Rectangle {
                                visible: !modelData.isSeparator && !sectionLabel && menuHover.hovered && modelData.enabled
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingXs
                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                height: Math.max(14, parent.height - Theme.spacingSm)
                                radius: width / 2
                                color: Theme.accent
                            }

                            Text {
                                visible: !modelData.isSeparator && !sectionLabel && hasCheck
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                text: modelData.checkState === Qt.Checked ? "✓" : ""
                                color: Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.trayMenuTextSize
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Image {
                                id: menuIcon
                                visible: !modelData.isSeparator && !sectionLabel && hasIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 24
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                height: 16
                                fillMode: Image.PreserveAspectFit
                                sourceSize: Qt.size(
                                    Math.max(1, Math.round(width * Screen.devicePixelRatio)),
                                    Math.max(1, Math.round(height * Screen.devicePixelRatio)))
                                source: modelData.icon
                                asynchronous: false
                                smooth: false
                            }

                            Text {
                                visible: !modelData.isSeparator && !sectionLabel
                                anchors.left: parent.left
                                anchors.leftMargin: menuIcon.visible ? 46 : panelRoot.menuTextInset
                                anchors.right: submenuGlyph.left
                                anchors.rightMargin: Theme.spacingSm
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: modelData.text || ""
                                color: Theme.text
                                font.family: Theme.fontFamilyProse
                                font.pixelSize: Theme.trayMenuTextSize
                                font.weight: Theme.fontWeightMedium
                                elide: Text.ElideRight
                            }

                            Text {
                                id: submenuGlyph
                                visible: !modelData.isSeparator && !sectionLabel && modelData.hasChildren
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingSm
                                anchors.verticalCenter: parent.verticalCenter
                                text: "›"
                                color: Theme.textMuted
                                font.family: Theme.fontFamilyProse
                                font.pixelSize: Theme.trayMenuTextSize
                            }

                            Text {
                                visible: sectionLabel
                                anchors.fill: parent
                                anchors.leftMargin: panelRoot.menuTextInset
                                anchors.rightMargin: Theme.spacingSm
                                textFormat: Text.PlainText
                                text: modelData.text || ""
                                color: Theme.textSecondary
                                font.family: Theme.fontFamilyProse
                                font.pixelSize: Theme.trayMenuSectionTextSize
                                font.weight: Theme.fontWeightMedium
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !modelData.isSeparator && !sectionLabel && modelData.enabled
                                cursorShape: Qt.PointingHandCursor
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
