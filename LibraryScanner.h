#pragma once

#include "trackinfo.h"

#include <QObject>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <atomic>

class QFileSystemWatcher;
class QTimer;

// ── LibraryScanner ────────────────────────────────────────────────────────
// Worker object that lives on a dedicated QThread managed by LibraryModel.
//
// Two scan modes:
//   fullScan     — walks all configured folders, reads every audio file tag,
//                  deduplicates cover thumbnails per album, saves the cache.
//   statCheck    — quickly validates existing cache entries (file still
//                  exists, lastModified unchanged) and finds new / deleted
//                  files without re-reading unchanged tags.
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

    // Triggered by LibraryModel via queued connection.
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
    // Walks dirPath (recursively if recursive=true), finds *.mp3/*.flac files.
    // Appends scanned tracks to result; seenAlbums tracks one-per-album covers.
    // existingIds maps filePath → UUID for stable IDs across rescans.
    void scanDirectory(const QString              &dirPath,
                       bool                        recursive,
                       const QSet<QString>        &configuredGenresLower,
                       const QHash<QString,QUuid> &existingIds,
                       const QHash<QString,qint64>&existingModified,
                       const QHash<QString,TrackInfo> &existingCache,
                       QSet<QString>              &seenAlbums,
                       QList<TrackInfo>            &result,
                       int                        &done,
                       int                         total);

    void updateWatcher(const QStringList &rootDirs);

    QFileSystemWatcher *m_watcher       = nullptr;
    QTimer             *m_debounce      = nullptr;
    QStringList         m_lastGenres;
    QVariantList        m_lastFolders;
    QList<TrackInfo>    m_lastCache;
    std::atomic<bool>   m_cancelRequested{false};
};
