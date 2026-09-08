#!/usr/bin/env bash

# Contract tests for the Aurelia calendar surface. These checks intentionally
# stay source-level: the repository test runner must remain safe to execute
# without starting the live shell or mutating the workstation.

set -Eeuo pipefail

calendar_file="$ROOT/plugins/aurelia.calendar/ui/CalendarPanel.qml"

section "Calendar Surface Geometry and Design Language"

if [[ -f "$calendar_file" ]] &&
   grep -Fq 'readonly property int gridGap: 5' "$calendar_file" &&
   grep -Fq 'readonly property int gridCellSize:' "$calendar_file" &&
   grep -Fq 'readonly property int gridWidth:' "$calendar_file" &&
   grep -Fq 'readonly property int gridHeight:' "$calendar_file" &&
   grep -Fq 'width: panelRoot.gridCellSize' "$calendar_file" &&
   grep -Fq 'height: panelRoot.gridCellSize' "$calendar_file" &&
   grep -Fq 'x: (index % 7)' "$calendar_file" &&
   grep -Fq 'Math.floor(index / 7)' "$calendar_file" &&
   ! grep -Fq 'GridLayout' "$calendar_file"; then
    pass "calendar uses explicit equal-cell geometry instead of stretchable layout rows"
else
    fail "calendar grid geometry is not explicit and equal-cell safe"
fi

if grep -Fq 'for (var index = 0; index < 42; index++)' "$calendar_file" &&
   grep -Fq 'inMonth: current.getMonth() === month' "$calendar_file" &&
   grep -Fq 'weekend: current.getDay() === 0 || current.getDay() === 6' "$calendar_file" &&
   grep -Fq 'isToday: dateKey(current) === todayKey' "$calendar_file"; then
    pass "calendar keeps a stable six-week readout with adjacent-month context"
else
    fail "calendar date model does not provide stable six-week context"
fi

if grep -Fq 'AURELIA / CALENDAR' "$calendar_file" &&
   grep -Fq 'text: "VIEWING"' "$calendar_file" &&
   grep -Fq 'text: "← →  MONTHS     T  TODAY"' "$calendar_file" &&
   grep -Fq 'popupWidth: 388' "$calendar_file" &&
   grep -Fq 'popupHeight: 486' "$calendar_file"; then
    pass "calendar exposes the Aurelia instrument-panel hierarchy and controls"
else
    fail "calendar visual hierarchy or navigation affordances are incomplete"
fi
