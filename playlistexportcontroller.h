#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

class QThread;
class PlaylistExportWorker;

// ── PlaylistExportController ─────────────────────────────────────────────
// Backs ExportPlaylistDialog.qml -- see UC-26 in the architecture doc.
// Analyzes a chosen destination folder (free space, writability, whether
// it's a removable USB drive or a fixed HDD/SSD) and, once the user
// confirms, copies the current queue's audio files there with a generated
// "<prefix><index>_<title>.<ext>" filename.
//
// The actual file copy runs on a dedicated worker QThread (PlaylistExportWorker),
// mirroring LibraryModel/LibraryScanner's moveToThread() pattern rather than
// MilkdropCleanupController's main-thread processEvents() pump -- copying
// multi-GB of audio is exactly the kind of file I/O that would visibly
// freeze the UI if done on the main thread, unlike the small per-file
// stat/delete work those two do.
//
// Destination analysis (analyzeDestination/computeRequiredBytes) stays
// synchronous on the main thread -- it's just a handful of QFileInfo/
// QStorageInfo stat calls, the same scale of work MilkdropCleanupController::
// presetFolders() already does synchronously.
//
// Instantiated once in Main.qml (same convention as every other stateful
// QML_ELEMENT controller in this app).
class PlaylistExportController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool    exporting       READ exporting       NOTIFY exportingChanged)
    Q_PROPERTY(int     exportProgress  READ exportProgress  NOTIFY exportProgressChanged)
    Q_PROPERTY(QString currentFileName READ currentFileName NOTIFY currentFileNameChanged)

public:
    explicit PlaylistExportController(QObject *parent = nullptr);
    ~PlaylistExportController() override;

    bool    exporting()       const { return m_exporting; }
    int     exportProgress()  const { return m_exportProgress; }
    QString currentFileName() const { return m_currentFileName; }

    // Returns { exists, writable, isRemovable, volumeLabel, freeBytes, totalBytes }
    // for destPath. writable is determined by actually creating and removing
    // a hidden probe file (QFileInfo::isWritable() alone can be wrong on some
    // network/FAT volumes) -- this, not UAC elevation, is how Topaz answers
    // "what if we can't write to the destination": detect it up front and
    // block EXPORT with a clear reason instead of prompting for admin rights.
    // isRemovable is Windows-only for now (GetDriveTypeW); always false
    // (treated as a fixed drive) on other platforms until a Linux port adds
    // a real equivalent -- see the future_linux_port tracking note.
    Q_INVOKABLE QVariantMap analyzeDestination(const QString &destPath) const;

    // Sums QFileInfo(path).size() for each entry in filePaths. Queried live
    // rather than trusting TrackInfo::fileSize, which the in-memory queue
    // never actually populates.
    Q_INVOKABLE qint64 computeRequiredBytes(const QVariantList &filePaths) const;

    // tracks: [{filePath, title, albumArtist, artist, album}, ...] in queue
    // order (see PlaybackEngine::trackList()). No-op if an export is already
    // running. replayGainNormalization/audiophileTrimDb: see
    // PlaylistExportWorker::runExport()'s doc comment (UC-26) -- both are
    // captured once here, at click time, not live-bound.
    Q_INVOKABLE void startExport(const QVariantList &tracks, const QString &destFolder,
                                  const QString &prefix, bool replayGainNormalization = false,
                                  double audiophileTrimDb = 0.0);

    // Cooperative cancel -- see PlaylistExportWorker::cancelExport().
    Q_INVOKABLE void cancelExport();

signals:
    void exportingChanged();
    void exportProgressChanged();
    void currentFileNameChanged();

    // results: [{sourcePath, destPath, success, errorString}, ...]
    void exportFinished(const QVariantList &results);

    // Commands → worker thread (queued so they execute on the worker's event loop).
    void _requestExport(QVariantList tracks, QString destFolder, QString prefix,
                         bool replayGainNormalization, double audiophileTrimDb);

private slots:
    void onWorkerProgress(int done, int total, const QString &currentFileName);
    void onWorkerFinished(const QVariantList &results);

private:
    void startWorkerThread();

    // Windows-only removable-drive check (GetDriveTypeW). Always returns
    // false elsewhere -- see the class comment above.
    static bool isRemovableDrive(const QString &rootPath);

    QThread               *m_workerThread = nullptr;
    PlaylistExportWorker   *m_worker       = nullptr;

    bool    m_exporting       = false;
    int     m_exportProgress  = 0;
    QString m_currentFileName;
};
