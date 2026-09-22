#include "backuprestorecontroller.h"
#include "librarycache.h"
#include "ratingcache.h"
#include "volumenormalizationcache.h"

#include "third_party/miniz/miniz.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>

namespace {

// Accept both plain paths and file:// URLs — same convention as
// AppConfig::addFolder()/PlaylistExportController::analyzeDestination().
QString normalizePath(const QString &pathOrUrl)
{
    const QUrl url(pathOrUrl);
    return url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
}

QString ratingsCacheDir()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(dir);
    return dir;
}

QString configFilePath()
{
    return ratingsCacheDir() + QStringLiteral("/Topaz.config");
}

// Opens zipFilePath, locates entryName, extracts it into *out. Returns an
// empty string on success, a human-readable error otherwise -- shared by
// restoreLibrary()/restoreVolumeNormalization() so each stays a simple
// "extract then write" call, same shape restoreConfig() already has inline.
QString extractZipEntry(const QString &zipFilePath, const char *entryName, QByteArray *out)
{
    QFile f(normalizePath(zipFilePath));
    if (!f.open(QIODevice::ReadOnly))
        return QStringLiteral("Could not open the file.");
    const QByteArray zipBytes = f.readAll();
    f.close();

    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));
    if (!mz_zip_reader_init_mem(&zip, zipBytes.constData(), size_t(zipBytes.size()), 0))
        return QStringLiteral("Not a valid zip archive.");

    const int index = mz_zip_reader_locate_file(&zip, entryName, nullptr, 0);
    if (index < 0) {
        mz_zip_reader_end(&zip);
        return QStringLiteral("That entry isn't in the archive.");
    }

    mz_zip_archive_file_stat stat;
    if (!mz_zip_reader_file_stat(&zip, mz_uint(index), &stat)) {
        mz_zip_reader_end(&zip);
        return QStringLiteral("Could not read entry metadata.");
    }

    out->resize(qsizetype(stat.m_uncomp_size));
    const bool ok = mz_zip_reader_extract_to_mem(&zip, mz_uint(index), out->data(),
                                                  size_t(out->size()), 0);
    mz_zip_reader_end(&zip);
    if (!ok) return QStringLiteral("Could not extract entry.");
    return QString();
}

} // namespace

BackupRestoreController::BackupRestoreController(QObject *parent) : QObject(parent) {}

void BackupRestoreController::setPlaylistManager(PlaylistManager *pm)
{
    if (m_playlistManager == pm) return;
    m_playlistManager = pm;
    emit playlistManagerChanged();
}

void BackupRestoreController::setAppConfig(AppConfig *cfg)
{
    if (m_appConfig == cfg) return;
    m_appConfig = cfg;
    emit appConfigChanged();
}

QString BackupRestoreController::finalZipPath(const QString &destFolder,
                                               const QString &zipFileName) const
{
    QString name = zipFileName.trimmed();
    if (!name.endsWith(QStringLiteral(".zip"), Qt::CaseInsensitive))
        name += QStringLiteral(".zip");
    return normalizePath(destFolder) + QChar('/') + name;
}

bool BackupRestoreController::backupTargetExists(const QString &destFolder,
                                                  const QString &zipFileName) const
{
    return QFile::exists(finalZipPath(destFolder, zipFileName));
}

// ── BACKUP ───────────────────────────────────────────────────────────────

QVariantMap BackupRestoreController::runBackup(const QStringList &categories,
                                                const QString &destFolder,
                                                const QString &zipFileName) const
{
    QVariantMap result;

    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));
    if (!mz_zip_writer_init_heap(&zip, 0, 0)) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Could not initialize the zip archive.");
        return result;
    }

    int fileCount = 0;

    auto addFile = [&](const QString &diskPath, const QString &archiveName) {
        QFile f(diskPath);
        if (!f.exists() || !f.open(QIODevice::ReadOnly)) return;
        const QByteArray bytes = f.readAll();
        f.close();
        const QByteArray archiveNameUtf8 = archiveName.toUtf8();
        if (mz_zip_writer_add_mem(&zip, archiveNameUtf8.constData(),
                                   bytes.constData(), bytes.size(), MZ_DEFAULT_LEVEL))
            ++fileCount;
    };

    if (categories.contains(QStringLiteral("config")))
        addFile(configFilePath(), QStringLiteral("config/Topaz.config"));

    if (categories.contains(QStringLiteral("playlists")) && m_playlistManager) {
        const QString dir = m_playlistManager->playlistDirectory();
        for (const QVariant &v : m_playlistManager->listPlaylists()) {
            const QString fileName = v.toMap().value(QStringLiteral("fileName")).toString();
            addFile(dir + QChar('/') + fileName, QStringLiteral("playlists/") + fileName);
        }
    }

    if (categories.contains(QStringLiteral("ratings")))
        addFile(RatingCache::cacheFilePath(), QStringLiteral("ratings/Topaz.rating.json"));

    if (categories.contains(QStringLiteral("library")))
        addFile(LibraryCache::cacheFilePath(), QStringLiteral("library/Topaz.library.json"));

    if (categories.contains(QStringLiteral("volumeNormalization")))
        addFile(VolumeNormalizationCache::cacheFilePath(),
                QStringLiteral("volumeNormalization/Topaz.volumeNormalization.json"));

    if (fileCount == 0) {
        mz_zip_writer_end(&zip);
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   =
            QStringLiteral("Nothing to back up for the selected options.");
        return result;
    }

    void *buf = nullptr;
    size_t bufSize = 0;
    const bool finalized = mz_zip_writer_finalize_heap_archive(&zip, &buf, &bufSize);
    mz_zip_writer_end(&zip);

    if (!finalized || !buf) {
        if (buf) mz_free(buf);
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Could not finalize the zip archive.");
        return result;
    }

    const QString zipPath = finalZipPath(destFolder, zipFileName);
    QFile out(zipPath);
    const bool opened = out.open(QIODevice::WriteOnly | QIODevice::Truncate);
    if (opened) {
        out.write(static_cast<const char *>(buf), qint64(bufSize));
        out.close();
    }
    mz_free(buf);

    if (!opened) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   =
            QStringLiteral("Could not write to the destination folder.");
        return result;
    }

    result[QStringLiteral("success")]   = true;
    result[QStringLiteral("error")]     = QString();
    result[QStringLiteral("zipPath")]   = zipPath;
    result[QStringLiteral("fileCount")] = fileCount;
    return result;
}

// ── RESTORE: inspection ─────────────────────────────────────────────────

QVariantMap BackupRestoreController::inspectZip(const QString &zipFilePath) const
{
    QVariantMap result;

    QFile f(normalizePath(zipFilePath));
    if (!f.open(QIODevice::ReadOnly)) {
        result[QStringLiteral("error")] = QStringLiteral("Could not open the file.");
        return result;
    }
    const QByteArray bytes = f.readAll();
    f.close();

    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));
    if (!mz_zip_reader_init_mem(&zip, bytes.constData(), size_t(bytes.size()), 0)) {
        result[QStringLiteral("error")] = QStringLiteral("Not a valid zip archive.");
        return result;
    }

    bool hasConfig = false, hasRatings = false, hasPlaylists = false;
    bool hasLibrary = false, hasVolumeNormalization = false;

    const mz_uint numFiles = mz_zip_reader_get_num_files(&zip);
    for (mz_uint i = 0; i < numFiles; ++i) {
        mz_zip_archive_file_stat stat;
        if (!mz_zip_reader_file_stat(&zip, i, &stat) || stat.m_is_directory)
            continue;
        const QString name = QString::fromUtf8(stat.m_filename);
        if (name == QStringLiteral("config/Topaz.config")) {
            hasConfig = true;
        } else if (name == QStringLiteral("ratings/Topaz.rating.json")) {
            hasRatings = true;
        } else if (name == QStringLiteral("library/Topaz.library.json")) {
            hasLibrary = true;
        } else if (name == QStringLiteral("volumeNormalization/Topaz.volumeNormalization.json")) {
            hasVolumeNormalization = true;
        } else if (name.startsWith(QStringLiteral("playlists/")) && name.size() > 10) {
            hasPlaylists = true;
        }
    }
    mz_zip_reader_end(&zip);

    result[QStringLiteral("error")]                  = QString();
    result[QStringLiteral("hasConfig")]              = hasConfig;
    result[QStringLiteral("hasRatings")]              = hasRatings;
    result[QStringLiteral("hasPlaylists")]            = hasPlaylists;
    result[QStringLiteral("hasLibrary")]              = hasLibrary;
    result[QStringLiteral("hasVolumeNormalization")]  = hasVolumeNormalization;
    result[QStringLiteral("ratingsConflict")]         = QFile::exists(RatingCache::cacheFilePath());
    return result;
}

// ── RESTORE: playlists, wholesale replace ───────────────────────────────

QVariantMap BackupRestoreController::restoreAllPlaylists(const QString &zipFilePath) const
{
    QVariantMap result;

    if (!m_playlistManager) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("No playlist manager available.");
        return result;
    }

    QFile f(normalizePath(zipFilePath));
    if (!f.open(QIODevice::ReadOnly)) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Could not open the file.");
        return result;
    }
    const QByteArray zipBytes = f.readAll();
    f.close();

    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));
    if (!mz_zip_reader_init_mem(&zip, zipBytes.constData(), size_t(zipBytes.size()), 0)) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Not a valid zip archive.");
        return result;
    }

    const QString dir = m_playlistManager->playlistDirectory();

    // 1. Clear every existing playlist first -- this is a wholesale
    // "switch environments" replace, not a merge (a leftover playlist from
    // before the restore could reference tracks that don't exist in the
    // newly-restored library at all).
    int deletedCount = 0;
    for (const QVariant &v : m_playlistManager->listPlaylists()) {
        const QString fileName = v.toMap().value(QStringLiteral("fileName")).toString();
        if (QFile::remove(dir + QChar('/') + fileName))
            ++deletedCount;
    }

    // 2. Write in every playlist the backup has.
    int writtenCount = 0;
    const mz_uint numFiles = mz_zip_reader_get_num_files(&zip);
    for (mz_uint i = 0; i < numFiles; ++i) {
        mz_zip_archive_file_stat stat;
        if (!mz_zip_reader_file_stat(&zip, i, &stat) || stat.m_is_directory)
            continue;
        const QString name = QString::fromUtf8(stat.m_filename);
        static const QString prefix = QStringLiteral("playlists/");
        if (!name.startsWith(prefix) || name.size() <= prefix.size())
            continue;
        const QString fileName = name.mid(prefix.size());

        QByteArray extracted(qsizetype(stat.m_uncomp_size), Qt::Uninitialized);
        if (!mz_zip_reader_extract_to_mem(&zip, i, extracted.data(), size_t(extracted.size()), 0))
            continue;   // skip this one entry rather than failing the whole restore

        QFile out(dir + QChar('/') + fileName);
        if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate))
            continue;
        out.write(extracted);
        out.close();
        ++writtenCount;
    }
    mz_zip_reader_end(&zip);

    result[QStringLiteral("success")]      = true;
    result[QStringLiteral("error")]        = QString();
    result[QStringLiteral("deletedCount")] = deletedCount;
    result[QStringLiteral("writtenCount")] = writtenCount;
    return result;
}

// ── RESTORE: ratings ─────────────────────────────────────────────────────

QVariantMap BackupRestoreController::restoreRatings(const QString &zipFilePath,
                                                      const QString &mode) const
{
    QVariantMap result;

    if (mode == QStringLiteral("skip")) {
        result[QStringLiteral("success")]      = true;
        result[QStringLiteral("error")]        = QString();
        result[QStringLiteral("addedCount")]   = 0;
        result[QStringLiteral("updatedCount")] = 0;
        return result;
    }

    QFile f(normalizePath(zipFilePath));
    if (!f.open(QIODevice::ReadOnly)) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Could not open the file.");
        return result;
    }
    const QByteArray zipBytes = f.readAll();
    f.close();

    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));
    if (!mz_zip_reader_init_mem(&zip, zipBytes.constData(), size_t(zipBytes.size()), 0)) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Not a valid zip archive.");
        return result;
    }

    const int index = mz_zip_reader_locate_file(&zip, "ratings/Topaz.rating.json", nullptr, 0);
    if (index < 0) {
        mz_zip_reader_end(&zip);
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("No ratings file in the archive.");
        return result;
    }

    mz_zip_archive_file_stat stat;
    if (!mz_zip_reader_file_stat(&zip, mz_uint(index), &stat)) {
        mz_zip_reader_end(&zip);
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Could not read entry metadata.");
        return result;
    }

    QByteArray extracted(qsizetype(stat.m_uncomp_size), Qt::Uninitialized);
    const bool extractedOk = mz_zip_reader_extract_to_mem(
        &zip, mz_uint(index), extracted.data(), size_t(extracted.size()), 0);
    mz_zip_reader_end(&zip);

    if (!extractedOk) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Could not extract entry.");
        return result;
    }

    const QList<RatingCache::Entry> backup = RatingCache::parseEntries(extracted);

    int addedCount = 0, updatedCount = 0;
    bool saved;

    if (mode == QStringLiteral("overwrite")) {
        saved = RatingCache::saveEntries(backup);
        addedCount = backup.size();
    } else if (mode == QStringLiteral("mergeNew") || mode == QStringLiteral("mergeAll")) {
        QList<RatingCache::Entry> local = RatingCache::loadEntries();
        QHash<QUuid, int> localIndexById;
        for (int i = 0; i < local.size(); ++i)
            localIndexById.insert(local[i].ratingId, i);

        for (const RatingCache::Entry &e : backup) {
            const auto it = localIndexById.constFind(e.ratingId);
            if (it == localIndexById.constEnd()) {
                local.append(e);
                localIndexById.insert(e.ratingId, local.size() - 1);
                ++addedCount;
            } else if (mode == QStringLiteral("mergeAll")) {
                local[it.value()].genre  = e.genre;
                local[it.value()].rating = e.rating;
                ++updatedCount;
            }
            // mergeNew: existing local entries are never touched.
        }
        saved = RatingCache::saveEntries(local);
    } else {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Unknown mode.");
        return result;
    }

    result[QStringLiteral("success")]      = saved;
    result[QStringLiteral("error")]        = saved ? QString() : QStringLiteral("Could not write the ratings file.");
    result[QStringLiteral("addedCount")]   = addedCount;
    result[QStringLiteral("updatedCount")] = updatedCount;
    return result;
}

// ── RESTORE: config ──────────────────────────────────────────────────────

QVariantMap BackupRestoreController::restoreConfig(const QString &zipFilePath) const
{
    QVariantMap result;

    if (!m_appConfig) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("No app config available.");
        return result;
    }

    QFile f(normalizePath(zipFilePath));
    if (!f.open(QIODevice::ReadOnly)) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Could not open the file.");
        return result;
    }
    const QByteArray zipBytes = f.readAll();
    f.close();

    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));
    if (!mz_zip_reader_init_mem(&zip, zipBytes.constData(), size_t(zipBytes.size()), 0)) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Not a valid zip archive.");
        return result;
    }

    const int index = mz_zip_reader_locate_file(&zip, "config/Topaz.config", nullptr, 0);
    if (index < 0) {
        mz_zip_reader_end(&zip);
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("No config file in the archive.");
        return result;
    }

    mz_zip_archive_file_stat stat;
    if (!mz_zip_reader_file_stat(&zip, mz_uint(index), &stat)) {
        mz_zip_reader_end(&zip);
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Could not read entry metadata.");
        return result;
    }

    QByteArray extracted(qsizetype(stat.m_uncomp_size), Qt::Uninitialized);
    const bool extractedOk = mz_zip_reader_extract_to_mem(
        &zip, mz_uint(index), extracted.data(), size_t(extracted.size()), 0);
    mz_zip_reader_end(&zip);

    if (!extractedOk) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Could not extract entry.");
        return result;
    }

    return m_appConfig->restoreFromJson(extracted);
}

// ── RESTORE: library / volume normalization ─────────────────────────────

QVariantMap BackupRestoreController::restoreLibrary(const QString &zipFilePath) const
{
    QVariantMap result;
    QByteArray extracted;
    const QString err = extractZipEntry(zipFilePath, "library/Topaz.library.json", &extracted);
    if (!err.isEmpty()) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = err;
        return result;
    }

    QFile out(LibraryCache::cacheFilePath());
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Could not write the library file.");
        return result;
    }
    out.write(extracted);
    out.close();

    result[QStringLiteral("success")] = true;
    result[QStringLiteral("error")]   = QString();
    return result;
}

QVariantMap BackupRestoreController::restoreVolumeNormalization(const QString &zipFilePath) const
{
    QVariantMap result;
    QByteArray extracted;
    const QString err = extractZipEntry(
        zipFilePath, "volumeNormalization/Topaz.volumeNormalization.json", &extracted);
    if (!err.isEmpty()) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = err;
        return result;
    }

    QFile out(VolumeNormalizationCache::cacheFilePath());
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   =
            QStringLiteral("Could not write the volume normalization file.");
        return result;
    }
    out.write(extracted);
    out.close();

    result[QStringLiteral("success")] = true;
    result[QStringLiteral("error")]   = QString();
    return result;
}
