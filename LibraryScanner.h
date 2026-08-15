#pragma once

#include "trackinfo.h"

#include <QObject>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <atomic>

class QFileInfo;
class QFileSystemWatcher;
class QThreadPool;
class QTimer;

// ── LibraryScanner ────────────────────────────────────────────────────────
// Worker object that lives on a dedicated QThread managed by LibraryModel.
//
// Two scan modes:
//   fullScan     — triggered by the user's rescan button.
//   statCheck    — triggered by app startup and by the debounced
//                  QFileSystemWatcher callback.
// Both are thin wrappers around the shared performScan() pipeline — they've
// always had near-identical "walk configured folders, reuse unchanged cached
// entries verbatim, read the rest" semantics; the only difference is which
// caller triggers them.
//
// performScan(): discover every audio file currently on disk in the
// configured folders (discoverAudioFiles()), classify each against the
// existing cache (reuse verbatim if present + unchanged + still genre-
// matching, else queue for a fresh tag read), read the queued set in
// parallel over a bounded QThreadPool (readTagsParallel()), then resolve
// album cover art in one order-independent pass (resolveCoverArt()). See
// libraryscanner.cpp for why this replaced the old fully-sequential,
// order-dependent scanDirectory().
//
// QFileSystemWatcher watches root-level configured directories at runtime;
// any change triggers a debounced (2 s) stat-check.
//
// All methods run on the worker thread; signals are delivered to the main
// thread via Qt's queued connection mechanism.
class LibraryScanner : public QObject
{
    Q_OBJECT

public:
    explicit LibraryScanner(QObject *parent = nullptr);
    ~LibraryScanner() override;

    // Thread-safe — callable from any thread (including from LibraryModel's
    // destructor while fullScan()/statCheck() is running on the worker thread).
    // Asks the running scan to stop at its next checkpoint instead of running
    // to completion. Not a slot: a queued call would never be processed while
    // the worker thread is busy inside a long-running scan loop.
    void cancelScan() { m_cancelRequested.store(true, std::memory_order_relaxed); }

public slots:
    // Called once when the thread starts – creates watcher + debounce timer.
    void onThreadStarted();

    // Triggered by LibraryModel via queued connection. Both delegate to
    // performScan() — see the class comment above.
    void fullScan(QStringList  genres,
                  QVariantList folders,
                  QList<TrackInfo> existingCache);

    void statCheck(QStringList  genres,
                   QVariantList folders,
                   QList<TrackInfo> existingCache);

signals:
    void scanProgress(int done, int total);
    void scanCompleted(QList<TrackInfo> tracks);

private slots:
    void onDirectoryChanged(const QString &path);
    void onDebounceTimeout();

private:
    // Shared implementation behind fullScan()/statCheck(). See class comment.
    void performScan(QStringList genres, QVariantList folders,
                      QList<TrackInfo> existingCache);

    // Recursively lists every *.mp3/*.flac/*.opus file under dirPath. Pure
    // filesystem listing, no tag reads — stays sequential (fast compared to
    // TagReader::read(), so parallelizing it wouldn't move the needle).
    QList<QFileInfo> discoverAudioFiles(const QString &dirPath, bool recursive) const;

    // Reads tags (no cover) for every path in `paths` in parallel over `pool`,
    // in chunks — checks m_cancelRequested and emits scanProgress(done, total)
    // between chunks, keeping cancellation/progress granularity close to the
    // old per-file feel without cross-thread per-item progress counters.
    QList<TrackInfo> readTagsParallel(const QStringList &paths, QThreadPool &pool,
                                       int &done, int total);

    // Deduplicates album cover thumbnails across `tracks`: for every
    // (albumArtist, album) pair with no coverThumb anywhere in `tracks` yet,
    // deterministically picks the entry with the lexicographically smallest
    // filePath as representative (order-independent, unlike the old
    // "whoever's processed first" — which only worked because that loop was
    // strictly sequential), re-reads just those representatives in parallel
    // over `pool` with cover extraction enabled, and splices the result back in.
    void resolveCoverArt(QList<TrackInfo> &tracks, QThreadPool &pool);

    void updateWatcher(const QStringList &rootDirs);

    QFileSystemWatcher *m_watcher       = nullptr;
    QTimer             *m_debounce      = nullptr;
    QStringList         m_lastGenres;
    QVariantList        m_lastFolders;
    QList<TrackInfo>    m_lastCache;
    std::atomic<bool>   m_cancelRequested{false};
};
