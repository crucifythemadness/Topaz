import QtQuick

// Dynamic library tree: Genre -> Artist -> Album.
// Uses a flat ListView (virtualized) instead of nested Repeaters inside a
// Flickable+Column. Only visible rows are instantiated, which eliminates the
// synchronous "instantiate everything then compute implicitHeight" cascade that
// made genre clicks feel sluggish with large libraries.
//
// Internal model: a JS flat array (flatRows) with row type tags:
//   type 0 = genre header
//   type 1 = artist row
//   type 2 = album row (only present when artist is expanded)
//   type 3 = "no artists" hint (injected after a genre that has 0 artists)
//
// flatRows is rebuilt:
//   - when lib.library changes  (genre activation / library scan)
//   - when expandedArtists changes (artist expand/collapse)
// Selection colours are purely reactive bindings on lib.selected* -- no
// flat-list rebuild needed for selection changes.
Rectangle {
    id: root
    property var lib: null
    color: Theme.surfaceContainerLowest

    // Ghost right border
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 1
        color: Theme.ov10
    }

    // ── Expand / collapse state ───────────────────────────────────────────
    // "genre:artistName" -> bool
    property var  expandedArtists: ({})
    // Set to true inside _toggleArtist so onExpandedArtistsChanged knows
    // to preserve the scroll position instead of resetting it.
    property bool _artistToggle:   false

    // ── Flat row array fed to ListView ────────────────────────────────────
    property var flatRows:     []
    property var activeGenres: []

    function _refreshGenres() {
        activeGenres = lib ? lib.library : []
        _rebuildFlatList()
    }

    // Build a flat JS array from activeGenres + expandedArtists state.
    // Pure JS array construction -- no C++ calls, no QML item creation.
    function _rebuildFlatList() {
        var rows = []
        for (var i = 0; i < activeGenres.length; i++) {
            var ge = activeGenres[i]
            rows.push({ type: 0, genre: ge.genre, name: "",      title: "", artist: "" })
            if (ge.artists.length === 0) {
                rows.push({ type: 3, genre: ge.genre, name: "", title: "", artist: "" })
            } else {
                for (var j = 0; j < ge.artists.length; j++) {
                    var ae = ge.artists[j]
                    rows.push({ type: 1, genre: ge.genre, name: ae.name,  title: "", artist: ae.name })
                    if (expandedArtists[ge.genre + ":" + ae.name]) {
                        for (var k = 0; k < ae.albums.length; k++) {
                            rows.push({ type: 2, genre: ge.genre, name: "", title: ae.albums[k].title, artist: ae.name })
                        }
                    }
                }
            }
        }
        flatRows = rows
    }

    onLibChanged: _refreshGenres()
    onExpandedArtistsChanged: {
        if (_artistToggle) {
            // Artist expand/collapse: preserve the current scroll position.
            var savedY = treeList.contentY
            _rebuildFlatList()
            Qt.callLater(function() { treeList.contentY = savedY })
        } else {
            _rebuildFlatList()
        }
    }

    Connections {
        target: lib
        function onLibraryChanged() { root._refreshGenres() }
    }

    // Scroll the tree to reveal a genre that was auto-selected (GenreBar toggle
    // activation, or the neighbour-select on deactivation) — never fired for
    // user-driven selection (manual tree clicks use lib.selectGenre() instead).
    Connections {
        target: lib
        function onGenreAutoSelected(genre) {
            Qt.callLater(function() {
                for (let i = 0; i < root.flatRows.length; i++) {
                    if (root.flatRows[i].type === 0 && root.flatRows[i].genre === genre) {
                        treeList.positionViewAtIndex(i, ListView.Contain)
                        break
                    }
                }
            })
        }
    }

    function _toggleArtist(genre, artist) {
        _artistToggle = true
        var key  = genre + ":" + artist
        var copy = {}
        for (var k in expandedArtists) copy[k] = expandedArtists[k]
        copy[key] = !copy[key]
        expandedArtists = copy          // triggers onExpandedArtistsChanged -> _rebuildFlatList()
        _artistToggle = false
        if (lib) lib.selectArtist(artist, genre)
    }

    function _selectGenre(genre) {
        expandedArtists = {}            // collapse all artists, triggers _rebuildFlatList()
        if (lib) lib.selectGenre(genre)
    }

    // ── Header ────────────────────────────────────────────────────────────
    Item {
        id: treeHeader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 56

        Row {
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            spacing: 8

            Text {
                text: "\u25BE"
                font.pixelSize: Theme.labelLg
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: qsTr("LIBRARY")
                font.family:        Theme.fontFamilyHeadline
                font.pixelSize:     Theme.labelLg
                font.weight:        Font.Bold
                font.letterSpacing: Theme.lsWidest
                color: Theme.primary
            }
        }
    }

    // ── Empty state ───────────────────────────────────────────────────────
    Text {
        anchors {
            top: treeHeader.bottom; topMargin: 16
            left: parent.left; right: parent.right
        }
        visible: root.flatRows.length === 0
        text:    qsTr("No genres active.\nToggle a genre button above.")
        font.family:    Theme.fontFamilyBody
        font.pixelSize: Theme.labelLg
        color:          Theme.fgSurfaceVariant
        wrapMode:       Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        leftPadding:  20
        rightPadding: 20
    }

    // ── Virtualised tree list ─────────────────────────────────────────────
    ListView {
        id: treeList
        anchors {
            left: parent.left; right: parent.right
            top: treeHeader.bottom; bottom: parent.bottom
            leftMargin: 20; rightMargin: 12; bottomMargin: 8
        }
        clip:        true
        cacheBuffer: 160   // keep ~4 extra rows above/below viewport instantiated
        model:       root.flatRows
        spacing:     0

        delegate: Item {
            id: rowDelegate
            width: treeList.width - 8
            height: modelData.type === 0 ? 44
                  : modelData.type === 1 ? 40
                  : modelData.type === 3 ? 28
                  :                        36   // type 2 album

            // ── Reactive state (no flat-list rebuild needed for these) ─────
            readonly property bool genreSel:  modelData.type === 0 && !!lib && lib.selectedGenre  === modelData.genre
            readonly property bool artistSel: modelData.type === 1 && !!lib && lib.selectedArtist === modelData.name
            readonly property bool artistExp: modelData.type === 1 && !!root.expandedArtists[modelData.genre + ":" + modelData.name]
            readonly property bool albumSel:  modelData.type === 2 && !!lib && lib.selectedAlbum  === modelData.title

            // ── Genre row (type 0) ────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: modelData.type === 0
                enabled: modelData.type === 0

                Rectangle {
                    anchors.fill: parent
                    color:  rowDelegate.genreSel ? Theme.s10 : "transparent"
                    radius: Theme.radiusSm
                }

                Row {
                    spacing: 8
                    anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }

                    Text {
                        text: "\u2B25"
                        font.pixelSize: Theme.labelMd
                        color: rowDelegate.genreSel ? Theme.secondary : Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: modelData.genre.toUpperCase()
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelLg
                        font.weight:        rowDelegate.genreSel ? Font.ExtraBold : Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: rowDelegate.genreSel ? Theme.secondary : Theme.primary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: root._selectGenre(modelData.genre)
                }
            }

            // ── "No artists" hint (type 3) ────────────────────────────────
            Text {
                anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
                visible:        modelData.type === 3
                text:           qsTr("No artists scanned yet")
                font.family:    Theme.fontFamilyBody
                font.pixelSize: Theme.labelMd
                color:          Theme.fgSurfaceVariant
            }

            // ── Artist row (type 1) ───────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: modelData.type === 1
                enabled: modelData.type === 1

                Rectangle {
                    anchors.fill: parent
                    color: rowDelegate.artistSel ? Theme.p05 : "transparent"
                }

                Row {
                    spacing: 6
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }

                    // Expand/collapse chevron
                    Text {
                        text: rowDelegate.artistExp ? "\u25BE" : "\u25B8"
                        font.pixelSize: Theme.labelSm
                        color: rowDelegate.artistSel ? Theme.primary : Theme.fgSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: modelData.name.toUpperCase()
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.labelLg
                        font.weight:    rowDelegate.artistSel ? Font.Bold : Font.Medium
                        color: rowDelegate.artistSel       ? Theme.primary
                             : artistMA.containsMouse      ? Theme.fgSurface
                             :                               Theme.fgSurfaceVariant
                    }
                }

                MouseArea {
                    id: artistMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: root._toggleArtist(modelData.genre, modelData.name)
                }
            }

            // ── Album row (type 2) ────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: modelData.type === 2
                enabled: modelData.type === 2

                // Left accent line
                Rectangle {
                    anchors { left: parent.left; leftMargin: 28; top: parent.top; bottom: parent.bottom }
                    width: 1
                    color: rowDelegate.albumSel ? Theme.primary : Theme.ov20
                }

                Rectangle {
                    anchors.fill: parent
                    color: rowDelegate.albumSel ? Theme.p05 : "transparent"
                }

                Text {
                    anchors { left: parent.left; leftMargin: 38; verticalCenter: parent.verticalCenter }
                    text: modelData.title
                    font.family:    Theme.fontFamilyBody
                    font.pixelSize: Theme.labelMd
                    font.weight:    rowDelegate.albumSel ? Font.Bold : Font.Normal
                    color: rowDelegate.albumSel    ? Theme.primary
                         : albumMA.containsMouse   ? Theme.primary
                         :                          Theme.fgSurfaceVariant
                    elide: Text.ElideRight
                    width: parent.width - 40
                }

                MouseArea {
                    id: albumMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: { if (lib) lib.selectAlbum(modelData.title) }
                }
            }
        }

        // Custom scrollbar — draggable thumb (see UC-12)
        Rectangle {
            id: treeScrollTrack
            z: 2   // guarantee hit-testing above delegate content, regardless of stacking order
            anchors { right: treeList.right; top: treeList.top; bottom: treeList.bottom }
            width: 4
            color: Theme.surfaceContainerLowest
            Rectangle {
                id: treeScrollThumb
                width:  parent.width
                height: Math.max(20, parent.height * treeList.visibleArea.heightRatio)
                y:      treeList.visibleArea.yPosition * parent.height
                color:  treeThumbMA.pressed         ? Theme.secondary
                      : treeThumbMA.containsMouse    ? Theme.fgSurfaceVariant
                      :                                Theme.outlineVariant
                radius: 2
                visible: treeList.contentHeight > treeList.height

                MouseArea {
                    id: treeThumbMA
                    anchors.fill: parent
                    hoverEnabled:    true
                    preventStealing: true
                    cursorShape:     Qt.PointingHandCursor

                    property real pressTrackY:   0
                    property real pressContentY: 0

                    onPressed: function(mouse) {
                        var pt = mapToItem(treeScrollTrack, mouse.x, mouse.y)
                        pressTrackY   = pt.y
                        pressContentY = treeList.contentY
                    }

                    onPositionChanged: function(mouse) {
                        if (!pressed) return
                        var pt = mapToItem(treeScrollTrack, mouse.x, mouse.y)
                        var trackRange = treeScrollTrack.height - treeScrollThumb.height
                        if (trackRange <= 0) return
                        var contentRange = treeList.contentHeight - treeList.height
                        if (contentRange <= 0) return
                        var newY = pressContentY + (pt.y - pressTrackY) * (contentRange / trackRange)
                        treeList.contentY = Math.max(0, Math.min(newY, contentRange))
                    }
                }
            }
        }
    }
}