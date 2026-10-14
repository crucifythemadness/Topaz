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
// QFileSystemWatcher watches root-level configured directories, plus each
// one's own parent directory (so a configured folder being deleted itself
// is detected too -- see UC-07 for why the parent is needed), at runtime;
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

    // Triggered by LibraryModel::rescanFolderContaining() (see UC-31) when a
    // queued track's file turns out to be missing right before playback --
    // rescans only scanOnlyFolderPath's contents while every other
    // configured folder's cached entries are carried through untouched
    // (see performScan()'s doc comment). `folders` must still be the
    // *complete* configured folder list -- needed both to determine which
    // cached entries fall outside the scanned folder and to keep
    // updateWatcher() covering everything, not just the one folder.
    void scanFolder(QStringList genres,
                     QVariantList folders,
                     QList<TrackInfo> existingCache,
                     QString scanOnlyFolderPath);

signals:
    // Emitted as the very first thing performScan() does, regardless of
    // which public slot (fullScan/statCheck/scanFolder) triggered it --
    // the single choke point that lets LibraryModel know a scan is
    // actually running even for triggers it didn't initiate itself (the
    // file-system-watcher's debounced auto-rescan, see UC-07). The three
    // LibraryModel-initiated triggers already set scanning=true
    // optimistically before this signal even arrives (instant feedback
    // for a manual click); this just closes the one gap where nothing did.
    void scanStarted();
    void scanProgress(int done, int total);
    void scanCompleted(QList<TrackInfo> tracks);

    // ── Visual Folder Scanning (Setup > MISC, opt-in) ────────────────────
    // scanningFolder reuses a checkpoint that already exists rather than
    // adding any new per-file cost: fires once per directory visited (from
    // discoverAudioFiles(), already one call per folder, not per file). A
    // naive per-file signal would mean 12,000+ cross-thread queued-signal
    // posts for a full library scan; this stays within a few thousand at
    // most, regardless of library size.
    void scanningFolder(const QString &path);

    // Emitted once, right after the discover/classify/tag-read phase ends
    // and before the two remaining steps that scanProgress never covers --
    // resolveCoverArt() and LibraryCache::save() (the latter especially:
    // writing a large Topaz.library.json, base64 cover thumbnails included,
    // is real, otherwise-invisible time on every scan). Lets a progress
    // dialog show it's still doing real work instead of sitting at a
    // premature 100% while nothing visibly happens.
    void scanFinalizing();

private slots:
    void onDirectoryChanged(const QString &path);
    void onDebounceTimeout();

private:
    // Shared implementation behind fullScan()/statCheck()/scanFolder(). See
    // class comment. scanOnlyFolderPath empty (fullScan/statCheck) scans
    // every folder in `folders`, exactly as before. Non-empty (scanFolder,
    // UC-31) skips discovery for every OTHER folder and instead carries its
    // existingCache entries through unchanged, so the result never loses
    // tracks from folders outside the requested scope -- see .cpp for why
    // performScan couldn't safely be called with a trimmed `folders` list
    // directly.
    void performScan(QStringList genres, QVariantList folders,
                      QList<TrackInfo> existingCache,
                      const QString &scanOnlyFolderPath = QString());

    // Recursively lists every *.mp3/*.flac/*.opus file under dirPath. Pure
    // filesystem listing, no tag reads — stays sequential (fast compared to
    // TagReader::read(), so parallelizing it wouldn't move the needle).
    // Not const: emits scanningFolder() once per directory visited (Visual
    // Folder Scanning, Setup > MISC).
    QList<QFileInfo> discoverAudioFiles(const QString &dirPath, bool recursive);

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
