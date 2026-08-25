import QtQuick

// Non-visual data object for the PLAYLISTS tab -- deliberately independent
// of LibraryData/SearchData, mirroring their pattern (see SearchData.qml).
// The one necessary read from outside is `engine.activePlaylistName`, so a
// playlist already loaded into the queue can be recognized and excluded
// from selection (see PlaylistsPanel.qml) -- a read-only reference, not a
// structural coupling to Library/Search state.
// Instantiated once in Main.qml (id: playlistsData) and passed down via a
// `property PlaylistsData playlistsData` on PlaylistsPanel.qml/PlaylistViewer.qml.
Item {
    id: root
    visible: false
    width:   0
    height:  0

    property PlaylistManager playlistManager: null
    property LibraryModel    libraryModel:    null
    // Set (one-way) by Main.qml from PlaybackEngine -- read-only here.
    property var             engine:          null

    property var    playlists:           []   // [{ fileName, displayName }]
    property string selectedFileName:    ""
    property string selectedDisplayName: ""
    // One standalone AlbumCard-shaped entry per track (no album grouping),
    // via LibraryModel.buildStandaloneTrackCards() -- preserves the
    // playlist's own track order (see UC-22).
    property var    albums:              []

    // Raw track maps for `selectedFileName`, exactly as returned by
    // PlaylistManager.loadPlaylist() -- kept so PlaylistViewer's LOAD button
    // can hand them straight to PlaybackEngine.addTracks() without
    // re-parsing the XSPF file and re-reading every tag a second time.
    property var    selectedRawTracks:   []

    // PlaylistViewer's ListView.contentY, persisted here so it survives the
    // view being destroyed/recreated by Main.qml's Loader -- same pattern as
    // LibraryData.albumScrollY / SearchData.resultScrollY (see UC-21).
    property real   resultScrollY: 0

    function refreshPlaylists() {
        playlists = playlistManager ? playlistManager.listPlaylists() : []
    }

    function selectPlaylist(fileName) {
        if (!playlistManager || !libraryModel) return
        const path   = playlistManager.playlistDirectory() + "/" + fileName
        const result = playlistManager.loadPlaylist(path)
        selectedFileName    = fileName
        selectedDisplayName = fileName.replace(/\.xml$/i, "")
        selectedRawTracks   = result.tracks || []
        albums              = libraryModel.buildStandaloneTrackCards(selectedRawTracks)
    }

    function clearSelection() {
        selectedFileName    = ""
        selectedDisplayName = ""
        selectedRawTracks   = []
        albums              = []
    }
}
