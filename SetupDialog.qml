import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
// qmllint disable Quick.layout-positioning
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// ── SetupDialog ──────────────────────────────────────────────────────────
// Modal setup window with seven tabs:
//   • GENRES        — add/delete genre names (up to 48) and choose which of them
//                     (up to 40) are enabled via a per-cell checkbox to appear as
//                     GenreBar buttons; SCAN FOLDERS discovers the genres tagged in
//                     the monitored folders (FoundGenresDialog, see UC-36)
//   • FILE MONITORING — add/delete monitored folders (with subfolders toggle)
//   • PLAYBACK      — choose the playback backend (FFmpeg/BASS Audio Library) and
//                     enable/disable crossfade and set its length (see UC-15)
//   • AUTO PLAY     — settings for the still-unimplemented AUTO PLAY feature:
//                     Queue Horizon lookahead, Consider Genre, and Consider
//                     Rating + Minimum Rating (see UC-14)
//   • AUDIO VISUALIZER — bar count, color, decay/sensitivity, opacity (see UC-19)
//   • MILKDROP      — preset folders, shuffle/duration, beat sensitivity (see UC-20)
//   • MISC          — one-off maintenance actions; currently just Remove
//                     Abandoned Ratings (see UC-24)
//
// Usage in Main.qml:
//   SetupDialog { id: setupDialog; appConfig: appConfig; playbackEngine: engine }
//   ...
//   setupDialog.open()

Popup {
    id: root

    // Required: bind to the AppConfig instance declared in Main.qml
    property AppConfig appConfig: null
    // Required: bind to the LibraryModel instance declared in Main.qml --
    // used only to trigger an automatic rescan on close, see below.
    property LibraryModel libraryModel: null
    // Required: bind to the PlaybackEngine instance declared in Main.qml --
    // used only to read activeBackendName for the PLAYBACK tab's "Currently
    // active" indicator, see below.
    property PlaybackEngine playbackEngine: null
    // Required: bind to the MilkdropCleanupController instance declared in
    // Main.qml -- backs the MISC tab's "Cleanup Incompatible Milkdrop
    // Presets" feature, see UC-25.
    property var cleanupController: null
    // Main.qml -- backs the MISC tab's "Backup/Restore Topaz Environment"
    // feature, see UC-27.
    property var backupRestoreController: null
    // Main.qml -- backs the GENRES tab's SCAN FOLDERS button / FOUND GENRES
    // dialog (genre discovery, see UC-36).
    property var genreScanController: null

    // ── Internal selection state ─────────────────────────────────────────
    property int selectedGenreIndex:  -1
    property int selectedFolderIndex: -1
    property int selectedMilkdropFolderIndex: -1

    // Set explicitly by each of the 5 real FILE MONITORING edit actions
    // below (add/remove/clear folder, SUBFOLDERS toggle, ACTIVE toggle) --
    // see UC-04/UC-05. NOT inferred from AppConfig.foldersChanged anymore:
    // that signal is also fired by AppConfig.refreshFolderAvailability()
    // after any background scan completes (see UC-07), which is not a user
    // edit and must not trigger the auto-rescan-on-close below. Reset per
    // open session in onAboutToShow so only changes made *this* time count.
    property bool _foldersDirty: false
    // Set when genres were added from FOUND GENRES (UC-36): their music is
    // only in the library after a scan, so closing Setup runs one -- the same
    // auto-rescan hook as _foldersDirty. A genre typed in by hand deliberately
    // doesn't set it (unchanged behaviour).
    property bool _genresDiscovered: false

    // Small "turning circle" busy indicator -- a dot orbiting a faint ring.
    // Stands in for the MILKDROP tab's PRESETS count while
    // scanPresetFolderCountsAsync() is still counting a folder in the
    // background (see refreshMilkdropFolderRows() below). No existing
    // spinner/BusyIndicator anywhere else in this codebase to reuse, and
    // every other progress affordance here is hand-rolled with Theme.*
    // rather than a default-styled QQC2 control.
    component BusySpinner: Item {
        implicitWidth: 16
        implicitHeight: 16

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.outlineVariant
        }

        Item {
            anchors.fill: parent

            RotationAnimation on rotation {
                loops: Animation.Infinite
                from: 0; to: 360
                duration: 900
            }

            Rectangle {
                width: 4; height: 4
                radius: 2
                color: Theme.secondary
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
            }
        }
    }

    // ── Geometry ─────────────────────────────────────────────────────────
    // Deliberately NOT anchors.centerIn: Popup's anchors.centerIn is backed
    // by QQuickPopupAnchors, which keeps reasserting x/y from C++ (not a
    // plain QML binding) — it fights the header drag MouseArea below and
    // the popup never visibly moves. Plain x/y bindings behave like normal
    // Item bindings and get cleanly overridden by the drag's direct
    // assignment, same as everywhere else in QML.
    x: Overlay.overlay ? (Overlay.overlay.width  - width)  / 2 : 0
    y: Overlay.overlay ? (Overlay.overlay.height - height) / 2 : 0
    // 1096 = room for a 6th genreManageGrid column (48 genres) while keeping the
    // cells exactly as wide as the earlier 5-column/920 px layout (168 px):
    // 6 * 168 + 5 * 8 spacing + 2 * 24 margins. Was 920 (itself widened once so
    // the cells grew ~20% for longer genre names).
    width:  1096
    height: 760   // grown to fit the AUTO PLAY tab's 8th settings row (Exceptions,
                  // a single-row 3-option radio group)
    padding: 0

    modal: true
    closePolicy: Popup.NoAutoClose

    // Dragging the header (below) moves this Popup via direct x/y
    // assignment, which breaks the bindings above — recompute them here on
    // every open so the dialog always reopens centered and the dragged
    // position is never persisted (no AppConfig involvement).
    onAboutToShow: {
        x = Overlay.overlay ? (Overlay.overlay.width  - width)  / 2 : 0
        y = Overlay.overlay ? (Overlay.overlay.height - height) / 2 : 0
        _foldersDirty = false
        _genresDiscovered = false
        // Dialog is a persistent instance that remembers its last-selected
        // tab across close/reopen -- if it reopens directly on MILKDROP,
        // the tab-switch handler below never fires, so refresh here too.
        if (tabBar.currentTab === 5) refreshMilkdropFolderRows()
    }

    // Auto-rescan if FILE MONITORING was touched this session -- see UC-04/
    // UC-05 -- or genres were added from FOUND GENRES (UC-36).
    // closePolicy: Popup.NoAutoClose (below) means the header's ✕ button is
    // the only way this fires, so this is a single reliable hook.
    onClosed: {
        if ((_foldersDirty || _genresDiscovered) && libraryModel) libraryModel.startFullScan()
        _foldersDirty = false
        _genresDiscovered = false
    }

    // Dark scrim behind the dialog
    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.72)
    }

    // Dialog surface
    background: Rectangle {
        color:  Theme.surfaceContainerLow
        radius: Theme.radiusLg
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── Header bar ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color:  Theme.surfaceContainerHigh
            radius: Theme.radiusLg

            // Drag-to-move — declared first so it sits underneath the close
            // button's own MouseArea below (later siblings win input in
            // overlapping regions), leaving the ✕ click unaffected.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                property real pressX: 0
                property real pressY: 0

                onPressed: (mouse) => { pressX = mouse.x; pressY = mouse.y }
                onPositionChanged: (mouse) => {
                    if (pressed) {
                        root.x += mouse.x - pressX
                        root.y += mouse.y - pressY
                    }
                }
            }

            // Square off the bottom corners so they sit flush against content
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Theme.radiusLg
                color:  parent.color
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 16 }
                spacing: 0

                Text {
                    text: "SETUP"
                    font.family:      Theme.fontFamilyHeadline
                    font.pixelSize:   Theme.headlineSm
                    font.weight:      Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                // Close ✕ button
                Rectangle {
                    width: 32; height: 32
                    radius: Theme.radiusFull
                    color: closeHover.containsMouse
                           ? Theme.surfaceContainerHighest : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\u2715"   // ✕
                        font.pixelSize: 14
                        color: Theme.fgSurfaceVariant
                    }
                    MouseArea {
                        id: closeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked:    root.close()
                    }
                }
            }
        }

        // ── Tab bar ──────────────────────────────────────────────────────
        Item {
            id: tabBar
            Layout.fillWidth: true
            height: 44

            property int currentTab: 0

            Row {
                anchors { left: parent.left; leftMargin: 24 }
                height: parent.height
                spacing: 0

                Repeater {
                    model: ["GENRES", "FILE MONITORING", "PLAYBACK", "AUTO PLAY", "AUDIO VISUALIZER", "MILKDROP", "MISC"]

                    delegate: Item {
                        width:  tabLabel.implicitWidth + 32
                        height: tabBar.height

                        readonly property bool isActive: tabBar.currentTab === index

                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.family:        Theme.fontFamilyBody
                            font.pixelSize:     Theme.labelSm
                            font.weight:        isActive ? Font.Bold : Font.Medium
                            font.letterSpacing: Theme.lsWidest
                            color: isActive ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        // Active underline
                        Rectangle {
                            visible: isActive
                            anchors {
                                bottom: parent.bottom
                                horizontalCenter: parent.horizontalCenter
                            }
                            width:  tabLabel.implicitWidth
                            height: 2
                            color:  Theme.primary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape:  Qt.PointingHandCursor
                            onClicked: {
                                tabBar.currentTab       = index
                                root.selectedGenreIndex  = -1
                                root.selectedFolderIndex = -1
                                root.selectedMilkdropFolderIndex = -1
                                if (index === 5) root.refreshMilkdropFolderRows()
                            }
                        }
                    }
                }
            }

            // Ghost bottom divider
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color:  Theme.ov10
            }
        }

        // ── Content area (both panels overlap; only one visible) ─────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true

            // ────────────────────────────────────────────────────────────
            // PANEL 1 — GENRES
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 0

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 12

                    // Genre chips — scrollable area
                    Item {
                        id: genreGridArea
                        Layout.fillWidth:  true
                        Layout.fillHeight: true

                        // Drag-to-reorder state (-1 = no drag active). Same
                        // two-plain-int pattern PlaybackQueue's queueArea uses
                        // for queue reordering — see UC-11/UC-33.
                        property int reorderFrom: -1
                        property int reorderTo:   -1
                        readonly property int genreCount:
                            root.appConfig ? root.appConfig.genres.length : 0

                        // Commits a finished drag. Lives here (not in the
                        // delegate) so it outlives the Repeater item that
                        // triggered it — see the Qt.callLater note at the
                        // drag handle's onReleased below.
                        function commitGenreMove(from, to) {
                            if (!root.appConfig) return
                            if (from < 0 || to < 0 || from === to) return
                            root.appConfig.moveGenre(from, to)

                            // Keep DELETE SELECTED pointing at the same
                            // *genre*, not the same slot — mirrors
                            // PlaybackEngine::moveTrack's m_currentIndex
                            // fixup, plus the sel === from case (the queue
                            // can't hit that; this grid can, since the
                            // selected cell is often the one being dragged).
                            var sel = root.selectedGenreIndex
                            if (sel < 0) return
                            if (sel === from)                              sel = to
                            else if (from < to && sel > from && sel <= to) sel -= 1
                            else if (from > to && sel >= to && sel <  from) sel += 1
                            root.selectedGenreIndex = sel
                        }

                        // Empty-state hint
                        Text {
                            anchors.centerIn: parent
                            visible: !root.appConfig || root.appConfig.genres.length === 0
                            text: "No genres configured.\nType a genre name below and click ADD."
                            horizontalAlignment: Text.AlignHCenter
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelLg
                            color: Theme.fgSurfaceVariant
                        }

                        // Fixed no-scroll grid — sized to hold up to 48 configured
                        // genres (6 columns × 8 rows). Each cell carries its own
                        // enable/disable checkbox (top right) controlling whether
                        // that genre is one of the <= 40 shown as a GenreBar
                        // button — see AppConfig.enabledGenres / UC-03. The
                        // configured-genre ceiling here is intentionally higher
                        // than GenreBar's own 40-button (10 x 4) capacity.
                        Grid {
                            id: genreManageGrid
                            anchors.fill: parent
                            visible: root.appConfig !== null && root.appConfig.genres.length > 0
                            clip: true              // defensive: beyond 48 genres, extra
                                                     // rows clip rather than overflow —
                                                     // AppConfig.addGenre() enforces that
                                                     // ceiling so this should never trigger
                            columns: 6
                            rowSpacing:    8
                            columnSpacing: 8

                            // Shared by the cell delegate, the drag hit-test
                            // mapping and the drop indicator below — all three
                            // must agree on the pitch or the indicator drifts.
                            readonly property real cellW: (width - (columns - 1) * columnSpacing) / columns
                            readonly property real cellH: 54
                            readonly property real pitchX: cellW + columnSpacing
                            readonly property real pitchY: cellH + rowSpacing

                            Repeater {
                                model: root.appConfig ? root.appConfig.genres : []

                                delegate: Rectangle {
                                    id: genreCell
                                    width:  genreManageGrid.cellW
                                    height: genreManageGrid.cellH
                                    radius: Theme.radiusSm

                                    // Dim this cell while it is the one being
                                    // dragged — no floating ghost copy, the
                                    // source just fades (UC-11 convention).
                                    opacity: genreGridArea.reorderFrom === index ? 0.45 : 1.0

                                    readonly property bool isSelected:
                                        root.selectedGenreIndex === index
                                    // Deliberately reads the enabledGenres property
                                    // directly (not isGenreEnabled()) -- QML only
                                    // re-evaluates a binding off a NOTIFYing
                                    // Q_PROPERTY it reads, not off an arbitrary
                                    // Q_INVOKABLE call, so this must not be
                                    // isGenreEnabled(modelData) or the checkbox
                                    // would freeze after its first paint.
                                    readonly property bool isEnabled:
                                        root.appConfig !== null
                                        && root.appConfig.enabledGenres.indexOf(modelData) !== -1
                                    readonly property bool atCap:
                                        root.appConfig !== null
                                        && root.appConfig.enabledGenres.length >= root.appConfig.maxEnabledGenres()

                                    color: isSelected
                                           ? Theme.secondaryContainer
                                           : cellHover.containsMouse
                                             ? Theme.surfaceContainerHighest
                                             : Theme.surfaceContainerHigh

                                    // Hover glow — matches GenreBar's micro-slab rule
                                    Rectangle {
                                        anchors { left: parent.left; right: parent.right; top: parent.top }
                                        height: 2
                                        color: Theme.primary
                                        visible: cellHover.containsMouse && !genreCell.isSelected
                                        radius: Theme.radiusSm
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: 5
                                        text: modelData.toUpperCase()
                                        font.family:        Theme.fontFamilyBody
                                        font.pixelSize:     Theme.labelMd
                                        font.letterSpacing: 1.2
                                        elide: Text.ElideRight
                                        width: parent.width - 56   // reserve the 24px drag-handle
                                                                    // strip on the left and the 28px
                                                                    // checkbox column on the right
                                        horizontalAlignment: Text.AlignHCenter
                                        color: genreCell.isSelected
                                               ? Theme.fgSecondaryContainer
                                               : Theme.fgSurfaceVariant
                                    }

                                    // Enable/disable checkbox — whether this genre
                                    // is one of the <= 40 shown in GenreBar. Given
                                    // its own reserved column (see cellHover below)
                                    // rather than overlapping it with z-stacking,
                                    // so there's no ambiguity over which MouseArea
                                    // a click in this corner reaches. Hit area
                                    // (28x28) is deliberately bigger than the
                                    // visible 18x18 checkbox glyph for an easier
                                    // target.
                                    Item {
                                        id: genreEnableHit
                                        width: 28; height: 28
                                        anchors { top: parent.top; right: parent.right; margins: 2 }

                                        Rectangle {
                                            id: genreEnableBox
                                            width: 18; height: 18
                                            anchors.centerIn: parent
                                            radius: 3
                                            opacity: genreCell.isEnabled || !genreCell.atCap ? 1.0 : 0.35
                                            color: genreCell.isEnabled
                                                   ? Theme.secondaryContainer
                                                   : "transparent"
                                            border.width: genreCell.isEnabled ? 0 : 1
                                            border.color: Theme.outlineVariant

                                            Text {
                                                anchors.centerIn: parent
                                                visible: genreCell.isEnabled
                                                text: "✓"   // ✓
                                                font.pixelSize: 11
                                                font.weight:    Font.Bold
                                                color: Theme.fgSecondaryContainer
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: (genreCell.isEnabled || !genreCell.atCap)
                                                         ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (root.appConfig)
                                                    root.appConfig.setGenreEnabled(
                                                        modelData, !genreCell.isEnabled)
                                            }
                                        }
                                    }

                                    // ── Reorder drag handle ──────────────────
                                    // Reserved 24px column on the cell's left
                                    // edge, same non-overlapping-hit-columns
                                    // convention as genreEnableHit above:
                                    // dragging here never selects the cell,
                                    // clicking the cell body never starts a
                                    // drag. Every genre is draggable, enabled
                                    // or not — order and enabled-membership
                                    // are orthogonal (see UC-33). The Item and
                                    // its MouseArea are always present — only
                                    // the glyph's visible reacts to hover,
                                    // which is the safe side of the
                                    // hover-visibility deadlock described in
                                    // UC-11 (the deadlock only occurs when the
                                    // handle *item itself* is hidden based on
                                    // a hover flag its own MouseArea steals).
                                    Item {
                                        id: genreDragHandle
                                        width: 24
                                        z: 2
                                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "⠇"   // braille six-dot — same drag-handle glyph as PlaybackQueue
                                            font.pixelSize: 12
                                            color: Theme.fgSurfaceVariant
                                            visible: genreDragMA.containsMouse
                                                     || cellHover.containsMouse
                                                     || genreGridArea.reorderFrom === index
                                        }

                                        MouseArea {
                                            id: genreDragMA
                                            anchors.fill: parent
                                            hoverEnabled:    true
                                            // No Flickable ancestor here (the grid
                                            // is fixed/no-scroll), so nothing can
                                            // currently steal the gesture — kept to
                                            // match UC-11 and to stay correct if
                                            // this panel ever gains one.
                                            preventStealing: true
                                            cursorShape: genreGridArea.reorderFrom >= 0
                                                         ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                                            onPressed: function(mouse) {
                                                if (genreGridArea.genreCount < 2) return
                                                genreGridArea.reorderFrom = index
                                                genreGridArea.reorderTo   = index
                                            }

                                            onPositionChanged: function(mouse) {
                                                if (genreGridArea.reorderFrom < 0) return
                                                // 2D hit test, straight into
                                                // genreManageGrid's local space --
                                                // no contentY term because nothing
                                                // here scrolls (cf. UC-11, which
                                                // had to map into a ListView's
                                                // contentItem).
                                                var pt   = mapToItem(genreManageGrid, mouse.x, mouse.y)
                                                var cols = genreManageGrid.columns
                                                var col  = Math.floor(pt.x / genreManageGrid.pitchX)
                                                var row  = Math.floor(pt.y / genreManageGrid.pitchY)
                                                col = Math.max(0, Math.min(col, cols - 1))
                                                row = Math.max(0, row)
                                                var flat = row * cols + col
                                                // Clamping (not rejecting)
                                                // out-of-range positions is
                                                // UC-11's rule: dragging past the
                                                // last genre or onto a trailing
                                                // empty slot simply means "move
                                                // to the end".
                                                genreGridArea.reorderTo =
                                                    Math.max(0, Math.min(flat, genreGridArea.genreCount - 1))
                                            }

                                            onReleased: function(mouse) {
                                                var from = genreGridArea.reorderFrom
                                                var to   = genreGridArea.reorderTo
                                                // Reset first so the indicator
                                                // is gone before the model
                                                // changes.
                                                genreGridArea.reorderFrom = -1
                                                genreGridArea.reorderTo   = -1
                                                // Deferred one tick on purpose:
                                                // moveGenre() emits
                                                // genresChanged synchronously,
                                                // which resets this Repeater's
                                                // QStringList model and tears
                                                // down *this very delegate* --
                                                // including the MouseArea whose
                                                // handler we are standing in.
                                                // Qt.callLater moves the
                                                // mutation out of that frame
                                                // entirely.
                                                if (from >= 0 && to >= 0 && from !== to)
                                                    Qt.callLater(genreGridArea.commitGenreMove, from, to)
                                            }
                                        }
                                    }

                                    // Cell-wide selection (for DELETE SELECTED) --
                                    // deliberately stops short of genreDragHandle's
                                    // column on the left and genreEnableHit's
                                    // column on the right so none ever overlap.
                                    MouseArea {
                                        id: cellHover
                                        anchors { left: genreDragHandle.right; top: parent.top; bottom: parent.bottom }
                                        width: parent.width - genreDragHandle.width - 30
                                        hoverEnabled: true
                                        cursorShape:  Qt.PointingHandCursor
                                        onClicked: root.selectedGenreIndex =
                                            (root.selectedGenreIndex === index) ? -1 : index
                                    }
                                }
                            }

                            // Inert visual placeholders for the unused slots of
                            // the fixed 48-cell board (6 x 8). Purely decorative
                            // -- no MouseArea, so they can never intercept a
                            // click or a drag -- but they make the capacity
                            // legible and make the "no gaps" invariant
                            // self-evident: because the order lives in a dense
                            // QStringList, empty slots can only ever be
                            // trailing ones.
                            Repeater {
                                model: root.appConfig
                                       ? Math.max(0, root.appConfig.maxGenres() - root.appConfig.genres.length)
                                       : 0
                                delegate: Rectangle {
                                    width:  genreManageGrid.cellW
                                    height: genreManageGrid.cellH
                                    radius: Theme.radiusSm
                                    color:  "transparent"
                                    border.width: 1
                                    border.color: Theme.ov10
                                }
                            }
                        }

                        // ── Reorder drop indicator ───────────────────────────
                        // One shared outline (UC-11's "single indicator" rule,
                        // in 2D) marking the slot the dragged genre will END UP
                        // in -- moveGenre()'s `to` is a final index, not an
                        // insert-before position, so an outline is the honest
                        // rendering; an insertion caret would also be ambiguous
                        // at row wraps. Deliberately NOT a child of
                        // genreManageGrid: a positioner lays out every visible
                        // child, so an indicator inside it would be given its
                        // own cell. Grid coords == genreGridArea coords because
                        // the Grid fills this Item.
                        Rectangle {
                            z: 10
                            visible: genreGridArea.reorderFrom >= 0
                                     && genreGridArea.reorderTo   >= 0
                                     && genreGridArea.reorderTo  !== genreGridArea.reorderFrom
                            width:  genreManageGrid.cellW
                            height: genreManageGrid.cellH
                            x: (genreGridArea.reorderTo % genreManageGrid.columns) * genreManageGrid.pitchX
                            y: Math.floor(genreGridArea.reorderTo / genreManageGrid.columns) * genreManageGrid.pitchY
                            color:  Theme.s10
                            radius: Theme.radiusSm
                            border.width: 2
                            border.color: Theme.secondary
                        }
                    }

                    // ── Add genre input row ──────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Text input
                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            color:  Theme.surfaceContainerHigh
                            radius: Theme.radiusSm
                            border.color: genreInput.activeFocus
                                          ? Theme.primary : "transparent"
                            border.width: 1

                            // Placeholder text
                            Text {
                                anchors { fill: genreInput }
                                visible: genreInput.text.length === 0
                                         && !genreInput.activeFocus
                                verticalAlignment: Text.AlignVCenter
                                text: "Type genre name and press Enter or ADD\u2026"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.labelLg
                                color: Theme.fgSurfaceVariant
                            }

                            TextInput {
                                id: genreInput
                                anchors {
                                    fill: parent
                                    leftMargin: 12; rightMargin: 12
                                }
                                verticalAlignment: TextInput.AlignVCenter
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.labelLg
                                color:      Theme.fgSurface
                                clip:       true
                                selectByMouse: true
                                Keys.onReturnPressed: root.doAddGenre()
                            }
                        }

                        // ADD button
                        Rectangle {
                            width: 80; height: 36
                            radius: Theme.radiusSm
                            color: addGHover.containsMouse
                                   ? Theme.primaryContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "ADD"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWidest
                                color: addGHover.containsMouse
                                       ? Theme.fgPrimaryContainer : Theme.primary
                            }
                            MouseArea {
                                id: addGHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked:    root.doAddGenre()
                            }
                        }
                    }

                    // ── Genre action buttons row ─────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // SCAN FOLDERS — genre discovery (UC-36): reads the
                        // genre tags in the ACTIVE monitored folders and opens
                        // FOUND GENRES to pick from. Enabled only when there is
                        // at least one active, connected folder. The binding
                        // reads appConfig.folders (a NOTIFYing property) as the
                        // call's argument, so it re-evaluates whenever the
                        // folder list changes -- a bare invokable call would
                        // freeze after the first paint.
                        Rectangle {
                            id: scanGenresBtn
                            readonly property bool canScan:
                                root.genreScanController !== null && root.appConfig !== null
                                && root.genreScanController.hasScannableFolder(root.appConfig.folders)
                            width: 150; height: 32
                            radius: Theme.radiusSm
                            opacity: canScan ? 1.0 : 0.35
                            color: scanGHover.containsMouse && canScan
                                   ? Theme.primaryContainer : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("SCAN FOLDERS")
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: scanGHover.containsMouse && scanGenresBtn.canScan
                                       ? Theme.fgPrimaryContainer : Theme.primary
                            }
                            MouseArea {
                                id: scanGHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: scanGenresBtn.canScan ? Qt.PointingHandCursor : Qt.ArrowCursor
                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text: scanGenresBtn.canScan
                                    ? qsTr("Find all genres tagged in your music folders and pick the ones to add")
                                    : qsTr("Add an active music folder in FILE MONITORING first")
                                onClicked: if (scanGenresBtn.canScan) foundGenresDialog.open()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // DELETE SELECTED
                        Rectangle {
                            width: 162; height: 32
                            radius: Theme.radiusSm
                            opacity: root.selectedGenreIndex >= 0 ? 1.0 : 0.35
                            color: delGHover.containsMouse
                                   && root.selectedGenreIndex >= 0
                                   ? Theme.errorContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "DELETE SELECTED"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: delGHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  root.selectedGenreIndex >= 0
                                              ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.selectedGenreIndex >= 0 && root.appConfig) {
                                        root.appConfig.removeGenreAt(root.selectedGenreIndex)
                                        root.selectedGenreIndex = -1
                                    }
                                }
                            }
                        }

                        // DELETE ALL
                        Rectangle {
                            width: 120; height: 32
                            radius: Theme.radiusSm
                            color: delAllGHover.containsMouse
                                   ? Theme.errorContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "DELETE ALL"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: delAllGHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked: deleteAllGenresConfirmBox.open()
                            }
                        }
                    }
                }

                MessageBox {
                    id: deleteAllGenresConfirmBox
                    title: qsTr("DELETE ALL")
                    message: qsTr("Are you sure you want to delete them all?")
                    confirmMode: true
                    confirmButtonText: qsTr("OK")
                    onAccepted: {
                        if (root.appConfig) {
                            root.appConfig.clearGenres()
                            root.selectedGenreIndex = -1
                        }
                    }
                }

                // FOUND GENRES (UC-36), opened by SCAN FOLDERS above.
                FoundGenresDialog {
                    id: foundGenresDialog
                    appConfig:      root.appConfig
                    scanController: root.genreScanController
                    onGenresAdded:  root._genresDiscovered = true
                }
            } // end GENRES panel

            // ────────────────────────────────────────────────────────────
            // PANEL 2 — FILE MONITORING
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 1

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 12

                    // Column header
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        color:  Theme.surfaceContainerHigh
                        radius: Theme.radiusSm

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 8   // must match the folder-row delegate's RowLayout below,
                                         // or ACTIVE/SUBFOLDERS drift out of column alignment
                            Text {
                                Layout.fillWidth: true
                                text: "FOLDER"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelXs
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWidest
                                color: Theme.fgSurfaceVariant
                            }
                            Text {
                                // Layout.preferredWidth, not plain width -- RowLayout
                                // sizes an unfilled child from its implicitWidth when
                                // that's non-zero (always true for Text), silently
                                // overriding a bare width: binding.
                                Layout.preferredWidth: 70
                                text: "ACTIVE"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelXs
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWidest
                                color: Theme.fgSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                Layout.preferredWidth: 100
                                text: "SUBFOLDERS"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelXs
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWidest
                                color: Theme.fgSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // Folder list
                    Item {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true

                        // Empty-state hint
                        Text {
                            anchors.centerIn: parent
                            visible: !root.appConfig || root.appConfig.folders.length === 0
                            text: "No folders configured.\nClick ADD FOLDER to add a music directory."
                            horizontalAlignment: Text.AlignHCenter
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelLg
                            color: Theme.fgSurfaceVariant
                        }

                        ScrollView {
                            anchors.fill: parent
                            visible: root.appConfig !== null
                                     && root.appConfig.folders.length > 0
                            clip: true

                            ListView {
                                id: folderList
                                model: root.appConfig ? root.appConfig.folders : []
                                spacing: 3

                                delegate: Rectangle {
                                    width:  folderList.width
                                    height: 38
                                    radius: Theme.radiusSm
                                    opacity: (modelData.available === false || modelData.active === false) ? 0.5 : 1.0

                                    readonly property bool isSelected:
                                        root.selectedFolderIndex === index

                                    color: isSelected
                                           ? Theme.p10
                                           : rowHover.containsMouse
                                             ? Theme.surfaceContainerHigh
                                             : Theme.surfaceContainer

                                    RowLayout {
                                        anchors {
                                            fill: parent
                                            leftMargin: 12; rightMargin: 12
                                        }
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.available
                                                  ? modelData.path
                                                  : "⚠ " + modelData.volume
                                                    + " not connected " + modelData.relPath
                                            font.family:    Theme.fontFamilyMono
                                            font.pixelSize: Theme.monoLg
                                            color: modelData.available
                                                   ? Theme.fgSurface : Theme.fgSurfaceVariant
                                            elide: Text.ElideMiddle
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        // Active checkbox cell
                                        Item {
                                            Layout.preferredWidth: 70
                                            height: parent.height

                                            Rectangle {
                                                width: 18; height: 18
                                                anchors.centerIn: parent
                                                radius: 3
                                                color: modelData.active
                                                       ? Theme.secondaryContainer
                                                       : "transparent"
                                                border.width: modelData.active ? 0 : 1
                                                border.color: Theme.outlineVariant

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: modelData.active
                                                    text: "✓"   // ✓
                                                    font.pixelSize: 11
                                                    font.weight:    Font.Bold
                                                    color: Theme.fgSecondaryContainer
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape:  Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (root.appConfig) {
                                                            root.appConfig.setFolderActive(
                                                                index,
                                                                !modelData.active)
                                                            root._foldersDirty = true
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Subfolders checkbox cell
                                        Item {
                                            Layout.preferredWidth: 100
                                            height: parent.height

                                            Rectangle {
                                                width: 18; height: 18
                                                anchors.centerIn: parent
                                                radius: 3
                                                color: modelData.includeSubfolders
                                                       ? Theme.secondaryContainer
                                                       : "transparent"
                                                border.width: modelData.includeSubfolders ? 0 : 1
                                                border.color: Theme.outlineVariant

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: modelData.includeSubfolders
                                                    text: "\u2713"   // ✓
                                                    font.pixelSize: 11
                                                    font.weight:    Font.Bold
                                                    color: Theme.fgSecondaryContainer
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape:  Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (root.appConfig) {
                                                            root.appConfig.setFolderSubfolders(
                                                                index,
                                                                !modelData.includeSubfolders)
                                                            root._foldersDirty = true
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Row-level click (select / deselect)
                                    MouseArea {
                                        id: rowHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        z: -1   // checkbox MouseArea sits on top
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedFolderIndex =
                                            (root.selectedFolderIndex === index) ? -1 : index
                                    }
                                }
                            }
                        }
                    }

                    // ── Folder action buttons row ────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // ADD FOLDER
                        Rectangle {
                            width: 130; height: 32
                            radius: Theme.radiusSm
                            color: addFHover.containsMouse
                                   ? Theme.primaryContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "ADD FOLDER"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: addFHover.containsMouse
                                       ? Theme.fgPrimaryContainer : Theme.primary
                            }
                            MouseArea {
                                id: addFHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked:    folderDialog.open()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // DELETE SELECTED
                        Rectangle {
                            width: 162; height: 32
                            radius: Theme.radiusSm
                            opacity: root.selectedFolderIndex >= 0 ? 1.0 : 0.35
                            color: delFHover.containsMouse
                                   && root.selectedFolderIndex >= 0
                                   ? Theme.errorContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "DELETE SELECTED"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: delFHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  root.selectedFolderIndex >= 0
                                              ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.selectedFolderIndex >= 0 && root.appConfig) {
                                        root.appConfig.removeFolderAt(root.selectedFolderIndex)
                                        root.selectedFolderIndex = -1
                                        root._foldersDirty = true
                                    }
                                }
                            }
                        }

                        // DELETE ALL
                        Rectangle {
                            width: 120; height: 32
                            radius: Theme.radiusSm
                            color: delAllFHover.containsMouse
                                   ? Theme.errorContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "DELETE ALL"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: delAllFHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked: deleteAllFoldersConfirmBox.open()
                            }
                        }
                    }
                }

                MessageBox {
                    id: deleteAllFoldersConfirmBox
                    title: qsTr("DELETE ALL")
                    message: qsTr("Are you sure you want to delete them all?")
                    confirmMode: true
                    confirmButtonText: qsTr("OK")
                    onAccepted: {
                        if (root.appConfig) {
                            root.appConfig.clearFolders()
                            root.selectedFolderIndex = -1
                            root._foldersDirty = true
                        }
                    }
                }
            } // end FILE MONITORING panel

            // ────────────────────────────────────────────────────────────
            // PANEL 3 — PLAYBACK
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 2

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 40

                    readonly property bool crossfadeOn:
                        root.appConfig !== null && root.appConfig.crossfadeEnabled

                    // Shown if the user picks BASS Audio Library while its DLLs
                    // aren't present next to Topaz.exe -- see UC-15. Local to
                    // this panel, same pattern NewPlaylistDialog.qml uses for
                    // its own "already exists" errorBox.
                    MessageBox {
                        id: missingBassDllsBox
                        title: "PLAYBACK ENGINE"
                        message: "BASS Audio Library was not found.<br><br>" +
                                 "To use it, download <b>bass.dll</b>, <b>bassflac.dll</b> and " +
                                 "<b>bassopus.dll</b> and place them next to Topaz.exe, then try again." +
                                 "<br><br><a href=\"https://www.un4seen.com/\">https://www.un4seen.com/</a>"
                    }

                    // Shown when "Consistent Background Music" is picked without
                    // the BASS_FX add-on next to Topaz -- see UC-35. Like
                    // bass.dll itself, bass_fx is never bundled.
                    MessageBox {
                        id: missingBassFxBox
                        title: "LOUDNESS CORRECTION"
                        message: "<b>Consistent Background Music</b> needs the BASS_FX add-on.<br><br>" +
                                 "Download <b>bass_fx.dll</b> (Windows) or <b>libbass_fx.so</b> (Linux) " +
                                 "and place it next to Topaz, then try again." +
                                 "<br><br><a href=\"https://www.un4seen.com/\">https://www.un4seen.com/</a>"
                    }

                    // Shown right when the user actually switches backends --
                    // see UC-15 "Step 2b". Not shown for clicking the
                    // already-selected option, and not shown on the
                    // missing-DLLs path above (missingBassDllsBox handles that).
                    MessageBox {
                        id: playbackBackendChangedBox
                        title: "PLAYBACK ENGINE"
                        message: "You changed the way Topaz is playing Audio Tracks.<br><br>" +
                                 "This takes effect after restarting Topaz.<br><br>" +
                                 "(Please check afterwards which Playback Engine is active)"
                    }

                    // ── Playback with row ──────────────────────────────
                    // See UC-15 "Step 2b". PlaybackEngine reads this choice
                    // once per app launch (when its two AudioDecks are first
                    // constructed) -- switching here takes effect after
                    // restarting Topaz, not live, hence playbackBackendChangedBox
                    // below (opened only when the selection actually changes).
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: "Playback with"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Row {
                                id: backendRadioRow
                                Layout.leftMargin: 24
                                spacing: 32

                                // x of the "BASS Audio Library" radio inside this
                                // row (kept up to date by that delegate) -- the
                                // Auto Loudness Correction block below is aligned
                                // under it.
                                property real bassX: 0

                                Repeater {
                                    model: [
                                        { value: "ffmpeg", label: "FFmpeg" },
                                        { value: "bass",    label: "BASS Audio Library" }
                                    ]

                                    delegate: RowLayout {
                                        spacing: 8

                                        readonly property bool selected:
                                            root.appConfig !== null
                                            && root.appConfig.audioBackend === modelData.value

                                        onXChanged: if (modelData.value === "bass") backendRadioRow.bassX = x

                                        Rectangle {
                                            width: 18; height: 18
                                            radius: 9
                                            color: "transparent"
                                            border.width: 2
                                            border.color: selected ? Theme.secondary : Theme.outlineVariant

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 10; height: 10
                                                radius: 5
                                                color: Theme.secondary
                                                visible: selected
                                            }
                                        }

                                        Text {
                                            text: modelData.label
                                            font.family:    Theme.fontFamilyBody
                                            font.pixelSize: Theme.labelXl
                                            color: Theme.fgSurface
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!root.appConfig) return
                                                if (selected) return // already this backend, nothing changed
                                                if (modelData.value === "bass"
                                                    && !root.appConfig.bassLibraryAvailable()) {
                                                    missingBassDllsBox.open()
                                                    return
                                                }
                                                root.appConfig.setAudioBackend(modelData.value)
                                                playbackBackendChangedBox.open()
                                            }
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Reports what's actually running THIS session --
                            // distinct from the radio group, which is only the
                            // stored preference for the *next* launch (and
                            // silently gets corrected back to FFmpeg if BASS was
                            // selected but turned out unusable). See UC-15
                            // "Step 2b" / PlaybackEngine.activeBackendName.
                            Text {
                                text: "Currently active: " +
                                      (root.playbackEngine && root.playbackEngine.activeBackendName
                                           ? root.playbackEngine.activeBackendName
                                           : "—")
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.labelMd
                                font.weight:    Font.Bold
                                color: Theme.fgSurface
                            }
                        }

                        // ── Auto Loudness Correction (UC-35) ─────────────
                        // Placed right under the "BASS Audio Library" radio
                        // (aligned to its left edge). Everything here is BASS
                        // only: greyed out and inert while FFmpeg is the
                        // selected backend, and the two strategy radios also
                        // need the checkbox on. The settings are live -- the
                        // running BASS engine reacts at once (PlaybackEngine).
                        ColumnLayout {
                            id: loudnessBlock
                            Layout.leftMargin: 24 + backendRadioRow.bassX
                            Layout.topMargin: 20
                            spacing: 14

                            readonly property bool bassSelected:
                                root.appConfig !== null && root.appConfig.audioBackend === "bass"
                            readonly property bool correctionOn:
                                bassSelected && root.appConfig.autoLoudnessCorrection

                            // Checkbox -- same visual idiom as the GENRES /
                            // Milkdrop-cleanup checkboxes.
                            RowLayout {
                                spacing: 10
                                opacity: loudnessBlock.bassSelected ? 1.0 : 0.35

                                Rectangle {
                                    width: 18; height: 18
                                    radius: 3
                                    color: loudnessBlock.correctionOn ? Theme.secondaryContainer : "transparent"
                                    border.width: loudnessBlock.correctionOn ? 0 : 1
                                    border.color: Theme.outlineVariant

                                    Text {
                                        anchors.centerIn: parent
                                        visible: loudnessBlock.correctionOn
                                        text: "✓"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Theme.fgSecondaryContainer
                                    }
                                }

                                Text {
                                    text: "Auto Loudness Correction"
                                    font.family:    Theme.fontFamilyBody
                                    font.pixelSize: Theme.labelXl
                                    color: Theme.fgSurface
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: loudnessBlock.bassSelected
                                    hoverEnabled: true
                                    cursorShape: loudnessBlock.bassSelected ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("Evens out the loudness of your tracks while playing with the BASS Audio Library. Your audio files are never changed.")
                                    onClicked: {
                                        if (root.appConfig)
                                            root.appConfig.setAutoLoudnessCorrection(
                                                !root.appConfig.autoLoudnessCorrection)
                                    }
                                }
                            }

                            // Strategy radios + Trim sliders (same visuals as "Playback with" /
                            // the crossfade Length slider). Bigger gap (24, vs. the checkbox
                            // block's 10) between the two strategies so each radio's Trim
                            // slider has room right under it, as asked.
                            ColumnLayout {
                                Layout.leftMargin: 28
                                spacing: 24
                                opacity: loudnessBlock.correctionOn ? 1.0 : 0.35

                                // ── Audiophile/Critical Listening ─────────────────────
                                ColumnLayout {
                                    id: audiophileStrategyBlock
                                    spacing: 10

                                    readonly property bool selected:
                                        root.appConfig !== null
                                        && root.appConfig.loudnessStrategy === "audiophile"

                                    RowLayout {
                                        spacing: 8

                                        Rectangle {
                                            width: 18; height: 18
                                            radius: 9
                                            color: "transparent"
                                            border.width: 2
                                            border.color: audiophileStrategyBlock.selected ? Theme.secondary : Theme.outlineVariant

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 10; height: 10
                                                radius: 5
                                                color: Theme.secondary
                                                visible: audiophileStrategyBlock.selected
                                            }
                                        }

                                        Text {
                                            text: "Audiophile/Critical Listening"
                                            font.family:    Theme.fontFamilyBody
                                            font.pixelSize: Theme.labelXl
                                            color: Theme.fgSurface
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: loudnessBlock.correctionOn
                                            hoverEnabled: true
                                            cursorShape: loudnessBlock.correctionOn ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay:   600
                                            ToolTip.text:    "Sets each track to the same level: uses a ReplayGain tag when the file has one (unless \"Always measure\" is on), otherwise measures the track once and remembers the result.\n" +
                                                             "K-weighted gated loudness (EBU R128 / ReplayGain 2.0 method, reference target -18 LUFS)"
                                            onClicked: {
                                                if (!root.appConfig || audiophileStrategyBlock.selected) return
                                                root.appConfig.setLoudnessStrategy("audiophile")
                                            }
                                        }
                                    }

                                    // Trim: a manual correction on top of the automatic one
                                    // above -- e.g. an outboard dB-meter reading the -18 LUFS
                                    // reference as too quiet. Applied live; NEVER written to
                                    // Topaz.volumeNormalization.json (only the automatic
                                    // reference value is).
                                    ColumnLayout {
                                        Layout.leftMargin: 28
                                        spacing: 8
                                        opacity: audiophileStrategyBlock.selected ? 1.0 : 0.35

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Trim"
                                                font.family:    Theme.fontFamilyBody
                                                font.pixelSize: Theme.titleMd
                                                font.weight:    Font.Medium
                                                color: Theme.fgSurface

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay:   600
                                                    ToolTip.text:    qsTr("Manual correction on top of the automatic one -- not saved to the analysis file, only ever applied live")
                                                }
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: (audiophileTrimSlider.value > 0 ? "+" : "")
                                                      + audiophileTrimSlider.value.toFixed(1) + " dB"
                                                font.family:    Theme.fontFamilyMono
                                                font.pixelSize: Theme.labelLg
                                                font.weight:    Font.Bold
                                                color: Theme.secondary
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Text {
                                                text: "-15 dB"
                                                font.family:    Theme.fontFamilyMono
                                                font.pixelSize: Theme.labelSm
                                                color: Theme.fgSurfaceVariant
                                            }

                                            Slider {
                                                id: audiophileTrimSlider
                                                Layout.fillWidth: true
                                                enabled: loudnessBlock.correctionOn && audiophileStrategyBlock.selected
                                                from: -15.0
                                                to:   15.0
                                                stepSize: 0.1
                                                snapMode: Slider.SnapAlways
                                                // qmllint disable missing-property
                                                value: root.appConfig ? root.appConfig.audiophileTrimDb : 0.0

                                                onMoved: {
                                                    if (root.appConfig)
                                                        root.appConfig.setAudiophileTrimDb(value)
                                                }
                                                // qmllint enable missing-property

                                                background: Rectangle {
                                                    x: audiophileTrimSlider.leftPadding
                                                    y: audiophileTrimSlider.topPadding
                                                       + audiophileTrimSlider.availableHeight / 2 - height / 2
                                                    implicitWidth:  200
                                                    implicitHeight: 4
                                                    width:  audiophileTrimSlider.availableWidth
                                                    height: implicitHeight
                                                    radius: 2
                                                    color:  Theme.surfaceContainerHighest

                                                    Rectangle {
                                                        width:  audiophileTrimSlider.visualPosition * parent.width
                                                        height: parent.height
                                                        radius: 2
                                                        color:  Theme.secondary
                                                    }
                                                }

                                                handle: Rectangle {
                                                    x: audiophileTrimSlider.leftPadding
                                                       + audiophileTrimSlider.visualPosition
                                                         * (audiophileTrimSlider.availableWidth - width)
                                                    y: audiophileTrimSlider.topPadding
                                                       + audiophileTrimSlider.availableHeight / 2 - height / 2
                                                    implicitWidth:  16
                                                    implicitHeight: 16
                                                    width:  implicitWidth
                                                    height: implicitHeight
                                                    radius: 8
                                                    color: Theme.secondary
                                                }
                                            }

                                            Text {
                                                text: "+15 dB"
                                                font.family:    Theme.fontFamilyMono
                                                font.pixelSize: Theme.labelSm
                                                color: Theme.fgSurfaceVariant
                                            }
                                        }
                                    }

                                    // Always measure: skips the ReplayGain / R128 tag tier
                                    // (LoudnessAnalyzer::determineReferenceGain). Toggle switch
                                    // copied from the Crossfade one below. Also honoured by the
                                    // Export's Replay Gain Normalization (stored value).
                                    RowLayout {
                                        id: alwaysMeasureRow
                                        Layout.leftMargin: 28
                                        Layout.fillWidth: true
                                        spacing: 12
                                        opacity: audiophileStrategyBlock.selected ? 1.0 : 0.35

                                        readonly property bool usable:
                                            loudnessBlock.correctionOn && audiophileStrategyBlock.selected
                                        readonly property bool alwaysMeasureOn:
                                            root.appConfig !== null && root.appConfig.loudnessAlwaysMeasure

                                        Text {
                                            text: "Always measure instead of using ReplayGain / R128 tag"
                                            font.family:    Theme.fontFamilyBody
                                            font.pixelSize: Theme.titleMd
                                            font.weight:    Font.Medium
                                            color: Theme.fgSurface

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                ToolTip.visible: containsMouse
                                                ToolTip.delay:   600
                                                ToolTip.text:    qsTr("Ignores ReplayGain / R128 tags in your files and measures every track itself, for one consistent level across the whole library. Your audio files are never changed.")
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        Rectangle {
                                            id: alwaysMeasureTrack
                                            width: 48; height: 24
                                            radius: 12
                                            color: alwaysMeasureRow.alwaysMeasureOn ? Theme.secondary : Theme.outlineVariant

                                            Rectangle {
                                                width: 18; height: 18
                                                radius: 9
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: alwaysMeasureRow.alwaysMeasureOn ? 27 : 3
                                                color: Theme.fgSurface
                                                Behavior on x { NumberAnimation { duration: 120 } }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: alwaysMeasureRow.usable
                                                cursorShape: alwaysMeasureRow.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    if (root.appConfig)
                                                        root.appConfig.setLoudnessAlwaysMeasure(
                                                            !root.appConfig.loudnessAlwaysMeasure)
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── Consistent Background Music ───────────────────────
                                ColumnLayout {
                                    id: backgroundStrategyBlock
                                    spacing: 10

                                    readonly property bool selected:
                                        root.appConfig !== null
                                        && root.appConfig.loudnessStrategy === "background"

                                    RowLayout {
                                        spacing: 8

                                        Rectangle {
                                            width: 18; height: 18
                                            radius: 9
                                            color: "transparent"
                                            border.width: 2
                                            border.color: backgroundStrategyBlock.selected ? Theme.secondary : Theme.outlineVariant

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 10; height: 10
                                                radius: 5
                                                color: Theme.secondary
                                                visible: backgroundStrategyBlock.selected
                                            }
                                        }

                                        Text {
                                            text: "Consistent Background Music"
                                            font.family:    Theme.fontFamilyBody
                                            font.pixelSize: Theme.labelXl
                                            color: Theme.fgSurface
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: loudnessBlock.correctionOn
                                            hoverEnabled: true
                                            cursorShape: loudnessBlock.correctionOn ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay:   600
                                            ToolTip.text:    "A compressor that continuously evens out the volume of everything you play. Needs the BASS_FX add-on."
                                            onClicked: {
                                                if (!root.appConfig || backgroundStrategyBlock.selected) return
                                                if (!root.appConfig.bassFxAvailable()) {
                                                    missingBassFxBox.open()
                                                    return
                                                }
                                                root.appConfig.setLoudnessStrategy("background")
                                            }
                                        }
                                    }

                                    // Trim: a manual correction on top of the compressor's own
                                    // make-up gain -- e.g. this strategy already plays louder
                                    // (around -6/-4 dB); Trim adjusts that further. Applied
                                    // live; NEVER written to Topaz.volumeNormalization.json.
                                    ColumnLayout {
                                        Layout.leftMargin: 28
                                        spacing: 8
                                        opacity: backgroundStrategyBlock.selected ? 1.0 : 0.35

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Trim"
                                                font.family:    Theme.fontFamilyBody
                                                font.pixelSize: Theme.titleMd
                                                font.weight:    Font.Medium
                                                color: Theme.fgSurface

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay:   600
                                                    ToolTip.text:    qsTr("Manual correction on top of the compressor's own make-up gain -- not saved to the analysis file, only ever applied live")
                                                }
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: (backgroundTrimSlider.value > 0 ? "+" : "")
                                                      + backgroundTrimSlider.value.toFixed(1) + " dB"
                                                font.family:    Theme.fontFamilyMono
                                                font.pixelSize: Theme.labelLg
                                                font.weight:    Font.Bold
                                                color: Theme.secondary
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Text {
                                                text: "-15 dB"
                                                font.family:    Theme.fontFamilyMono
                                                font.pixelSize: Theme.labelSm
                                                color: Theme.fgSurfaceVariant
                                            }

                                            Slider {
                                                id: backgroundTrimSlider
                                                Layout.fillWidth: true
                                                enabled: loudnessBlock.correctionOn && backgroundStrategyBlock.selected
                                                from: -15.0
                                                to:   15.0
                                                stepSize: 0.1
                                                snapMode: Slider.SnapAlways
                                                // qmllint disable missing-property
                                                value: root.appConfig ? root.appConfig.backgroundTrimDb : 0.0

                                                onMoved: {
                                                    if (root.appConfig)
                                                        root.appConfig.setBackgroundTrimDb(value)
                                                }
                                                // qmllint enable missing-property

                                                background: Rectangle {
                                                    x: backgroundTrimSlider.leftPadding
                                                    y: backgroundTrimSlider.topPadding
                                                       + backgroundTrimSlider.availableHeight / 2 - height / 2
                                                    implicitWidth:  200
                                                    implicitHeight: 4
                                                    width:  backgroundTrimSlider.availableWidth
                                                    height: implicitHeight
                                                    radius: 2
                                                    color:  Theme.surfaceContainerHighest

                                                    Rectangle {
                                                        width:  backgroundTrimSlider.visualPosition * parent.width
                                                        height: parent.height
                                                        radius: 2
                                                        color:  Theme.secondary
                                                    }
                                                }

                                                handle: Rectangle {
                                                    x: backgroundTrimSlider.leftPadding
                                                       + backgroundTrimSlider.visualPosition
                                                         * (backgroundTrimSlider.availableWidth - width)
                                                    y: backgroundTrimSlider.topPadding
                                                       + backgroundTrimSlider.availableHeight / 2 - height / 2
                                                    implicitWidth:  16
                                                    implicitHeight: 16
                                                    width:  implicitWidth
                                                    height: implicitHeight
                                                    radius: 8
                                                    color: Theme.secondary
                                                }
                                            }

                                            Text {
                                                text: "+15 dB"
                                                font.family:    Theme.fontFamilyMono
                                                font.pixelSize: Theme.labelSm
                                                color: Theme.fgSurfaceVariant
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Crossfade on/off row ──────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Crossfade"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text:    qsTr("Activate/Deactivate linear Fading-In/Fading-Out")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle switch — same visual pattern as PlaybackQueue's
                        // LOCK PLAYLIST toggle, scaled up (48×24 / 18×18) for more
                        // prominence in this dialog.
                        Rectangle {
                            id: crossfadeTrack

                            readonly property bool crossfadeOn:
                                root.appConfig !== null && root.appConfig.crossfadeEnabled

                            width: 48; height: 24
                            radius: 12
                            color: crossfadeOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: crossfadeTrack.crossfadeOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setCrossfadeEnabled(
                                            !root.appConfig.crossfadeEnabled)
                                }
                            }
                        }
                    }

                    // ── Length row ─────────────────────────────────────
                    // Negative top margin pulls it up from the panel's 40 px
                    // section spacing to 16 px, so it reads as belonging to the
                    // Crossfade switch above.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        Layout.topMargin: -24
                        spacing: 8
                        opacity: parent.crossfadeOn ? 1.0 : 0.35

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Length"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("Time duration of Fading-In the next Track whilst Fading-Out the actual Track")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: crossfadeSlider.value.toFixed(1) + " s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "2.0 s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: crossfadeSlider
                                Layout.fillWidth: true
                                enabled: root.appConfig !== null
                                         && root.appConfig.crossfadeEnabled
                                from: 2.0
                                to:   12.0
                                stepSize: 0.5
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.crossfadeSeconds : 5.0

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setCrossfadeSeconds(value)
                                }

                                background: Rectangle {
                                    x: crossfadeSlider.leftPadding
                                    y: crossfadeSlider.topPadding
                                       + crossfadeSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  crossfadeSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  crossfadeSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: crossfadeSlider.leftPadding
                                       + crossfadeSlider.visualPosition
                                         * (crossfadeSlider.availableWidth - width)
                                    y: crossfadeSlider.topPadding
                                       + crossfadeSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "12.0 s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }   // push content to top
                }
            } // end PLAYBACK panel

            // ────────────────────────────────────────────────────────────
            // PANEL 4 — AUTO PLAY
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 3

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 40

                    // ── Queue Horizon row ─────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Queue Horizon"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How many Tracks are pre-loaded with AUTO PLAY")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(queueHorizonSlider.value) + " tracks"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "1"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: queueHorizonSlider
                                Layout.fillWidth: true
                                from: 1
                                to:   15
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.autoPlayQueueHorizon : 5

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayQueueHorizon(
                                            Math.round(value))
                                }

                                background: Rectangle {
                                    x: queueHorizonSlider.leftPadding
                                    y: queueHorizonSlider.topPadding
                                       + queueHorizonSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  queueHorizonSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  queueHorizonSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: queueHorizonSlider.leftPadding
                                       + queueHorizonSlider.visualPosition
                                         * (queueHorizonSlider.availableWidth - width)
                                    y: queueHorizonSlider.topPadding
                                       + queueHorizonSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "15"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Title Adding row ──────────────────────────────
                    // Polling interval AUTO PLAY will use to add one new track at
                    // a time to the queue (see UC-14 design note).
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Title Adding"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("Interval until the next Track will be added")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(titleAddingSlider.value) + " s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "5 s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: titleAddingSlider
                                Layout.fillWidth: true
                                from: 5
                                to:   90
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.autoPlayTitleAddingIntervalSeconds : 30

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayTitleAddingIntervalSeconds(
                                            Math.round(value))
                                }

                                background: Rectangle {
                                    x: titleAddingSlider.leftPadding
                                    y: titleAddingSlider.topPadding
                                       + titleAddingSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  titleAddingSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  titleAddingSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: titleAddingSlider.leftPadding
                                       + titleAddingSlider.visualPosition
                                         * (titleAddingSlider.availableWidth - width)
                                    y: titleAddingSlider.topPadding
                                       + titleAddingSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "90 s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Consider Genre row ────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Consider Genre"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle switch — same visual pattern as the PLAYBACK tab's
                        // on/off toggle.
                        Rectangle {
                            id: considerGenreTrack

                            readonly property bool considerGenreOn:
                                root.appConfig !== null && root.appConfig.autoPlayConsiderGenre

                            width: 48; height: 24
                            radius: 12
                            color: considerGenreOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: considerGenreTrack.considerGenreOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayConsiderGenre(
                                            !root.appConfig.autoPlayConsiderGenre)
                                }
                            }
                        }
                    }

                    // ── Consider Rating row ───────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Consider Rating"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle switch — same visual pattern as the PLAYBACK tab's
                        // and Consider Genre's on/off toggle.
                        Rectangle {
                            id: considerRatingTrack

                            readonly property bool considerRatingOn:
                                root.appConfig !== null && root.appConfig.autoPlayConsiderRating

                            width: 48; height: 24
                            radius: 12
                            color: considerRatingOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: considerRatingTrack.considerRatingOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayConsiderRating(
                                            !root.appConfig.autoPlayConsiderRating)
                                }
                            }
                        }
                    }

                    // ── Minimum Rating row ─────────────────────────────
                    // Enabled/visible-strength only while Consider Rating is on.
                    // Stars mirror NowPlaying.qml's rating-star Repeater — same
                    // glyph, size, and blue palette — but drive
                    // appConfig.autoPlayMinimumRating instead of the currently
                    // playing track's rating. A plain Item (not RowLayout) is used
                    // so the star Row can be explicitly positioned against
                    // queueHorizonSlider's right edge above — Layout-managed items
                    // can't carry anchors, and Qt Quick anchors only work between
                    // siblings/parent anyway (queueHorizonSlider is neither), hence
                    // the explicit x binding below instead of anchors.right.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(minRatingLabel.implicitHeight, 18)
                        enabled: root.appConfig !== null && root.appConfig.autoPlayConsiderRating
                        opacity: enabled ? 1.0 : 0.35

                        Text {
                            id: minRatingLabel
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Minimum Rating"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Medium
                            color: Theme.fgSurface
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: queueHorizonSlider.x + queueHorizonSlider.width - width
                            spacing: 3

                            Repeater {
                                model: 10

                                delegate: Text {
                                    text: "★"   // ★
                                    font.pixelSize: 18

                                    readonly property bool filled:
                                        root.appConfig && index < root.appConfig.autoPlayMinimumRating

                                    color: filled                    ? "#00A6ED"
                                         : minRatingMA.containsMouse ? Qt.rgba(0, 0.651, 0.929, 0.45)
                                         :                             Theme.outlineVariant

                                    MouseArea {
                                        id: minRatingMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape:  Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.appConfig)
                                                root.appConfig.setAutoPlayMinimumRating(index + 1)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Allow Manual Modification + Exceptions group ───
                    // Wrapped together (tight spacing: 16) so "Exceptions" reads
                    // clearly as belonging to "Allow Manual Modification" above it,
                    // distinct from the outer panel's spacing: 40 between unrelated
                    // rows/blocks.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Allow Manual Modification"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle switch — same visual pattern as the PLAYBACK tab's
                        // and Consider Genre's on/off toggle.
                        Rectangle {
                            id: allowManualModificationTrack

                            readonly property bool allowManualModificationOn:
                                root.appConfig !== null && root.appConfig.autoPlayAllowManualModification

                            width: 48; height: 24
                            radius: 12
                            color: allowManualModificationOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: allowManualModificationTrack.allowManualModificationOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayAllowManualModification(
                                            !root.appConfig.autoPlayAllowManualModification)
                                }
                            }
                        }
                    }

                    // ── Exceptions row (dependent on Allow Manual Modification) ──
                    // Only interactive while Allow Manual Modification is OFF —
                    // governs what limited manual interaction (if any) remains
                    // possible during an active AUTO PLAY session. Dimmed/disabled
                    // the opposite way Minimum Rating is: here the row goes inert
                    // when its parent toggle is ON, since it's then moot (full
                    // manual control already applies).
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        spacing: 12
                        enabled: root.appConfig !== null && !root.appConfig.autoPlayAllowManualModification
                        opacity: enabled ? 1.0 : 0.35

                        Text {
                            text: "Exceptions"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Row {
                            Layout.leftMargin: 24
                            spacing: 32

                            Repeater {
                                model: [
                                    { value: "nothing",            label: "Nothing" },
                                    { value: "playPause",          label: "Play/Pause allowed" },
                                    { value: "playPauseAndSelect", label: "Play/Pause & Select another Track allowed" }
                                ]

                                delegate: RowLayout {
                                    spacing: 8

                                    readonly property bool selected:
                                        root.appConfig !== null
                                        && root.appConfig.autoPlayTransportAccess === modelData.value

                                    Rectangle {
                                        width: 18; height: 18
                                        radius: 9
                                        color: "transparent"
                                        border.width: 2
                                        border.color: selected ? Theme.secondary : Theme.outlineVariant

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 10; height: 10
                                            radius: 5
                                            color: Theme.secondary
                                            visible: selected
                                        }
                                    }

                                    Text {
                                        text: modelData.label
                                        font.family:    Theme.fontFamilyBody
                                        font.pixelSize: Theme.labelXl
                                        color: Theme.fgSurface
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.appConfig)
                                                root.appConfig.setAutoPlayTransportAccess(modelData.value)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    } // end Allow Manual Modification + Exceptions group

                    // ── New Tracks are Flickering row ────────────────────
                    // Toggle switch — same visual pattern as the PLAYBACK
                    // tab's and Allow Manual Modification's on/off toggle.
                    // Gates PlaybackQueue's brief flicker on a row AUTO PLAY
                    // just added — see UC-16.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "New Tracks are Flickering"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: flickerNewTracksTrack

                            readonly property bool flickerNewTracksOn:
                                root.appConfig !== null && root.appConfig.autoPlayFlickerNewTracks

                            width: 48; height: 24
                            radius: 12
                            color: flickerNewTracksOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: flickerNewTracksTrack.flickerNewTracksOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayFlickerNewTracks(
                                            !root.appConfig.autoPlayFlickerNewTracks)
                                }
                            }
                        }
                    }

                    // ── Play a Song row ────────────────────────────────
                    // First radio-button control in the app: a single row of
                    // mutually-exclusive song-repeat modes. Circle border/dot
                    // colors match every other AUTO PLAY control's selected/
                    // unselected pairing (Theme.secondary / Theme.outlineVariant).
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: "Play a Title"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Grid {
                            Layout.leftMargin: 24
                            columns: 4
                            rowSpacing:    12
                            columnSpacing: 32

                            Repeater {
                                model: [
                                    { value: "once",                  label: "Once" },
                                    { value: "twice",                 label: "Twice" },
                                    { value: "twiceIfNoneAvailable",  label: "Twice when no other available" },
                                    { value: "several",               label: "Several times" }
                                ]

                                delegate: RowLayout {
                                    spacing: 8

                                    readonly property bool selected:
                                        root.appConfig !== null
                                        && root.appConfig.autoPlaySongRepeat === modelData.value

                                    Rectangle {
                                        width: 18; height: 18
                                        radius: 9
                                        color: "transparent"
                                        border.width: 2
                                        border.color: selected ? Theme.secondary : Theme.outlineVariant

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 10; height: 10
                                            radius: 5
                                            color: Theme.secondary
                                            visible: selected
                                        }
                                    }

                                    Text {
                                        text: modelData.label
                                        font.family:    Theme.fontFamilyBody
                                        font.pixelSize: Theme.labelXl
                                        color: Theme.fgSurface
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.appConfig)
                                                root.appConfig.setAutoPlaySongRepeat(modelData.value)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }   // push content to top
                }
            } // end AUTO PLAY panel

            // ────────────────────────────────────────────────────────────
            // PANEL 5 — AUDIO VISUALIZER
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 4

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 40

                    // ── Bar Count row ──────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Bar Count"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How many bars the Audio Visualizer pane shows")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(barCountSlider.value) + " bars"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "8"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: barCountSlider
                                Layout.fillWidth: true
                                from: 8
                                to:   64
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.audioVisualizerBarCount : 24

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerBarCount(
                                            Math.round(value))
                                }

                                background: Rectangle {
                                    x: barCountSlider.leftPadding
                                    y: barCountSlider.topPadding
                                       + barCountSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  barCountSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  barCountSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: barCountSlider.leftPadding
                                       + barCountSlider.visualPosition
                                         * (barCountSlider.availableWidth - width)
                                    y: barCountSlider.topPadding
                                       + barCountSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "64"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Decay Speed row ────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Decay Speed"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How quickly bars fall after a peak")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: decaySpeedSlider.value.toFixed(2)
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "SLOW"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: decaySpeedSlider
                                Layout.fillWidth: true
                                from: 0.0
                                to:   1.0
                                stepSize: 0.05
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.audioVisualizerDecaySpeed : 0.5

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerDecaySpeed(value)
                                }

                                background: Rectangle {
                                    x: decaySpeedSlider.leftPadding
                                    y: decaySpeedSlider.topPadding
                                       + decaySpeedSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  decaySpeedSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  decaySpeedSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: decaySpeedSlider.leftPadding
                                       + decaySpeedSlider.visualPosition
                                         * (decaySpeedSlider.availableWidth - width)
                                    y: decaySpeedSlider.topPadding
                                       + decaySpeedSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "FAST"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Sensitivity row ─────────────────────────────────
                    // How high the bars react to a given signal level — gain
                    // offset applied before AudioVisualizerController's dB
                    // normalization. 50% matches the original, unmodified
                    // response; higher pushes bars closer to full height on
                    // loud passages, lower makes them noticeably less reactive.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Sensitivity"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How high the bars react to the current signal — 50% matches the default response")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(sensitivitySlider.value) + "%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "LOW"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: sensitivitySlider
                                Layout.fillWidth: true
                                from: 0
                                to:   100
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.audioVisualizerSensitivity * 100 : 50

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerSensitivity(value / 100)
                                }

                                background: Rectangle {
                                    x: sensitivitySlider.leftPadding
                                    y: sensitivitySlider.topPadding
                                       + sensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  sensitivitySlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  sensitivitySlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: sensitivitySlider.leftPadding
                                       + sensitivitySlider.visualPosition
                                         * (sensitivitySlider.availableWidth - width)
                                    y: sensitivitySlider.topPadding
                                       + sensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "HIGH"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Peak Hold row ──────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Peak Hold"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text:    qsTr("Show a lingering marker at each bar's recent peak")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle switch — same visual pattern as the PLAYBACK
                        // tab's on/off toggle.
                        Rectangle {
                            id: peakHoldTrack

                            readonly property bool peakHoldOn:
                                root.appConfig !== null && root.appConfig.audioVisualizerPeakHoldEnabled

                            width: 48; height: 24
                            radius: 12
                            color: peakHoldOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: peakHoldTrack.peakHoldOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerPeakHoldEnabled(
                                            !root.appConfig.audioVisualizerPeakHoldEnabled)
                                }
                            }
                        }
                    }

                    // ── Pane Opacity row ────────────────────────────────
                    // Background-only opacity — the bars themselves always
                    // stay fully opaque, only the pane's own background fades.
                    // See AudioVisualizerWindow.qml.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Pane Opacity"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How visible the pane's background is — the bars themselves always stay fully visible")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(paneOpacitySlider.value) + "%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "0%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: paneOpacitySlider
                                Layout.fillWidth: true
                                from: 0
                                to:   100
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.audioVisualizerPaneOpacity * 100 : 100

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerPaneOpacity(value / 100)
                                }

                                background: Rectangle {
                                    x: paneOpacitySlider.leftPadding
                                    y: paneOpacitySlider.topPadding
                                       + paneOpacitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  paneOpacitySlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  paneOpacitySlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: paneOpacitySlider.leftPadding
                                       + paneOpacitySlider.visualPosition
                                         * (paneOpacitySlider.availableWidth - width)
                                    y: paneOpacitySlider.topPadding
                                       + paneOpacitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "100%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Bar Opacity row ──────────────────────────────────
                    // Foreground-only opacity — fades the bars/peak ticks
                    // themselves, independent of Pane Opacity above.
                    // See AudioVisualizerWindow.qml.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Bar Opacity"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How visible the bars themselves are")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(barOpacitySlider.value) + "%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "0%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: barOpacitySlider
                                Layout.fillWidth: true
                                from: 0
                                to:   100
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.audioVisualizerBarOpacity * 100 : 100

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerBarOpacity(value / 100)
                                }

                                background: Rectangle {
                                    x: barOpacitySlider.leftPadding
                                    y: barOpacitySlider.topPadding
                                       + barOpacitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  barOpacitySlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  barOpacitySlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: barOpacitySlider.leftPadding
                                       + barOpacitySlider.visualPosition
                                         * (barOpacitySlider.availableWidth - width)
                                    y: barOpacitySlider.topPadding
                                       + barOpacitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "100%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Color row ───────────────────────────────────────
                    // Preset swatches rather than a full HSV/RGB picker —
                    // same "Repeater over an options array compared against
                    // one AppConfig value" idiom as the AUTO PLAY radio
                    // groups above, just rendered as color chips instead of
                    // labeled circles.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: "Color"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Grid {
                            Layout.leftMargin: 24
                            columns: 16   // 32 swatches → exactly two full rows
                            spacing: 16

                            Repeater {
                                model: [
                                    // Original 8 — kept as-is (4 already match
                                    // Theme tokens: secondary/primary/tertiary/fgSurface)
                                    "#00DAF3", "#44E2CD", "#D0BCFF", "#FFB869",
                                    "#FF6B6B", "#7CFF6B", "#FFE066", "#E5E2E1",
                                    // 24 additional presets — a saturated spread
                                    // across the hue wheel for clear visual
                                    // distinction against the pane's dark background
                                    "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
                                    "#00C7BE", "#30B0C7", "#007AFF", "#5856D6",
                                    "#AF52DE", "#FF2D55", "#FF6482", "#A2845E",
                                    "#8E8E93", "#64D2FF", "#BF5AF2", "#32ADE6",
                                    "#FFD60A", "#4CD964", "#FF7A45", "#C77DFF",
                                    "#06D6A0", "#EF476F", "#FFD166", "#118AB2"
                                ]

                                delegate: Rectangle {
                                    width: 32; height: 32
                                    radius: 16
                                    color: modelData
                                    border.width: (root.appConfig && root.appConfig.audioVisualizerColor === modelData) ? 3 : 1
                                    border.color: (root.appConfig && root.appConfig.audioVisualizerColor === modelData) ? Theme.fgSurface : Theme.outlineVariant

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.appConfig)
                                                root.appConfig.setAudioVisualizerColor(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }   // push content to top
                }
            } // end AUDIO VISUALIZER panel

            // ────────────────────────────────────────────────────────────
            // PANEL 6 — MILKDROP
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 5

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 20

                    // ── Preset folder list ──────────────────────────────
                    // Cached rows -- see refreshMilkdropFolderRows() below for
                    // why this isn't a live binding to appConfig.milkdropPresetFolders.
                    ListModel { id: milkdropFolderListModel }

                    // Patches the matching row in place as each folder's
                    // background scan finishes -- see refreshMilkdropFolderRows()
                    // and MilkdropCleanupController::scanPresetFolderCountsAsync().
                    // Matched by path rather than index so a result that
                    // arrives after the folder list was rebuilt (ADD/DELETE
                    // mid-scan) just no-ops instead of patching the wrong row.
                    Connections {
                        target: root.cleanupController
                        function onPresetFolderCountReady(path, presetCount) {
                            for (let i = 0; i < milkdropFolderListModel.count; i++) {
                                if (milkdropFolderListModel.get(i).path === path) {
                                    milkdropFolderListModel.setProperty(i, "presetCount", presetCount)
                                    milkdropFolderListModel.setProperty(i, "scanning", false)
                                    break
                                }
                            }
                        }
                    }

                    // Column header
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        color:  Theme.surfaceContainerHigh
                        radius: Theme.radiusSm
                        visible: milkdropFolderListModel.count > 0

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 8   // must match the folder-row delegate's RowLayout below,
                                         // or PRESETS/ACTIVE drift out of column alignment
                            Text {
                                Layout.fillWidth: true
                                text: "PRESET FOLDER"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelXs
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWidest
                                color: Theme.fgSurfaceVariant
                            }
                            Text {
                                Layout.preferredWidth: 90
                                text: "PRESETS"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelXs
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWidest
                                color: Theme.fgSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                Layout.preferredWidth: 70
                                text: "ACTIVE"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelXs
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWidest
                                color: Theme.fgSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 140

                        Text {
                            anchors.centerIn: parent
                            visible: milkdropFolderListModel.count === 0
                            text: "No preset folders configured.\nClick ADD FOLDER to point at a downloaded .milk preset pack."
                            horizontalAlignment: Text.AlignHCenter
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelLg
                            color: Theme.fgSurfaceVariant
                        }

                        ScrollView {
                            anchors.fill: parent
                            visible: milkdropFolderListModel.count > 0
                            clip: true

                            ListView {
                                id: milkdropFolderList
                                model: milkdropFolderListModel
                                spacing: 3

                                delegate: Rectangle {
                                    width:  milkdropFolderList.width
                                    height: 38
                                    radius: Theme.radiusSm
                                    opacity: (model.exists === false || model.active === false) ? 0.5 : 1.0

                                    readonly property bool isSelected:
                                        root.selectedMilkdropFolderIndex === index

                                    color: isSelected
                                           ? Theme.p10
                                           : mdRowHover.containsMouse
                                             ? Theme.surfaceContainerHigh
                                             : Theme.surfaceContainer

                                    RowLayout {
                                        anchors {
                                            fill: parent
                                            leftMargin: 12; rightMargin: 12
                                        }
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: model.path
                                            font.family:    Theme.fontFamilyMono
                                            font.pixelSize: Theme.monoLg
                                            color: Theme.fgSurface
                                            elide: Text.ElideMiddle
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        Item {
                                            Layout.preferredWidth: 90
                                            height: parent.height

                                            BusySpinner {
                                                anchors.centerIn: parent
                                                visible: model.scanning
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                visible: !model.scanning
                                                text: model.exists ? model.presetCount : "not found"
                                                font.family:    Theme.fontFamilyMono
                                                font.pixelSize: Theme.monoLg
                                                color: model.exists ? Theme.fgSurfaceVariant : Theme.error
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }

                                        // Active checkbox cell
                                        Item {
                                            Layout.preferredWidth: 70
                                            height: parent.height

                                            Rectangle {
                                                width: 18; height: 18
                                                anchors.centerIn: parent
                                                radius: 3
                                                color: model.active
                                                       ? Theme.secondaryContainer
                                                       : "transparent"
                                                border.width: model.active ? 0 : 1
                                                border.color: Theme.outlineVariant

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: model.active
                                                    text: "✓"   // ✓
                                                    font.pixelSize: 11
                                                    font.weight:    Font.Bold
                                                    color: Theme.fgSecondaryContainer
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape:  Qt.PointingHandCursor
                                                    onClicked: {
                                                        const newActive = !model.active
                                                        if (root.appConfig)
                                                            root.appConfig.setMilkdropPresetFolderActive(index, newActive)
                                                        // Patch in place rather than a full
                                                        // refreshMilkdropFolderRows() -- avoids
                                                        // re-scanning every folder's preset
                                                        // count on a plain toggle click.
                                                        milkdropFolderListModel.setProperty(index, "active", newActive)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Row-level click (select / deselect)
                                    MouseArea {
                                        id: mdRowHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        z: -1   // checkbox MouseArea sits on top
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedMilkdropFolderIndex =
                                            (root.selectedMilkdropFolderIndex === index) ? -1 : index
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 130; height: 32
                            radius: Theme.radiusSm
                            color: addMdFHover.containsMouse
                                   ? Theme.primaryContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "ADD FOLDER"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: addMdFHover.containsMouse
                                       ? Theme.fgPrimaryContainer : Theme.primary
                            }
                            MouseArea {
                                id: addMdFHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked:    milkdropFolderDialog.open()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 162; height: 32
                            radius: Theme.radiusSm
                            opacity: root.selectedMilkdropFolderIndex >= 0 ? 1.0 : 0.35
                            color: delMdFHover.containsMouse
                                   && root.selectedMilkdropFolderIndex >= 0
                                   ? Theme.errorContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "DELETE SELECTED"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: delMdFHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  root.selectedMilkdropFolderIndex >= 0
                                              ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.selectedMilkdropFolderIndex >= 0 && root.appConfig) {
                                        root.appConfig.removeMilkdropPresetFolderAt(root.selectedMilkdropFolderIndex)
                                        root.selectedMilkdropFolderIndex = -1
                                        root.refreshMilkdropFolderRows()
                                    }
                                }
                            }
                        }
                    }

                    // ── Shuffle row ──────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Shuffle Presets"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: shuffleTrack
                            readonly property bool shuffleOn:
                                root.appConfig !== null && root.appConfig.milkdropShuffleEnabled
                            width: 48; height: 24
                            radius: 12
                            color: shuffleOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: shuffleTrack.shuffleOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropShuffleEnabled(
                                            !root.appConfig.milkdropShuffleEnabled)
                                }
                            }
                        }
                    }

                    // ── Preset Duration row ──────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Preset Duration"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(presetDurationSlider.value) + "s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "10s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: presetDurationSlider
                                Layout.fillWidth: true
                                from: 10
                                to:   150
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.milkdropPresetDuration : 20

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropPresetDuration(value)
                                }

                                background: Rectangle {
                                    x: presetDurationSlider.leftPadding
                                    y: presetDurationSlider.topPadding
                                       + presetDurationSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  presetDurationSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  presetDurationSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: presetDurationSlider.leftPadding
                                       + presetDurationSlider.visualPosition
                                         * (presetDurationSlider.availableWidth - width)
                                    y: presetDurationSlider.topPadding
                                       + presetDurationSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "150s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Beat Sensitivity row ─────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Beat Sensitivity"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: beatSensitivitySlider.value.toFixed(2)
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "LOW"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: beatSensitivitySlider
                                Layout.fillWidth: true
                                from: 0.0
                                to:   4.0
                                stepSize: 0.1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.milkdropBeatSensitivity : 1.0

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropBeatSensitivity(value)
                                }

                                background: Rectangle {
                                    x: beatSensitivitySlider.leftPadding
                                    y: beatSensitivitySlider.topPadding
                                       + beatSensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  beatSensitivitySlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  beatSensitivitySlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: beatSensitivitySlider.leftPadding
                                       + beatSensitivitySlider.visualPosition
                                         * (beatSensitivitySlider.availableWidth - width)
                                    y: beatSensitivitySlider.topPadding
                                       + beatSensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "HIGH"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Hard Cuts row ─────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Hard Cuts"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text:    qsTr("Beat-triggered instant preset changes, instead of always smoothly transitioning")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: hardCutsTrack
                            readonly property bool hardCutsOn:
                                root.appConfig !== null && root.appConfig.milkdropHardCutsEnabled
                            width: 48; height: 24
                            radius: 12
                            color: hardCutsOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: hardCutsTrack.hardCutsOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropHardCutsEnabled(
                                            !root.appConfig.milkdropHardCutsEnabled)
                                }
                            }
                        }
                    }

                    // ── Hard Cut Sensitivity row ──────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Hard Cut Sensitivity"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(hardCutSensitivitySlider.value) + "%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "0%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: hardCutSensitivitySlider
                                Layout.fillWidth: true
                                from: 0
                                to:   100
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.milkdropHardCutSensitivity * 100 : 60

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropHardCutSensitivity(value / 100)
                                }

                                background: Rectangle {
                                    x: hardCutSensitivitySlider.leftPadding
                                    y: hardCutSensitivitySlider.topPadding
                                       + hardCutSensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  hardCutSensitivitySlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  hardCutSensitivitySlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: hardCutSensitivitySlider.leftPadding
                                       + hardCutSensitivitySlider.visualPosition
                                         * (hardCutSensitivitySlider.availableWidth - width)
                                    y: hardCutSensitivitySlider.topPadding
                                       + hardCutSensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "100%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Preset Locked row ─────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Lock Preset"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text:    qsTr("Disables all automatic preset transitions — stays on the current preset")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: presetLockedTrack
                            readonly property bool lockedOn:
                                root.appConfig !== null && root.appConfig.milkdropPresetLocked
                            width: 48; height: 24
                            radius: 12
                            color: lockedOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: presetLockedTrack.lockedOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropPresetLocked(
                                            !root.appConfig.milkdropPresetLocked)
                                }
                            }
                        }
                    }

                    // ── Show Preset Name row ──────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Show Preset Name"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text:    qsTr("Briefly shows the preset name in the pane on every switch, then fades out")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: showPresetNameTrack
                            readonly property bool showOn:
                                root.appConfig !== null && root.appConfig.milkdropShowPresetName
                            width: 48; height: 24
                            radius: 12
                            color: showOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: showPresetNameTrack.showOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropShowPresetName(
                                            !root.appConfig.milkdropShowPresetName)
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }   // push content to top
                }
            } // end MILKDROP panel

            // ────────────────────────────────────────────────────────────
            // PANEL 7 — MISC
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 6

                MessageBox {
                    id: abandonedRatingsResultBox
                    title: "ABANDONED RATINGS"
                    // Same fix as CLEANUP/BACKUP/RESTORE -- see
                    // removeRatingsHover's own comment.
                    onClosed: removeRatingsHover.hovered = false
                }

                Connections {
                    target: root.libraryModel
                    function onAbandonedRatingsRemovalFinished(removed, corrected, remaining) {
                        let msg = "Removed " + removed + " abandoned rating"
                                  + (removed === 1 ? "" : "s") + "."
                        if (corrected > 0)
                            msg += "<br><br>Corrected the genre for " + corrected
                                   + " rating" + (corrected === 1 ? "" : "s") + "."
                        msg += "<br><br>The " + remaining + " existing rating"
                               + (remaining === 1 ? "" : "s")
                               + " now match" + (remaining === 1 ? "es" : "")
                               + " the tracks in the library."
                        abandonedRatingsResultBox.message = msg
                        abandonedRatingsResultBox.open()
                    }
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 12

                    // ── Remove Abandoned Ratings row ────────────────────
                    // Removes every Topaz.rating.json entry whose track no
                    // longer exists in the library, and corrects the stored
                    // genre for any surviving entry whose track was
                    // re-tagged to a different genre since being rated --
                    // see UC-24.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            Layout.fillWidth: true
                            text: "Remove Abandoned Ratings"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Rectangle {
                            visible: !root.libraryModel || !root.libraryModel.removingAbandonedRatings
                            width: 110; height: 32
                            radius: Theme.radiusSm
                            color: removeRatingsHover.hovered
                                   ? Theme.primaryContainer : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "REMOVE"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: removeRatingsHover.hovered
                                       ? Theme.fgPrimaryContainer : Theme.primary
                            }
                            MouseArea {
                                id: removeRatingsHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // Tracked manually rather than reading
                                // containsMouse directly -- the result
                                // MessageBox opened after removal finishes
                                // is a modal Popup whose input grab
                                // suppresses hover events for this button
                                // while it's open, freezing containsMouse
                                // true with no way for Qt to self-correct
                                // once it closes. See
                                // milkdropCleanupHover's own comment for
                                // the full explanation (same fix as
                                // CLEANUP/BACKUP/RESTORE).
                                property bool hovered: false
                                onEntered: hovered = true
                                onExited:  hovered = false
                                onClicked: {
                                    if (root.libraryModel)
                                        root.libraryModel.removeAbandonedRatings()
                                }
                            }
                        }
                    }

                    // Progress bar -- only shown while the operation runs;
                    // no existing ProgressBar visual elsewhere in the app to
                    // match, so themed directly with Theme.* tokens.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: root.libraryModel && root.libraryModel.removingAbandonedRatings
                        height: 8
                        radius: height / 2
                        color: Theme.surfaceContainerHigh
                        clip: true

                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            color: Theme.primary
                            width: parent.width
                                   * (root.libraryModel ? root.libraryModel.abandonedRatingsProgress : 0)
                                   / 100
                            Behavior on width { NumberAnimation { duration: 120 } }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        height: 1
                        color: Theme.ov20
                    }

                    // ── Cleanup Incompatible Milkdrop Presets row ────────
                    // Opens MilkdropCleanupDialog.qml, which scans configured
                    // Milkdrop preset folders with MilkdropPresetChecker and
                    // deletes whatever it flags -- see UC-25. Styled as a
                    // destructive action (Theme.error) since, unlike REMOVE
                    // above, this deletes real files from disk, permanently.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 16

                        Text {
                            Layout.fillWidth: true
                            text: "Cleanup Incompatible Milkdrop Presets"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Rectangle {
                            width: 110; height: 32
                            radius: Theme.radiusSm
                            color: milkdropCleanupHover.hovered
                                   ? Theme.errorContainer : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "CLEANUP"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: milkdropCleanupHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // Tracked manually rather than reading
                                // containsMouse directly -- a modal Popup's
                                // input grab suppresses hover events for
                                // whatever's underneath while it's open, so
                                // containsMouse freezes true and Qt never
                                // re-evaluates it once the grab releases
                                // (toggling hoverEnabled doesn't force a
                                // re-hit-test either -- confirmed that
                                // attempt didn't work). Forcing this false
                                // directly in the dialog's onClosed below
                                // sidesteps needing Qt to generate any event.
                                property bool hovered: false
                                onEntered: hovered = true
                                onExited:  hovered = false
                                onClicked: milkdropCleanupDialog.open()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        height: 1
                        color: Theme.ov20
                    }

                    // ── Backup/Restore Topaz Environment rows ────────────
                    // Zips/unzips config, playlists, and ratings via
                    // BackupRestoreController -- see UC-27. Non-destructive
                    // coloring (unlike CLEANUP above) -- neither opens with
                    // data loss; RestoreDialog's own per-conflict prompts
                    // are where anything destructive can actually happen.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 16

                        Text {
                            Layout.fillWidth: true
                            text: "Backup Topaz Environment"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Rectangle {
                            width: 110; height: 32
                            radius: Theme.radiusSm
                            color: backupHover.hovered
                                   ? Theme.primaryContainer : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "BACKUP"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.primary
                            }
                            MouseArea {
                                id: backupHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                property bool hovered: false
                                onEntered: hovered = true
                                onExited:  hovered = false
                                onClicked: backupDialog.open()
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 16

                        Text {
                            Layout.fillWidth: true
                            text: "Restore Topaz Environment"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Rectangle {
                            width: 110; height: 32
                            radius: Theme.radiusSm
                            color: restoreHover.hovered
                                   ? Theme.primaryContainer : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "RESTORE"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.primary
                            }
                            MouseArea {
                                id: restoreHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                property bool hovered: false
                                onEntered: hovered = true
                                onExited:  hovered = false
                                onClicked: restoreDialog.open()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        height: 1
                        color: Theme.ov20
                    }

                    // ── Start Topaz in Full Screen row ───────────────────
                    // Overrides the old resolution-sniffing auto-fullscreen
                    // behavior with an explicit user preference -- see
                    // Main.qml's `visibility` binding. Takes effect on next
                    // launch (F11 still toggles the running window live).
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 16

                        Text {
                            Layout.fillWidth: true
                            text: "Start Topaz in Full Screen"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        // Same 48x24/18x18 pill toggle as the Crossfade
                        // on/off row (PLAYBACK tab).
                        Rectangle {
                            id: startFullscreenTrack
                            readonly property bool on:
                                root.appConfig !== null && root.appConfig.startFullscreen

                            width: 48; height: 24
                            radius: 12
                            color: on ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: startFullscreenTrack.on ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setStartFullscreen(
                                            !root.appConfig.startFullscreen)
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        height: 1
                        color: Theme.ov20
                    }

                    // ── Visual Folder Scanning row ───────────────────────
                    // Opt-in SCAN FOLDERS progress dialog (auto-opens on any
                    // scan start, auto-closes on completion) -- see
                    // ScanFoldersDialog.qml.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 16

                        Text {
                            Layout.fillWidth: true
                            text: "Visual Folder Scanning"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        // Same 48x24/18x18 pill toggle as the other MISC toggles.
                        // Both visualFolderScanning/setVisualFolderScanning are
                        // real AppConfig members (qmllint --ignore-settings
                        // reports 0) -- see CLAUDE.md's "Editor diagnostics" note.
                        // qmllint disable missing-property
                        Rectangle {
                            id: visualFolderScanningTrack
                            readonly property bool on:
                                root.appConfig !== null && root.appConfig.visualFolderScanning

                            width: 48; height: 24
                            radius: 12
                            color: on ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: visualFolderScanningTrack.on ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setVisualFolderScanning(
                                            !root.appConfig.visualFolderScanning)
                                }
                            }
                        }
                        // qmllint enable missing-property
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        height: 1
                        color: Theme.ov20
                    }

                    // ── Delete the Rating for the Track currently playing row
                    // Opt-in for NowPlaying's delete-current-rating trash-bin
                    // button (next to the rating stars) -- hidden entirely in
                    // NowPlaying, not just disabled, while this is off. See
                    // UC-29.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 16

                        Text {
                            Layout.fillWidth: true
                            text: "Delete the Rating for the Track currently playing"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        // Same 48x24/18x18 pill toggle as the other MISC/
                        // PLAYBACK toggles.
                        Rectangle {
                            id: deleteRatingTrack
                            readonly property bool on:
                                root.appConfig !== null && root.appConfig.deleteCurrentRatingEnabled

                            width: 48; height: 24
                            radius: 12
                            color: on ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: deleteRatingTrack.on ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setDeleteCurrentRatingEnabled(
                                            !root.appConfig.deleteCurrentRatingEnabled)
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        height: 1
                        color: Theme.ov20
                    }

                    // ── Album Browser & Search Result Sort Order row ─────
                    // Same radio-delegate styling as PLAYBACK's "Playback
                    // with" / AUTO PLAY's "Play a Title"/"Exceptions"
                    // groups, but stacked in a Column instead of a Row/Grid
                    // -- these two labels are long, and vertical stacking
                    // was explicitly requested. Drives
                    // LibraryModel::filteredAlbums()/searchLibrary() via
                    // AppConfig.albumBrowserSortOrder (see UC-01/UC-21).
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 12

                        Text {
                            text: "Album Browser & Search Result Sort Order"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Column {
                            Layout.leftMargin: 24
                            spacing: 12

                            Repeater {
                                model: [
                                    { value: "artistYearAlbum",
                                      label: "Artist ascending → Year descending → Album ascending" },
                                    { value: "artistAlbum",
                                      label: "Artist ascending → Album ascending" }
                                ]

                                delegate: RowLayout {
                                    spacing: 8

                                    readonly property bool selected:
                                        root.appConfig !== null
                                        && root.appConfig.albumBrowserSortOrder === modelData.value

                                    Rectangle {
                                        width: 18; height: 18
                                        radius: 9
                                        color: "transparent"
                                        border.width: 2
                                        border.color: selected ? Theme.secondary : Theme.outlineVariant

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 10; height: 10
                                            radius: 5
                                            color: Theme.secondary
                                            visible: selected
                                        }
                                    }

                                    Text {
                                        text: modelData.label
                                        font.family:    Theme.fontFamilyBody
                                        font.pixelSize: Theme.labelXl
                                        color: Theme.fgSurface
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.appConfig)
                                                root.appConfig.setAlbumBrowserSortOrder(modelData.value)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }   // push content to top
                }

                MilkdropCleanupDialog {
                    id: milkdropCleanupDialog
                    appConfig:         root.appConfig
                    cleanupController: root.cleanupController
                    // Direct, unconditional reset -- see milkdropCleanupHover's
                    // own comment for why toggling hoverEnabled (the first
                    // attempt at this fix) didn't actually work.
                    onClosed: milkdropCleanupHover.hovered = false
                }

                BackupDialog {
                    id: backupDialog
                    controller: root.backupRestoreController
                    onClosed: backupHover.hovered = false
                }

                RestoreDialog {
                    id: restoreDialog
                    controller: root.backupRestoreController
                    libraryModel: root.libraryModel
                    playbackEngine: root.playbackEngine
                    onClosed: restoreHover.hovered = false
                }
            } // end MISC panel

        } // content Item
    } // contentItem ColumnLayout

    // ── Native folder picker ─────────────────────────────────────────────
    FolderDialog {
        id: folderDialog
        title: "Select Music Folder"
        onAccepted: {
            if (root.appConfig) {
                root.appConfig.addFolder(selectedFolder.toString(), true)
                root._foldersDirty = true
            }
        }
    }

    FolderDialog {
        id: milkdropFolderDialog
        title: "Select Preset Folder"
        onAccepted: {
            if (root.appConfig)
                root.appConfig.addMilkdropPresetFolder(selectedFolder.toString())
            root.refreshMilkdropFolderRows()
        }
    }

    // ── Helper functions ─────────────────────────────────────────────────
    function doAddGenre() {
        const name = genreInput.text.trim()
        if (name.length > 0 && root.appConfig) {
            root.appConfig.addGenre(name)
            genreInput.text = ""
        }
    }

    // Rebuilds milkdropFolderListModel by zipping AppConfig's persisted
    // path/active per folder with MilkdropCleanupController's synchronous,
    // stat-only existence check (same underlying list, same order,
    // index-aligned zip is safe). Deliberately NOT a live binding:
    // appConfig.milkdropChanged fires for unrelated milkdrop settings too
    // (shuffle, duration, etc.), so binding directly would rebuild far more
    // often than needed. Call after anything that changes the folder *set*
    // (add/remove) or when the tab becomes visible; ACTIVE toggling patches
    // the model in place instead (see the ACTIVE cell below) to avoid
    // rebuilding on every click.
    //
    // Preset counts are NOT fetched here -- every existing folder starts at
    // scanning:true (see the PRESETS cell's BusySpinner above) and
    // scanPresetFolderCountsAsync() kicks off one background task per
    // folder; onPresetFolderCountReady (Connections above) patches each
    // row in place as its count arrives. This is what lets the tab render
    // immediately instead of blocking on a synchronous recursive directory
    // walk (formerly presetFolders()) for every configured folder.
    function refreshMilkdropFolderRows() {
        milkdropFolderListModel.clear()
        if (!root.appConfig) return
        const folders   = root.appConfig.milkdropPresetFolders
        const existence = root.cleanupController
                           ? root.cleanupController.presetFolderExistence() : []
        for (let i = 0; i < folders.length; i++) {
            const f = folders[i]
            const exists = (existence[i] && existence[i].exists) !== false
            milkdropFolderListModel.append({
                path:        f.path,
                active:      f.active !== false,
                presetCount: 0,
                exists:      exists,
                scanning:    exists   // "not found" rows never spin
            })
        }
        if (root.cleanupController) root.cleanupController.scanPresetFolderCountsAsync()
    }
}
