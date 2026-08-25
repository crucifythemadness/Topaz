#include "librarymodel.h"
#include "librarycache.h"
#include "libraryscanner.h"

#include <QThread>
#include <algorithm>
#include <numeric>

namespace {

QString formatDuration(qint64 ms)
{
    const int totalSecs = static_cast<int>(ms / 1000);
    return QString("%1:%2")
        .arg(totalSecs / 60)
        .arg(totalSecs % 60, 2, 10, QChar('0'));
}

// Whole-word substring match for searchLibrary()'s "Match whole word"
// option: needle must occur bounded by non-alphanumeric characters (or
// haystack start/end) on both sides, e.g. "Love" matches "Love" but not
// "Lovely"/"Loveless". Plain QString scanning rather than
// QRegularExpression, to match this file's existing style.
bool matchesWholeWord(const QString &haystack, const QString &needle)
{
    if (needle.isEmpty()) return false;
    int from = 0;
    while (true) {
        const int idx = haystack.indexOf(needle, from, Qt::CaseInsensitive);
        if (idx < 0) return false;
        const bool leftOk  = (idx == 0) || !haystack.at(idx - 1).isLetterOrNumber();
        const int afterIdx = idx + needle.length();
        const bool rightOk = (afterIdx >= haystack.length()) || !haystack.at(afterIdx).isLetterOrNumber();
        if (leftOk && rightOk) return true;
        from = idx + 1; // keep looking -- an earlier occurrence might not be word-bounded
    }
}

// Shared accumulator for grouping tracks into album cards, keyed by
// (genre|albumArtist|album). Used by both filteredAlbums() and
// searchLibrary() so the two stay in lockstep on shape/behavior.
struct AlbumAccum {
    QString              genre;
    QString              albumArtist;
    QString              album;
    QString              coverThumb;
    int                  year = 0;
    QList<const TrackInfo *> tracks;
};

// Sorts (albumArtist asc, year desc, albumTitle asc, case-insensitive),
// sorts each album's tracks by track number, and serializes into the
// QVariantList shape AlbumCard/AlbumBrowser expect. markFirstActive mirrors
// filteredAlbums()'s "highlight the first card" behavior for genre/artist
// drill-down; searchLibrary() passes false since no search result card is
// naturally "selected." preserveOrder=true (buildStandaloneTrackCards(),
// for playlists) skips both sorts instead, since a playlist's own
// listening order matters more than alphabetical browsing order — cards
// then emit in the order their tracks appear in the playlist.
QVariantList serializeAlbumAccum(QList<AlbumAccum> &albumAccum, bool markFirstActive = true,
                                  bool preserveOrder = false)
{
    if (albumAccum.isEmpty()) return {};

    QList<int> sortedIdx(albumAccum.size());
    std::iota(sortedIdx.begin(), sortedIdx.end(), 0);
    if (!preserveOrder) {
        std::sort(sortedIdx.begin(), sortedIdx.end(),
                  [&albumAccum](int a, int b) {
                      const AlbumAccum &aa = albumAccum[a];
                      const AlbumAccum &bb = albumAccum[b];
                      int c = aa.albumArtist.compare(bb.albumArtist, Qt::CaseInsensitive);
                      if (c != 0) return c < 0;
                      if (aa.year != bb.year) return aa.year > bb.year;
                      return aa.album.compare(bb.album, Qt::CaseInsensitive) < 0;
                  });
    }

    QVariantList result;
    result.reserve(albumAccum.size());

    for (int si = 0; si < sortedIdx.size(); ++si) {
        AlbumAccum &aa = albumAccum[sortedIdx[si]];

        if (!preserveOrder) {
            std::sort(aa.tracks.begin(), aa.tracks.end(),
                      [](const TrackInfo *a, const TrackInfo *b) {
                          return a->track < b->track;
                      });
        }

        const QString coverSrc = aa.coverThumb.isEmpty()
            ? QString()
            : QStringLiteral("data:image/jpeg;base64,") + aa.coverThumb;

        QVariantList trackList;
        trackList.reserve(aa.tracks.size());
        for (const TrackInfo *t : std::as_const(aa.tracks)) {
            QVariantMap tm;
            tm[QStringLiteral("number")]      = t->track > 0
                                                ? QString::number(t->track).rightJustified(2, '0')
                                                : QStringLiteral("—");
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
        album[QStringLiteral("genre")]       = aa.genre;
        album[QStringLiteral("isActive")]    = markFirstActive && (si == 0);
        album[QStringLiteral("coverSource")] = coverSrc;
        album[QStringLiteral("year")]        = aa.year;
        album[QStringLiteral("tracks")]      = trackList;
        result.append(album);
    }

    return result;
}

} // namespace

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

    // Single O(N_tracks) pass to count distinct albums, same
    // trimmed+lowercased canonicalization buildLibraryTree() uses.
    QSet<QString> uniqueAlbums;
    uniqueAlbums.reserve(m_tracks.size());
    for (const TrackInfo &t : std::as_const(m_tracks)) {
        if (t.album.isEmpty()) continue;
        uniqueAlbums.insert(t.albumArtist.trimmed().toLower()
                             + QLatin1Char('\x1f')
                             + t.album.trimmed().toLower());
    }
    if (uniqueAlbums.size() != m_albumCount) {
        m_albumCount = uniqueAlbums.size();
        emit albumCountChanged();
    }

    emit libraryRefreshed();
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
            albumAccum.append({ t.genre, t.albumArtist, t.album,
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

    return serializeAlbumAccum(albumAccum);
}

QVariantList LibraryModel::searchLibrary(const QString &query,
                                          const QString &mode,
                                          const QStringList &activeGenres,
                                          bool considerGenre,
                                          bool matchWholeWord) const
{
    const QString q = query.trimmed();
    if (q.isEmpty()) return {};
    if (considerGenre && activeGenres.isEmpty()) return {};

    QSet<QString> activeGenresLower;
    if (considerGenre) {
        activeGenresLower.reserve(activeGenres.size());
        for (const QString &g : activeGenres)
            activeGenresLower.insert(g.trimmed().toLower());
    }

    // "all" (or any unrecognized mode) searches all three fields.
    const bool wantArtists = (mode == QLatin1String("artists") || mode == QLatin1String("all"));
    const bool wantAlbums  = (mode == QLatin1String("albums")  || mode == QLatin1String("all"));
    const bool wantTracks  = (mode == QLatin1String("tracks")  || mode == QLatin1String("all"));
    const bool anyMode     = wantArtists || wantAlbums || wantTracks;

    auto fieldMatches = [&](const QString &field) {
        return matchWholeWord ? matchesWholeWord(field, q)
                               : field.contains(q, Qt::CaseInsensitive);
    };

    // ── Single O(N_tracks) pass ──────────────────────────────────────────
    // albumArtist/album are constant across every track in their group (the
    // same invariant filteredAlbums()'s grouping key relies on), so a match
    // on either field for one track is guaranteed to also match every
    // sibling track in that album — the "pull in the whole album" behavior
    // for artist/album matches falls out of per-track evaluation for free,
    // with no second "find matches, then rescan for siblings" pass needed.
    // A title-only match is inherently per-track already, which is exactly
    // the "just this track" behavior track-mode search needs.
    QHash<QString, int> keyToIndex;
    QList<AlbumAccum>   albumAccum;

    for (const TrackInfo &t : std::as_const(m_tracks)) {
        if (considerGenre && !activeGenresLower.contains(t.genre.trimmed().toLower()))
            continue;

        const bool matched = anyMode
            && ((wantArtists && fieldMatches(t.albumArtist))
             || (wantAlbums  && fieldMatches(t.album))
             || (wantTracks  && fieldMatches(t.title)));
        if (!matched) continue;

        const QString key = t.genre.trimmed().toLower() + QChar('|')
                           + t.albumArtist.toLower() + QChar('|') + t.album.toLower();
        auto it = keyToIndex.find(key);
        if (it == keyToIndex.end()) {
            keyToIndex.insert(key, albumAccum.size());
            albumAccum.append({ t.genre, t.albumArtist, t.album, t.coverThumb, t.year, { &t } });
        } else {
            AlbumAccum &aa = albumAccum[it.value()];
            if (aa.coverThumb.isEmpty() && !t.coverThumb.isEmpty())
                aa.coverThumb = t.coverThumb;
            if (aa.year == 0 && t.year != 0)
                aa.year = t.year;
            aa.tracks.append(&t);
        }
    }

    // ── Cover fix-up (search-only convenience) ───────────────────────────
    // TRACKS-mode (and ALL-mode title-only) matches deliberately include
    // only the matching track(s), not the rest of the album — so if that
    // one track's own tag has no embedded cover (common when only track 1
    // of a rip carries it), the card would show no cover even though a
    // sibling track (correctly excluded above) has one.
    // filteredAlbums()/buildLibraryTree() never need this since they always
    // include an album's full track list already. Skips entirely (the
    // common case) if every matched album already has a cover.
    QHash<QString, int> missingCoverKeys; // same keys as keyToIndex above
    for (auto it = keyToIndex.constBegin(); it != keyToIndex.constEnd(); ++it) {
        if (albumAccum[it.value()].coverThumb.isEmpty())
            missingCoverKeys.insert(it.key(), it.value());
    }
    if (!missingCoverKeys.isEmpty()) {
        for (const TrackInfo &t : std::as_const(m_tracks)) {
            if (missingCoverKeys.isEmpty()) break;
            if (t.coverThumb.isEmpty()) continue;
            const QString key = t.genre.trimmed().toLower() + QChar('|')
                               + t.albumArtist.toLower() + QChar('|') + t.album.toLower();
            auto found = missingCoverKeys.constFind(key);
            if (found != missingCoverKeys.constEnd()) {
                albumAccum[found.value()].coverThumb = t.coverThumb;
                missingCoverKeys.erase(found);
            }
        }
    }

    return serializeAlbumAccum(albumAccum, /*markFirstActive=*/false);
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

// ── buildStandaloneTrackCards ─────────────────────────────────────────────
// Converts an arbitrary track list (e.g. PlaylistManager::loadPlaylist()'s
// output) into one standalone AlbumCard-shaped entry per track -- no
// grouping by album, so PlaylistViewer shows exactly how the playlist is
// composed track by track. See UC-22.
QVariantList LibraryModel::buildStandaloneTrackCards(const QVariantList &tracks) const
{
    if (tracks.isEmpty()) return {};

    // filePath -> TrackInfo* for tracks already in the scanned library, so
    // playlist tracks reuse their own tag data (and, via coverThumbForAlbum()
    // below, their album's cover) instead of re-decoding JPEGs from disk.
    QHash<QString, const TrackInfo *> byPath;
    byPath.reserve(m_tracks.size());
    for (const TrackInfo &t : std::as_const(m_tracks))
        byPath.insert(t.filePath, &t);

    // Owns TrackInfo instances synthesized for tracks not found in byPath.
    // Reserved up front so AlbumAccum's raw pointers into it stay valid.
    QList<TrackInfo> fallback;
    fallback.reserve(tracks.size());

    QList<AlbumAccum> albumAccum;
    albumAccum.reserve(tracks.size());

    for (const QVariant &v : tracks) {
        const QVariantMap m = v.toMap();
        const QString filePath = m.value(QStringLiteral("filePath")).toString();

        const TrackInfo *t = byPath.value(filePath, nullptr);
        if (!t) {
            TrackInfo synth;
            synth.filePath    = filePath;
            synth.title       = m.value(QStringLiteral("title")).toString();
            synth.artist      = m.value(QStringLiteral("artist")).toString();
            synth.albumArtist = m.value(QStringLiteral("albumArtist")).toString();
            synth.album       = m.value(QStringLiteral("album")).toString();
            synth.genre       = m.value(QStringLiteral("genre")).toString();
            synth.year        = m.value(QStringLiteral("year")).toInt();
            synth.track       = m.value(QStringLiteral("trackNumber"),
                                         m.value(QStringLiteral("number"))).toInt();
            synth.duration    = m.value(QStringLiteral("durationMs")).toLongLong();
            synth.bitrate     = m.value(QStringLiteral("bitrate")).toInt();
            fallback.append(synth);
            t = &fallback.last();
        }

        // t->coverThumb is only non-empty for the one representative track
        // the scanner chose per (genre, albumArtist, album) -- see UC-05
        // step 4d -- so most tracks of an album have it empty even though
        // the album genuinely has a cover. Fall back to coverThumbForAlbum()
        // per track: an O(N_tracks) scan per call, which would be wasteful
        // across the whole library, but is negligible for a playlist
        // (capped in practice at a few hundred tracks).
        QString coverThumb = t->coverThumb;
        if (coverThumb.isEmpty())
            coverThumb = coverThumbForAlbum(t->album, t->albumArtist);

        // Each track becomes its own one-track "album" accumulator -- no
        // (genre|albumArtist|album) dedup, unlike filteredAlbums()/
        // searchLibrary(), so consecutive same-album tracks still render as
        // separate cards.
        albumAccum.append({ t->genre, t->albumArtist, t->album, coverThumb, t->year, { t } });
    }

    return serializeAlbumAccum(albumAccum, /*markFirstActive=*/false, /*preserveOrder=*/true);
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
