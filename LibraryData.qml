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

    // AlbumBrowser's ListView.contentY, persisted here (not in the view
    // itself) so it survives the view being destroyed/recreated by
    // Main.qml's Loader when switching away from and back to LIBRARY.
    property real   albumScrollY:    0

    // Set (one-way) by Main.qml from its own activeTab. Read-only here --
    // used only to suppress the LIBRARY-tab-specific genre auto-select
    // convenience in toggleGenre() while SEARCH is active (LibraryTree/
    // AlbumBrowser aren't even loaded then, and leaving a stale
    // selectedGenre around would surprise the user when they switch back).
    property string activeTab: "library"

    // Emitted only when a genre is auto-selected as a result of GenreBar
    // activation/deactivation (see _selectGenreExclusive()) — never for
    // user-driven selection (tree clicks go through selectGenre() instead).
    signal genreAutoSelected(string genre)

    // ── Genre Toggle Model ────────────────────────────────────────────────
    // Populated at runtime by rebuildGenreModel() from AppConfig.genres.
    property alias genreModel: _genreModel

    ListModel {
        id: _genreModel
        // Starts empty; filled once AppConfig is bound.
    }

    // ── Mutation Functions ────────────────────────────────────────────────

    function toggleGenre(index) {
        const entry      = _genreModel.get(index)
        const name       = entry.name
        const activating = !entry.active

        if (activating) {
            _genreModel.setProperty(index, "active", true)
            _rebuildActiveNames()
            if (activeTab === "library") _selectGenreExclusive(name)
        } else {
            // Capture this genre's position among the currently-active genres
            // before removing it, so we can auto-select its nearest neighbour.
            const oldActive = activeGenreNames
            const pos = Math.max(0, oldActive.indexOf(name))

            _genreModel.setProperty(index, "active", false)
            _rebuildActiveNames()

            if (activeTab === "library") {
                if (activeGenreNames.length === 0) {
                    selectedGenre = ""
                } else {
                    // Removing the genre at `pos` shifts everything after it down by
                    // one, so the genre that was next now sits at this same index;
                    // if this genre was last, clamp to the new last (previous) genre.
                    const neighborIdx = Math.min(pos, activeGenreNames.length - 1)
                    _selectGenreExclusive(activeGenreNames[neighborIdx])
                }
            }
        }
    }

    // Selects exactly one genre, replacing any prior genre/artist/album selection.
    function _selectGenreExclusive(name) {
        selectedGenre  = name
        selectedArtist = ""
        selectedAlbum  = ""
        genreAutoSelected(name)
    }

    function selectGenre(name) {
        selectedGenre  = (selectedGenre === name) ? "" : name
        selectedArtist = ""
        selectedAlbum  = ""
    }

    function selectArtist(name, genre) {
        const sameArtist = (selectedArtist === name)
        const sameGenre  = (genre === undefined || genre === selectedGenre)
        if (sameArtist && sameGenre) {
            // Clicking the exact same artist row again — deselect.
            selectedArtist = ""
            selectedAlbum  = ""
            return
        }
        // An artist can appear under more than one genre section if their tracks
        // carry different genre tags — pre-select the row's actual genre so
        // filteredAlbums() doesn't narrow to the wrong (empty-for-this-artist) genre.
        if (genre !== undefined && genre !== selectedGenre)
            selectedGenre = genre
        selectedArtist = name
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
        // Only clear the drill-down selection on the LIBRARY tab -- while
        // SEARCH is active, toggling a genre (e.g. for "Consider Genre")
        // must not disturb whatever artist/album the user had selected in
        // LibraryTree, since that view isn't even loaded right now.
        if (activeTab === "library") {
            selectedArtist = ""
            selectedAlbum  = ""
        }
        _rebuildTree()
    }

    function _slug(s) {
        return s.toUpperCase().replace(/ /g, "_")
    }
}