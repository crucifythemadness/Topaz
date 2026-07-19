pragma Singleton
import QtQuick

// Design-token store for the "Technical Monolith" dark theme.
// All QML files in the Topaz module access this as `Theme.<property>`
// without an explicit import (same-module types are auto-visible).
QtObject {

    // в”Ђв”Ђ Surface Hierarchy в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    // Use background shifts instead of borders to separate regions.
    readonly property color surface:                 "#131313"
    readonly property color surfaceContainerLowest:  "#0E0E0E"
    readonly property color surfaceContainerLow:     "#1C1B1B"
    readonly property color surfaceContainer:        "#201F1F"
    readonly property color surfaceContainerHigh:    "#2A2A2A"
    readonly property color surfaceContainerHighest: "#353534"
    readonly property color surfaceBright:           "#393939"

    // в”Ђв”Ђ Brand Palette в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    readonly property color primary:               "#D0BCFF"
    readonly property color primaryContainer:      "#A078FF"
    readonly property color fgPrimary:             "#3C0091"
    readonly property color fgPrimaryContainer:    "#340080"
    readonly property color fgPrimaryFixedVariant: "#5516BE"

    readonly property color secondary:             "#44E2CD"
    readonly property color secondaryContainer:    "#03C6B2"
    readonly property color fgSecondary:           "#003731"
    readonly property color fgSecondaryContainer:  "#004D44"

    readonly property color tertiary:              "#FFB869"
    readonly property color fgTertiary:            "#482900"
    readonly property color fgTertiaryFixedVariant:"#673D00"

    // в”Ђв”Ђ Surface On-Colors в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    readonly property color fgSurface:        "#E5E2E1"
    readonly property color fgSurfaceVariant: "#CBC3D7"

    // в”Ђв”Ђ Stroke в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    readonly property color outline:        "#958EA0"
    readonly property color outlineVariant: "#494454"

    // в”Ђв”Ђ Error в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    readonly property color error:          "#FFB4AB"
    readonly property color errorContainer: "#93000A"

    // в”Ђв”Ђ Pre-computed Alpha Variants в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    // outlineVariant (#494454) at key opacities
    readonly property color ov10: Qt.rgba(0x49/255, 0x44/255, 0x54/255, 0.10)
    readonly property color ov20: Qt.rgba(0x49/255, 0x44/255, 0x54/255, 0.20)
    readonly property color ov30: Qt.rgba(0x49/255, 0x44/255, 0x54/255, 0.30)
    // primary (#D0BCFF) at key opacities
    readonly property color p05:  Qt.rgba(0xD0/255, 0xBC/255, 0xFF/255, 0.05)
    readonly property color p10:  Qt.rgba(0xD0/255, 0xBC/255, 0xFF/255, 0.10)
    readonly property color p20:  Qt.rgba(0xD0/255, 0xBC/255, 0xFF/255, 0.20)
    // secondary (#44E2CD) at key opacities
    readonly property color s05:  Qt.rgba(0x44/255, 0xE2/255, 0xCD/255, 0.05)
    readonly property color s10:  Qt.rgba(0x44/255, 0xE2/255, 0xCD/255, 0.10)
    readonly property color s20:  Qt.rgba(0x44/255, 0xE2/255, 0xCD/255, 0.20)

    // в”Ђв”Ђ Typography Families (ordered by preference) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    // Manrope, Inter, JetBrains Mono must be embedded as Qt resources
    // for the intended look. System fonts are fallbacks only.
    readonly property string fontFamilyHeadline: "Manrope"
    readonly property string fontFamilyBody:    "Inter"
    readonly property string fontFamilyMono:    "JetBrains Mono"

    // в”Ђв”Ђ Font Sizes (px) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    readonly property int displayLg:  32
    readonly property int headlineLg: 24
    readonly property int headlineMd: 20
    readonly property int headlineSm: 18
    readonly property int titleMd:    14
    readonly property int labelLg:    12
    readonly property int labelMd:    11
    readonly property int labelSm:    10
    readonly property int labelXs:     9
    readonly property int monoMd:     11
    readonly property int monoSm:     10
    readonly property int monoLg:     12

    // в”Ђв”Ђ Letter Spacing (px) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    readonly property real lsWide:   1.5
    readonly property real lsWidest: 3.0
    readonly property real lsTight: -0.5

    // в”Ђв”Ђ Spacing (px) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    readonly property int sp1:  4
    readonly property int sp2:  8
    readonly property int sp3: 12
    readonly property int sp4: 16
    readonly property int sp5: 20
    readonly property int sp6: 24

    // в”Ђв”Ђ Corner Radii (px) в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
    readonly property int radiusSm:   2
    readonly property int radiusMd:   4
    readonly property int radiusLg:  12
    readonly property int radiusFull: 9999
}
