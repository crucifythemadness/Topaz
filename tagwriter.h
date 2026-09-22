#pragma once

#include <QString>

// ── TagWriter ─────────────────────────────────────────────────────────────
// Writes ONLY a REPLAYGAIN_TRACK_GAIN (+ optionally _PEAK) tag into a file --
// backs UC-26's "Replay Gain Normalization" export option (ExportPlaylistDialog.qml
// / PlaylistExportWorker). filePath is always the EXPORT COPY, never a library
// original: Topaz's "never changes an audio track" rule is about the source
// library file, not a fresh copy the export itself just created. Every other
// byte of existing tag/comment/cover data in the file is preserved unchanged.
//
// Supports the same three formats TagReader::readReplayGain() reads: MP3
// (ID3v2 TXXX frame), FLAC (VORBIS_COMMENT block) and Opus (OpusTags packet,
// inside its Ogg container -- the one format needing a real container remux,
// since a size change there shifts every following page's sequence number and
// therefore its CRC -- see tagwriter.cpp). Dependency-free, like TagReader.
// Safe to call from any thread; each call replaces filePath via a temp file +
// atomic rename (same convention as VolumeNormalizationCache::save()).
class TagWriter
{
public:
    // gainDb is written as "+X.XX dB" / "-X.XX dB" (REPLAYGAIN_TRACK_GAIN).
    // peakLinear <= 0 skips writing a peak tag -- "unknown", the same
    // convention VolumeNormalizationCache::Entry::peak / TagReader::ReplayGain::
    // trackPeak already use.
    // Returns false when the format can't be safely rewritten -- the file is
    // then left completely untouched (not even partially written). Examples:
    // an unrecognized extension, an ID3v2 tag with the unsynchronization flag
    // set (TagReader doesn't decode that either), a malformed/truncated
    // container, or an Ogg/Opus file whose OpusTags packet shares a page with
    // another packet (real encoders never do this, but Topaz refuses to guess).
    static bool writeReplayGain(const QString &filePath, double gainDb, double peakLinear);

private:
    // gainValue/peakValue are already-formatted "REPLAYGAIN_TRACK_..." VALUE
    // strings ("+X.XX dB" / "X.XXXXXX"), not full "KEY=value" pairs -- each
    // per-format writer builds its own framing (an ID3v2 TXXX desc+value pair,
    // or a Vorbis-comment "KEY=value" entry) around them. peakValue is empty
    // when peakLinear <= 0 (skip writing that tag).
    static bool writeMp3(const QString &filePath, const QByteArray &gainValue, const QByteArray &peakValue);
    static bool writeFlac(const QString &filePath, const QByteArray &gainValue, const QByteArray &peakValue);
    static bool writeOpus(const QString &filePath, const QByteArray &gainValue, const QByteArray &peakValue);

    // Writes `data` to filePath via a "<filePath>.tmp" + atomic rename, same
    // pattern as VolumeNormalizationCache::save()/RatingCache.
    static bool atomicReplace(const QString &filePath, const QByteArray &data);
};
