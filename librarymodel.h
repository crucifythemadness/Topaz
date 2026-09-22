#pragma once

#include "appconfig.h"
#include "trackinfo.h"

#include <QAbstractListModel>
#include <QQmlEngine>
#include <QStringList>
#include <QVariantList>

class LibraryScanner;
class QThread;

// ── LibraryModel ──────────────────────────────────────────────────────────
// QAbstractListModel that backs the Topaz audio library.
//
// Owns a LibraryScanner worker on a dedicated QThread.
// Exposes the full track list as a QML list model (for PlaybackQueue) plus
// Q_INVOKABLE query helpers used by LibraryData.qml, LibraryTree.qml and
// AlbumBrowser.qml to build the tree / album views.
//
// Lifecycle (called from Main.qml):
//   1. Component.onCompleted → loadCacheAndStartStatCheck()
//      • loads Topaz.library.json instantly (< 100ms for 12K tracks)
//      • fires libraryRefreshed() so the UI can display cached data
//      • schedules a background stat-check on the worker thread
//   2. BottomBar "SCAN FOLDERS" button → startFullScan()
//      (Setup Dialog has no scan button of its own -- editing FILE
//      MONITORING there triggers startFullScan() automatically when the
//      dialog closes, see UC-04's "Auto-rescan on close")
//   3. The file-system watcher's own debounced auto-rescan (UC-07) and
//      UC-31's missing-track self-heal rescan also flip `scanning` --
//      the former via onScanStarted() below (LibraryScanner runs it
//      without LibraryModel ever having requested it), the latter via
//      rescanFolderContaining()'s own immediate set.
class LibraryModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(AppConfig* appConfig  READ appConfig  WRITE setAppConfig  NOTIFY appConfigChanged)
    Q_PROPERTY(bool        scanning   READ scanning   NOTIFY scanningChanged)
    Q_PROPERTY(int         scanProgress READ scanProgress NOTIFY scanProgressChanged)
    // Visual Folder Scanning (Setup > MISC, opt-in) -- see ScanFoldersDialog.qml.
    Q_PROPERTY(QString currentScanFolder READ currentScanFolder NOTIFY currentScanFolderChanged)
    Q_PROPERTY(bool    finalizingScan    READ finalizingScan    NOTIFY finalizingScanChanged)
    Q_PROPERTY(int         trackCount READ trackCount  NOTIFY trackCountChanged)
    Q_PROPERTY(int         albumCount READ albumCount  NOTIFY albumCountChanged)
    Q_PROPERTY(int         ratingCount READ ratingCount NOTIFY ratingCountChanged)
    Q_PROPERTY(bool        ratingsReady READ ratingsReady NOTIFY ratingsReadyChanged)
    Q_PROPERTY(bool        removingAbandonedRatings READ removingAbandonedRatings NOTIFY removingAbandonedRatingsChanged)
    Q_PROPERTY(int         abandonedRatingsProgress READ abandonedRatingsProgress NOTIFY abandonedRatingsProgressChanged)

public:
    // ── Roles exposed to QML delegates ───────────────────────────────────
    enum TrackRole {
        TrackIdRole       = Qt::UserRole + 1,
        FilePathRole,
        FileNameRole,
        TitleRole,
        ArtistRole,
        AlbumArtistRole,
        AlbumRole,
        GenreRole,
        TrackNumberRole,
        YearRole,
        DurationRole,       // milliseconds (int)
        DurationStringRole, // "MM:SS"
        BitrateRole,        // kbps (int)
        FileSizeRole,
        CoverThumbRole      // base64 JPEG or empty string
    };
    Q_ENUM(TrackRole)

    explicit LibraryModel(QObject *parent = nullptr);
    ~LibraryModel() override;

    // ── QAbstractListModel ────────────────────────────────────────────────
    int      rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // ── Properties ────────────────────────────────────────────────────────
    AppConfig *appConfig()    const { return m_appConfig; }
    bool       scanning()     const { return m_scanning; }
    int        scanProgress() const { return m_scanProgress; }
    QString    currentScanFolder() const { return m_currentScanFolder; }
    bool       finalizingScan()    const { return m_finalizingScan; }
    int        trackCount()   const { return m_tracks.size(); }
    int        albumCount()   const { return m_albumCount; }
    // Number of tracks in the current library with a rating (1-10) set --
    // shown as the RATINGS chip in AboutDialog's TOPAZ tab. See UC-14 for
    // rating persistence.
    int        ratingCount()  const { return m_ratingCount; }
    // True once a scan (full or stat-check) has completed at least once in this
    // session with rating enrichment applied — gates the AUTO PLAY button.
    bool       ratingsReady() const { return m_ratingsReady; }
    bool       removingAbandonedRatings() const { return m_removingAbandonedRatings; }
    int        abandonedRatingsProgress() const { return m_abandonedRatingsProgress; }
    void       setAppConfig(AppConfig *cfg);

    // ── Invokable actions ─────────────────────────────────────────────────
    // Load cache from disk, emit libraryRefreshed(), then start a background
    // stat-check.  Call this from Main.qml Component.onCompleted.
    Q_INVOKABLE void loadCacheAndStartStatCheck();

    // Trigger a full re-scan of all configured folders in background.
    Q_INVOKABLE void startFullScan();

    // UC-27 Restore: reloads m_tracks straight from Topaz.library.json on disk
    // (exactly step 1 of loadCacheAndStartStatCheck() -- applyTracks(LibraryCache::
    // load()) -- and nothing else: deliberately no stat-check/scan kicked off here,
    // so a just-restored library shows immediately without implying a scan the user
    // hasn't asked for yet. Reuses applyTracks(), so libraryRefreshed() fires exactly
    // as it does after a normal scan/cache load, and every existing reactive view
    // (LibraryTree/AlbumBrowser/GenreBar) updates with zero further changes needed.
    Q_INVOKABLE void reloadFromCache();

    // UC-27 Restore: re-syncs every currently-loaded track's in-memory rating from
    // Topaz.rating.json on disk right after it was restored -- a track with no
    // matching entry in the restored file goes back to unrated (0), not left
    // showing a stale rating from before the restore ("clear, then reapply").
    // Same two calls (updateRatingCount() + ratingsChanged()) applyRating() already
    // makes for a single star click, so existing reactive UI needs no changes.
    Q_INVOKABLE void reapplyRatingsFromDisk();

    // Rescans only the single configured FILE MONITORING folder that
    // filePath falls under (matched by prefix against m_appConfig->
    // activeFolders(), respecting includeSubfolders) -- called when
    // PlaybackEngine discovers a queued track's file is missing right
    // before playback, so the library self-heals without a full rescan.
    // No-op if a scan is already running (same "don't stack scans" guard
    // as startFullScan()) or no configured folder matches filePath (e.g.
    // it was removed from FILE MONITORING in the meantime). See UC-31.
    Q_INVOKABLE void rescanFolderContaining(const QString &filePath);

    // ── Invokable query helpers (used by LibraryData.qml) ────────────────

    // Distinct genres present in the current library, sorted.
    Q_INVOKABLE QStringList genres() const;

    // Artist names for a genre, sorted alphabetically.
    Q_INVOKABLE QStringList artistsForGenre(const QString &genre) const;

    // Album titles for an artist (optionally filtered by genre), sorted.
    Q_INVOKABLE QStringList albumsForArtist(const QString &artist,
                                             const QString &genre = {}) const;

    // Returns a QVariantList of album objects compatible with AlbumBrowser /
    // AlbumCard.  Each element is a QVariantMap:
    //   { albumTitle, albumArtist, artistLabel, isActive, coverSource, year, tracks }
    // where tracks is a QVariantList of { number, title, duration, filePath }.
    // Sorted by albumArtist ascending, then year descending, then albumTitle
    // ascending (case-insensitive); year 0 (unknown) sorts last per artist.
    Q_INVOKABLE QVariantList filteredAlbums(const QStringList &activeGenres,
                                             const QString     &selectedArtist,
                                             const QString     &selectedAlbum) const;

    // Cover thumbnail base64 string for the given album (first available).
    Q_INVOKABLE QString coverThumbForAlbum(const QString &album,
                                            const QString &albumArtist) const;

    // Converts a raw track list (the shape PlaylistManager::loadPlaylist()
    // returns) into one standalone AlbumCard-shaped entry per track — no
    // grouping by album, unlike filteredAlbums()/searchLibrary(), so
    // PlaylistViewer shows exactly how the playlist is composed track by
    // track (consecutive same-album tracks still render as separate cards).
    // Any track whose filePath matches a track in the scanned library
    // reuses that track's own tag data at zero extra I/O cost via a single
    // O(N_tracks) lookup pass. Cover art is resolved per track via
    // coverThumbForAlbum() whenever the matched (or synthesized) track's own
    // coverThumb is empty — which is the common case, since coverThumb is
    // only populated on one representative track per album in the whole
    // scanned library — so every track of an album shows its cover
    // regardless of which one happens to be that representative; a track
    // whose album has no cover anywhere in the library still renders
    // correctly, just without one. isActive is always false. The playlist's
    // own track order is preserved rather than alphabetically re-sorted.
    Q_INVOKABLE QVariantList buildStandaloneTrackCards(const QVariantList &tracks) const;

    // Substring search across album-artist / album title / track title.
    // mode is "all" | "artists" | "albums" | "tracks" ("all" or any
    // unrecognized value searches all three fields). considerGenre=false
    // ignores activeGenres entirely; considerGenre=true with an empty
    // activeGenres returns no results (mirrors filteredAlbums()). Empty
    // (or whitespace-only) query returns no results.
    // Same QVariantList shape as filteredAlbums(), except "isActive" is
    // always false (no card is naturally "selected" in search results).
    // Single O(N_tracks) pass — see librarymodel.cpp for why no second
    // "pull in sibling tracks" pass is needed for artist/album matches.
    // matchWholeWord=true requires the matched substring to be bounded by
    // non-alphanumeric characters (or string start/end) on both sides —
    // e.g. "Love" then matches "Love" but not "Lovely"/"Loveless".
    Q_INVOKABLE QVariantList searchLibrary(const QString &query,
                                            const QString &mode,
                                            const QStringList &activeGenres,
                                            bool considerGenre,
                                            bool matchWholeWord) const;

    // Single-pass tree builder for LibraryData._rebuildTree().
    // Returns QVariantList matching the shape:
    //   [ { genre, artists: [ { name, albums: [ { title } ] } ] } ]
    // for exactly the supplied activeGenres list.
    // One O(N_tracks) scan replaces N_genres + N_artists separate scans.
    Q_INVOKABLE QVariantList buildLibraryTree(const QStringList &activeGenres) const;

    // AUTO PLAY candidate pool: tracks passing the genre+rating filters, each
    // returned as a QVariantMap with (at least) filePath, title, artist,
    // albumArtist, album, genre, durationMs, rating. Genre matching is
    // case-insensitive/trimmed (same convention as filteredAlbums()/
    // buildLibraryTree()). considerGenre=false skips genre filtering entirely;
    // considerRating=false skips rating filtering (unrated tracks, rating==0,
    // are naturally excluded whenever considerRating is true and minimumRating
    // is clamped to [1,10] — no special-casing needed).
    Q_INVOKABLE QVariantList autoPlayCandidatePool(const QStringList &activeGenres,
                                                    bool considerGenre,
                                                    bool considerRating,
                                                    int  minimumRating) const;

    // How many tracks autoPlayCandidatePool() would return for the same
    // arguments (same shared filter), without building the per-track maps.
    // Gates the AUTO PLAY button -- see AutoPlayController::
    // ratingRequirementMet(). Ignores the repeat-mode cap, which is
    // per-session state, not a property of the library.
    int autoPlayCandidateCount(const QStringList &activeGenres,
                               bool considerGenre,
                               bool considerRating,
                               int  minimumRating) const;

    // Applies a rating that was just stored at runtime (a star click or a
    // rating deletion in NowPlaying) to the library's own tracks, so
    // ratingCount and the AUTO PLAY candidate pool see it immediately instead
    // of only after the next scan (ratings reach m_tracks otherwise only via
    // scan-time enrichment, see UC-14). ratingId is a QUuid string (with or
    // without braces); rating 0 means "rating removed". Every track sharing
    // that ratingId is updated (duplicate pressings share one rating). Does
    // not touch Topaz.library.json -- Topaz.rating.json stays authoritative
    // and a scan re-applies it, exactly as before.
    Q_INVOKABLE void applyRating(const QString &ratingId, int rating);

    // ── MISC tab: Remove Abandoned Ratings (see UC-24) ────────────────────
    // Removes every Topaz.rating.json entry whose ratingId matches no track
    // currently in the library (existence alone decides removal -- no
    // genre-enabled dependency, since the scanner already indexes every
    // configured genre's tracks regardless of GenreBar enabled state).
    // Entries that DO still match a track have their stored genre corrected
    // in place if it no longer matches the track's current genre tag
    // (ratingId doesn't encode genre, so a re-tagged track would otherwise
    // leave a stale genre in the ratings file). Runs synchronously (ratings
    // files are small -- RatingCache reads/writes already happen
    // synchronously on every track change/star click) but reports chunked
    // progress via abandonedRatingsProgress so the MISC tab's progress bar
    // has something real to show. No-op if already running.
    Q_INVOKABLE void removeAbandonedRatings();

signals:
    void appConfigChanged();
    void scanningChanged();
    void scanProgressChanged();
    void currentScanFolderChanged();
    void finalizingScanChanged();
    void trackCountChanged();
    void albumCountChanged();
    void ratingCountChanged();
    // Emitted by applyRating() whenever a track's rating actually changed in
    // the library -- the trigger for anything derived from the rating
    // distribution (AutoPlayController::ratingRequirementMet), which
    // ratingCountChanged alone doesn't cover (a rating edit that keeps the
    // count the same can still change which tracks pass a minimum rating).
    void ratingsChanged();
    void ratingsReadyChanged();
    void removingAbandonedRatingsChanged();
    void abandonedRatingsProgressChanged();
    // Emitted once removeAbandonedRatings() finishes. genreCorrectedCount
    // counts entries that survived (a matching track exists) but had a
    // stale genre field corrected -- see removeAbandonedRatings()' doc
    // comment above. remainingCount is the total number of ratings left
    // in Topaz.rating.json after the removal (all of which now match a
    // track in the library).
    void abandonedRatingsRemovalFinished(int removedCount, int genreCorrectedCount,
                                          int remainingCount);

    // Emitted after the model is populated (cache load or scan complete).
    // LibraryData.qml connects to this to rebuild its tree.
    void libraryRefreshed();

    // Internal – queued signals to the worker thread.
    void _requestFullScan(QStringList  genres,
                          QVariantList folders,
                          QList<TrackInfo> cache);
    void _requestStatCheck(QStringList  genres,
                           QVariantList folders,
                           QList<TrackInfo> cache);
    void _requestFolderScan(QStringList  genres,
                            QVariantList folders,
                            QList<TrackInfo> cache,
                            QString      scanOnlyFolderPath);

private slots:
    // The only scanning=true source for a scan LibraryModel didn't
    // itself request -- see the class comment's lifecycle note and
    // LibraryScanner::scanStarted()'s own doc comment.
    void onScanStarted();
    void onScanProgress(int done, int total);
    void onScanCompleted(QList<TrackInfo> tracks);
    // Visual Folder Scanning (Setup > MISC) -- see LibraryScanner's matching
    // signals' doc comments.
    void onScanningFolder(const QString &path);
    void onScanFinalizing();

private:
    void applyTracks(QList<TrackInfo> &&tracks);
    // Recounts tracks with rating > 0 into m_ratingCount, emitting
    // ratingCountChanged() only if it changed. Shared by applyTracks() and
    // applyRating().
    void updateRatingCount();
    void startWorkerThread();
    // m_appConfig->folders() filtered down to entries whose "active" key
    // (default true, see AppConfig::load()) is truthy -- used instead of
    // folders() when dispatching a scan, so an inactive folder is excluded
    // from discovery entirely. See UC-04/UC-05.
    QVariantList activeFolders() const;
    // Reflects AppConfig::albumBrowserSortOrder -- true unless the user
    // picked "artistAlbum" (Artist asc -> Album asc only, no year
    // tiebreak). Passed into serializeAlbumAccum() by both
    // filteredAlbums() and searchLibrary().
    bool albumBrowserSortByYear() const;

    AppConfig        *m_appConfig    = nullptr;
    QList<TrackInfo>  m_tracks;
    int               m_albumCount   = 0;
    int               m_ratingCount  = 0;
    LibraryScanner   *m_scanWorker   = nullptr;
    QThread          *m_scanThread   = nullptr;
    bool              m_scanning     = false;
    int               m_scanProgress = 0;
    QString           m_currentScanFolder;
    bool              m_finalizingScan = false;
    bool              m_ratingsReady = false;
    bool              m_removingAbandonedRatings = false;
    int               m_abandonedRatingsProgress = 0;
};
