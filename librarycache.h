#pragma once

#include "trackinfo.h"
#include <QString>

// ── LibraryCache ──────────────────────────────────────────────────────────
// Reads and writes Topaz.library.json alongside Topaz.config.
//
// JSON schema  (version 1):
// {
//   "version": 1,
//   "tracks": [
//     {
//       "id":           "uuid-string",
//       "filePath":     "/absolute/path/track.flac",
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
//       "fileSize":     12345678,
//       "lastModified": 1234567890123,
//       "coverThumb":   "base64...",
//       "rating":       0,
//       "ratingId":     "uuid-string"
//     }, ...
//   ]
// }
class LibraryCache
{
public:
    // Absolute path to Topaz.library.json in AppConfigLocation.
    static QString cacheFilePath();

    // Load and deserialise the cache.  Returns an empty list on any error.
    static QList<TrackInfo> load();

    // Serialise and write the cache atomically (write to .tmp, then rename).
    // Returns true on success.
    static bool save(const QList<TrackInfo> &tracks);
};
