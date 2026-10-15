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
// Destination analysis (analyzeDestination/computeExportBytes) stays
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
    // True while the file currently being processed is converted to MP3
    // rather than copied -- the dialog shows "Converting:" instead of "Exporting:".
    Q_PROPERTY(bool    converting      READ converting      NOTIFY convertingChanged)
    // Result of the last export's "Create M3U Playlist" (UC-26): the written
    // file name ("" = not requested, or the export was cancelled) and whether
    // writing it succeeded. Updated right before exportFinished().
    Q_PROPERTY(QString m3uFileName     READ m3uFileName     NOTIFY m3uResultChanged)
    Q_PROPERTY(bool    m3uOk           READ m3uOk           NOTIFY m3uResultChanged)

public:
    explicit PlaylistExportController(QObject *parent = nullptr);
    ~PlaylistExportController() override;

    bool    exporting()       const { return m_exporting; }
    int     exportProgress()  const { return m_exportProgress; }
    QString currentFileName() const { return m_currentFileName; }
    bool    converting()      const { return m_converting; }
    QString m3uFileName()     const { return m_m3uFileName; }
    bool    m3uOk()           const { return m_m3uOk; }

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

    // Bytes the export of `tracks` ([{filePath, durationMs, ...}], the same
    // maps startExport() takes) will need at the destination. A file that is
    // copied counts its real size, queried live rather than trusting
    // TrackInfo::fileSize, which the in-memory queue never actually populates.
    // With convertToMp3, a non-MP3 track counts what its MP3 will take instead:
    // 320 kbps = 40 bytes per millisecond, plus 1 MiB of headroom for the tags
    // and cover art (an Opus file re-encoded at 320 kbps grows ~2.5x, so the
    // source size would badly underestimate it). Unknown duration falls back
    // to the source size.
    Q_INVOKABLE qint64 computeExportBytes(const QVariantList &tracks, bool convertToMp3) const;

    // True if an ffmpeg with the libmp3lame encoder can be found (next to the
    // app or on the PATH) -- what the "Convert to MP3" checkbox needs. See
    // Mp3Converter. Probes ffmpeg once per file (cached), so cheap to call
    // every time the dialog opens.
    Q_INVOKABLE bool ffmpegAvailable() const;

    // tracks: [{filePath, title, albumArtist, artist, album, durationMs}, ...]
    // in queue order (see PlaybackEngine::trackList()). No-op if an export is
    // already running. replayGainNormalization/audiophileTrimDb/convertToMp3/
    // alwaysMeasure/createM3u/playlistName: see PlaylistExportWorker::
    // runExport()'s doc comment (UC-26) -- all captured once here, at click
    // time, not live-bound.
    Q_INVOKABLE void startExport(const QVariantList &tracks, const QString &destFolder,
                                  const QString &prefix, bool replayGainNormalization = false,
                                  double audiophileTrimDb = 0.0, bool convertToMp3 = false,
                                  bool alwaysMeasure = false, bool createM3u = false,
                                  const QString &playlistName = QString());

    // Cooperative cancel -- see PlaylistExportWorker::cancelExport().
    Q_INVOKABLE void cancelExport();

signals:
    void exportingChanged();
    void exportProgressChanged();
    void currentFileNameChanged();
    void convertingChanged();
    void m3uResultChanged();

    // results: [{sourcePath, destPath, success, errorString, replayGainTagged,
    // converted}, ...]
    void exportFinished(const QVariantList &results);

    // Commands → worker thread (queued so they execute on the worker's event loop).
    void _requestExport(QVariantList tracks, QString destFolder, QString prefix,
                         bool replayGainNormalization, double audiophileTrimDb,
                         bool convertToMp3, bool alwaysMeasure,
                         bool createM3u, QString playlistName);

private slots:
    void onWorkerProgress(int done, int total, const QString &currentFileName,
                          double fraction, bool converting);
    void onWorkerFinished(const QVariantList &results, const QString &m3uFileName, bool m3uOk);

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
    bool    m_converting      = false;
    QString m_m3uFileName;
    bool    m_m3uOk           = false;
};
