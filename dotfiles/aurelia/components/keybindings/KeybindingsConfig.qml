pragma Singleton
import QtQuick
import "../../theme"

// KeybindingsConfig — Authoritative Component Design Configuration
//
// Single source of truth for Keybindings-specific geometry, layout constraints,
// responsive breakpoints, and interaction target dimensions.
//
// Hierarchy:
//   1. Aurelia Design Tokens (Theme.qml) -> Shared shell-wide visual language & tokens
//   2. Keybindings Component Config (KeybindingsConfig.qml) -> Component-owned layout/geometry truth
//   3. User Preferences (preferences.json) -> User-selectable persistent choices (e.g. motion, shortcuts)
//   4. Runtime Component State -> Transient local state (e.g. search query, selected index)
//
// Invariants:
// - Zero user preferences (preferences belong exclusively to preferences.json)
// - Zero color duplication (semantic colors belong exclusively to Theme.qml)
// - Zero duplicate tokens (shared radii, borders, spacing, durations consume Theme.qml)
// - Responsive layout constraints rather than rigid fixed-pixel blueprints

QtObject {
    id: config

    // Component Metadata & Provenance Fingerprint
    readonly property string componentName: "keybindings"
    readonly property string uiRevision: "2026.09.05.r2"

    // =========================================================================
    // 1. Surface (Palette Window Dimensions & Margins)
    // =========================================================================
    readonly property int palettePreferredWidth: 800
    readonly property int palettePreferredHeight: 480
    readonly property int paletteMinWidth: 580
    readonly property int paletteMinHeight: 340
    readonly property int contentPaddingHorizontal: Theme.spacingLg
    readonly property int contentPaddingVertical: 14
    readonly property int surfaceRadius: Theme.radiusLg
    readonly property int cardBorderWidth: Theme.borderWidthDefault

    // =========================================================================
    // 2. Header (Navigation Tabs & Settings Cog)
    // =========================================================================
    readonly property int headerHeight: 36
    readonly property int headerSpacing: 8
    readonly property int tabHeight: 30
    readonly property int tabPaddingHorizontal: 12
    readonly property int tabBorderRadius: 6
    readonly property int cogHitTargetWidth: 34
    readonly property int cogHitTargetHeight: 28
    readonly property int cogIconSize: 21

    // =========================================================================
    // 3. Search (Command Palette Search Bar)
    // =========================================================================
    readonly property int searchHeight: 40
    readonly property int searchBorderRadius: Theme.radiusMd
    readonly property int searchPaddingHorizontal: 14

    // =========================================================================
    // 4. List & Rows (Shortcut Table Layout)
    // =========================================================================
    readonly property int rowHeight: 38
    readonly property int rowSpacing: Theme.rowSpacing
    readonly property int rowRadius: Theme.radiusSm
    readonly property int rowPaddingHorizontal: Theme.spacingLg
    readonly property int scrollBarWidth: Theme.scrollBarWidth

    // =========================================================================
    // 5. Columns (Shortcut List Column Proportions)
    // =========================================================================
    readonly property int shortcutColumnWidth: 350
    readonly property int separatorColumnWidth: 28

    // =========================================================================
    // 6. Settings (Responsive Preferences Layout)
    // =========================================================================
    readonly property int settingsContentPreferredWidth: 640
    readonly property int settingsContentMaxWidth: 720
    readonly property int settingsMarginHorizontal: Theme.spacingXxl
    readonly property int settingsMarginVertical: Theme.spacingLg
    readonly property int settingsBreakpointWidth: 540
    readonly property int settingsValueColumnPreferredWidth: 120
    readonly property int settingsRowMinHeight: 44
    readonly property int settingsRowSpacing: Theme.spacingSm
    readonly property int settingsSectionSpacing: Theme.spacingLg
    readonly property int settingsBadgeRadius: Theme.radiusSm
    readonly property int settingsBadgePaddingHorizontal: 10
    readonly property int settingsBadgeHeight: 26

    // =========================================================================
    // 7. Forms (Custom Executable / Script Creation)
    // =========================================================================
    readonly property int formLabelWidth: 110
    readonly property int formFieldHeight: 38
    readonly property int formFieldSpacing: 10
    readonly property int formBorderRadius: 6
    readonly property int formButtonHeight: 36
    readonly property int formButtonMinWidth: 80

    // =========================================================================
    // 8. Autocomplete (Path Suggestion Dropdown)
    // =========================================================================
    readonly property int autocompleteRowHeight: 32
    readonly property int autocompleteMaxVisibleRows: 5
    readonly property int autocompleteDropdownMaxHeight: 160
    readonly property int autocompleteRadius: 6

    // =========================================================================
    // 9. Motion (Component Baseline Animation Defaults)
    // =========================================================================
    readonly property int defaultTransitionFast: Theme.durationFast
    readonly property int defaultTransitionNormal: Theme.durationNormal
}
