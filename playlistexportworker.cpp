#include "playlistexportworker.h"

#include "loudnessanalyzer.h"
#include "mp3converter.h"
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

bool PlaylistExportWorker::writeM3u(const QString &path, const QStringList &lines)
{
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    // UTF-8 without BOM, CRLF -- see runExport()'s doc comment.
    const QByteArray data = (lines.join(QStringLiteral("\r\n")) + QStringLiteral("\r\n")).toUtf8();
    const bool ok = f.write(data) == data.size();
    f.close();
    return ok && f.error() == QFileDevice::NoError;
}

void PlaylistExportWorker::runExport(QVariantList tracks, QString destFolder, QString prefix,
                                      bool replayGainNormalization, double audiophileTrimDb,
                                      bool convertToMp3, bool alwaysMeasure,
                                      bool createM3u, QString playlistName)
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

    // Resolved once per run (UC-26 "Convert to MP3"); empty = none found, in
    // which case every convertible track fails with a clear message instead of
    // the run silently exporting FLAC/Opus the user asked to have converted.
    const QString ffmpegPath = convertToMp3 ? Mp3Converter::findFfmpeg() : QString();

    QVariantList results;
    QStringList  m3uLines { QStringLiteral("#EXTM3U") };
    bool         cancelled = false;
    for (int i = 0; i < total; ++i) {
        if (m_cancelRequested.load(std::memory_order_relaxed)) {
            cancelled = true;
            break;
        }

        const QVariantMap track = tracks.at(i).toMap();
        const QString sourcePath   = track.value(QStringLiteral("filePath")).toString();
        const QString title        = track.value(QStringLiteral("title")).toString();
        const QString artist       = track.value(QStringLiteral("artist")).toString();
        const QString albumArtist  = track.value(QStringLiteral("albumArtist")).toString();
        const QString album        = track.value(QStringLiteral("album")).toString();
        const qint64  durationMs   = track.value(QStringLiteral("durationMs")).toLongLong();

        const QString sourceFileName = QFileInfo(sourcePath).fileName();
        const QString suffix = QFileInfo(sourcePath).suffix();
        // Already-MP3 sources are copied as they are, never re-encoded.
        const bool wantConvert = convertToMp3
                                 && suffix.compare(QLatin1String("mp3"), Qt::CaseInsensitive) != 0;

        emit progress(i, total, sourceFileName, 0.0, wantConvert);

        const QString paddedIndex = QString(QStringLiteral("%1"))
                                         .arg(i + 1, digitWidth, 10, QChar('0'));
        const QString destSuffix = wantConvert ? QStringLiteral("mp3") : suffix;
        const QString destFileName = prefix + paddedIndex + QStringLiteral("_")
                                      + sanitizeForFilename(title)
                                      + (destSuffix.isEmpty() ? QString() : QStringLiteral(".") + destSuffix);
        const QString trackDestPath = destDir.filePath(destFileName);

        // Overwrite any leftover file from a previous export attempt --
        // QFile::copy() refuses to copy onto an existing destination.
        if (QFile::exists(trackDestPath))
            QFile::remove(trackDestPath);

        bool ok = false;
        bool converted = false;
        QString errorString;
        if (wantConvert) {
            if (ffmpegPath.isEmpty()) {
                errorString = QStringLiteral("Conversion failed (ffmpeg not found)");
            } else {
                const Mp3Converter::Outcome o = Mp3Converter::convert(
                    ffmpegPath, sourcePath, trackDestPath, durationMs, m_cancelRequested,
                    [&](double fraction) {
                        emit progress(i, total, sourceFileName, fraction, true);
                    });
                if (o.cancelled) {
                    cancelled = true;
                    break;   // partial file already removed; like the loop-top cancel, no result entry
                }
                ok = converted = o.ok;
                if (!ok)
                    errorString = QStringLiteral("Conversion failed (%1)").arg(o.error);
            }
        } else {
            ok = QFile::copy(sourcePath, trackDestPath);
            if (!ok)
                errorString = QStringLiteral("Copy failed (source missing, or destination not writable)");
        }
        bool tagged = false;

        // UC-26: Replay Gain Normalization. Only ever touches trackDestPath
        // (the copy just created above) -- the source library file is never
        // opened for writing anywhere in this class.
        if (ok && replayGainNormalization) {
            const QUuid id = TrackInfo::computeNormalizationId(albumArtist, artist, album, title);
            const qint64 fileSize = QFileInfo(sourcePath).size();
            const LoudnessAnalyzer::ReferenceResult ref =
                LoudnessAnalyzer::determineReferenceGain(sourcePath, id, fileSize, normCache,
                                                         {}, alwaysMeasure);
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
        result[QStringLiteral("errorString")]     = errorString;
        result[QStringLiteral("replayGainTagged")] = tagged;
        result[QStringLiteral("converted")]       = converted;
        results.append(result);

        if (ok && createM3u) {
            const QString shown = artist.isEmpty() ? title : artist + QStringLiteral(" - ") + title;
            m3uLines << QStringLiteral("#EXTINF:%1,%2").arg(durationMs > 0 ? durationMs / 1000 : -1).arg(shown)
                     << destFileName;
        }
    }

    if (normCacheDirty)
        VolumeNormalizationCache::save(normCache);

    // UC-26 "Create M3U Playlist" -- see runExport()'s doc comment.
    QString m3uFileName;
    bool    m3uOk = false;
    if (createM3u && !cancelled) {
        QString base = sanitizeForFilename(playlistName);
        if (base.isEmpty()) base = QStringLiteral("Topaz Playlist");
        m3uFileName = base + QStringLiteral(".m3u");
        m3uOk = writeM3u(destDir.filePath(m3uFileName), m3uLines);
    }

    emit finished(results, m3uFileName, m3uOk);
}
