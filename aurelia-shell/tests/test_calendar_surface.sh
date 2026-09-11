#!/usr/bin/env bash

# Contract tests for the Aurelia calendar surface. These checks intentionally
# stay source-level: the repository test runner must remain safe to execute
# without starting the live shell or mutating the workstation.

set -Eeuo pipefail

calendar_file="$ROOT/plugins/aurelia.calendar/ui/CalendarPanel.qml"
theme_file="$ROOT/theme/Theme.qml"
theme_conf="$ROOT/theme.conf"

section "Calendar Surface Geometry and Design Language"

if [[ -f "$calendar_file" ]] &&
   grep -Fq 'readonly property int gridGap: Theme.calendarCellGap' "$calendar_file" &&
   grep -Fq 'readonly property int gridCellSize:' "$calendar_file" &&
   grep -Fq 'readonly property int gridWidth:' "$calendar_file" &&
   grep -Fq 'readonly property int gridHeight:' "$calendar_file" &&
   grep -Fq 'required property int index' "$calendar_file" &&
   grep -Fq 'width: panelRoot.gridCellSize' "$calendar_file" &&
   grep -Fq 'height: panelRoot.gridCellSize' "$calendar_file" &&
   grep -Fq 'x: (index % 7)' "$calendar_file" &&
   grep -Fq 'Math.floor(index / 7)' "$calendar_file" &&
   ! grep -Fq 'GridLayout {' "$calendar_file"; then
    pass "calendar uses explicit equal-cell geometry and a bound repeater index"
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
   grep -Fq 'text: "← →  MONTHS    T  TODAY"' "$calendar_file" &&
   grep -Fq 'contentPadding: Theme.calendarPadding' "$calendar_file" &&
   grep -Fq 'popupWidth: Theme.calendarPopupWidth' "$calendar_file" &&
   grep -Fq 'popupHeight: Theme.calendarPopupHeight' "$calendar_file" &&
   grep -Fq 'Theme.calendarAccent' "$calendar_file" &&
   grep -Fq 'color: modelData.isToday' "$calendar_file" &&
   grep -Fq '? Theme.bgBase' "$calendar_file" &&
   ! grep -Fq 'text: "VIEWING"' "$calendar_file"; then
    pass "calendar exposes the compact customizable Aurelia surface"
else
    fail "calendar compact visual hierarchy or customization hooks are incomplete"
fi

if grep -Fq 'readonly property int calendarPopupWidth:' "$theme_file" &&
   grep -Fq 'readonly property int calendarCellSize:' "$theme_file" &&
   grep -Fq 'readonly property color calendarAccent:' "$theme_file" &&
   grep -q '^calendarPopupWidth = ' "$theme_conf" &&
   grep -q '^calendarAccent = ' "$theme_conf" &&
   grep -Fq 'property int contentPadding: Theme.popupPadding' "$ROOT/ui/AureliaKeyboardPanel.qml"; then
    pass "calendar density, colors, and popup padding are customizable through theme.conf"
else
    fail "calendar customization tokens are incomplete"
fi
