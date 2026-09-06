section "29. Verification Matrix O: Motion Control & Immediate Transitions"

# 29.1: Motion disabled produces zero effective duration in Theme.qml
qml_theme="$ROOT/dotfiles/aurelia/theme/Theme.qml"
if grep -q "readonly property bool motionEnabled:" "$qml_theme" && \
   grep -q "readonly property int effectiveDurationFast: motionEnabled ? Math.round(durationFast \* motionScale) : 0" "$qml_theme" && \
   grep -q "readonly property int effectiveDurationNormal: motionEnabled ? Math.round(durationNormal \* motionScale) : 0" "$qml_theme"; then
    pass "29.1 motion disabled evaluates effectiveDurationFast and effectiveDurationNormal to 0ms (immediate)"
else
    fail "29.1 motion duration resolution missing in Theme.qml"
fi

# 29.2: Motion scale multiplier scales component durations proportionally
if grep -q "readonly property real motionScale:" "$qml_theme" && \
   grep -q "Math.round(baseDuration \* componentMotionScale(componentId))" "$qml_theme"; then
    pass "29.2 motion scale multiplier scales component durations proportionally"
else
    fail "29.2 motion scale calculation missing in Theme.qml"
fi

# 29.3: Malformed or negative motion scale falls back safely
test_29_3_out="$("$lua_bin" - "$ROOT" << 'LUA_CHECK'
local root = arg[1]
package.path = root .. "/dotfiles/aurelia/core/?.lua;" .. package.path
local pref = require("preferences")

local tmp = os.tmpname()
local f = io.open(tmp, "w")
f:write("{\"aurelia\": {\"motion\": {\"scale\": -5.0}}}")
f:close()

local s = pref.get_effective("aurelia.motion.scale", tmp)
os.remove(tmp)
assert(s == 1.0, "Motion scale should fall back to 1.0 on negative value, got " .. tostring(s))
print("TEST_29_3_OK")
LUA_CHECK
)"
if grep -q "TEST_29_3_OK" <<< "$test_29_3_out"; then
    pass "29.3 negative or malformed motion scale falls back safely to non-negative value"
else
    fail "29.3 motion scale fallback check failed: $test_29_3_out"
fi
