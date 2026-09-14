#!/usr/bin/env bash

# T37 Audio panel and output interaction contract. These checks are isolated
# and do not change PipeWire, MPRIS, or the live bar configuration.

set -Eeuo pipefail

section "Aurelia Audio Panel and Output Interaction"

audio_root="$ROOT/plugins/aurelia.audio"
panel_file="$audio_root/AudioPanel.qml"
widget_file="$audio_root/AudioBarWidget.qml"
default_file="$ROOT/config/bar-default.json"

if [[ -f "$panel_file" && -f "$widget_file" ]] &&
   grep -Fq 'AureliaKeyboardPanel' "$panel_file" &&
   grep -Fq 'import Quickshell.Services.Pipewire' "$panel_file" &&
   grep -Fq 'import Quickshell.Services.Mpris' "$panel_file" &&
   grep -Fq 'candidateSinks' "$panel_file" &&
   grep -Fq 'candidateSources' "$panel_file" &&
   grep -Fq 'candidateStreams' "$panel_file" &&
   grep -Fq 'displayAudioSinks' "$panel_file" &&
   grep -Fq 'displayAudioSources' "$panel_file" &&
   grep -Fq 'displayAudioStreams' "$panel_file" &&
   grep -Fq 'ScrollView' "$panel_file" &&
   grep -Fq 'SinkRow' "$panel_file" &&
   grep -Fq 'SourceRow' "$panel_file" &&
   grep -Fq 'StreamRow' "$panel_file"; then
    pass "[static] Audio panel owns output, input, and per-application PipeWire sections"
else
    fail "[static] Audio panel is missing the reference output/input/stream structure"
fi

if grep -Fq 'function safeListLength' "$panel_file" &&
   grep -Fq 'function visibleSectionList' "$panel_file" &&
   grep -Fq 'var sections = root.visibleSectionList()' "$panel_file"; then
    pass "[static] Audio cursor clamping tolerates transiently unavailable section state"
else
    fail "[static] Audio cursor clamping can dereference transient undefined section state"
fi

if grep -Fq 'function setOutputVolume' "$panel_file" &&
   grep -Fq 'function setInputVolume' "$panel_file" &&
   grep -Fq 'function toggleOutputMute' "$panel_file" &&
   grep -Fq 'function toggleInputMute' "$panel_file" &&
   grep -Fq 'function setDefaultSink' "$panel_file" &&
   grep -Fq 'function setDefaultSource' "$panel_file" &&
   grep -Fq 'function adjustVolume' "$panel_file" &&
   grep -Fq 'function refreshDisplayAudioModels' "$panel_file" &&
   grep -Fq 'Model.clampVolume' "$panel_file" &&
   grep -Fq 'Model.steppedVolume' "$panel_file"; then
    pass "[static] Audio controls bound volumes, mute state, defaults, and refresh snapshots"
else
    fail "[static] Audio control ownership or bounds are incomplete"
fi

if grep -Fq 'mouse.button === Qt.MiddleButton' "$widget_file" &&
   grep -Fq 'root.open("{}")' "$widget_file" &&
   grep -Fq 'mouse.button === Qt.RightButton' "$widget_file" &&
   grep -Fq 'root.toggleMute()' "$widget_file" &&
   grep -Fq 'onWheel: function(wheel)' "$widget_file" &&
   grep -Fq 'root.adjustOutput' "$widget_file"; then
    pass "[static] Audio bar maps primary/middle panel, right mute, and scroll output volume"
else
    fail "[static] Audio bar interaction semantics are incomplete"
fi

if grep -Fq 'function outputBarGlyph' "$audio_root/Model.js" &&
   grep -Fq 'Model.outputBarGlyph' "$widget_file" &&
   grep -Fq 'Model.outputBarGlyph' "$panel_file"; then
    pass "[static] Audio bar and hero consume one canonical volume-sensitive output glyph"
else
    fail "[static] Audio output glyph ownership or bar/hero integration is incomplete"
fi

if jq -e '
      [.layout.right[].id] == [
        "aurelia.tray", "aurelia.network", "aurelia.audio",
        "aurelia.bluetooth", "aurelia.monitor", "aurelia.screenshot",
        "aurelia.session-actions", "aurelia.power"
      ]
   ' "$default_file" >/dev/null; then
    pass "[static] Audio is placed after Network in the canonical right-side default bar"
else
    fail "[static] canonical default bar does not contain Audio at the reference location"
fi

if command -v node >/dev/null; then
    if node - "$audio_root/Model.js" <<'NODE_AUDIO_CONTROLS'
const audio = require(process.argv[2])
const assert = (condition, message) => { if (!condition) throw new Error(message) }
const nodes = [
  { isSink: true, isStream: false, ready: true, name: 'alsa_output.pci', audio: { volume: 0.5, muted: false } },
  { isSink: false, isStream: false, ready: true, name: 'alsa_input.pci', audio: { volume: 0.4, muted: false } },
  { isSink: true, isStream: true, ready: true, type: 'Stream/Output/Audio', name: 'spotify', audio: { volume: 0.7, muted: false } },
  { isSink: false, isStream: true, ready: true, type: 'Stream/Input/Audio', name: 'microphone', audio: { volume: 0.7, muted: false } }
]
assert(audio.isPlaybackStream(nodes[0]) === false, 'device sink is not a playback stream')
assert(audio.isPlaybackStream(nodes[2]) === true, 'playback stream remains selectable')
assert(audio.isAudioSource(nodes[1]) === true, 'input source remains selectable')
assert(audio.isAudioSource(nodes[3]) === true, 'capture stream remains source-like')
assert(audio.listSnapshot(nodes).length === nodes.length, 'display snapshots preserve node count')
assert(audio.clampVolume(-1, 1) === 0, 'output volume clamps at zero')
assert(audio.clampVolume(2, 1) === 1, 'output/input volume clamps at one')
assert(audio.clampVolume(2, 1.5) === 1.5, 'stream volume clamps at stream maximum')
assert(audio.steppedVolume(0.95, 0.1, 1) === 1, 'output wheel step clamps at one')
assert(audio.steppedVolume(0.05, -0.1, 1) === 0, 'input wheel step clamps at zero')
assert(audio.outputBarGlyph(null, 0, false) === '', 'missing output uses muted glyph')
const speakers = { description: 'Built-in Speakers', audio: {} }
assert(audio.outputBarGlyph(speakers, 0.2, false) === '', 'low output glyph')
assert(audio.outputBarGlyph(speakers, 0.5, false) === '', 'medium output glyph')
assert(audio.outputBarGlyph(speakers, 0.8, false) === '', 'high output glyph')
assert(audio.outputBarGlyph(speakers, 0.8, true) === '', 'muted output glyph')
assert(audio.outputBarGlyph({ description: 'Bluetooth Headphones', audio: {} }, 0.8, true) === '󰋋', 'headphone glyph takes precedence')
assert(audio.outputVolumeName(0, false) === 'Silenced', 'zero output remains bounded')
assert(audio.outputVolumeName(1.5, false) === 'Concert hall', 'loud output label remains deterministic')
NODE_AUDIO_CONTROLS
    then
        pass "[isolated-runtime] Audio interaction model preserves sink/source/stream control identities and bounds"
    else
        fail "[isolated-runtime] Audio interaction model failed"
    fi
else
    skip "[isolated-runtime] Audio interaction model (node unavailable)"
fi
