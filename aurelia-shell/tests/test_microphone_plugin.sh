#!/usr/bin/env bash

# T38 Microphone bar-widget contract. These checks are isolated and never
# mutate PipeWire, shell.json, the live bar, or user configuration.

set -Eeuo pipefail

section "Aurelia Microphone Plugin"

microphone_root="$ROOT/plugins/aurelia.microphone"
manifest_file="$microphone_root/manifest.json"
widget_file="$microphone_root/MicrophoneBarWidget.qml"
audio_model_file="$ROOT/plugins/aurelia.audio/Model.js"
default_file="$ROOT/config/bar-default.json"
fixture_root="$ROOT/tests/fixtures/microphone-foundation"

if [[ -f "$manifest_file" && -f "$widget_file" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.microphone" and
       .name == "Microphone" and
       (.kinds == ["bar-widget"]) and
       .entryPoints.barWidget == "MicrophoneBarWidget.qml" and
       .barWidget.displayName == "Microphone" and
       .barWidget.category == "Audio" and
       .barWidget.allowMultiple == false and
       (.barWidget.defaultSection == null)
   ' "$manifest_file" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$microphone_root" >/dev/null; then
    pass "[static] Microphone has a validated optional bar-widget manifest matching the reference metadata"
else
    fail "[static] Microphone manifest, entry point, or optional metadata is incomplete"
fi

if grep -Fq 'import Quickshell.Services.Pipewire' "$widget_file" &&
   grep -Fq 'import "../aurelia.audio/Model.js" as Model' "$widget_file" &&
   grep -Fq 'Pipewire.defaultAudioSource' "$widget_file" &&
   grep -Fq 'Pipewire.nodes' "$widget_file" &&
   grep -Fq 'PwObjectTracker' "$widget_file" &&
   grep -Fq 'visible: root.hasSource' "$widget_file" &&
   grep -Fq 'function toggleMute' "$widget_file" &&
   grep -Fq 'function summonAudio' "$widget_file" &&
   grep -Fq 'function adjustInput' "$widget_file" &&
   grep -Fq 'function handleClick' "$widget_file" &&
   grep -Fq 'function handleWheel' "$widget_file" &&
   grep -Fq 'AureliaToolTip' "$widget_file"; then
    pass "[static] Microphone reads one PipeWire source boundary and exposes safe mute, summon, wheel, and tooltip behavior"
else
    fail "[static] Microphone source, interaction, retention, or tooltip boundary is incomplete"
fi

if grep -Fq 'root.shell.summon("aurelia.audio"' "$widget_file" &&
   grep -Fq 'button === Qt.MiddleButton' "$widget_file" &&
   grep -Fq 'root.handleClick(mouse.button)' "$widget_file" &&
   grep -Fq 'Model.stepInputVolume' "$widget_file" &&
   grep -Fq 'root.source.audio.muted' "$widget_file" &&
   ! grep -Eq 'omarchy-shell|wpctl|pactl|systemctl|bash[[:space:]]+-c|execDetached' "$widget_file"; then
    pass "[static] Microphone uses the resident host API without shell-command or second-service shortcuts"
else
    fail "[static] Microphone cross-plugin routing or ownership boundary is unsafe"
fi

if jq -e '[.layout.left[], .layout.center[], .layout.right[]] | map(.id) | index("aurelia.microphone") | not' "$default_file" >/dev/null; then
    pass "[static] Microphone remains absent from the shipped default bar like the reference"
else
    fail "[static] Microphone was incorrectly added to the shipped default bar"
fi

if grep -Fq 'function isCaptureStream' "$audio_model_file" &&
   grep -Fq 'function activeCaptureStreamCount' "$audio_model_file" &&
   grep -Fq 'function microphoneInUse' "$audio_model_file" &&
   grep -Fq 'function microphoneMuted' "$audio_model_file" &&
   grep -Fq 'function microphoneVolume' "$audio_model_file" &&
   grep -Fq 'function stepInputVolume' "$audio_model_file"; then
    pass "[static] shared Audio model owns pure capture, mute, in-use, and input-volume helpers"
else
    fail "[static] shared Audio microphone model helpers are incomplete"
fi

if command -v node >/dev/null; then
    if node - "$audio_model_file" <<'NODE_MICROPHONE_MODEL'
const audio = require(process.argv[2])
const assert = (condition, message) => { if (!condition) throw new Error(message) }
const equal = (actual, expected, message) => assert(actual === expected, `${message}: ${actual}`)

const source = { isStream: false, isSink: false, audio: { volume: 0.4, muted: false } }
const capture = { isStream: true, isSink: false, audio: { muted: false } }
const mutedCapture = { isStream: true, isSink: false, audio: { muted: true } }
const playback = { isStream: true, isSink: true, audio: { muted: false } }

assert(audio.isCaptureStream(capture), 'capture stream detected')
assert(!audio.isCaptureStream(playback), 'playback stream rejected')
equal(audio.activeCaptureStreamCount([capture, mutedCapture, playback]), 1, 'active capture count')
assert(audio.microphoneInUse(source, [capture]), 'microphone in-use state')
assert(!audio.microphoneInUse({ audio: { volume: 0.4, muted: true } }, [capture]), 'muted source is not in use')
assert(!audio.microphoneInUse(null, [capture]), 'missing source is not in use')
assert(audio.microphoneInUse(source, [capture, { isStream: true, isSink: false }]), 'capture without audio remains observable')
assert(audio.microphoneMuted(null), 'missing source defaults muted')
equal(audio.microphoneVolume(null), 0, 'missing source volume')
equal(audio.microphoneVolume(source), 0.4, 'source volume')
equal(audio.stepInputVolume(0.95, 0.1), 1, 'input upper bound')
equal(audio.stepInputVolume(0.05, -0.1), 0, 'input lower bound')
NODE_MICROPHONE_MODEL
    then
        pass "[isolated-runtime] shared Audio model handles capture streams, missing sources, mute state, in-use state, and input bounds"
    else
        fail "[isolated-runtime] shared Audio microphone model matrix failed"
    fi
else
    skip "[isolated-runtime] shared Audio microphone model matrix (node unavailable)"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] Microphone entry-point QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root"  || true' RETURN
result_file="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/config" "$runtime_root/cache"
: >"$result_file"

AURELIA_MICROPHONE_FOUNDATION_RESULT="$result_file" \
AURELIA_MICROPHONE_FOUNDATION_SOURCE="file://$widget_file" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell.qml" --no-color >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$result_file" ]] &&
   runtime_log_is_environment_only "$runtime_log" &&
   jq -e '.microphoneLoaded == true and .noSource.visible == false and
          .noSource.inUse == false and .noSource.muted == true and
          .noSource.volume == 0 and .fake.initialVisible == true and
          .fake.initialInUse == true and .fake.initialMuted == false and
          .fake.initialStatusText == "Microphone in use" and
          .fake.afterMuteMuted == true and .fake.afterMuteInUse == false and
          .fake.afterMuteStatusText == "Microphone muted" and
          .fake.afterUnmuteMuted == false and .fake.afterUnmuteInUse == true and
          .fake.afterMiddleMuted == false and .fake.summonCalls == 1 and
          .fake.summonedPlugin == "aurelia.audio" and
          .fake.upperVolume == 1 and .fake.lowerVolume == 0' "$result_file" >/dev/null; then
    pass "[isolated-runtime] real Microphone widget handlers load safely and cover mute, Audio summon, in-use text, and input bounds"
elif runtime_log_has_environment_diagnostic "$runtime_log" &&
     runtime_skip_if_environment_only "$runtime_log" "[isolated-runtime] Microphone entry-point fixture cannot create a disposable runtime backend"; then
    :
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$result_file" ]]; then details="$details result=$(tr '\n' ' ' <"$result_file")"; fi
    fail "[isolated-runtime] Microphone entry-point fixture failed (status=$runtime_status): $details"
fi
