#include "playlistexportcontroller.h"
#include "mp3converter.h"
#include "playlistexportworker.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStorageInfo>
#include <QThread>
#include <QUrl>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

PlaylistExportController::PlaylistExportController(QObject *parent) : QObject(parent)
{
    startWorkerThread();
}

PlaylistExportController::~PlaylistExportController()
{
    if (m_workerThread && m_workerThread->isRunning()) {
        if (m_worker) m_worker->cancelExport();
        m_workerThread->quit();
        if (!m_workerThread->wait(3000)) {
            // Copy didn't stop in time (e.g. a single huge file mid-copy).
            // Detach instead of letting ~QObject delete a still-running
            // QThread, which Qt treats as a fatal error -- same reasoning
            // as LibraryModel's destructor.
            m_workerThread->setParent(nullptr);
        }
    }
}

// ── Worker thread ─────────────────────────────────────────────────────────

void PlaylistExportController::startWorkerThread()
{
    m_worker = new PlaylistExportWorker();
    m_workerThread = new QThread(this);
    m_worker->moveToThread(m_workerThread);

    connect(m_workerThread, &QThread::finished,
            m_worker, &QObject::deleteLater);

    connect(m_worker, &PlaylistExportWorker::progress,
            this, &PlaylistExportController::onWorkerProgress,
            Qt::QueuedConnection);
    connect(m_worker, &PlaylistExportWorker::finished,
            this, &PlaylistExportController::onWorkerFinished,
            Qt::QueuedConnection);

    connect(this, &PlaylistExportController::_requestExport,
            m_worker, &PlaylistExportWorker::runExport,
            Qt::QueuedConnection);

    m_workerThread->start();
}

void PlaylistExportController::onWorkerProgress(int done, int total, const QString &currentFileName,
                                                 double fraction, bool converting)
{
    // fraction = share of the current file already done, so a long conversion
    // moves the bar smoothly instead of in one jump per track.
    m_exportProgress = total > 0
        ? int((done + qBound(0.0, fraction, 1.0)) * 100.0 / total)
        : 100;
    emit exportProgressChanged();
    if (m_currentFileName != currentFileName) {
        m_currentFileName = currentFileName;
        emit currentFileNameChanged();
    }
    if (m_converting != converting) {
        m_converting = converting;
        emit convertingChanged();
    }
}

void PlaylistExportController::onWorkerFinished(const QVariantList &results)
{
    m_exporting = false;
    emit exportingChanged();
    m_exportProgress = 100;
    emit exportProgressChanged();
    m_currentFileName.clear();
    emit currentFileNameChanged();
    if (m_converting) {
        m_converting = false;
        emit convertingChanged();
    }
    emit exportFinished(results);
}

// ── Destination analysis ──────────────────────────────────────────────────

bool PlaylistExportController::isRemovableDrive(const QString &rootPath)
{
#ifdef Q_OS_WIN
    QString native = QDir::toNativeSeparators(rootPath);
    if (!native.endsWith(QLatin1Char('\\')))
        native += QLatin1Char('\\');
    const UINT type = GetDriveTypeW(reinterpret_cast<const wchar_t *>(native.utf16()));
    return type == DRIVE_REMOVABLE;
#else
    // No Linux equivalent implemented yet -- treat everything as a fixed
    // drive (harddisk icon) until the eventual Linux port adds a real check
    // (e.g. reading /sys/block/<dev>/removable).
    Q_UNUSED(rootPath);
    return false;
#endif
}

QVariantMap PlaylistExportController::analyzeDestination(const QString &destPath) const
{
    // Accept both plain paths and file:// URLs — same convention as
    // AppConfig::addFolder()/addMilkdropPresetFolder().
    const QUrl url(destPath);
    const QString path = url.isLocalFile() ? url.toLocalFile() : destPath;

    QVariantMap result;
    QDir dir(path);
    const bool exists = dir.exists();
    result[QStringLiteral("exists")] = exists;

    if (!exists) {
        result[QStringLiteral("writable")]    = false;
        result[QStringLiteral("isRemovable")] = false;
        result[QStringLiteral("volumeLabel")] = QString();
        result[QStringLiteral("freeBytes")]   = qint64(0);
        result[QStringLiteral("totalBytes")]  = qint64(0);
        return result;
    }

    QStorageInfo si(path);
    si.refresh();
    result[QStringLiteral("volumeLabel")] = si.name();
    result[QStringLiteral("freeBytes")]   = si.bytesAvailable();
    result[QStringLiteral("totalBytes")]  = si.bytesTotal();
    result[QStringLiteral("isRemovable")] = isRemovableDrive(si.rootPath());

    // Writability probe: create + immediately remove a hidden file, rather
    // than trusting QFileInfo::isWritable() alone (unreliable on some
    // network/FAT volumes) -- this is the concrete "no write permission"
    // detection in place of any UAC-elevation flow.
    QFile probe(dir.filePath(QStringLiteral(".topaz_write_test")));
    bool writable = probe.open(QIODevice::WriteOnly);
    if (writable) {
        probe.close();
        probe.remove();
    }
    result[QStringLiteral("writable")] = writable;

    return result;
}

qint64 PlaylistExportController::computeExportBytes(const QVariantList &tracks, bool convertToMp3) const
{
    constexpr qint64 kMp3BytesPerMs  = 40;          // 320 kbps = 40,000 bytes/s
    constexpr qint64 kTagCoverHeadroom = 1 << 20;   // ID3 tag + embedded cover art

    qint64 total = 0;
    for (const QVariant &v : tracks) {
        const QVariantMap track = v.toMap();
        const QFileInfo src(track.value(QStringLiteral("filePath")).toString());
        const qint64 durationMs = track.value(QStringLiteral("durationMs")).toLongLong();
        const bool isMp3 = src.suffix().compare(QLatin1String("mp3"), Qt::CaseInsensitive) == 0;

        if (convertToMp3 && !isMp3 && durationMs > 0)
            total += durationMs * kMp3BytesPerMs + kTagCoverHeadroom;
        else
            total += src.size();
    }
    return total;
}

bool PlaylistExportController::ffmpegAvailable() const
{
    return Mp3Converter::ffmpegUsable(Mp3Converter::findFfmpeg());
}

// ── Export ─────────────────────────────────────────────────────────────────

void PlaylistExportController::startExport(const QVariantList &tracks, const QString &destFolder,
                                            const QString &prefix, bool replayGainNormalization,
                                            double audiophileTrimDb, bool convertToMp3)
{
    if (m_exporting) return;

    m_exporting = true;
    emit exportingChanged();
    m_exportProgress = 0;
    emit exportProgressChanged();
    m_currentFileName.clear();
    emit currentFileNameChanged();

    emit _requestExport(tracks, destFolder, prefix, replayGainNormalization, audiophileTrimDb,
                         convertToMp3);
}

void PlaylistExportController::cancelExport()
{
    if (m_worker) m_worker->cancelExport();
}
