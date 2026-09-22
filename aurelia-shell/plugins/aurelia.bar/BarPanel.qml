import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "."

// One mapped layer-shell surface for one monitor. Bar.qml is the resident
// host; this component owns only monitor-local geometry, content, gestures,
// and remapping. This is the same host/panel boundary used by Omarchy.
PanelWindow {
    id: panelRoot

    property var bar: null
    property var screenModel: null
    readonly property bool vertical: !!panelRoot.bar && panelRoot.bar.vertical === true
    readonly property int barSize: panelRoot.bar && panelRoot.bar.barSize
        ? panelRoot.bar.barSize : Theme.bar.sizeHorizontal
    readonly property var contentAnchorItem: contentLoader.item && contentLoader.item.contentAnchorItem
        ? contentLoader.item.contentAnchorItem : barSurface
    readonly property string surfaceColor: String(barSurface.color)
    readonly property string surfaceBorderColor: String(barSurface.border.color)

    screen: panelRoot.screenModel
    visible: !remapGuard.remapping
    exclusionMode: panelRoot.bar && panelRoot.bar.barHidden
        ? ExclusionMode.Ignore : ExclusionMode.Auto

    margins {
        top: panelRoot.bar && panelRoot.bar.barHidden && panelRoot.bar.position === "top"
            ? -panelRoot.barSize : 0
        bottom: panelRoot.bar && panelRoot.bar.barHidden && panelRoot.bar.position === "bottom"
            ? -panelRoot.barSize : 0
        left: panelRoot.bar && panelRoot.bar.barHidden && panelRoot.bar.position === "left"
            ? -panelRoot.barSize : 0
        right: panelRoot.bar && panelRoot.bar.barHidden && panelRoot.bar.position === "right"
            ? -panelRoot.barSize : 0
    }

    anchors {
        top: panelRoot.bar && (panelRoot.bar.position === "top" || panelRoot.vertical)
        bottom: panelRoot.bar && (panelRoot.bar.position === "bottom" || panelRoot.vertical)
        left: panelRoot.bar && (panelRoot.bar.position === "left" || !panelRoot.vertical)
        right: panelRoot.bar && (panelRoot.bar.position === "right" || !panelRoot.vertical)
    }

    implicitWidth: panelRoot.vertical ? panelRoot.barSize : 0
    implicitHeight: panelRoot.vertical ? 0 : panelRoot.barSize
    color: panelRoot.bar && panelRoot.bar.transparent
        ? "transparent" : (panelRoot.bar ? panelRoot.bar.background : Theme.bar.background)
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "aurelia-bar"
    WlrLayershell.layer: WlrLayer.Top

    ScreenMoveRemap {
        id: remapGuard
        window: panelRoot
    }

    function beginBarMove() {
        return panelRoot.bar && typeof panelRoot.bar.beginBarMove === "function"
            ? panelRoot.bar.beginBarMove(panelRoot) : false
    }

    function updateBarMove(point) {
        if (panelRoot.bar && typeof panelRoot.bar.updateBarMove === "function")
            panelRoot.bar.updateBarMove(point)
    }

    function finishBarMove() {
        return panelRoot.bar && typeof panelRoot.bar.finishBarMove === "function"
            ? panelRoot.bar.finishBarMove() : "not-ready"
    }

    function clearBarMove() {
        if (panelRoot.bar && typeof panelRoot.bar.clearBarMove === "function")
            panelRoot.bar.clearBarMove()
    }

    function beginWidgetDrag(source, point) {
        return panelRoot.bar && typeof panelRoot.bar.beginWidgetDrag === "function"
            ? panelRoot.bar.beginWidgetDrag(source, point) : false
    }

    function updateWidgetDrag(source, point) {
        if (panelRoot.bar && typeof panelRoot.bar.updateWidgetDrag === "function")
            panelRoot.bar.updateWidgetDrag(source, point)
    }

    function endWidgetDrag(source) {
        return panelRoot.bar && typeof panelRoot.bar.endWidgetDrag === "function"
            ? panelRoot.bar.endWidgetDrag(source) : "not-ready"
    }

    function cancelWidgetDrag(source) {
        if (panelRoot.bar && typeof panelRoot.bar.cancelWidgetDrag === "function")
            panelRoot.bar.cancelWidgetDrag(source)
    }

    function widgetDropMarkerFor(target, after) {
        if (!target || !barSurface) return null
        try {
            var point = target.mapToItem(barSurface, 0, 0)
            var thickness = 2
            if (panelRoot.vertical) return {
                x: Math.round(point.x),
                y: Math.round(point.y + (after ? target.height : 0) - thickness / 2),
                width: Math.max(1, target.width),
                height: thickness
            }
            return {
                x: Math.round(point.x + (after ? target.width : 0) - thickness / 2),
                y: Math.round(point.y),
                width: thickness,
                height: Math.max(1, target.height)
            }
        } catch (error) {
            console.warn("[BAR] widget_drop_marker_failed")
            return null
        }
    }

    Rectangle {
        id: barSurface
        anchors.fill: parent
        color: panelRoot.bar && panelRoot.bar.transparent
            ? "transparent" : (panelRoot.bar ? panelRoot.bar.background : Theme.bar.background)
        border.color: panelRoot.bar && panelRoot.bar.transparent
            ? "transparent" : Theme.bar.border
        border.width: panelRoot.bar && panelRoot.bar.transparent ? 0 : Theme.borderWidthDefault

        // A transparent bar keeps the wallpaper visible but still draws a
        // subtle scrim behind the strip. The scrim is a translucent overlay,
        // never an opaque surface, so the user's transparency choice is
        // preserved while text and icons keep local contrast.
        // bin/aurelia-bar-text-color strengthens it when the sampled wallpaper
        // needs it.
        Rectangle {
            id: barScrim
            anchors.fill: parent
            visible: panelRoot.bar && panelRoot.bar.transparent === true &&
                panelRoot.bar.transparentScrimAlpha > 0
            color: panelRoot.bar ? panelRoot.bar.transparentScrim : "transparent"
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            sourceComponent: panelRoot.vertical ? verticalBarContent : horizontalBarContent
        }

        Rectangle {
            id: widgetDropMarker
            readonly property var geometry: panelRoot.bar ? panelRoot.bar.widgetDropMarkerGeometry : null
            visible: panelRoot.bar && panelRoot.bar.widgetDragActive &&
                panelRoot.bar.widgetDragPanel === panelRoot && geometry !== null
            x: geometry ? geometry.x : 0
            y: geometry ? geometry.y : 0
            width: geometry ? geometry.width : 0
            height: geometry ? geometry.height : 0
            radius: Math.min(width, height) / 2
            color: panelRoot.bar ? panelRoot.bar.barForeground : Theme.text
            z: 100
        }
    }

    component BarContent: Item {
        id: contentRoot

        property bool orientationVertical: false
        readonly property var contentAnchorItem: barContentAnchor

        anchors.fill: parent
        anchors.leftMargin: contentRoot.orientationVertical ? 0
            : (panelRoot.bar ? panelRoot.bar.barOuterMargin : Theme.bar.outerMargin)
        anchors.rightMargin: contentRoot.orientationVertical ? 0
            : (panelRoot.bar ? panelRoot.bar.barOuterMargin : Theme.bar.outerMargin)
        anchors.topMargin: contentRoot.orientationVertical
            ? (panelRoot.bar ? panelRoot.bar.barOuterMargin : Theme.bar.outerMargin) : 0
        anchors.bottomMargin: contentRoot.orientationVertical
            ? (panelRoot.bar ? panelRoot.bar.barOuterMargin : Theme.bar.outerMargin) : 0

        Item {
            id: barContentAnchor
            objectName: "aurelia-bar-content-anchor"
            anchors.fill: parent
            visible: true
            opacity: 0
            enabled: false
            z: -100
        }

        BarCenter {
            anchors.fill: parent
            entries: panelRoot.bar ? panelRoot.bar.entriesFor("center") : []
            anchorId: panelRoot.bar ? panelRoot.bar.centerAnchor : ""
            bar: panelRoot.bar
            barPanel: panelRoot
            shell: panelRoot.bar ? panelRoot.bar.shell : null
            pluginRegistry: panelRoot.bar ? panelRoot.bar.pluginRegistry : null
            barWidgetRegistry: panelRoot.bar ? panelRoot.bar.barWidgetRegistry : null
            pluginHost: panelRoot.bar ? panelRoot.bar.pluginHost : null
            aureliaPath: panelRoot.bar ? panelRoot.bar.aureliaPath : ""
        }

        // Keep the left group after the full-center gesture surface, matching
        // the reference stacking order. Its logo and widgets must remain the
        // topmost pointer targets while the center still owns empty-bar drag
        // and transparency gestures.
        GridLayout {
            id: leftGroup
            anchors.left: contentRoot.orientationVertical ? undefined : parent.left
            anchors.top: contentRoot.orientationVertical ? parent.top : undefined
            anchors.horizontalCenter: contentRoot.orientationVertical ? parent.horizontalCenter : undefined
            anchors.verticalCenter: contentRoot.orientationVertical ? undefined : parent.verticalCenter
            columns: contentRoot.orientationVertical ? 1 : 2
            columnSpacing: contentRoot.orientationVertical ? 0 : Theme.spacingSm
            rowSpacing: contentRoot.orientationVertical ? Theme.spacingSm : 0

            AureliaLogo {
                bar: panelRoot.bar
                shell: panelRoot.bar ? panelRoot.bar.shell : null
                Layout.preferredWidth: contentRoot.orientationVertical
                    ? panelRoot.barSize : implicitWidth
                Layout.preferredHeight: contentRoot.orientationVertical
                    ? implicitHeight : panelRoot.barSize
            }

            BarWidgetRow {
                entries: panelRoot.bar ? panelRoot.bar.entriesFor("left") : []
                bar: panelRoot.bar
                barPanel: panelRoot
                shell: panelRoot.bar ? panelRoot.bar.shell : null
                pluginRegistry: panelRoot.bar ? panelRoot.bar.pluginRegistry : null
                barWidgetRegistry: panelRoot.bar ? panelRoot.bar.barWidgetRegistry : null
                pluginHost: panelRoot.bar ? panelRoot.bar.pluginHost : null
                aureliaPath: panelRoot.bar ? panelRoot.bar.aureliaPath : ""
                region: "left"
                Layout.preferredWidth: contentRoot.orientationVertical
                    ? panelRoot.barSize : implicitWidth
                Layout.preferredHeight: contentRoot.orientationVertical
                    ? implicitHeight : panelRoot.barSize
            }
        }

        BarWidgetRow {
            id: rightGroup
            anchors.right: contentRoot.orientationVertical ? undefined : parent.right
            anchors.bottom: contentRoot.orientationVertical ? parent.bottom : undefined
            anchors.horizontalCenter: contentRoot.orientationVertical ? parent.horizontalCenter : undefined
            anchors.verticalCenter: contentRoot.orientationVertical ? undefined : parent.verticalCenter
            entries: panelRoot.bar ? panelRoot.bar.entriesFor("right") : []
            bar: panelRoot.bar
            barPanel: panelRoot
            shell: panelRoot.bar ? panelRoot.bar.shell : null
            pluginRegistry: panelRoot.bar ? panelRoot.bar.pluginRegistry : null
            barWidgetRegistry: panelRoot.bar ? panelRoot.bar.barWidgetRegistry : null
            pluginHost: panelRoot.bar ? panelRoot.bar.pluginHost : null
            aureliaPath: panelRoot.bar ? panelRoot.bar.aureliaPath : ""
            region: "right"
        }
    }

    Component {
        id: horizontalBarContent
        BarContent { orientationVertical: false }
    }

    Component {
        id: verticalBarContent
        BarContent { orientationVertical: true }
    }

    Component.onCompleted: {
        if (panelRoot.bar && typeof panelRoot.bar.registerBarPanel === "function")
            panelRoot.bar.registerBarPanel(panelRoot)
    }

    Component.onDestruction: {
        if (panelRoot.bar && typeof panelRoot.bar.unregisterBarPanel === "function")
            panelRoot.bar.unregisterBarPanel(panelRoot)
    }
}
