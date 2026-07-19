import QtQuick

// Non-visual data object — acts as the shared model for GenreBar, LibraryTree,
// and AlbumBrowser.  Instantiated once in Main.qml (id: lib) and passed down
// via a `property var lib` on each panel.
Item {
    id: root
    visible: false
    width:   0
    height:  0

    // ── AppConfig binding ─────────────────────────────────────────────────
    property AppConfig appConfig: null

    onAppConfigChanged: {
        if (appConfig) {
            appConfig.genresChanged.connect(rebuildGenreModel)
            rebuildGenreModel()
        }
    }

    // Rebuild the genre toggle model from the persisted config.
    function rebuildGenreModel() {
        _genreModel.clear()
        activeGenreNames = []
        selectedArtist   = ""
        selectedAlbum    = ""
        if (!appConfig) return
        for (let i = 0; i < appConfig.genres.length; i++)
            _genreModel.append({ name: appConfig.genres[i], active: false })
    }

    // ── LibraryModel binding ──────────────────────────────────────────────
    // Set by Main.qml.  Drives the library tree and album browser.
    property LibraryModel libraryModel: null

    onLibraryModelChanged: {
        if (libraryModel) {
            libraryModel.libraryRefreshed.connect(_rebuildTree)
            _rebuildTree()
        }
    }

    // ── Library tree (genre → artists → albums) ───────────────────────────
    // Consumed by LibraryTree.qml via lib.library.
    // Shape: [ { genre, artists: [ { name, albums: [{title}] } ] } ]
    property var library: []

    function _rebuildTree() {
        if (!libraryModel) { library = []; return }
        // Single C++ call — one O(N_tracks) pass replaces N+1 separate scans.
        library = libraryModel.buildLibraryTree(activeGenreNames)
    }

    // ── Filter / Selection State ──────────────────────────────────────────
    property var    activeGenreNames: []
    property string selectedGenre:   ""
    property string selectedArtist:  ""
    property string selectedAlbum:   ""

    // ── Genre Toggle Model ────────────────────────────────────────────────
    // Populated at runtime by rebuildGenreModel() from AppConfig.genres.
    property alias genreModel: _genreModel

    ListModel {
        id: _genreModel
        // Starts empty; filled once AppConfig is bound.
    }

    // ── Mutation Functions ────────────────────────────────────────────────

    function toggleGenre(index) {
        const was = _genreModel.get(index).active
        _genreModel.setProperty(index, "active", !was)
        _rebuildActiveNames()
    }

    function selectGenre(name) {
        selectedGenre  = (selectedGenre === name) ? "" : name
        selectedArtist = ""
        selectedAlbum  = ""
    }

    function selectArtist(name) {
        selectedArtist = (selectedArtist === name) ? "" : name
        selectedAlbum  = ""
    }

    function selectAlbum(title) {
        selectedAlbum = (selectedAlbum === title) ? "" : title
    }

    function clearSelection() {
        selectedGenre  = ""
        selectedArtist = ""
        selectedAlbum  = ""
    }

    // ── Query Helpers ─────────────────────────────────────────────────────

    // Returns album objects for AlbumBrowser / AlbumCard.
    function filteredAlbums() {
        if (!libraryModel) return []
        // When a specific genre is selected in the tree, narrow to that one genre;
        // otherwise show all active genres.
        const effectiveGenres = selectedGenre !== ""
            ? [selectedGenre]
            : activeGenreNames
        return libraryModel.filteredAlbums(effectiveGenres, selectedArtist, selectedAlbum)
    }

    // Human-readable path for the AlbumBrowser subtitle.
    function statusPath() {
        if (activeGenreNames.length === 0) return "\u2014  NO GENRES ACTIVE"
        if (selectedAlbum  !== "") return _slug(selectedArtist) + "/" + _slug(selectedAlbum)
        if (selectedArtist !== "") return _slug(selectedArtist)
        if (selectedGenre  !== "") return _slug(selectedGenre)
        if (activeGenreNames.length === 1) return _slug(activeGenreNames[0])
        return activeGenreNames.map(_slug).join("  +  ")
    }

    // ── Private Helpers ───────────────────────────────────────────────────

    function _rebuildActiveNames() {
        const names = []
        for (let i = 0; i < _genreModel.count; i++) {
            if (_genreModel.get(i).active) names.push(_genreModel.get(i).name)
        }
        activeGenreNames = names
        selectedGenre    = ""
        selectedArtist   = ""
        selectedAlbum    = ""
        _rebuildTree()
    }

    function _slug(s) {
        return s.toUpperCase().replace(/ /g, "_")
    }
}