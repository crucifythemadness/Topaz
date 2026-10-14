#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <atomic>

class QThread;

// ── Genre discovery scan (UC-36) ──────────────────────────────────────────
// Setup -> GENRES -> SCAN FOLDERS: reads the genre tag of every audio file in
// the ACTIVE monitored folders and reports which genres exist, with a track
// count each, so the user can pick genres to add (FoundGenresDialog.qml)
// instead of typing them exactly as tagged.
//
// Why a scan of its own: Topaz.library.json only holds files whose genre is
// already configured, so it can never reveal a new genre -- every file's tags
// have to be read. The file listing and the tag reading are the library
// scan's own (LibraryScanner::listAudioFiles(), TagReader::read(), same chunk
// size and pool cap), so both scans see the same files and the same genre
// values -- TagReader already reduces a multi-genre tag to its first genre,
// exactly the value the library matches against.
//
// Runs on its own worker thread, not LibraryScanner's: it must neither wait
// behind a running library scan nor trigger the library's scan signals
// (scanning state, Visual Folder Scanning dialog). Same controller/worker
// shape as PlaylistExportController/PlaylistExportWorker.

class GenreScanWorker : public QObject
{
    Q_OBJECT

public:
    explicit GenreScanWorker(QObject *parent = nullptr) : QObject(parent) {}

    // Thread-safe (not a slot -- a queued call couldn't run while the worker
    // is busy). The scan stops at its next checkpoint (per folder visited
    // while listing, per chunk of 200 files while reading tags).
    void cancel() { m_cancel.store(true, std::memory_order_relaxed); }
    // Called by the controller right before it queues a new scan -- not by
    // runScan() itself, or a STOP pressed before the worker picked the scan
    // up would be wiped out and ignored.
    void resetCancel() { m_cancel.store(false, std::memory_order_relaxed); }

public slots:
    // folders: [{path, includeSubfolders}] -- already filtered by the controller.
    void runScan(QVariantList folders);

signals:
    // done/total = files whose tags have been read / all files found.
    // genres = [{name, count}], sorted case-insensitively, deduplicated
    // case-insensitively (the spelling first seen wins). Emitted after every
    // chunk, so newly found genres show up while the scan is still running.
    void progress(int done, int total, QVariantList genres, int withoutGenre);
    void finished(QVariantList genres, int withoutGenre, int total, bool cancelled);

private:
    std::atomic<bool> m_cancel{false};
};

class GenreScanController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool         scanning          READ scanning          NOTIFY stateChanged)
    // True while the files are still being listed (no total known yet).
    Q_PROPERTY(bool         listing           READ listing           NOTIFY stateChanged)
    Q_PROPERTY(int          filesDone         READ filesDone         NOTIFY stateChanged)
    Q_PROPERTY(int          filesTotal        READ filesTotal        NOTIFY stateChanged)
    Q_PROPERTY(int          progress          READ progress          NOTIFY stateChanged)
    Q_PROPERTY(QVariantList genres            READ genres            NOTIFY genresChanged)
    Q_PROPERTY(int          filesWithoutGenre READ filesWithoutGenre NOTIFY stateChanged)
    // True if the last scan was stopped before reading every file.
    Q_PROPERTY(bool         cancelled         READ cancelled         NOTIFY stateChanged)

public:
    explicit GenreScanController(QObject *parent = nullptr);
    ~GenreScanController() override;

    bool         scanning()          const { return m_scanning; }
    bool         listing()           const { return m_listing; }
    int          filesDone()         const { return m_filesDone; }
    int          filesTotal()        const { return m_filesTotal; }
    int          progress()          const;
    QVariantList genres()            const { return m_genres; }
    int          filesWithoutGenre() const { return m_filesWithoutGenre; }
    bool         cancelled()         const { return m_cancelled; }

    // folders: AppConfig.folders as-is. Only entries that are ACTIVE (default
    // true) and available (volume connected, non-empty path) are scanned;
    // includeSubfolders is honoured. Called while a scan is still running, it
    // stops that one and starts this one as soon as it has ended.
    Q_INVOKABLE void startScan(const QVariantList &folders);
    Q_INVOKABLE void cancelScan();

    // True if at least one entry of `folders` would be scanned by startScan()
    // -- drives whether Setup's SCAN FOLDERS button is enabled.
    Q_INVOKABLE bool hasScannableFolder(const QVariantList &folders) const;

signals:
    void stateChanged();
    void genresChanged();
    void scanFinished();

    void _requestScan(QVariantList folders);   // -> worker thread (queued)

private slots:
    void onWorkerProgress(int done, int total, const QVariantList &genres, int withoutGenre);
    void onWorkerFinished(const QVariantList &genres, int withoutGenre, int total, bool cancelled);

private:
    static QVariantList scannableFolders(const QVariantList &folders);

    QThread         *m_thread = nullptr;
    GenreScanWorker *m_worker = nullptr;

    bool         m_scanning  = false;
    bool         m_listing   = false;
    bool         m_cancelled = false;
    int          m_filesDone  = 0;
    int          m_filesTotal = 0;
    int          m_filesWithoutGenre = 0;
    QVariantList m_genres;

    bool         m_restartPending = false;   // see startScan()
    QVariantList m_pendingFolders;
};
