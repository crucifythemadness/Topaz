#include "libraryscanner.h"
#include "librarycache.h"
#include "ratingcache.h"
#include "tagreader.h"

#include <QDir>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QThread>
#include <QThreadPool>
#include <QTimer>
#include <QtConcurrent>

// ─────────────────────────────────────────────────────────────────────────

LibraryScanner::LibraryScanner(QObject *parent) : QObject(parent) {}

LibraryScanner::~LibraryScanner() = default;

// ── Thread init ───────────────────────────────────────────────────────────

void LibraryScanner::onThreadStarted()
{
    m_watcher  = new QFileSystemWatcher(this);
    m_debounce = new QTimer(this);
    m_debounce->setSingleShot(true);
    m_debounce->setInterval(2000); // 2-second debounce

    connect(m_watcher,  &QFileSystemWatcher::directoryChanged,
            this, &LibraryScanner::onDirectoryChanged);
    connect(m_debounce, &QTimer::timeout,
            this, &LibraryScanner::onDebounceTimeout);
}

// ── Watcher management ────────────────────────────────────────────────────

void LibraryScanner::updateWatcher(const QStringList &rootDirs)
{
    if (!m_watcher) return;
    const QStringList current = m_watcher->directories();
    if (!current.isEmpty()) m_watcher->removePaths(current);
    if (!rootDirs.isEmpty()) m_watcher->addPaths(rootDirs);
}

void LibraryScanner::onDirectoryChanged(const QString &/*path*/)
{
    if (m_debounce) m_debounce->start(); // restart / start the debounce timer
}

void LibraryScanner::onDebounceTimeout()
{
    if (!m_lastGenres.isEmpty() || !m_lastFolders.isEmpty())
        statCheck(m_lastGenres, m_lastFolders, m_lastCache);
}

// ── Internal scan helpers ─────────────────────────────────────────────────

// Returns the album key used for cover-deduplication. Includes genre (case-
// insensitively, matching this file's other genre comparisons) so that two
// same-named albums filed under different genres — e.g. a duplicate rip
// classified both "Alt. Rock" and "Punk Rock" — are treated as distinct
// albums, each resolving its own cover, instead of colliding into one slot
// (matches the genre-scoping LibraryModel::buildLibraryTree() already uses).
static inline QString albumKey(const TrackInfo &t)
{
    return t.genre.trimmed().toLower() + QChar('|') + t.albumArtist + QChar('|') + t.album;
}

// Files handled per QtConcurrent::blockingMapped() batch — small enough to
// keep cancellation checks and scanProgress updates feeling responsive
// (close to the old per-file cadence), large enough to amortize thread-pool
// dispatch overhead.
static constexpr int kTagReadChunkSize = 200;

QList<QFileInfo> LibraryScanner::discoverAudioFiles(const QString &dirPath, bool recursive) const
{
    QList<QFileInfo> result;
    const QDir::Filters dirFilter =
        QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable;

    QDir dir(dirPath);
    const QFileInfoList entries = dir.entryInfoList(dirFilter);

    for (const QFileInfo &fi : entries) {
        if (m_cancelRequested.load(std::memory_order_relaxed)) return result;

        if (fi.isDir()) {
            if (recursive)
                result.append(discoverAudioFiles(fi.absoluteFilePath(), true));
            continue;
        }

        const QString suffix = fi.suffix().toLower();
        if (suffix == "mp3" || suffix == "flac" || suffix == "opus")
            result.append(fi);
    }
    return result;
}

QList<TrackInfo> LibraryScanner::readTagsParallel(const QStringList &paths, QThreadPool &pool,
                                                    int &done, int total)
{
    QList<TrackInfo> result;
    result.reserve(paths.size());

    for (int i = 0; i < paths.size(); i += kTagReadChunkSize) {
        if (m_cancelRequested.load(std::memory_order_relaxed)) break;

        const QStringList chunk = paths.mid(i, kTagReadChunkSize);
        const QList<TrackInfo> chunkResult = QtConcurrent::blockingMapped<QList<TrackInfo>>(
            &pool, chunk,
            [](const QString &path) { return TagReader::read(path, false); });

        result.append(chunkResult);
        done += chunkResult.size();
        emit scanProgress(done, total);
    }
    return result;
}

void LibraryScanner::resolveCoverArt(QList<TrackInfo> &tracks, QThreadPool &pool)
{
    if (m_cancelRequested.load(std::memory_order_relaxed)) return;

    // Albums that already have a cover somewhere in the merged set (most
    // commonly, a reused cache entry) don't need a fresh one.
    QSet<QString> albumsWithCover;
    for (const TrackInfo &t : std::as_const(tracks)) {
        if (!t.coverThumb.isEmpty())
            albumsWithCover.insert(albumKey(t));
    }

    // Deterministic representative per remaining album: lexicographically
    // smallest filePath — order-independent, unlike the old "whoever's
    // processed first" (which only worked because that loop was sequential).
    QHash<QString, int> representativeIndex; // albumKey -> index into tracks
    for (int i = 0; i < tracks.size(); ++i) {
        const TrackInfo &t = tracks.at(i);
        const QString aKey = albumKey(t);
        if (albumsWithCover.contains(aKey)) continue;

        const auto it = representativeIndex.constFind(aKey);
        if (it == representativeIndex.constEnd() || t.filePath < tracks.at(it.value()).filePath)
            representativeIndex[aKey] = i;
    }

    if (representativeIndex.isEmpty()) return;

    QStringList repPaths;
    repPaths.reserve(representativeIndex.size());
    for (auto it = representativeIndex.constBegin(); it != representativeIndex.constEnd(); ++it)
        repPaths.append(tracks.at(it.value()).filePath);

    const QList<TrackInfo> withCovers = QtConcurrent::blockingMapped<QList<TrackInfo>>(
        &pool, repPaths,
        [](const QString &path) { return TagReader::read(path, true); });

    QHash<QString, QString> coverByPath; // filePath -> coverThumb
    for (const TrackInfo &t : withCovers)
        coverByPath[t.filePath] = t.coverThumb;

    for (auto it = representativeIndex.constBegin(); it != representativeIndex.constEnd(); ++it) {
        TrackInfo &t = tracks[it.value()];
        t.coverThumb = coverByPath.value(t.filePath);
    }
}

// ── Shared scan pipeline ────────────────────────────────────────────────
//
// fullScan() and statCheck() have always had near-identical "walk configured
// folders, reuse unchanged cached entries verbatim, read the rest" semantics
// — the only real historical difference was statCheck()'s extra pass that
// re-read tags for every already-known file instead of just new ones (a
// wiring bug, since fixed by unifying on this single pipeline). Both public
// slots now delegate here.
void LibraryScanner::performScan(QStringList genres, QVariantList folders,
                                  QList<TrackInfo> existingCache)
{
    m_cancelRequested.store(false, std::memory_order_relaxed);

    m_lastGenres  = genres;
    m_lastFolders = folders;
    m_lastCache   = existingCache;

    QHash<QString, QUuid>     existingIds;
    QHash<QString, qint64>    existingModified;
    QHash<QString, TrackInfo> existingCacheMap;
    for (const TrackInfo &t : std::as_const(existingCache)) {
        existingIds[t.filePath]      = t.id;
        existingModified[t.filePath] = t.lastModified;
        existingCacheMap[t.filePath] = t;
    }

    QSet<QString> configuredGenresLower;
    for (const QString &g : std::as_const(genres))
        configuredGenresLower.insert(g.trimmed().toLower());

    // 1. Discover every audio file currently on disk in the configured
    //    folders. A cached entry whose path never shows up here (deleted, or
    //    its folder removed from configuration) is simply never re-added to
    //    the result below — that's the deletion-detection mechanism.
    QList<QFileInfo> discovered;
    QStringList rootDirs;
    for (const QVariant &v : std::as_const(folders)) {
        if (m_cancelRequested.load(std::memory_order_relaxed)) return;
        const QVariantMap m    = v.toMap();
        const QString     path = m[QStringLiteral("path")].toString();
        if (path.isEmpty()) continue;
        rootDirs.append(path);
        const bool recursive = m[QStringLiteral("includeSubfolders")].toBool();
        discovered.append(discoverAudioFiles(path, recursive));
    }
    if (m_cancelRequested.load(std::memory_order_relaxed)) return;

    // 2. Classify against the real existingModified map: unchanged files
    //    reuse their cached entry verbatim (no tag read at all); new/changed
    //    files queue for a fresh parallel tag read.
    QList<TrackInfo> result;
    result.reserve(discovered.size());
    QStringList needsRead;
    needsRead.reserve(discovered.size());

    for (const QFileInfo &fi : std::as_const(discovered)) {
        const QString path       = fi.absoluteFilePath();
        const qint64  modifiedMs = fi.lastModified().toMSecsSinceEpoch();

        if (existingModified.contains(path) && existingModified.value(path) == modifiedMs) {
            const TrackInfo cached = existingCacheMap.value(path);
            if (configuredGenresLower.contains(cached.genre.trimmed().toLower()))
                result.append(cached);
        } else {
            needsRead.append(path);
        }
    }

    // 3. Parallel tag-read for new/changed files only. Pool size capped
    //    conservatively — this is disk-I/O-bound work, and concurrent random
    //    reads can be net slower than sequential on spinning/external drives.
    QThreadPool pool;
    pool.setMaxThreadCount(qMin(QThread::idealThreadCount(), 4));

    int       done  = result.size();
    const int total = discovered.size();
    emit scanProgress(done, total);

    const QList<TrackInfo> freshlyRead = readTagsParallel(needsRead, pool, done, total);
    if (m_cancelRequested.load(std::memory_order_relaxed)) return;

    for (const TrackInfo &raw : freshlyRead) {
        if (configuredGenresLower.isEmpty() ||
            !configuredGenresLower.contains(raw.genre.trimmed().toLower()))
            continue;

        TrackInfo info = raw;
        info.id = existingIds.value(info.filePath, QUuid::createUuid());
        result.append(info);
    }

    // 4. Resolve album cover art — one deterministic, order-independent pass
    //    (see resolveCoverArt()) instead of the old fully sequential,
    //    processing-order-dependent dedup.
    resolveCoverArt(result, pool);
    if (m_cancelRequested.load(std::memory_order_relaxed)) return;

    // 5. Rating enrichment: backfill any missing ratingId (e.g. a
    //    Topaz.library.json predating this feature) and (re-)apply persisted
    //    ratings from Topaz.rating.json — the latter is always authoritative,
    //    so this also picks up external edits.
    const QHash<QUuid, int> ratings = RatingCache::load();
    for (TrackInfo &t : result) {
        if (t.ratingId.isNull())
            t.ratingId = TrackInfo::computeRatingId(t.albumArtist, t.artist, t.album, t.title);
        t.rating = ratings.value(t.ratingId, 0);
    }

    LibraryCache::save(result);
    updateWatcher(rootDirs);
    emit scanCompleted(result);
}

// ── Public scan entry points ──────────────────────────────────────────────

void LibraryScanner::fullScan(QStringList genres, QVariantList folders,
                               QList<TrackInfo> existingCache)
{
    performScan(std::move(genres), std::move(folders), std::move(existingCache));
}

void LibraryScanner::statCheck(QStringList genres, QVariantList folders,
                                QList<TrackInfo> existingCache)
{
    performScan(std::move(genres), std::move(folders), std::move(existingCache));
}
