#!/usr/bin/env bash

# T36 Audio plugin foundation contract. This test owns the pure PipeWire/MPRIS
# model matrix and the opt-in/failure-contained plugin boundary; it never
# mutates live audio state.

set -Eeuo pipefail

section "Aurelia Audio Plugin Foundation"

audio_root="$ROOT/plugins/aurelia.audio"
manifest_file="$audio_root/manifest.json"
model_file="$audio_root/Model.js"
widget_file="$audio_root/AudioBarWidget.qml"
fixture_root="$ROOT/tests/fixtures/audio-foundation"

if [[ -f "$manifest_file" && -f "$model_file" && -f "$widget_file" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.audio" and
       .name == "Audio" and
       (.kinds == ["bar-widget"]) and
       .entryPoints.barWidget == "AudioBarWidget.qml" and
       .barWidget.displayName == "Audio" and
       .barWidget.category == "Audio" and
       .barWidget.allowMultiple == false
   ' "$manifest_file" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$audio_root" >/dev/null 2>&1; then
    pass "[static] Audio has a validated opt-in bar-widget manifest and safe entry point"
else
    fail "[static] Audio manifest, entry point, or shared validation contract is incomplete"
fi

if grep -Fq 'import Quickshell.Services.Pipewire' "$widget_file" &&
   grep -Fq 'import "Model.js" as Model' "$widget_file" &&
   grep -Fq 'Pipewire.defaultAudioSink' "$widget_file" &&
   grep -Fq 'Pipewire.defaultAudioSource' "$widget_file" &&
   grep -Fq 'Pipewire.nodes' "$widget_file" &&
   grep -Fq 'property var bar' "$widget_file" &&
   grep -Fq 'property var shell' "$widget_file" &&
   grep -Fq 'property var pluginRegistry' "$widget_file" &&
   grep -Fq 'visible: root.audioAvailable' "$widget_file"; then
    pass "[static] Audio entry point reads host-owned PipeWire state and degrades when unavailable"
else
    fail "[static] Audio entry point is missing the safe PipeWire/host boundary"
fi

if grep -Fq 'function isPlaybackStream' "$model_file" &&
   grep -Fq 'function isAudioSource' "$model_file" &&
   grep -Fq 'function listSnapshot' "$model_file" &&
   grep -Fq 'function nodeLabel' "$model_file" &&
   grep -Fq 'function streamLabel' "$model_file" &&
   grep -Fq 'function streamRepresentsPlayer' "$model_file" &&
   ! grep -Eq 'execDetached|systemctl|wpctl|pactl|bash[[:space:]]+-c' "$model_file"; then
    pass "[static] Audio model is pure and contains no process or system mutation path"
else
    fail "[static] Audio model is incomplete or owns an unsafe process path"
fi

if command -v node >/dev/null 2>&1; then
    if node - "$model_file" <<'NODE_AUDIO_MODEL'
const audio = require(process.argv[2])
const assert = (condition, message) => { if (!condition) throw new Error(message) }
const equal = (actual, expected, message) => assert(actual === expected, `${message}: ${actual}`)
const deepEqual = (actual, expected, message) => equal(JSON.stringify(actual), JSON.stringify(expected), message)

assert(audio.isPlaybackStream({ isStream: true, isSink: true }), 'sink-backed playback stream detected')
assert(audio.isPlaybackStream({ isStream: true, type: 'Stream/Output/Audio' }), 'typed playback stream detected')
assert(audio.isPlaybackStream({ isStream: true, type: 'AudioOutStream' }), 'named playback stream detected')
assert(!audio.isPlaybackStream({ isStream: false, isSink: true }), 'non-stream rejected as playback')
assert(audio.isAudioSource({ audio: {} }), 'audio source detected by audio channel')
assert(audio.isAudioSource({ type: 'Audio/Source' }), 'typed audio source detected')
assert(!audio.isAudioSource({ type: 'Video/Output' }), 'video output rejected')

equal(audio.outputVolumeName(0, false), 'Silenced', 'silent output label')
equal(audio.outputVolumeName(0.9, false), 'Party mode', 'loud output label')
equal(audio.outputVolumeName(0.5, true), 'Muted', 'muted output label')
deepEqual(audio.parseSinkAvailability('alsa_output\t1\nhdmi_output\t0\n'), {
  alsa_output: true,
  hdmi_output: false
}, 'sink availability parsing')
equal(audio.friendlyDeviceLabel('Built-in Audio Speakers Output'), 'Speakers', 'friendly output label')
equal(audio.nodeLabel({
  ready: true,
  properties: { 'node.nick': 'Built-in Audio Microphones Input' },
  name: 'alsa_input'
}), 'Microphone', 'friendly node label')
NODE_AUDIO_MODEL
    then
        pass "[isolated-runtime] Audio model classifies nodes, bounds labels, and parses sink availability"
    else
        fail "[isolated-runtime] Audio model classification/label matrix failed"
    fi
else
    skip "[isolated-runtime] Audio model matrix (node unavailable)"
fi

if command -v node >/dev/null 2>&1; then
    if node - "$model_file" <<'NODE_AUDIO_MPRIS'
const audio = require(process.argv[2])
const assert = (condition, message) => { if (!condition) throw new Error(message) }
const equal = (actual, expected, message) => {
  if (actual !== expected) throw new Error(`${message}: ${actual}`)
}

const players = [
  { identity: 'Spotify', canPlay: true, isPlaying: true, dbusName: 'org.mpris.MediaPlayer2.spotify' },
  { identity: 'Chromium', canPlay: true, isPlaying: false, dbusName: 'org.mpris.MediaPlayer2.chromium' }
]
const streams = [
  { ready: true, properties: { 'application.name': 'Chromium' } },
  { ready: true, properties: { 'application.name': 'audio-src' } }
]

equal(audio.friendlyStreamLabel('spotify'), 'Spotify', 'known stream label')
equal(audio.matchingMprisStreamLabel('Chromium Browser', players), 'Chromium', 'matching MPRIS label')
equal(audio.unmatchedMprisStreamLabel('audio-src', players, streams), 'Spotify', 'unmatched MPRIS label')
equal(audio.streamLabel(streams[0], players, streams), 'Chromium', 'stream label from MPRIS')
equal(audio.streamLabel(streams[1], players, streams), 'Spotify', 'generic stream label from unmatched player')
assert(audio.streamRepresentsPlayer(streams[1], players[0], players, streams), 'generic stream links to active player')
assert(!audio.streamRepresentsPlayer(streams[0], { identity: 'Firefox', canPlay: true }, players, streams), 'unrelated stream rejects player')
NODE_AUDIO_MPRIS
    then
        pass "[isolated-runtime] Audio model resolves MPRIS labels without live object ownership"
    else
        fail "[isolated-runtime] Audio MPRIS stream-label matrix failed"
    fi
else
    skip "[isolated-runtime] Audio MPRIS matrix (node unavailable)"
fi

if grep -Fq 'property bool audioAvailable' "$widget_file" &&
   grep -Fq 'readonly property var sink' "$widget_file" &&
   grep -Fq 'readonly property var source' "$widget_file" &&
   grep -Fq 'function open' "$widget_file" &&
   grep -Fq 'function close' "$widget_file" &&
   grep -Fq 'function toggle' "$widget_file" &&
   grep -Fq 'onStatusChanged' "$widget_file" &&
   grep -Fq 'Loader.Error' "$widget_file"; then
    pass "[static] Audio has bounded loader failure reporting and a stable plugin lifecycle"
else
    fail "[static] Audio opt-in/failure-containment boundary is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] Audio entry-point QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
result_file="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/config" "$runtime_root/cache"

AURELIA_AUDIO_FOUNDATION_RESULT="$result_file" \
AURELIA_AUDIO_FOUNDATION_SOURCE="file://$widget_file" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell.qml" --no-color >"$runtime_log" 2>&1 || runtime_status=$?

unexpected_diagnostics="$(grep -E 'WARN|ERROR|FATAL|TypeError|ReferenceError|QML Error|Segmentation fault|Cannot assign' "$runtime_log" | \
    grep -Ev 'ERROR quickshell\.ipc: Failed to start IPC server on path |\[AUDIO\] panel_load_failed|No PanelWindow backend loaded' || true)"

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$result_file" ]] &&
   [[ -z "$unexpected_diagnostics" ]] &&
   jq -e '.audioLoaded == true and .exposesAudioAvailability == true and
          .exposesPanelVisibility == true and .panelVisible == false' \
       "$result_file" >/dev/null; then
    pass "[isolated-runtime] real Audio bar entry point loads safely without mutating audio state"
elif grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin|No PanelWindow backend loaded' "$runtime_log" &&
     runtime_skip_if_environment_only "$runtime_log" "[isolated-runtime] Audio entry-point fixture cannot create a disposable window backend"; then
    :
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$result_file" ]]; then details="$details result=$(tr '\n' ' ' <"$result_file")"; fi
    fail "[isolated-runtime] Audio entry-point fixture failed (status=$runtime_status): $details"
fi
