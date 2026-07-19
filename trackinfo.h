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
    int     bitrate      = 0;   // kbps
    qint64  fileSize     = 0;   // bytes
    qint64  lastModified = 0;   // QDateTime::toMSecsSinceEpoch

    // Base64-encoded JPEG thumbnail 160×160.
    // Only populated for one representative track per (albumArtist, album) pair;
    // all other tracks in the same album store an empty string.
    QString coverThumb;
};

Q_DECLARE_METATYPE(TrackInfo)
// QList<TrackInfo> is auto-handled by Qt 6 metatype system once TrackInfo is registered.
