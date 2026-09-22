#pragma once

#include <QHash>
#include <QList>
#include <QString>
#include <QUuid>

// ── VolumeNormalizationCache ──────────────────────────────────────────────
// Reads and writes Topaz.volumeNormalization.json alongside Topaz.rating.json /
// Topaz.config: the per-track loudness correction ("Auto Loudness Correction",
// UC-35) once it has been determined, so it is only ever determined once.
//
// Format:
//   { "version": 1,
//     "normalizations": [
//       { "genre": "Synthwave",
//         "normalizationId": "2e01a9cc-7ee7-5048-adec-1a8526c856d8",
//         "dB": -1.2,
//         "source": "tag" | "measured",
//         "peak": 0.98,          // linear sample peak, 0 = unknown
//         "fileSize": 12345678   // bytes of the file it was determined for
//       }, ... ] }
//
// normalizationId is TrackInfo::computeNormalizationId() (UUIDv5 of
// "albumArtist;artist;album;title", the same identity Topaz.rating.json uses).
// source/peak/fileSize are additions beyond the id + dB pair: fileSize makes an
// entry stale when the file was replaced or re-tagged by an external tool
// (e.g. a ReplayGain tag was added), so the value is re-determined instead of
// a wrong one being trusted forever; peak lets a boost be capped so it never
// clips.
//
// Unlike RatingCache (one rating per user click, load-modify-save each time)
// thousands of entries get added as a library is analysed, so this class only
// offers whole-file load/save; LoudnessAnalyzer keeps the entries in memory and
// flushes them debounced. Topaz never writes to an audio file -- this JSON is
// the only thing the feature persists.
class VolumeNormalizationCache
{
public:
    struct Entry {
        QString genre;
        QUuid   id;
        double  dB       = 0.0;
        QString source;          // "tag" or "measured"
        double  peak     = 0.0;  // linear, 0 = unknown
        qint64  fileSize = 0;
    };

    // Absolute path to Topaz.volumeNormalization.json in AppConfigLocation.
    static QString cacheFilePath();

    // Empty hash on any error/missing file. Entries with a null id or a dB
    // outside a sane range are skipped defensively.
    static QHash<QUuid, Entry> load();

    // Atomic replace (write .tmp, then rename), same as RatingCache.
    static bool save(const QHash<QUuid, Entry> &entries);
};
