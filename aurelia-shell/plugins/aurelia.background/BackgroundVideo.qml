import QtQuick
import QtMultimedia

// Bare MediaPlayer/VideoOutput implementation adapted from the Omarchy
// background contract. It primes paused video once so the first frame is
// committed before playback is stopped.
Item {
    id: root

    property url mediaSource: ""
    property bool playbackEnabled: true
    property bool audioEnabled: false
    property int mediaGeneration: 0
    property bool priming: false
    property int primingGeneration: -1
    property bool frameReceived: false
    readonly property bool ready: player.hasVideo

    onMediaSourceChanged: {
        root.mediaGeneration += 1
        root.priming = false
        root.primingGeneration = -1
        root.frameReceived = false
        primePauseTimer.stop()
        framePauseTimer.stop()
        output.clearOutput()
    }

    onPlaybackEnabledChanged: {
        root.priming = false
        root.frameReceived = false
        primePauseTimer.stop()
        framePauseTimer.stop()
        if (root.playbackEnabled) player.play()
        else player.pause()
    }

    function pauseAfterPrimedFrame() {
        if (!root.priming || root.playbackEnabled ||
            root.primingGeneration !== root.mediaGeneration) return
        root.priming = false
        primePauseTimer.stop()
        framePauseTimer.stop()
        player.pause()
    }

    Timer {
        id: primePauseTimer
        interval: 1000
        repeat: false
        onTriggered: root.pauseAfterPrimedFrame()
    }

    Timer {
        id: framePauseTimer
        interval: 50
        repeat: false
        onTriggered: root.pauseAfterPrimedFrame()
    }

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }

    Loader {
        id: audioLoader
        active: root.audioEnabled && player.hasAudio
        sourceComponent: AudioOutput {
            muted: root.priming || !root.playbackEnabled
        }
    }

    MediaPlayer {
        id: player
        source: root.mediaSource
        videoOutput: output
        audioOutput: audioLoader.item
        loops: MediaPlayer.Infinite
        autoPlay: root.playbackEnabled

        onMediaStatusChanged: {
            if (mediaStatus !== MediaPlayer.LoadedMedia) return
            if (!root.playbackEnabled) {
                root.priming = true
                root.primingGeneration = root.mediaGeneration
                root.frameReceived = false
                primePauseTimer.restart()
            }
            player.play()
        }
    }

    Connections {
        target: output.videoSink

        function onVideoFrameChanged() {
            if (player.mediaStatus !== MediaPlayer.BufferedMedia ||
                !root.priming || root.playbackEnabled ||
                root.primingGeneration !== root.mediaGeneration ||
                root.frameReceived) return
            root.frameReceived = true
            framePauseTimer.restart()
        }
    }
}
