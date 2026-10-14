import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
// qmllint disable Quick.layout-positioning
import QtQuick.Controls
import QtQuick.Layouts

// ── FoundGenresDialog ────────────────────────────────────────────────────
// FOUND GENRES (UC-36), opened from Setup -> GENRES -> SCAN FOLDERS. Starts a
// genre discovery scan (GenreScanController) of the ACTIVE monitored folders
// as soon as it opens; every genre found is shown at once, as a chip with its
// track count, while the scan is still running (the footer shows the
// progress). Genres already in GENRES are shown dimmed and can't be picked;
// new ones can be picked at any time, up to the free GENRES slots. ADD
// SELECTED adds them (AppConfig.addGenre, alphabetical) and emits
// genresAdded() -- SetupDialog then rescans the library when it closes.
//
// Chrome modeled on ExportPlaylistDialog.qml (header + ✕, draggable header,
// dark scrim). The chips mirror the GENRES grid cells; the grid's scrollbar
// is the main window's draggable one (UC-12).
//
// Usage in SetupDialog.qml:
//   FoundGenresDialog { appConfig: root.appConfig; scanController: root.genreScanController
//                       onGenresAdded: ... }
Popup {
    id: root

    property AppConfig appConfig: null
    property var       scanController: null

    // Emitted after ADD SELECTED with the number of genres actually added.
    signal genresAdded(int count)

    // ── State ────────────────────────────────────────────────────────────
    // Picked genres, keyed by lower-cased name (genres are compared
    // case-insensitively everywhere, same as AppConfig.addGenre). Always
    // reassigned (never mutated in place) so bindings re-evaluate.
    property var selection: ({})
    readonly property int selectedCount: Object.keys(selection).length

    readonly property bool scanning: scanController !== null && scanController.scanning
    readonly property var  configuredLower:
        appConfig ? appConfig.genres.map(function (g) { return g.toLowerCase() }) : []
    readonly property int  freeSlots:
        appConfig ? Math.max(0, appConfig.maxGenres() - appConfig.genres.length) : 0
    readonly property int  newCount: {
        let n = 0
        const list = scanController ? scanController.genres : []
        for (let i = 0; i < list.length; ++i)
            if (!isConfigured(list[i].name)) ++n
        return n
    }

    function isConfigured(name) { return configuredLower.indexOf(name.toLowerCase()) >= 0 }
    function isSelected(name)   { return selection[name.toLowerCase()] === true }
    function canPick(name) {
        return !isConfigured(name) && (isSelected(name) || selectedCount < freeSlots)
    }
    function toggle(name) {
        if (!canPick(name)) return
        const s = Object.assign({}, selection)
        const k = name.toLowerCase()
        if (s[k]) delete s[k]; else s[k] = true
        selection = s
    }
    function fmt(n) { return Number(n).toLocaleString(Qt.locale(), 'f', 0) }

    // The grid's model is synced incrementally from scanController.genres
    // (which is replaced wholesale after every chunk of files): genres are only
    // ever added during a scan, so existing chips stay where they are, keep
    // their delegate and the scroll position doesn't jump back to the top.
    ListModel { id: genreModel }
    function syncModel() {
        const list = scanController ? scanController.genres : []
        for (let i = 0; i < list.length; ++i) {
            const g = list[i]
            if (i < genreModel.count && genreModel.get(i).name.toLowerCase() === g.name.toLowerCase())
                genreModel.setProperty(i, "count", g.count)
            else
                genreModel.insert(i, { name: g.name, count: g.count })
        }
        while (genreModel.count > list.length) genreModel.remove(genreModel.count - 1)
    }
    Connections {
        target: root.scanController
        function onGenresChanged() { root.syncModel() }
    }

    function addSelected() {
        if (!appConfig || !scanController || selectedCount === 0) return
        const before = appConfig.genres.length
        const list = scanController.genres   // already alphabetical
        for (let i = 0; i < list.length; ++i)
            if (isSelected(list[i].name)) appConfig.addGenre(list[i].name)
        const added = appConfig.genres.length - before
        selection = ({})
        close()
        if (added > 0) genresAdded(added)
    }

    // ── Geometry ─────────────────────────────────────────────────────────
    // This dialog is declared inside SetupDialog's GENRES panel, and a
    // Popup's x/y are relative to its parent item -- so without this it was
    // offset by the panel's own position instead of centered in the window.
    // Parenting it to the window overlay makes x/y window coordinates.
    parent: Overlay.overlay
    // Plain x/y bindings, not anchors.centerIn (which fights the header
    // drag) -- recomputed in onOpened, same as ExportPlaylistDialog.
    x: Overlay.overlay ? (Overlay.overlay.width  - width)  / 2 : 0
    y: Overlay.overlay ? (Overlay.overlay.height - height) / 2 : 0
    width:  900
    height: 640
    padding: 0
    modal: true
    closePolicy: Popup.NoAutoClose

    onOpened: {
        x = Overlay.overlay ? (Overlay.overlay.width  - width)  / 2 : 0
        y = Overlay.overlay ? (Overlay.overlay.height - height) / 2 : 0
        selection = ({})
        genreModel.clear()
        if (scanController && appConfig) scanController.startScan(appConfig.folders)
    }
    onClosed: if (scanning) scanController.cancelScan()

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.72) }

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

            // Drag-to-move -- declared first so the ✕ button's MouseArea
            // (a later sibling) wins its own clicks.
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

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Theme.radiusLg
                color:  parent.color
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 16 }
                spacing: 0

                Text {
                    text: qsTr("FOUND GENRES")
                    font.family:        Theme.fontFamilyHeadline
                    font.pixelSize:     Theme.headlineSm
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                // ✕ -- always available; closing stops a running scan.
                Rectangle {
                    width: 32; height: 32
                    radius: Theme.radiusFull
                    color: closeHover.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
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

        // ── Body: the genre chips ────────────────────────────────────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true

            // Empty states
            Text {
                anchors.centerIn: parent
                visible: genreModel.count === 0
                horizontalAlignment: Text.AlignHCenter
                text: root.scanController && root.scanController.listing
                      ? qsTr("Looking for audio files…")
                      : (root.scanning ? qsTr("Reading genre tags…")
                                       : qsTr("No genre tags found in the active music folders."))
                font.family:    Theme.fontFamilyBody
                font.pixelSize: Theme.labelLg
                color: Theme.fgSurfaceVariant
            }

            GridView {
                id: genreGrid
                anchors { fill: parent; leftMargin: 24; rightMargin: 24 + 14; topMargin: 20; bottomMargin: 12 }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: genreModel
                cellWidth:  Math.floor(width / 3)
                cellHeight: 62

                delegate: Item {
                    id: chipCell
                    width:  genreGrid.cellWidth
                    height: genreGrid.cellHeight

                    required property string name
                    required property int    count

                    readonly property bool configured: root.isConfigured(name)
                    readonly property bool picked:     root.isSelected(name)
                    readonly property bool pickable:   root.canPick(name)

                    Rectangle {
                        anchors { fill: parent; rightMargin: 8; bottomMargin: 8 }
                        radius: Theme.radiusSm
                        color: chipCell.picked ? Theme.secondaryContainer
                             : chipHover.containsMouse && chipCell.pickable ? Theme.surfaceContainerHighest
                             : Theme.surfaceContainerHigh
                        opacity: chipCell.configured ? 0.45
                               : (chipCell.pickable ? 1.0 : 0.35)

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 10

                            // Checkbox -- same idiom as the Export dialog's
                            Rectangle {
                                width: 18; height: 18
                                radius: 3
                                color: chipCell.picked || chipCell.configured
                                       ? Theme.secondaryContainer : "transparent"
                                border.width: chipCell.picked || chipCell.configured ? 0 : 1
                                border.color: Theme.outlineVariant
                                Text {
                                    anchors.centerIn: parent
                                    visible: chipCell.picked || chipCell.configured
                                    text: "✓"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: Theme.fgSecondaryContainer
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 2
                                // The genre exactly as it is tagged -- the
                                // spelling that gets added to GENRES.
                                Text {
                                    width: parent.width
                                    text: chipCell.name
                                    elide: Text.ElideRight
                                    font.family:    Theme.fontFamilyBody
                                    font.pixelSize: Theme.labelLg
                                    font.weight:    Font.DemiBold
                                    color: chipCell.picked ? Theme.fgSecondaryContainer : Theme.fgSurface
                                }
                                Text {
                                    width: parent.width
                                    text: chipCell.configured
                                          ? qsTr("already in GENRES")
                                          : (chipCell.count === 1 ? qsTr("1 track")
                                                                  : qsTr("%1 tracks").arg(root.fmt(chipCell.count)))
                                    font.family:    Theme.fontFamilyMono
                                    font.pixelSize: Theme.monoSm
                                    color: chipCell.picked ? Theme.fgSecondaryContainer : Theme.fgSurfaceVariant
                                }
                            }
                        }

                        MouseArea {
                            id: chipHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: chipCell.pickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.toggle(chipCell.name)
                        }
                    }
                }
            }

            // Draggable scrollbar thumb -- same look and behaviour as the
            // main window's panels (UC-12).
            Rectangle {
                id: scrollTrack
                z: 2
                anchors { right: parent.right; rightMargin: 24; top: genreGrid.top; bottom: genreGrid.bottom }
                width: 8
                color: Theme.surfaceContainerLowest
                visible: genreGrid.contentHeight > genreGrid.height
                Rectangle {
                    id: scrollThumb
                    width:  parent.width
                    height: Math.max(20, parent.height * genreGrid.visibleArea.heightRatio)
                    y:      genreGrid.visibleArea.yPosition * parent.height
                    color:  thumbMA.pressed       ? Theme.secondary
                          : thumbMA.containsMouse ? Theme.fgSurfaceVariant
                          :                         Theme.outlineVariant
                    radius: 2
                    MouseArea {
                        id: thumbMA
                        anchors.fill: parent
                        hoverEnabled:    true
                        preventStealing: true
                        cursorShape:     Qt.PointingHandCursor
                        property real pressTrackY:   0
                        property real pressContentY: 0
                        onPressed: function(mouse) {
                            const pt = mapToItem(scrollTrack, mouse.x, mouse.y)
                            pressTrackY   = pt.y
                            pressContentY = genreGrid.contentY
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed) return
                            const pt = mapToItem(scrollTrack, mouse.x, mouse.y)
                            const trackRange = scrollTrack.height - scrollThumb.height
                            const contentRange = genreGrid.contentHeight - genreGrid.height
                            if (trackRange <= 0 || contentRange <= 0) return
                            const newY = pressContentY + (pt.y - pressTrackY) * (contentRange / trackRange)
                            genreGrid.contentY = Math.max(0, Math.min(newY, contentRange))
                        }
                    }
                }
            }
        }

        // ── Footer: progress / summary + buttons ─────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 72
            color:  Theme.surfaceContainerLow

            Rectangle {   // ghost separator
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color: Theme.ov10
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.labelLg
                        color: Theme.fgSurface
                        text: {
                            const sc = root.scanController
                            if (!sc) return ""
                            const genres = sc.genres.length
                            const gText = genres === 1 ? qsTr("1 genre") : qsTr("%1 genres").arg(genres)
                            if (sc.listing) return qsTr("Looking for audio files…")
                            if (root.scanning)
                                return qsTr("Scanning… %1 / %2 files · %3")
                                       .arg(root.fmt(sc.filesDone)).arg(root.fmt(sc.filesTotal)).arg(gText)
                            let s = (sc.cancelled ? qsTr("Scan stopped — ") : "")
                                    + qsTr("%1 found · %2 new · %3 free slots")
                                      .arg(gText).arg(root.newCount).arg(root.freeSlots)
                            if (sc.filesWithoutGenre > 0)
                                s += qsTr(" · %1 files without a genre tag").arg(root.fmt(sc.filesWithoutGenre))
                            return s
                        }
                    }

                    // Progress bar while scanning; the selection limit once
                    // the free slots are used up.
                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.scanning
                        height: 6
                        radius: height / 2
                        color: Theme.surfaceContainerHigh
                        clip: true
                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            color: Theme.primary
                            width: parent.width * (root.scanController ? root.scanController.progress : 0) / 100
                            Behavior on width { NumberAnimation { duration: 120 } }
                        }
                    }
                    Text {
                        visible: !root.scanning && root.freeSlots > 0
                                 && root.selectedCount >= root.freeSlots
                        text: qsTr("All free GENRES slots are taken by your selection.")
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.labelMd
                        color: Theme.tertiary
                    }
                    Text {
                        visible: !root.scanning && root.freeSlots === 0
                        text: qsTr("GENRES is full (%1). Delete a genre to make room.")
                              .arg(root.appConfig ? root.appConfig.maxGenres() : 0)
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.labelMd
                        color: Theme.tertiary
                    }
                }

                // STOP (while scanning) / CANCEL
                Rectangle {
                    width: 100; height: 36
                    radius: Theme.radiusSm
                    color: cancelHover.containsMouse ? Theme.surfaceContainerHighest
                                                     : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: root.scanning ? qsTr("STOP") : qsTr("CANCEL")
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelSm
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: Theme.fgSurfaceVariant
                    }
                    MouseArea {
                        id: cancelHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            if (root.scanning) root.scanController.cancelScan()
                            else root.close()
                        }
                    }
                }

                // ADD SELECTED (n) -- usable while the scan is still running.
                Rectangle {
                    readonly property bool active: root.selectedCount > 0
                    width: 180; height: 36
                    radius: Theme.radiusSm
                    opacity: active ? 1.0 : 0.35
                    color: addHover.containsMouse && active ? Theme.primaryContainer
                                                            : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: root.selectedCount > 0
                              ? qsTr("ADD SELECTED (%1)").arg(root.selectedCount)
                              : qsTr("ADD SELECTED")
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelSm
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: addHover.containsMouse && parent.active
                               ? Theme.fgPrimaryContainer : Theme.primary
                    }
                    MouseArea {
                        id: addHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.active ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.addSelected()
                    }
                }
            }
        }
    }
}
