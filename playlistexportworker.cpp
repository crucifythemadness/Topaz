#include "playlistexportworker.h"

#include "loudnessanalyzer.h"
#include "tagwriter.h"
#include "trackinfo.h"
#include "volumenormalizationcache.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>

PlaylistExportWorker::PlaylistExportWorker(QObject *parent) : QObject(parent) {}

QString PlaylistExportWorker::sanitizeForFilename(const QString &name)
{
    QString out = name;
    // Windows-reserved filename characters -- strip rather than substitute,
    // to keep generated names short and readable on a car head unit's display.
    static const QString illegal = QStringLiteral("\\/:*?\"<>|");
    for (const QChar &c : illegal)
        out.remove(c);
    return out.trimmed();
}

void PlaylistExportWorker::runExport(QVariantList tracks, QString destFolder, QString prefix,
                                      bool replayGainNormalization, double audiophileTrimDb)
{
    m_cancelRequested.store(false, std::memory_order_relaxed);

    // Accept both plain paths and file:// URLs — same convention as
    // AppConfig::addFolder()/PlaylistExportController::analyzeDestination().
    const QUrl url(destFolder);
    const QString destPath = url.isLocalFile() ? url.toLocalFile() : destFolder;

    const int total = tracks.size();
    const int digitWidth = qMax(2, QString::number(total).size());
    QDir destDir(destPath);

    // Loaded once for the whole run (not per track); newly-discovered
    // entries are merged in and saved once at the end, so export also
    // usefully warms the same cache normal playback reads from.
    QHash<QUuid, VolumeNormalizationCache::Entry> normCache;
    bool normCacheDirty = false;
    if (replayGainNormalization)
        normCache = VolumeNormalizationCache::load();

    QVariantList results;
    for (int i = 0; i < total; ++i) {
        if (m_cancelRequested.load(std::memory_order_relaxed))
            break;

        const QVariantMap track = tracks.at(i).toMap();
        const QString sourcePath   = track.value(QStringLiteral("filePath")).toString();
        const QString title        = track.value(QStringLiteral("title")).toString();
        const QString artist       = track.value(QStringLiteral("artist")).toString();
        const QString albumArtist  = track.value(QStringLiteral("albumArtist")).toString();
        const QString album        = track.value(QStringLiteral("album")).toString();

        emit progress(i, total, QFileInfo(sourcePath).fileName());

        const QString paddedIndex = QString(QStringLiteral("%1"))
                                         .arg(i + 1, digitWidth, 10, QChar('0'));
        const QString suffix = QFileInfo(sourcePath).suffix();
        const QString destFileName = prefix + paddedIndex + QStringLiteral("_")
                                      + sanitizeForFilename(title)
                                      + (suffix.isEmpty() ? QString() : QStringLiteral(".") + suffix);
        const QString trackDestPath = destDir.filePath(destFileName);

        // Overwrite any leftover file from a previous export attempt --
        // QFile::copy() refuses to copy onto an existing destination.
        if (QFile::exists(trackDestPath))
            QFile::remove(trackDestPath);

        const bool ok = QFile::copy(sourcePath, trackDestPath);
        bool tagged = false;

        // UC-26: Replay Gain Normalization. Only ever touches trackDestPath
        // (the copy just created above) -- the source library file is never
        // opened for writing anywhere in this class.
        if (ok && replayGainNormalization) {
            const QUuid id = TrackInfo::computeNormalizationId(albumArtist, artist, album, title);
            const qint64 fileSize = QFileInfo(sourcePath).size();
            const LoudnessAnalyzer::ReferenceResult ref =
                LoudnessAnalyzer::determineReferenceGain(sourcePath, id, fileSize, normCache);
            if (ref.ok) {
                const double finalGainDb = ref.gainDb + audiophileTrimDb;
                tagged = TagWriter::writeReplayGain(trackDestPath, finalGainDb, ref.peak);
                if (!id.isNull() && ref.source != QStringLiteral("cache")) {
                    VolumeNormalizationCache::Entry e;
                    e.id = id; e.dB = ref.gainDb; e.source = ref.source;
                    e.peak = ref.peak; e.fileSize = fileSize;
                    normCache.insert(id, e);
                    normCacheDirty = true;
                }
            }
        }

        QVariantMap result;
        result[QStringLiteral("sourcePath")]      = sourcePath;
        result[QStringLiteral("destPath")]        = trackDestPath;
        result[QStringLiteral("success")]         = ok;
        result[QStringLiteral("errorString")] =
            ok ? QString()
               : QStringLiteral("Copy failed (source missing, or destination not writable)");
        result[QStringLiteral("replayGainTagged")] = tagged;
        results.append(result);
    }

    if (normCacheDirty)
        VolumeNormalizationCache::save(normCache);

    emit finished(results);
}
