#pragma once

#include "trackinfo.h"
#include <QHash>
#include <QString>
#include <QUuid>

// ── RatingCache ───────────────────────────────────────────────────────────
// Reads and writes Topaz.rating.json alongside Topaz.config / Topaz.library.json.
// Stores user ratings independently of the scanned library, so a full library
// rebuild (rescan) never loses them. Only rated tracks (rating 1-10) are persisted;
// unrated tracks (rating 0) are never written.
//
// JSON schema  (version 1):
// {
//   "version": 1,
//   "ratings": [
//     { "genre": "Techno", "ratingId": "uuid-string", "rating": 8 }, ...
//   ]
// }
class RatingCache
{
public:
    // Absolute path to Topaz.rating.json in AppConfigLocation.
    static QString cacheFilePath();

    // Load and deserialise the cache as ratingId -> rating (1-10).
    // Returns an empty hash on any error. Entries with an invalid ratingId or a
    // rating outside 1-10 are skipped.
    static QHash<QUuid, int> load();

    // Serialise and write the cache atomically (write to .tmp, then rename).
    // Full overwrite — only tracks with rating in [1,10] are written. Intended for
    // LibraryScanner's bulk enrichment pass, which always has the complete,
    // authoritative current track list. Returns true on success.
    static bool save(const QList<TrackInfo> &tracks);

    // Insert or update a single track's rating (upsert by ratingId) and persist
    // immediately, preserving every other track's existing rating. Intended for a
    // single user action (e.g. clicking a star in NowPlaying). Returns false if
    // ratingId is null or rating is outside 1-10.
    static bool setRating(const QString &genre, const QUuid &ratingId, int rating);

private:
    struct Entry { QString genre; QUuid ratingId; int rating; };

    static QList<Entry> loadEntries();
    static bool saveEntries(const QList<Entry> &entries);
};
