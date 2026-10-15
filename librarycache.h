#pragma once

#include "trackinfo.h"
#include <QString>

// ── LibraryCache ──────────────────────────────────────────────────────────
// Reads and writes Topaz.library.json alongside Topaz.config.
//
// JSON schema  (version 3):
// {
//   "version": 3,
//   "tracks": [
//     {
//       "id":           "uuid-string",
//       "volume":       "MusicDrive",
//       "relPath":      "/Music/track.flac",
//       "rawPath":      "D:/Music/track.flac",
//       "fileName":     "track.flac",
//       "title":        "Track Title",
//       "artist":       "Artist Name",
//       "albumArtist":  "Album Artist",
//       "album":        "Album Name",
//       "genre":        "Techno",
//       "track":        1,
//       "year":         2010,
//       "duration":     234000,
//       "bitrate":      320,
//       "vbr":          false,
//       "fileSize":     12345678,
//       "lastModified": 1234567890123,
//       "coverThumb":   "base64...",
//       "rating":       0,
//       "ratingId":     "uuid-string"
//     }, ...
//   ]
// }
//
// "volume"/"relPath"/"rawPath" replace what used to be a single absolute
// "filePath" — see volumepath.h (VolumePath). load() resolves each entry's
// in-memory TrackInfo::filePath via VolumePath::quickPath(), a zero-
// filesystem-I/O match against currently mounted volumes: load() runs
// synchronously on the main thread for an instant startup UI, at up to
// 12K+ tracks, so it must never call QFileInfo::exists() per track — real
// existence verification happens in the async statCheck that always follows
// immediately after (see LibraryModel::loadCacheAndStartStatCheck()).
//
// Version history: 3 (Topaz 1.1.0) = VBR MP3s store their average bitrate
// (TagReader::estimateMp3Duration()) and a "vbr" flag; version 1 (1.0.0)
// stored the first frame's bitrate (version 2 was a 1.1.0 development step
// without "vbr"). Loading a file older than version 3 zeroes lastModified on
// every .mp3 entry, so that statCheck re-reads those tags once (ids kept,
// ratings re-applied); the next save() writes version 3 and nothing is
// re-read again.
class LibraryCache
{
public:
    // Absolute path to Topaz.library.json in AppConfigLocation.
    static QString cacheFilePath();

    // Load and deserialise the cache.  Returns an empty list on any error.
    // Tracks whose volume can't be matched among currently mounted volumes
    // are silently skipped (see quickPath() note above).
    static QList<TrackInfo> load();

    // Serialise and write the cache atomically (write to .tmp, then rename).
    // Returns true on success.
    static bool save(const QList<TrackInfo> &tracks);
};
