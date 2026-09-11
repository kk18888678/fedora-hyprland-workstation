import QtQuick

// Shared image/video surface for the Aurelia background service. Video support
// is loaded only when the selected path is a video, keeping still-only sessions
// free of the multimedia component tree.
Item {
    id: root

    property string path: ""
    property int reloads: 0
    property bool playbackEnabled: true
    property bool audioEnabled: false
    property bool reloading: false

    readonly property bool video: root.isVideoPath(root.path)
    readonly property var current: root.video ? videoLoader.item : imageLoader.item
    readonly property bool ready: current ? current.ready === true : false
    readonly property string imageSource: root.path !== "" && !root.video
        ? root.fileUrl(root.path) + (root.reloads > 0 ? "?v=" + root.reloads : "")
        : ""
    readonly property string videoSource: root.path !== "" && root.video
        ? root.fileUrl(root.path)
        : ""

    function isVideoPath(value) {
        return /\.(mp4|m4v|mov|webm|mkv|avi)$/i.test(String(value || ""))
    }

    function fileUrl(value) {
        var parts = String(value || "").split("/")
        for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
        return "file://" + parts.join("/")
    }

    Loader {
        id: imageLoader
        anchors.fill: parent
        active: root.path !== "" && !root.video
        sourceComponent: imageComponent
    }

    Loader {
        id: videoLoader
        anchors.fill: parent
        active: root.path !== "" && root.video && !root.reloading
        source: Qt.resolvedUrl("BackgroundVideo.qml")
    }

    Component {
        id: imageComponent

        Image {
            readonly property bool ready: status === Image.Ready
            source: root.imageSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: root.reloads === 0
            smooth: true
            mipmap: true
        }
    }

    Binding {
        target: videoLoader.item
        property: "mediaSource"
        value: root.videoSource
        when: videoLoader.item !== null
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: videoLoader.item
        property: "playbackEnabled"
        value: root.playbackEnabled
        when: videoLoader.item !== null
    }

    Binding {
        target: videoLoader.item
        property: "audioEnabled"
        value: root.audioEnabled
        when: videoLoader.item !== null
    }

    onReloadsChanged: {
        if (!root.video) return
        root.reloading = true
        Qt.callLater(function() { root.reloading = false })
    }
}
