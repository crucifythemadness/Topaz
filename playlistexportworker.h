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
    // tracks: [{filePath, title, albumArtist, artist, album, durationMs}, ...]
    // in queue order (albumArtist/artist/album are only needed when
    // replayGainNormalization is true, durationMs only for the progress of a
    // conversion -- see below). Builds "<prefix><index>_<title>.<ext>" per
    // track (index zero-padded to qMax(2, digits in tracks.size())) and copies
    // each source file to destFolder under that name, overwriting any leftover
    // file from a previous export attempt with the same name.
    //
    // convertToMp3 (UC-26 "Convert to MP3"): when true, every source that is
    // not already an .mp3 is converted (Mp3Converter -- an external ffmpeg,
    // 44.1 kHz / stereo / CBR 320 kbps) into the destination instead of
    // copied, and gets the extension ".mp3". MP3 sources are still copied
    // untouched. The source file is only ever read. A failed conversion is a
    // failed track like a failed copy (the loop continues); cancelExport()
    // kills a running ffmpeg and removes its partial file.
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
    // alwaysMeasure (AppConfig::loudnessAlwaysMeasure, the stored value even
    // while Auto Loudness Correction is off): skips the existing-tag tier and
    // tag-sourced cache entries, same as playback.
    void runExport(QVariantList tracks, QString destFolder, QString prefix,
                    bool replayGainNormalization, double audiophileTrimDb,
                    bool convertToMp3, bool alwaysMeasure);

signals:
    // fraction: 0..1 share of the CURRENT file already done (only a conversion
    // reports anything between 0 and 1; a copy stays 0 until the next file).
    // converting: the current file is being converted rather than copied.
    void progress(int done, int total, QString currentFileName, double fraction, bool converting);
    // results: [{sourcePath, destPath, success, errorString, replayGainTagged,
    // converted}, ...] -- truncated (not padded with skipped entries) if
    // cancelExport() cut the loop short. replayGainTagged is always false when
    // replayGainNormalization was off; converted is true only for a track that
    // was successfully converted to MP3.
    void finished(QVariantList results);

private:
    static QString sanitizeForFilename(const QString &name);

    std::atomic<bool> m_cancelRequested{false};
};
