import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// Non-visual data object for the SEARCH tab — deliberately independent of
// LibraryData: it never reads or writes LibraryData's selection state, and
// LibraryData never reads it back. Two intentional read-only exceptions:
// activeGenreNames (bound one-way from LibraryData in Main.qml, the genres
// currently toggled active in GenreBar this session -- used when "Consider
// Genre" is checked) and enabledGenreNames (bound one-way from AppConfig,
// every genre currently enabled to appear in GenreBar at all -- the baseline
// used when "Consider Genre" is unchecked, see UC-03/UC-21). Both exist only
// to keep search's scope from ever exceeding what's visible/enabled; neither
// is a structural coupling of search's behavior to the library's.
// Instantiated once in Main.qml (id: search) and passed down via a
// `property SearchData searchData` on SearchPanel.qml/SearchResultBrowser.qml.
Item {
    id: root
    visible: false
    width:   0
    height:  0

    property LibraryModel libraryModel: null

    // Set (one-way) by Main.qml from LibraryData.activeGenreNames.
    property var activeGenreNames: []
    // Set (one-way) by Main.qml from AppConfig.enabledGenres.
    property var enabledGenreNames: []

    property string query:          ""
    property string mode:           "all"   // "all" | "artists" | "albums" | "tracks"
    property bool   considerGenre:  false
    property bool   matchWholeWord: false
    property var    results:        []

    // SearchResultBrowser's top-visible-row anchor, persisted here (not in
    // the view itself) so it survives the view being destroyed/recreated by
    // Main.qml's Loader when switching away from and back to SEARCH.
    // Index-based (not a raw contentY pixel value) because AlbumCard's
    // content-derived height makes contentHeight only an estimate until
    // every delegate is realized -- restoring a pixel value can land on a
    // different logical row than where the user actually was. See UC-12.
    property int    resultScrollIndex:  0
    property real   resultScrollOffset: 0

    onQueryChanged:          _scheduleSearch()
    onModeChanged:           _scheduleSearch()
    onConsiderGenreChanged:  _scheduleSearch()
    onMatchWholeWordChanged: _scheduleSearch()
    onActiveGenreNamesChanged:  if (considerGenre)  _scheduleSearch()
    onEnabledGenreNamesChanged: if (!considerGenre) _scheduleSearch()

    // Re-sorts immediately when the user changes Setup > MISC's "Album
    // Browser & Search Result Sort Order" -- see UC-32. libraryModel
    // already exposes appConfig, so no new property plumbing is needed
    // here. _scheduleSearch() already no-ops safely with no active query.
    Connections {
        target: root.libraryModel ? root.libraryModel.appConfig : null
        function onAlbumBrowserSortOrderChanged() { root._scheduleSearch() }
    }

    function _scheduleSearch() {
        if (query.trim() === "") {
            // No debounce wait needed for the empty case, and start clean
            // next time the user types something.
            results = []
            mode    = "all"
            return
        }
        _debounce.restart()
    }

    Timer {
        id: _debounce
        interval: 250
        repeat:   false
        onTriggered: {
            // Baseline (unchecked) restricts to every enabled genre -- a
            // disabled genre must never surface in search even though
            // "Consider Genre" itself is off; checked narrows further to
            // just the genres currently toggled active in GenreBar. Either
            // way genre filtering is now always applied (considerGenre: true
            // passed to searchLibrary()), just against a different list.
            const genresForSearch = root.considerGenre ? root.activeGenreNames
                                                         : root.enabledGenreNames
            results = root.libraryModel
                ? root.libraryModel.searchLibrary(root.query.trim(), root.mode,
                                                   genresForSearch, true,
                                                   root.matchWholeWord)
                : []
        }
    }
}
