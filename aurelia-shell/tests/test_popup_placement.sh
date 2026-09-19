#!/usr/bin/env bash

# Global popup placement suite: one shared rule (PopupPlacement.computeOrigin)
# that both AureliaKeyboardPanel and the notification surface consume, plus the
# per-widget `popupAlign` override.

set -Eeuo pipefail

section "Aurelia Popup Placement"

repo_root="$(cd -- "$ROOT/.." && pwd -P)"
placement="$ROOT/ui/PopupPlacement.js"
keyboard_panel="$ROOT/ui/AureliaKeyboardPanel.qml"
notification_surface="$ROOT/plugins/aurelia.notifications/ui/NotificationPopupSurface.qml"

if [[ -f "$placement" ]]; then
    pass "[static] one shared popup placement module exists"
else
    fail "[static] PopupPlacement.js is missing"
fi

if grep -q 'as Placement' "$keyboard_panel" &&
   grep -q 'Placement.computeOrigin' "$keyboard_panel" &&
   grep -q 'as Placement' "$notification_surface" &&
   grep -q 'Placement.computeOrigin' "$notification_surface"; then
    pass "[static] every bar popup routes through the one global placement rule"
else
    fail "[static] a popup surface still computes its own placement"
fi

if grep -q 'popupAlign' "$keyboard_panel" &&
   grep -q 'popupAlign' "$notification_surface"; then
    pass "[static] popups expose the per-widget popupAlign override"
else
    fail "[static] popupAlign override wiring is incomplete"
fi

# The old notification surface clamped a failed anchor mapping into the
# top-left corner; the shared rule centers on the bar instead.
if ! grep -q 'return Qt.point(Math.round(x), Math.round(y))' "$notification_surface"; then
    pass "[static] notification surface no longer hand-rolls a corner fallback"
else
    fail "[static] notification surface still hand-rolls its origin"
fi

if ! command -v node >/dev/null; then
    skip "[unit] popup placement math (node unavailable)"
    return 0
fi

placement_test="$(mktemp --suffix=.js)"
sed '/^\.pragma library/d' "$placement" >"$placement_test"
cat >>"$placement_test" <<'PLACEMENT_EXPORTS'
module.exports = { computeOrigin, normalizeAlign };
PLACEMENT_EXPORTS

if node -e '
const P = require(process.argv[1]);
const near = (a, b) => Math.abs(a - b) < 0.5;
const base = { barPosition: "top", barSize: 30, popupWidth: 200, popupHeight: 100,
    screenW: 1920, screenH: 1080, margin: 8, anchorX: 900, anchorY: 0,
    anchorWidth: 40, anchorHeight: 30, anchored: true };
const follow = P.computeOrigin(base);
const left = P.computeOrigin(Object.assign({}, base, { align: "left" }));
const right = P.computeOrigin(Object.assign({}, base, { align: "right" }));
const center = P.computeOrigin(Object.assign({}, base, { align: "center" }));
const unanchored = P.computeOrigin(Object.assign({}, base, { anchored: false }));
const bottom = P.computeOrigin(Object.assign({}, base, { barPosition: "bottom" }));
const clamped = P.computeOrigin(Object.assign({}, base, { anchorX: 5 }));
const vertical = P.computeOrigin(Object.assign({}, base, { barPosition: "left", anchorY: 500, anchorHeight: 30 }));
const ok =
    near(follow.x, 820) && near(follow.y, 38) &&
    near(left.x, 900) && near(right.x, 740) &&
    near(center.x, 860) && near(center.y, 38) &&
    near(unanchored.x, 860) &&
    near(bottom.y, 1080 - 30 - 100 - 8) &&
    near(clamped.x, 8) &&
    near(vertical.x, 38) && near(vertical.y, 465) &&
    P.normalizeAlign("bogus") === "follow" && P.normalizeAlign("left") === "left";
process.exit(ok ? 0 : 1);
' "$placement_test" >/dev/null; then
    pass "[unit] popup placement follows the widget, honors align, clamps, and never corners"
else
    fail "[unit] popup placement math diverged"
fi
rm -f -- "$placement_test"
