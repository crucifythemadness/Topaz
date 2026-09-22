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
    // tracks: [{filePath, title, albumArtist, artist, album}, ...] in queue
    // order (the last three are only needed when replayGainNormalization is
    // true -- see below). Builds "<prefix><index>_<title>.<ext>" per track
    // (index zero-padded to qMax(2, digits in tracks.size())) and copies each
    // source file to destFolder under that name, overwriting any leftover
    // file from a previous export attempt with the same name.
    //
    // replayGainNormalization (UC-26): when true, after each successful copy
    // a REPLAYGAIN_TRACK_GAIN tag is written into the COPY (never the source)
    // via TagWriter, using the same reference-determination fallback UC-35's
    // Audiophile strategy uses (Topaz.volumeNormalization.json -> an existing
    // tag -> a fresh BASS measurement) plus audiophileTrimDb, captured once
    // here rather than live-read per track. A track whose reference can't be
    // determined is still copied successfully, just left untagged. Any newly
    // discovered/measured entries are merged back into
    // Topaz.volumeNormalization.json once, at the end of the whole export.
    void runExport(QVariantList tracks, QString destFolder, QString prefix,
                    bool replayGainNormalization, double audiophileTrimDb);

signals:
    void progress(int done, int total, QString currentFileName);
    // results: [{sourcePath, destPath, success, errorString, replayGainTagged}, ...]
    // -- truncated (not padded with skipped entries) if cancelExport() cut the
    // loop short. replayGainTagged is always false when replayGainNormalization
    // was off.
    void finished(QVariantList results);

private:
    static QString sanitizeForFilename(const QString &name);

    std::atomic<bool> m_cancelRequested{false};
};
