#include "libraryscanner.h"
#include "librarycache.h"
#include "tagreader.h"

#include <QDir>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QTimer>

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

// Returns the album key used for cover-deduplication.
static inline QString albumKey(const TrackInfo &t)
{
    return t.albumArtist + QChar('|') + t.album;
}

void LibraryScanner::scanDirectory(
    const QString              &dirPath,
    bool                        recursive,
    const QSet<QString>        &configuredGenresLower,
    const QHash<QString,QUuid> &existingIds,
    const QHash<QString,qint64>&existingModified,
    const QHash<QString,TrackInfo> &existingCache,
    QSet<QString>              &seenAlbums,
    QList<TrackInfo>            &result,
    int                        &done,
    int                         total)
{
    const QStringList filters{ QStringLiteral("*.mp3"), QStringLiteral("*.flac") };
    const QDir::Filters dirFilter =
        QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable;

    QDir dir(dirPath);
    const QFileInfoList entries = dir.entryInfoList(dirFilter);

    for (const QFileInfo &fi : entries) {
        if (m_cancelRequested.load(std::memory_order_relaxed)) return;

        if (fi.isDir()) {
            if (recursive)
                scanDirectory(fi.absoluteFilePath(), true,
                              configuredGenresLower, existingIds,
                              existingModified, existingCache,
                              seenAlbums, result, done, total);
            continue;
        }

        const QString suffix = fi.suffix().toLower();
        if (suffix != "mp3" && suffix != "flac") continue;

        const QString path       = fi.absoluteFilePath();
        const qint64  modifiedMs = fi.lastModified().toMSecsSinceEpoch();

        // If the file is unchanged since last scan, reuse the cached entry.
        if (existingModified.contains(path) && existingModified[path] == modifiedMs) {
            const TrackInfo &cached = existingCache[path];
            // Still check genre match (genre config may have changed)
            if (configuredGenresLower.contains(cached.genre.trimmed().toLower()))
                result.append(cached);
            ++done;
            emit scanProgress(done, total);
            continue;
        }

        // New or changed file – read tags
        const bool needCover = !seenAlbums.isEmpty(); // placeholder; real check below
        Q_UNUSED(needCover)

        TrackInfo info = TagReader::read(path, false); // cover decided below

        // Genre filter
        if (configuredGenresLower.isEmpty() ||
            !configuredGenresLower.contains(info.genre.trimmed().toLower()))
        {
            ++done;
            emit scanProgress(done, total);
            continue;
        }

        // Assign stable UUID
        info.id = existingIds.value(path, QUuid::createUuid());

        // Cover thumbnail – one per (albumArtist, album)
        const QString aKey = albumKey(info);
        if (!seenAlbums.contains(aKey)) {
            seenAlbums.insert(aKey);
            // Re-read with cover extraction enabled
            TrackInfo withCover = TagReader::read(path, true);
            info.coverThumb = withCover.coverThumb;
        }

        result.append(info);
        ++done;
        emit scanProgress(done, total);
    }
}

// ── Public scan entry points ──────────────────────────────────────────────

void LibraryScanner::fullScan(QStringList  genres,
                               QVariantList folders,
                               QList<TrackInfo> existingCache)
{
    m_cancelRequested.store(false, std::memory_order_relaxed);

    m_lastGenres  = genres;
    m_lastFolders = folders;
    m_lastCache   = existingCache;

    // Build lookup maps from existing cache for stable IDs and cached entries
    QHash<QString, QUuid>      existingIds;
    QHash<QString, qint64>     existingModified;
    QHash<QString, TrackInfo>  existingCacheMap;
    for (const TrackInfo &t : std::as_const(existingCache)) {
        existingIds[t.filePath]      = t.id;
        existingModified[t.filePath] = t.lastModified;
        existingCacheMap[t.filePath] = t;
    }

    QSet<QString> configuredGenresLower;
    for (const QString &g : std::as_const(genres))
        configuredGenresLower.insert(g.trimmed().toLower());

    // Count total audio files for progress reporting
    int total = 0;
    QStringList rootDirs;
    for (const QVariant &v : std::as_const(folders)) {
        const QVariantMap m    = v.toMap();
        const QString     path = m[QStringLiteral("path")].toString();
        if (path.isEmpty()) continue;
        rootDirs.append(path);

        const bool recursive = m[QStringLiteral("includeSubfolders")].toBool();
        std::function<void(const QString &)> countFiles;
        countFiles = [&](const QString &dir) {
            const QDir d(dir);
            const QFileInfoList entries =
                d.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot);
            for (const QFileInfo &fi : entries) {
                if (fi.isDir() && recursive) { countFiles(fi.absoluteFilePath()); continue; }
                const QString suf = fi.suffix().toLower();
                if (suf == "mp3" || suf == "flac") ++total;
            }
        };
        countFiles(path);
    }

    QList<TrackInfo> result;
    result.reserve(qMax(total, existingCache.size()));
    QSet<QString> seenAlbums;
    int done = 0;

    emit scanProgress(0, total);

    for (const QVariant &v : std::as_const(folders)) {
        if (m_cancelRequested.load(std::memory_order_relaxed)) break;
        const QVariantMap m    = v.toMap();
        const QString     path = m[QStringLiteral("path")].toString();
        if (path.isEmpty()) continue;
        const bool recursive = m[QStringLiteral("includeSubfolders")].toBool();
        scanDirectory(path, recursive,
                      configuredGenresLower,
                      existingIds, existingModified, existingCacheMap,
                      seenAlbums, result, done, total);
    }

    // Shutting down mid-scan: skip writing a partial cache and don't bother
    // signaling completion — the app is already tearing down.
    if (m_cancelRequested.load(std::memory_order_relaxed)) return;

    LibraryCache::save(result);
    updateWatcher(rootDirs);
    emit scanCompleted(result);
}

void LibraryScanner::statCheck(QStringList  genres,
                                QVariantList folders,
                                QList<TrackInfo> existingCache)
{
    m_cancelRequested.store(false, std::memory_order_relaxed);

    m_lastGenres  = genres;
    m_lastFolders = folders;
    m_lastCache   = existingCache;

    QHash<QString, QUuid>      existingIds;
    QHash<QString, qint64>     existingModified;
    QHash<QString, TrackInfo>  existingCacheMap;
    for (const TrackInfo &t : std::as_const(existingCache)) {
        existingIds[t.filePath]      = t.id;
        existingModified[t.filePath] = t.lastModified;
        existingCacheMap[t.filePath] = t;
    }

    QSet<QString> configuredGenresLower;
    for (const QString &g : std::as_const(genres))
        configuredGenresLower.insert(g.trimmed().toLower());

    // 1. Validate existing cache entries (remove deleted / re-read changed files)
    QList<TrackInfo> result;
    result.reserve(existingCache.size());
    QSet<QString> seenAlbums;
    QSet<QString> stillPresentPaths;

    for (const TrackInfo &t : std::as_const(existingCache)) {
        if (m_cancelRequested.load(std::memory_order_relaxed)) return;

        const QFileInfo fi(t.filePath);
        if (!fi.exists()) continue; // deleted
        if (!configuredGenresLower.contains(t.genre.trimmed().toLower())) continue;

        if (fi.lastModified().toMSecsSinceEpoch() != t.lastModified) {
            // Changed – re-read tags
            const QString aKey = albumKey(t);
            const bool needCover = !seenAlbums.contains(aKey);
            TrackInfo updated = TagReader::read(t.filePath, needCover);
            updated.id = t.id;
            if (!configuredGenresLower.contains(updated.genre.trimmed().toLower())) continue;
            if (needCover) seenAlbums.insert(aKey);
            result.append(updated);
        } else {
            const QString aKey = albumKey(t);
            if (!seenAlbums.contains(aKey)) {
                seenAlbums.insert(aKey);
                if (t.coverThumb.isEmpty()) {
                    // Cover was missing last time – try again
                    TrackInfo withCover = TagReader::read(t.filePath, true);
                    TrackInfo updated = t;
                    updated.coverThumb = withCover.coverThumb;
                    result.append(updated);
                    continue;
                }
            }
            result.append(t);
        }
        stillPresentPaths.insert(t.filePath);
    }

    // 2. Find new files in configured folders
    int done = result.size();
    const int total = done; // progress is approximate for stat-check
    QStringList rootDirs;
    for (const QVariant &v : std::as_const(folders)) {
        if (m_cancelRequested.load(std::memory_order_relaxed)) break;
        const QVariantMap m    = v.toMap();
        const QString     path = m[QStringLiteral("path")].toString();
        if (path.isEmpty()) continue;
        rootDirs.append(path);

        // Temporarily remove known files from the existingModified map so
        // scanDirectory picks up genuinely new files.
        QHash<QString, qint64> newFilesOnly;   // empty → triggers tag read for all
        const bool recursive = m[QStringLiteral("includeSubfolders")].toBool();
        scanDirectory(path, recursive,
                      configuredGenresLower,
                      existingIds, newFilesOnly, existingCacheMap,
                      seenAlbums, result, done, total);
    }

    // Shutting down mid-scan: skip writing a partial cache and don't bother
    // signaling completion — the app is already tearing down.
    if (m_cancelRequested.load(std::memory_order_relaxed)) return;

    // Deduplicate (scanDirectory may encounter files already in result)
    QSet<QString> seen;
    QList<TrackInfo> deduped;
    deduped.reserve(result.size());
    for (const TrackInfo &t : std::as_const(result)) {
        if (!seen.contains(t.filePath)) {
            seen.insert(t.filePath);
            deduped.append(t);
        }
    }

    LibraryCache::save(deduped);
    updateWatcher(rootDirs);
    emit scanCompleted(deduped);
}
