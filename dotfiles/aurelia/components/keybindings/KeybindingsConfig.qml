pragma Singleton
import QtQuick

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
// - Responsive layout constraints rather than rigid fixed-pixel blueprints

QtObject {
    id: config

    // =========================================================================
    // 1. Surface (Palette Window Dimensions & Margins)
    // =========================================================================
    readonly property int palettePreferredWidth: 800
    readonly property int palettePreferredHeight: 480
    readonly property int paletteMinWidth: 580
    readonly property int paletteMinHeight: 340
    readonly property int contentPaddingHorizontal: 16
    readonly property int contentPaddingVertical: 14
    readonly property int surfaceRadius: 12
    readonly property int cardBorderWidth: 1

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
    readonly property int searchBorderRadius: 8
    readonly property int searchPaddingHorizontal: 14

    // =========================================================================
    // 4. List & Rows (Shortcut Table Layout)
    // =========================================================================
    readonly property int rowHeight: 38
    readonly property int rowSpacing: 3
    readonly property int rowRadius: 4
    readonly property int rowPaddingHorizontal: 16
    readonly property int scrollBarWidth: 4

    // =========================================================================
    // 5. Columns (Shortcut List Column Proportions)
    // =========================================================================
    readonly property int shortcutColumnWidth: 350
    readonly property int separatorColumnWidth: 28

    // =========================================================================
    // 6. Settings (Responsive Preferences Layout)
    // =========================================================================
    readonly property int settingsContentPreferredWidth: 620
    readonly property int settingsContentMaxWidth: 680
    readonly property int settingsMarginHorizontal: 24
    readonly property int settingsMarginVertical: 16
    readonly property int settingsBreakpointWidth: 540
    readonly property int settingsValueColumnPreferredWidth: 120
    readonly property int settingsRowMinHeight: 44
    readonly property int settingsRowSpacing: 8
    readonly property int settingsSectionSpacing: 16
    readonly property int settingsBadgeRadius: 4
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
    readonly property int defaultTransitionFast: 100
    readonly property int defaultTransitionNormal: 200
}
