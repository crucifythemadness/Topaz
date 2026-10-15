#pragma once

#include <QMetaType>
#include <QString>
#include <QUuid>

// ── TrackInfo ─────────────────────────────────────────────────────────────
// Flat record representing one scanned audio file.
// Combines AudioFile + ID3Info from the architecture class diagram into a
// cache-friendly struct. Genre, AlbumArtist and Album are plain strings
// (no separate entity objects) for version-1 simplicity.
//
// Stored as the primary element in Topaz.library.json.
// Transferred across the scan-thread boundary via queued Qt signals.
struct TrackInfo
{
    QUuid   id;              // stable UUID – generated on first scan, preserved in cache
    QString filePath;        // absolute path to the audio file
    QString fileName;        // base-name only
    QString title;
    QString artist;          // ID3: TPE1 / Vorbis: ARTIST
    QString albumArtist;     // ID3: TPE2 / Vorbis: ALBUMARTIST  (falls back to artist)
    QString album;
    QString genre;           // raw tag value – casing as found in the file
    int     track        = 0;
    int     year         = 0;
    qint64  duration     = 0;   // milliseconds
    int     bitrate      = 0;   // kbps (VBR MP3: average)
    bool    vbr          = false;   // MP3 only: Xing/VBRI header found (NowPlaying "VBR"/"CBR")
    qint64  fileSize     = 0;   // bytes
    qint64  lastModified = 0;   // QDateTime::toMSecsSinceEpoch

    // Base64-encoded JPEG thumbnail 160×160.
    // Only populated for one representative track per (genre, albumArtist, album)
    // triple — genre included so a same-named album filed under two different
    // genres gets its own cover instead of colliding into one slot; all other
    // tracks in the same album (and genre) store an empty string.
    QString coverThumb;

    int    rating   = 0;     // user rating 1-10; 0 = not rated yet
    QUuid  ratingId;         // deterministic identity for Topaz.rating.json persistence

    // Runtime-only hint for PlaybackQueue's "new track" flicker (see
    // UC-16) -- never persisted to Topaz.library.json or an XSPF file
    // (LibraryCache and PlaylistManager never touch this field). Always
    // false except briefly on a track PlaybackEngine::addTrack() just
    // added on AutoPlayController's behalf.
    bool   autoPlayAdded = false;

    // Deterministic (repeatable) UUIDv5 identity so ratings survive a full library
    // rebuild/rescan. Recomputed by LibraryScanner whenever a track's tags are (re-)read;
    // if albumArtist/artist/album/title change later, this — and the link to any existing
    // rating — changes too, the same way every other derived track property already does.
    static QUuid computeRatingId(const QString &albumArtist, const QString &artist,
                                  const QString &album, const QString &title)
    {
        // Fixed, hardcoded namespace — must never change, or every existing ratingId
        // would stop matching previously-persisted ratings.
        static const QUuid kRatingNamespace(
            QStringLiteral("{2f8e6a4c-0f1d-4a3b-9c2e-5b7d1a9e3f6b}"));
        const QString key = albumArtist + QChar(';') + artist + QChar(';')
                           + album + QChar(';') + title;
        return QUuid::createUuidV5(kRatingNamespace, key.toUtf8());
    }

    // Identity of a track in Topaz.volumeNormalization.json (Auto Loudness
    // Correction, UC-35): deliberately the very same UUIDv5 of
    // "albumArtist;artist;album;title" as the ratingId, so a track has one
    // stable identity across both files. A separate name because the two files
    // are independent (the JSON field is called "normalizationId").
    static QUuid computeNormalizationId(const QString &albumArtist, const QString &artist,
                                         const QString &album, const QString &title)
    {
        return computeRatingId(albumArtist, artist, album, title);
    }
};

Q_DECLARE_METATYPE(TrackInfo)
// QList<TrackInfo> is auto-handled by Qt 6 metatype system once TrackInfo is registered.
