#pragma once

#include <QString>
#include <atomic>
#include <functional>

// ── Mp3Converter ──────────────────────────────────────────────────────────
// Converts one audio file (FLAC / Opus / anything ffmpeg reads) to MP3 --
// 44.1 kHz, stereo, CBR 320 kbps, always -- by running an external `ffmpeg`
// program. Used only by PlaylistExportWorker (UC-26 "Convert to MP3"), on its
// worker thread, and only ever WRITES the destination file passed in; the
// source is opened read-only by ffmpeg.
//
// Why an external program: the FFmpeg that Qt Multimedia ships with Topaz is
// libraries only (no command line tool, no headers) and has no LAME MP3
// encoder -- Windows has just the Media Foundation wrapper, Linux no MP3
// encoder at all. So, exactly like the BASS libraries, ffmpeg is supplied by
// the user and never bundled: next to Topaz.exe / topaz-bin, or on the PATH.
namespace Mp3Converter {

// Path of the ffmpeg to use, or an empty string if there is none: a copy
// next to the application first, then the system PATH. Cheap (a couple of
// stat calls) -- callers re-evaluate it whenever they need it, so a file
// dropped in while Topaz is running is picked up.
QString findFfmpeg();

// True if the ffmpeg at `ffmpegPath` runs and has the libmp3lame encoder (an
// ffmpeg built without it would fail every single track). Runs
// `ffmpeg -encoders` once per (path, size, mtime) and caches the answer, so
// repeated calls are free. Blocking for up to a few seconds the first time.
bool ffmpegUsable(const QString &ffmpegPath);

struct Outcome
{
    bool    ok        = false;
    bool    cancelled = false;   // `cancel` was raised; the partial file is already deleted
    QString error;               // ffmpeg's last diagnostic line, when !ok && !cancelled
};

// Converts srcPath -> destPath (overwriting it). Blocks until done; tags and
// the embedded cover art are carried over (ID3v2.3). `durationMs` (0 = unknown)
// only scales the progress. `onFraction(0..1)` is called a couple of times per
// second with the share of this file done. `cancel` is polled about ten times
// per second; when it turns true ffmpeg is killed and the partial destination
// file removed. A failed conversion never leaves a partial destination file.
Outcome convert(const QString &ffmpegPath, const QString &srcPath, const QString &destPath,
                qint64 durationMs, const std::atomic<bool> &cancel,
                const std::function<void(double)> &onFraction);

} // namespace Mp3Converter
