#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <atomic>

// ── PlaylistExportWorker ─────────────────────────────────────────────────
// Worker object that lives on a dedicated QThread managed by
// PlaylistExportController -- mirrors LibraryScanner's worker-thread shape
// (see libraryscanner.h) so bulk audio-file copying never blocks the main
// thread, the way a multi-GB USB export otherwise would.
//
// All methods run on the worker thread; signals are delivered to the main
// thread via Qt's queued connection mechanism.
class PlaylistExportWorker : public QObject
{
    Q_OBJECT

public:
    explicit PlaylistExportWorker(QObject *parent = nullptr);

    // Thread-safe -- callable from any thread. Asks the running export to
    // stop before its next file instead of running to completion. Not a
    // slot: a queued call would never be processed while the worker thread
    // is busy inside runExport()'s loop.
    void cancelExport() { m_cancelRequested.store(true, std::memory_order_relaxed); }

public slots:
    // tracks: [{filePath, title}, ...] in queue order. Builds
    // "<prefix><index>_<title>.<ext>" per track (index zero-padded to
    // qMax(2, digits in tracks.size())) and copies each source file to
    // destFolder under that name, overwriting any leftover file from a
    // previous export attempt with the same name.
    void runExport(QVariantList tracks, QString destFolder, QString prefix);

signals:
    void progress(int done, int total, QString currentFileName);
    // results: [{sourcePath, destPath, success, errorString}, ...] --
    // truncated (not padded with skipped entries) if cancelExport() cut the
    // loop short.
    void finished(QVariantList results);

private:
    static QString sanitizeForFilename(const QString &name);

    std::atomic<bool> m_cancelRequested{false};
};
