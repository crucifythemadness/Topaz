#include "librarymodel.h"
#include "librarycache.h"
#include "libraryscanner.h"

#include <QThread>
#include <algorithm>
#include <numeric>

// ─────────────────────────────────────────────────────────────────────────

LibraryModel::LibraryModel(QObject *parent)
    : QAbstractListModel(parent)
{
    // Register custom types for queued cross-thread signals
    static const bool once = []() {
        qRegisterMetaType<TrackInfo>();
        qRegisterMetaType<QList<TrackInfo>>();
        return true;
    }();
    Q_UNUSED(once)

    startWorkerThread();
}

LibraryModel::~LibraryModel()
{
    if (m_scanThread && m_scanThread->isRunning()) {
        if (m_scanWorker) m_scanWorker->cancelScan();
        m_scanThread->quit();
        if (!m_scanThread->wait(3000)) {
            // Scan didn't stop in time (e.g. unresponsive I/O). Detach instead of
            // letting ~QObject delete a still-running QThread, which Qt treats as
            // a fatal error — the OS reclaims the thread when the process exits.
            m_scanThread->setParent(nullptr);
        }
    }
}

// ── Worker thread ─────────────────────────────────────────────────────────

void LibraryModel::startWorkerThread()
{
    m_scanWorker = new LibraryScanner();
    m_scanThread = new QThread(this);
    m_scanWorker->moveToThread(m_scanThread);

    // Worker initialisation (creates watcher + timer on the worker thread)
    connect(m_scanThread, &QThread::started,
            m_scanWorker,  &LibraryScanner::onThreadStarted);
    connect(m_scanThread, &QThread::finished,
            m_scanWorker,  &QObject::deleteLater);

    // Scan results → main thread
    connect(m_scanWorker, &LibraryScanner::scanProgress,
            this, &LibraryModel::onScanProgress,
            Qt::QueuedConnection);
    connect(m_scanWorker, &LibraryScanner::scanCompleted,
            this, &LibraryModel::onScanCompleted,
            Qt::QueuedConnection);

    // Commands → worker thread (queued so they execute on the worker's event loop)
    connect(this, &LibraryModel::_requestFullScan,
            m_scanWorker, &LibraryScanner::fullScan,
            Qt::QueuedConnection);
    connect(this, &LibraryModel::_requestStatCheck,
            m_scanWorker, &LibraryScanner::statCheck,
            Qt::QueuedConnection);

    m_scanThread->start();
}

// ── AppConfig property ────────────────────────────────────────────────────

void LibraryModel::setAppConfig(AppConfig *cfg)
{
    if (m_appConfig == cfg) return;
    m_appConfig = cfg;
    emit appConfigChanged();
}

// ── QAbstractListModel implementation ────────────────────────────────────

int LibraryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_tracks.size();
}

QVariant LibraryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_tracks.size())
        return {};

    const TrackInfo &t = m_tracks.at(index.row());
    switch (role) {
    case TrackIdRole:       return t.id.toString(QUuid::WithoutBraces);
    case FilePathRole:      return t.filePath;
    case FileNameRole:      return t.fileName;
    case TitleRole:         return t.title;
    case ArtistRole:        return t.artist;
    case AlbumArtistRole:   return t.albumArtist;
    case AlbumRole:         return t.album;
    case GenreRole:         return t.genre;
    case TrackNumberRole:   return t.track;
    case YearRole:          return t.year;
    case DurationRole:      return static_cast<int>(t.duration);
    case DurationStringRole:return formatDuration(t.duration);
    case BitrateRole:       return t.bitrate;
    case FileSizeRole:      return static_cast<qlonglong>(t.fileSize);
    case CoverThumbRole:    return t.coverThumb;
    default:                return {};
    }
}

QHash<int, QByteArray> LibraryModel::roleNames() const
{
    return {
        { TrackIdRole,        "trackId"       },
        { FilePathRole,       "filePath"      },
        { FileNameRole,       "fileName"      },
        { TitleRole,          "title"         },
        { ArtistRole,         "artist"        },
        { AlbumArtistRole,    "albumArtist"   },
        { AlbumRole,          "album"         },
        { GenreRole,          "genre"         },
        { TrackNumberRole,    "trackNumber"   },
        { YearRole,           "year"          },
        { DurationRole,       "duration"      },
        { DurationStringRole, "durationString"},
        { BitrateRole,        "bitrate"       },
        { FileSizeRole,       "fileSize"      },
        { CoverThumbRole,     "coverThumb"    }
    };
}

// ── Public actions ────────────────────────────────────────────────────────

void LibraryModel::loadCacheAndStartStatCheck()
{
    // 1. Load cache synchronously → instant display
    QList<TrackInfo> cached = LibraryCache::load();
    applyTracks(std::move(cached));

    // 2. If no AppConfig yet, nothing to scan
    if (!m_appConfig) return;

    // 3. Dispatch stat-check on the worker thread
    m_scanning     = true;
    m_scanProgress = 0;
    emit scanningChanged();
    emit scanProgressChanged();

    emit _requestStatCheck(m_appConfig->genres(),
                           m_appConfig->folders(),
                           m_tracks);
}

void LibraryModel::startFullScan()
{
    if (!m_appConfig) return;
    if (m_scanning) return; // don't stack scans

    m_scanning     = true;
    m_scanProgress = 0;
    emit scanningChanged();
    emit scanProgressChanged();

    emit _requestFullScan(m_appConfig->genres(),
                          m_appConfig->folders(),
                          m_tracks);
}

// ── Scan result slots ─────────────────────────────────────────────────────

void LibraryModel::onScanProgress(int done, int total)
{
    m_scanProgress = (total > 0) ? (done * 100 / total) : 0;
    emit scanProgressChanged();
}

void LibraryModel::onScanCompleted(QList<TrackInfo> tracks)
{
    m_scanning     = false;
    m_scanProgress = 100;
    emit scanningChanged();
    emit scanProgressChanged();
    applyTracks(std::move(tracks));

    // Every completed scan now applies rating enrichment (see LibraryScanner),
    // so the first one to arrive in this session is when ratings become trustworthy.
    if (!m_ratingsReady) {
        m_ratingsReady = true;
        emit ratingsReadyChanged();
    }
}

void LibraryModel::applyTracks(QList<TrackInfo> &&tracks)
{
    const int oldCount = m_tracks.size();
    beginResetModel();
    m_tracks = std::move(tracks);
    endResetModel();

    if (m_tracks.size() != oldCount)
        emit trackCountChanged();

    emit libraryRefreshed();
}

// ── Query helpers ─────────────────────────────────────────────────────────

QString LibraryModel::formatDuration(qint64 ms)
{
    const int totalSecs = static_cast<int>(ms / 1000);
    return QString("%1:%2")
        .arg(totalSecs / 60)
        .arg(totalSecs % 60, 2, 10, QChar('0'));
}

QStringList LibraryModel::genres() const
{
    QSet<QString> seen;
    for (const TrackInfo &t : std::as_const(m_tracks))
        if (!t.genre.isEmpty()) seen.insert(t.genre);
    QStringList list(seen.cbegin(), seen.cend());
    std::sort(list.begin(), list.end());
    return list;
}

QStringList LibraryModel::artistsForGenre(const QString &genre) const
{
    const QString genreLower = genre.trimmed().toLower();
    QSet<QString> seen;
    for (const TrackInfo &t : std::as_const(m_tracks)) {
        if (t.genre.trimmed().toLower() == genreLower && !t.albumArtist.isEmpty())
            seen.insert(t.albumArtist);
    }
    QStringList list(seen.cbegin(), seen.cend());
    std::sort(list.begin(), list.end(), [](const QString &a, const QString &b) {
        return a.compare(b, Qt::CaseInsensitive) < 0;
    });
    return list;
}

QStringList LibraryModel::albumsForArtist(const QString &artist,
                                           const QString &genre) const
{
    const QString artistLower = artist.trimmed().toLower();
    const QString genreLower  = genre.trimmed().toLower();
    QSet<QString> seen;
    for (const TrackInfo &t : std::as_const(m_tracks)) {
        if (t.albumArtist.trimmed().toLower() != artistLower) continue;
        if (!genreLower.isEmpty() &&
            t.genre.trimmed().toLower() != genreLower) continue;
        if (!t.album.isEmpty()) seen.insert(t.album);
    }
    QStringList list(seen.cbegin(), seen.cend());
    std::sort(list.begin(), list.end(), [](const QString &a, const QString &b) {
        return a.compare(b, Qt::CaseInsensitive) < 0;
    });
    return list;
}

QVariantList LibraryModel::filteredAlbums(const QStringList &activeGenres,
                                           const QString     &selectedArtist,
                                           const QString     &selectedAlbum) const
{
    if (activeGenres.isEmpty()) return {};

    // ── Normalise filter strings once ─────────────────────────────────────
    QSet<QString> activeGenresLower;
    activeGenresLower.reserve(activeGenres.size());
    for (const QString &g : activeGenres)
        activeGenresLower.insert(g.trimmed().toLower());

    const bool    filterArtist        = !selectedArtist.isEmpty();
    const bool    filterAlbum         = !selectedAlbum.isEmpty();
    const QString selectedArtistLower = filterArtist
                                        ? selectedArtist.trimmed().toLower() : QString();
    const QString selectedAlbumLower  = filterAlbum
                                        ? selectedAlbum.trimmed().toLower()  : QString();

    // ── Single O(N_tracks) pass: group tracks by (albumArtist, album) ─────
    // Replaces the former three-pass O(N_tracks × N_albums) loop:
    //   pass 1 – collect unique album keys
    //   pass 2 – per-album full rescan for tracks (N_albums × N_tracks)
    //   pass 3 – coverThumbForAlbum() per album (N_albums × N_tracks)
    struct AlbumAccum {
        QString              albumArtist;
        QString              album;
        QString              coverThumb;
        int                  year = 0;
        QList<const TrackInfo *> tracks;
    };

    QHash<QString, int> keyToIndex; // lowercased key → index in albumAccum
    QList<AlbumAccum>   albumAccum;

    for (const TrackInfo &t : std::as_const(m_tracks)) {
        if (!activeGenresLower.contains(t.genre.trimmed().toLower())) continue;
        if (filterArtist && t.albumArtist.trimmed().toLower() != selectedArtistLower) continue;
        if (filterAlbum  && t.album.trimmed().toLower()       != selectedAlbumLower)  continue;

        // Genre is part of the key so that two same-named albums filed under
        // different genres (e.g. a duplicate rip classified both "Alt. Rock"
        // and "Punk Rock") show as separate cards instead of colliding into
        // one — matches buildLibraryTree()'s genre → artist → album scoping.
        const QString key = t.genre.trimmed().toLower() + QChar('|')
                           + t.albumArtist.toLower() + QChar('|') + t.album.toLower();
        auto it = keyToIndex.find(key);
        if (it == keyToIndex.end()) {
            keyToIndex.insert(key, albumAccum.size());
            albumAccum.append({ t.albumArtist, t.album,
                                t.coverThumb,            // grab first cover seen
                                t.year,                  // grab first non-zero year seen
                                { &t } });
        } else {
            AlbumAccum &aa = albumAccum[it.value()];
            if (aa.coverThumb.isEmpty() && !t.coverThumb.isEmpty())
                aa.coverThumb = t.coverThumb;
            if (aa.year == 0 && t.year != 0)
                aa.year = t.year;
            aa.tracks.append(&t);
        }
    }

    if (albumAccum.isEmpty()) return {};

    // ── Sort albums: albumArtist asc, then year desc, then album title asc
    // (case-insensitive) ────────────────────────────────────────────────────
    // Albums with no year tag (year == 0) naturally sort last within their
    // artist group — no special-casing needed.
    QList<int> sortedIdx(albumAccum.size());
    std::iota(sortedIdx.begin(), sortedIdx.end(), 0);
    std::sort(sortedIdx.begin(), sortedIdx.end(),
              [&albumAccum](int a, int b) {
                  const AlbumAccum &aa = albumAccum[a];
                  const AlbumAccum &bb = albumAccum[b];
                  int c = aa.albumArtist.compare(bb.albumArtist, Qt::CaseInsensitive);
                  if (c != 0) return c < 0;
                  if (aa.year != bb.year) return aa.year > bb.year;
                  return aa.album.compare(bb.album, Qt::CaseInsensitive) < 0;
              });

    // ── Build result ──────────────────────────────────────────────────────
    QVariantList result;
    result.reserve(albumAccum.size());

    for (int si = 0; si < sortedIdx.size(); ++si) {
        AlbumAccum &aa = albumAccum[sortedIdx[si]];

        // Sort tracks within album by track number
        std::sort(aa.tracks.begin(), aa.tracks.end(),
                  [](const TrackInfo *a, const TrackInfo *b) {
                      return a->track < b->track;
                  });

        const QString coverSrc = aa.coverThumb.isEmpty()
            ? QString()
            : QStringLiteral("data:image/jpeg;base64,") + aa.coverThumb;

        QVariantList trackList;
        trackList.reserve(aa.tracks.size());
        for (const TrackInfo *t : std::as_const(aa.tracks)) {
            QVariantMap tm;
            tm[QStringLiteral("number")]      = t->track > 0
                                                ? QString::number(t->track).rightJustified(2, '0')
                                                : QStringLiteral("\u2014");
            tm[QStringLiteral("title")]       = t->title;
            tm[QStringLiteral("duration")]    = formatDuration(t->duration);
            tm[QStringLiteral("durationMs")]  = static_cast<qlonglong>(t->duration);
            tm[QStringLiteral("bitrate")]     = t->bitrate;
            tm[QStringLiteral("filePath")]    = t->filePath;
            tm[QStringLiteral("artist")]      = t->artist;
            tm[QStringLiteral("albumArtist")] = t->albumArtist;
            tm[QStringLiteral("album")]       = t->album;
            tm[QStringLiteral("genre")]       = t->genre;
            tm[QStringLiteral("year")]        = t->year;
            tm[QStringLiteral("coverSource")] = coverSrc; // set directly – no post-loop needed
            trackList.append(tm);
        }

        QVariantMap album;
        album[QStringLiteral("albumTitle")]  = aa.album;
        album[QStringLiteral("albumArtist")] = aa.albumArtist;
        album[QStringLiteral("artistLabel")] = aa.albumArtist;
        album[QStringLiteral("isActive")]    = (si == 0);
        album[QStringLiteral("coverSource")] = coverSrc;
        album[QStringLiteral("year")]        = aa.year;
        album[QStringLiteral("tracks")]      = trackList;
        result.append(album);
    }

    return result;
}

QVariantList LibraryModel::autoPlayCandidatePool(const QStringList &activeGenres,
                                                  bool considerGenre,
                                                  bool considerRating,
                                                  int  minimumRating) const
{
    QSet<QString> activeGenresLower;
    if (considerGenre) {
        activeGenresLower.reserve(activeGenres.size());
        for (const QString &g : activeGenres)
            activeGenresLower.insert(g.trimmed().toLower());
    }

    // Cover thumbnails are only stored on one representative track per album
    // (see TrackInfo comment) — build the per-album lookup once, same
    // convention as filteredAlbums(), to avoid an O(N_tracks) rescan per
    // candidate below.
    QHash<QString, QString> albumCoverThumb;
    for (const TrackInfo &t : std::as_const(m_tracks)) {
        if (t.coverThumb.isEmpty()) continue;
        // Genre included in the key — see filteredAlbums() for why.
        const QString key = t.genre.trimmed().toLower() + QChar('|')
                           + t.albumArtist.toLower() + QChar('|') + t.album.toLower();
        if (!albumCoverThumb.contains(key))
            albumCoverThumb.insert(key, t.coverThumb);
    }

    QVariantList result;
    for (const TrackInfo &t : std::as_const(m_tracks)) {
        if (considerGenre && !activeGenresLower.contains(t.genre.trimmed().toLower()))
            continue;
        if (considerRating && t.rating < minimumRating)
            continue;

        const QString key = t.genre.trimmed().toLower() + QChar('|')
                           + t.albumArtist.toLower() + QChar('|') + t.album.toLower();
        const QString cover = albumCoverThumb.value(key);

        QVariantMap tm;
        tm[QStringLiteral("filePath")]    = t.filePath;
        tm[QStringLiteral("title")]       = t.title;
        tm[QStringLiteral("artist")]      = t.artist;
        tm[QStringLiteral("albumArtist")] = t.albumArtist;
        tm[QStringLiteral("album")]       = t.album;
        tm[QStringLiteral("genre")]       = t.genre;
        tm[QStringLiteral("year")]        = t.year;
        tm[QStringLiteral("durationMs")]  = static_cast<qlonglong>(t.duration);
        tm[QStringLiteral("bitrate")]     = t.bitrate;
        tm[QStringLiteral("rating")]      = t.rating;
        tm[QStringLiteral("coverSource")] = cover.isEmpty()
            ? QString()
            : QStringLiteral("data:image/jpeg;base64,") + cover;
        result.append(tm);
    }
    return result;
}

QString LibraryModel::coverThumbForAlbum(const QString &album,
                                          const QString &albumArtist) const
{
    for (const TrackInfo &t : std::as_const(m_tracks)) {
        if (t.album.compare(album, Qt::CaseInsensitive) == 0 &&
            t.albumArtist.compare(albumArtist, Qt::CaseInsensitive) == 0 &&
            !t.coverThumb.isEmpty())
            return t.coverThumb;
    }
    return {};
}

// ── buildLibraryTree ──────────────────────────────────────────────────────
// Single O(N_tracks) pass → builds the full Genre→Artist→Album tree for QML.
// Replaces N_genres + N_artists separate invokable calls each re-scanning the
// full track list, reducing latency from O(N_tracks × (N_genres + N_artists))
// to O(N_tracks).
QVariantList LibraryModel::buildLibraryTree(const QStringList &activeGenres) const
{
    if (activeGenres.isEmpty()) return {};

    // Normalise active genre names for fast lookup
    QSet<QString> activeGenresLower;
    activeGenresLower.reserve(activeGenres.size());
    for (const QString &g : activeGenres)
        activeGenresLower.insert(g.trimmed().toLower());

    // genre_lower → artist_lower → set<album>
    // Using QMap so the outer iteration order is deterministic
    struct AlbumSet {
        QSet<QString> albums; // canonical casing of album titles seen
    };
    struct ArtistMap {
        QMap<QString /*artistLower*/, QString /*artistCanonical*/> canonicalArtist;
        QMap<QString /*artistLower*/, AlbumSet> albums;
    };
    QMap<QString /*genreLower*/, ArtistMap> tree;

    // One pass through all tracks
    for (const TrackInfo &t : std::as_const(m_tracks)) {
        const QString gl = t.genre.trimmed().toLower();
        if (!activeGenresLower.contains(gl)) continue;
        if (t.albumArtist.isEmpty()) continue;

        const QString al = t.albumArtist.trimmed().toLower();

        ArtistMap &am = tree[gl];
        if (!am.canonicalArtist.contains(al))
            am.canonicalArtist.insert(al, t.albumArtist);

        if (!t.album.isEmpty())
            am.albums[al].albums.insert(t.album);
    }

    // Build output in the order of activeGenres (preserve user-defined order)
    QVariantList result;
    result.reserve(activeGenres.size());

    for (const QString &g : activeGenres) {
        const QString gl = g.trimmed().toLower();
        const ArtistMap &am = tree.value(gl);

        // Sort artists case-insensitively
        QStringList artistsLower = am.canonicalArtist.keys();
        std::sort(artistsLower.begin(), artistsLower.end());

        QVariantList artistList;
        artistList.reserve(artistsLower.size());

        for (const QString &al : std::as_const(artistsLower)) {
            const QString &artistName = am.canonicalArtist.value(al);

            // Sort albums case-insensitively
            QStringList albums(am.albums.value(al).albums.cbegin(),
                               am.albums.value(al).albums.cend());
            std::sort(albums.begin(), albums.end(),
                      [](const QString &a, const QString &b) {
                          return a.compare(b, Qt::CaseInsensitive) < 0;
                      });

            QVariantList albumList;
            albumList.reserve(albums.size());
            for (const QString &title : std::as_const(albums)) {
                QVariantMap am2;
                am2[QStringLiteral("title")] = title;
                albumList.append(am2);
            }

            QVariantMap artistMap;
            artistMap[QStringLiteral("name")]   = artistName;
            artistMap[QStringLiteral("albums")] = albumList;
            artistList.append(artistMap);
        }

        QVariantMap genreMap;
        genreMap[QStringLiteral("genre")]   = g;
        genreMap[QStringLiteral("artists")] = artistList;
        result.append(genreMap);
    }

    return result;
}
