import QtQuick

// Non-visual data object for the SEARCH tab — deliberately independent of
// LibraryData: it never reads or writes LibraryData's selection state, and
// LibraryData never reads it back. The one intentional exception is
// activeGenreNames, bound one-way from LibraryData in Main.qml so the
// "Consider Genre" checkbox can read which genres are currently active in
// GenreBar; that's a read-only value the spec itself requires, not a
// structural coupling of search's behavior to the library's.
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

    property string query:          ""
    property string mode:           "all"   // "all" | "artists" | "albums" | "tracks"
    property bool   considerGenre:  false
    property bool   matchWholeWord: false
    property var    results:        []

    // SearchResultBrowser's ListView.contentY, persisted here (not in the
    // view itself) so it survives the view being destroyed/recreated by
    // Main.qml's Loader when switching away from and back to SEARCH.
    property real   resultScrollY:  0

    onQueryChanged:          _scheduleSearch()
    onModeChanged:           _scheduleSearch()
    onConsiderGenreChanged:  _scheduleSearch()
    onMatchWholeWordChanged: _scheduleSearch()
    onActiveGenreNamesChanged: if (considerGenre) _scheduleSearch()

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
            results = root.libraryModel
                ? root.libraryModel.searchLibrary(root.query.trim(), root.mode,
                                                   root.activeGenreNames, root.considerGenre,
                                                   root.matchWholeWord)
                : []
        }
    }
}
