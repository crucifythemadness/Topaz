#include "playlistexportworker.h"

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

void PlaylistExportWorker::runExport(QVariantList tracks, QString destFolder, QString prefix)
{
    m_cancelRequested.store(false, std::memory_order_relaxed);

    // Accept both plain paths and file:// URLs — same convention as
    // AppConfig::addFolder()/PlaylistExportController::analyzeDestination().
    const QUrl url(destFolder);
    const QString destPath = url.isLocalFile() ? url.toLocalFile() : destFolder;

    const int total = tracks.size();
    const int digitWidth = qMax(2, QString::number(total).size());
    QDir destDir(destPath);

    QVariantList results;
    for (int i = 0; i < total; ++i) {
        if (m_cancelRequested.load(std::memory_order_relaxed))
            break;

        const QVariantMap track = tracks.at(i).toMap();
        const QString sourcePath = track.value(QStringLiteral("filePath")).toString();
        const QString title      = track.value(QStringLiteral("title")).toString();

        emit progress(i, total, QFileInfo(sourcePath).fileName());

        const QString paddedIndex = QString(QStringLiteral("%1"))
                                         .arg(i + 1, digitWidth, 10, QChar('0'));
        const QString suffix = QFileInfo(sourcePath).suffix();
        const QString destFileName = prefix + paddedIndex + QStringLiteral("_")
                                      + sanitizeForFilename(title)
                                      + (suffix.isEmpty() ? QString() : QStringLiteral(".") + suffix);
        const QString destPath = destDir.filePath(destFileName);

        // Overwrite any leftover file from a previous export attempt --
        // QFile::copy() refuses to copy onto an existing destination.
        if (QFile::exists(destPath))
            QFile::remove(destPath);

        const bool ok = QFile::copy(sourcePath, destPath);

        QVariantMap result;
        result[QStringLiteral("sourcePath")] = sourcePath;
        result[QStringLiteral("destPath")]   = destPath;
        result[QStringLiteral("success")]    = ok;
        result[QStringLiteral("errorString")] =
            ok ? QString()
               : QStringLiteral("Copy failed (source missing, or destination not writable)");
        results.append(result);
    }

    emit finished(results);
}
