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
//   2. Gear icon → SetupDialog → user clicks SCAN DIRECTORIES
//      → startFullScan()  (or BottomBar "SCAN DIRECTORIES" button)
class LibraryModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(AppConfig* appConfig  READ appConfig  WRITE setAppConfig  NOTIFY appConfigChanged)
    Q_PROPERTY(bool        scanning   READ scanning   NOTIFY scanningChanged)
    Q_PROPERTY(int         scanProgress READ scanProgress NOTIFY scanProgressChanged)
    Q_PROPERTY(int         trackCount READ trackCount  NOTIFY trackCountChanged)
    Q_PROPERTY(int         albumCount READ albumCount  NOTIFY albumCountChanged)
    Q_PROPERTY(bool        ratingsReady READ ratingsReady NOTIFY ratingsReadyChanged)

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
    int        trackCount()   const { return m_tracks.size(); }
    int        albumCount()   const { return m_albumCount; }
    // True once a scan (full or stat-check) has completed at least once in this
    // session with rating enrichment applied — gates the AUTO PLAY button.
    bool       ratingsReady() const { return m_ratingsReady; }
    void       setAppConfig(AppConfig *cfg);

    // ── Invokable actions ─────────────────────────────────────────────────
    // Load cache from disk, emit libraryRefreshed(), then start a background
    // stat-check.  Call this from Main.qml Component.onCompleted.
    Q_INVOKABLE void loadCacheAndStartStatCheck();

    // Trigger a full re-scan of all configured folders in background.
    Q_INVOKABLE void startFullScan();

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

signals:
    void appConfigChanged();
    void scanningChanged();
    void scanProgressChanged();
    void trackCountChanged();
    void albumCountChanged();
    void ratingsReadyChanged();

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

private slots:
    void onScanProgress(int done, int total);
    void onScanCompleted(QList<TrackInfo> tracks);

private:
    void applyTracks(QList<TrackInfo> &&tracks);
    void startWorkerThread();

    AppConfig        *m_appConfig    = nullptr;
    QList<TrackInfo>  m_tracks;
    int               m_albumCount   = 0;
    LibraryScanner   *m_scanWorker   = nullptr;
    QThread          *m_scanThread   = nullptr;
    bool              m_scanning     = false;
    int               m_scanProgress = 0;
    bool              m_ratingsReady = false;
};
