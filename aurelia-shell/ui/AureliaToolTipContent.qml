import QtQuick
import QtQuick.Layouts
import "../theme"

// Shared tooltip body for both tooltip hosts (the PopupWindow `AureliaToolTip`
// used by bar widgets and the in-scene `AureliaInlineToolTip` used inside the
// panel). It owns the text, the optional structured `lines` / `list` / `footer`
// content and the intrinsic size, so the two hosts and their callers cannot
// drift apart.
//
// Colours are inherited from the running theme only. Tooltip text is always
// `Theme.tooltip.text`: `Theme.textSecondary` and the alert tokens measure
// below the contrast floor on the tooltip surface, so tone is carried by a
// leading glyph or dot instead of by the text colour.
Item {
    id: contentRoot

    // Plain, backward-compatible body. Used when no structured content is set.
    property string text: ""
    // Each line: { text, tone: "default" | "warning" | "error", strong }.
    property var lines: []
    // Each row: { name, value, tone: "success" | "warning" | "error" | "neutral" }.
    property var list: []
    // One line below a hairline: { text, tone }.
    property var footer: null
    // The single source of truth for the tooltip text width. Both hosts (the
    // bar PopupWindow `AureliaToolTip` and the in-panel `AureliaInlineToolTip`)
    // inherit this default; neither declares nor forwards its own cap, because
    // two caps for one shared body drift, and 300 px wraps a string such as
    // "<Provider> didn't report its monthly limit" for a long provider name.
    // A future host override MUST state its reason inline and update the
    // static test that guards this invariant.
    property int maxTextWidth: 360
    readonly property bool hasLines: Array.isArray(lines) && lines.length > 0
    readonly property bool hasList: Array.isArray(list) && list.length > 0
    readonly property bool hasFooter: footer !== null && footer !== undefined &&
        String(footer.text || "") !== ""
    readonly property bool structured: hasLines || hasList || hasFooter

    readonly property int bodyFontSize: Theme.fontSizeSm

    // One-way wrap decision for the plain-text body. The alignment below must
    // NOT read `lineCount`: lineCount is a function of the Text's own laid-out
    // width, which is itself derived from this body's alignment-sensitive
    // layout, so `lineCount > 1 ? AlignLeft : AlignHCenter` was a binding loop
    // (reproduced on the live shell as:
    //   Binding loop detected for property "horizontalAlignment" in
    //   AureliaToolTipContent.qml). TextMetrics measures the unconstrained
    //   advance against the same cap the layout uses, so the wrap decision
    //   reads only `text`, the font and `maxTextWidth`.
    readonly property bool textExceedsCap: plainTextMetrics.advanceWidth > maxTextWidth
    readonly property bool textHasNewline: contentRoot.text.indexOf("\n") >= 0
    readonly property bool textIsWrapped: !contentRoot.structured &&
        (contentRoot.textExceedsCap || contentRoot.textHasNewline)

    TextMetrics {
        id: plainTextMetrics
        font.family: Theme.fontFamilyResolved
        font.pixelSize: contentRoot.bodyFontSize
        text: contentRoot.text
    }

    function toneGlyph(tone) {
        if (tone === "warning") return "\u25b2"
        if (tone === "error") return "\u25cf"
        return ""
    }

    function toneColor(tone) {
        if (tone === "warning") return Theme.warning
        if (tone === "error") return Theme.error
        if (tone === "success") return Theme.success
        return Theme.tooltip.text
    }

    function lineText(line) {
        var glyph = toneGlyph(line ? line.tone : "")
        return (glyph !== "" ? glyph + " " : "") + String((line && line.text) || "")
    }

    // The intrinsic width comes from a hidden, never-width-constrained
    // measurement column that mirrors the visible one with NoWrap text. This
    // is deterministic and avoids both binding loops and imperative
    // TextMetrics reads that are not available synchronously.
    implicitWidth: Math.min(maxTextWidth, Math.max(1, measureColumn.implicitWidth))
    // Floored: a model rebuild momentarily empties the visible column, and a
    // zero intrinsic height would resize (and can unmap) a PopupWindow host.
    implicitHeight: Math.max(1, bodyColumn.implicitHeight)

    Column {
        id: measureColumn
        visible: false
        spacing: 0

        Text {
            visible: !contentRoot.structured
            text: contentRoot.text
            font.family: Theme.fontFamilyResolved
            font.pixelSize: contentRoot.bodyFontSize
            wrapMode: Text.NoWrap
        }

        Repeater {
            model: contentRoot.hasList ? contentRoot.list : []

            delegate: Row {
                required property var modelData
                spacing: Theme.spacingSm

                Item { width: 8; height: 8 }

                Text {
                    text: String(modelData.name || "")
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: contentRoot.bodyFontSize
                    font.weight: Theme.fontWeightBold
                    wrapMode: Text.NoWrap
                }

                Text {
                    text: String(modelData.value || "")
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: contentRoot.bodyFontSize
                    wrapMode: Text.NoWrap
                }
            }
        }

        Repeater {
            model: contentRoot.hasLines ? contentRoot.lines : []

            delegate: Text {
                required property var modelData
                text: contentRoot.lineText(modelData)
                font.family: Theme.fontFamilyResolved
                font.pixelSize: contentRoot.bodyFontSize
                font.weight: modelData.strong === true
                    ? Theme.fontWeightBold : Theme.fontWeightNormal
                wrapMode: Text.NoWrap
            }
        }

        Text {
            visible: contentRoot.hasFooter
            text: contentRoot.footer ? contentRoot.lineText(contentRoot.footer) : ""
            font.family: Theme.fontFamilyResolved
            font.pixelSize: contentRoot.bodyFontSize
            wrapMode: Text.NoWrap
        }
    }

    ColumnLayout {
        id: bodyColumn
        width: contentRoot.implicitWidth
        spacing: Theme.spacingXs

        // Plain text: centred when it is a single line, left aligned otherwise.
        Text {
            visible: !contentRoot.structured
            Layout.fillWidth: true
            text: contentRoot.text
            color: Theme.tooltip.text
            font.family: Theme.fontFamilyResolved
            font.pixelSize: contentRoot.bodyFontSize
            lineHeight: 1.15
            wrapMode: Text.WordWrap
            horizontalAlignment: contentRoot.textIsWrapped
                ? Text.AlignLeft : Text.AlignHCenter
        }

        // Structured list: tone dot, bold name, right-aligned value.
        Repeater {
            model: contentRoot.hasList ? contentRoot.list : []

            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    Layout.alignment: Qt.AlignVCenter
                    radius: 4
                    color: contentRoot.toneColor(modelData.tone)
                }

                Text {
                    text: String(modelData.name || "")
                    color: Theme.tooltip.text
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: contentRoot.bodyFontSize
                    font.weight: Theme.fontWeightBold
                    wrapMode: Text.NoWrap
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: String(modelData.value || "")
                    color: Theme.tooltip.text
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: contentRoot.bodyFontSize
                    wrapMode: Text.NoWrap
                }
            }
        }

        // Structured lines: optional leading tone glyph, wrapping text.
        Repeater {
            model: contentRoot.hasLines ? contentRoot.lines : []

            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 0

                Text {
                    visible: contentRoot.toneGlyph(modelData.tone) !== ""
                    text: contentRoot.toneGlyph(modelData.tone)
                    color: contentRoot.toneColor(modelData.tone)
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: contentRoot.bodyFontSize
                    wrapMode: Text.NoWrap
                }

                Text {
                    Layout.fillWidth: true
                    text: contentRoot.lineText(modelData)
                    color: Theme.tooltip.text
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: contentRoot.bodyFontSize
                    font.weight: modelData.strong === true
                        ? Theme.fontWeightBold : Theme.fontWeightNormal
                    lineHeight: 1.15
                    wrapMode: Text.WordWrap
                }
            }
        }

        // Footer: hairline, then one line.
        Rectangle {
            visible: contentRoot.hasFooter
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.tooltip.border
        }

        RowLayout {
            visible: contentRoot.hasFooter
            Layout.fillWidth: true
            spacing: 0

            Text {
                visible: contentRoot.toneGlyph(contentRoot.footer ? contentRoot.footer.tone : "") !== ""
                text: contentRoot.toneGlyph(contentRoot.footer ? contentRoot.footer.tone : "")
                color: contentRoot.toneColor(contentRoot.footer ? contentRoot.footer.tone : "")
                font.family: Theme.fontFamilyResolved
                font.pixelSize: contentRoot.bodyFontSize
                wrapMode: Text.NoWrap
            }

            Text {
                Layout.fillWidth: true
                text: contentRoot.footer ? contentRoot.lineText(contentRoot.footer) : ""
                color: Theme.tooltip.text
                font.family: Theme.fontFamilyResolved
                font.pixelSize: contentRoot.bodyFontSize
                lineHeight: 1.15
                wrapMode: Text.WordWrap
            }
        }
    }
}
