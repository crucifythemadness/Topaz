import QtQuick

// ── BigCoverWindow ────────────────────────────────────────────────────────
// Detachable cover-art viewer — see FloatingPane.qml for the movable/
// resizable/right-click-to-close chrome this builds on. Opened by clicking
// the album cover in NowPlaying.qml (see Main.qml's Loader wiring).
//
// Reuses PlaybackEngine's existing currentLargeCoverSource/currentCoverSource
// properties directly (same fallback expression NowPlaying.qml's own cover
// Image uses) — both already have NOTIFY signals that fire on every track
// change, so this window's cover updates automatically; no new C++ needed.
FloatingPane {
    id: bigCover

    property var engine: null

    title: qsTr("Topaz — Cover")
    color: Theme.surfaceContainerLowest

    // Covers are always square — lock resize to a 1:1 ratio (see
    // FloatingPane.qml's "Aspect-locked resize" for how this is enforced;
    // startSystemResize() can't be constrained mid-drag, so a fixed ratio
    // switches the resize grips to manual, JS-computed geometry instead).
    fixedAspectRatio: 1.0

    // Placeholder while no track / no cover is available yet.
    Rectangle {
        anchors.fill: parent
        visible: coverImage.status !== Image.Ready
        gradient: Gradient {
            orientation: Gradient.Diagonal
            GradientStop { position: 0.0; color: Theme.surfaceContainerHigh }
            GradientStop { position: 1.0; color: Theme.surfaceBright }
        }
        Text {
            anchors.centerIn: parent
            text: "♫"
            font.family:    Theme.fontFamilyHeadline
            font.pixelSize: Math.min(parent.width, parent.height) * 0.25
            font.weight:    Font.Bold
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.30)
        }
    }

    Image {
        id: coverImage
        anchors.fill: parent
        source: bigCover.engine
                ? (bigCover.engine.currentLargeCoverSource !== ""
                   ? bigCover.engine.currentLargeCoverSource
                   : bigCover.engine.currentCoverSource)
                : ""
        // PreserveAspectFit (not NowPlaying's PreserveAspectCrop) since a
        // freshly-opened pane could in principle race a resize before the
        // very first frame; Fit never crops, so nothing is ever lost either
        // way. Constrains decode size to the pane's own size, reactive to
        // resize — matches NowPlaying's sourceSize pattern.
        sourceSize.width:  bigCover.width
        sourceSize.height: bigCover.height
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: status === Image.Ready
    }
}
