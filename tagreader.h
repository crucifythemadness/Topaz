#pragma once

#include "trackinfo.h"

#include <QFile>

// ── TagReader ─────────────────────────────────────────────────────────────
// Lightweight, dependency-free audio tag reader.
// Supports:
//   • MP3  – ID3v2.2, ID3v2.3, ID3v2.4  (text frames + APIC cover)
//           – MPEG frame header for bitrate; Xing/Info VBR header for duration
//   • FLAC – STREAMINFO (duration), VORBIS_COMMENT (tags), PICTURE (cover)
//
// All file I/O is synchronous and intentionally minimal: only the bytes needed
// to fill TrackInfo are read.  Safe to call from any thread.
class TagReader
{
public:
    // Read tags from one audio file and return a filled TrackInfo.
    // filePath, fileName, fileSize, lastModified are set from QFileInfo.
    // albumArtist falls back to artist when TPE2/ALBUMARTIST is absent.
    // title falls back to the base-name when the TIT2/TITLE frame is absent.
    //
    // generateCoverThumb: set false to skip cover extraction entirely.
    // When true, a 160×160 JPEG thumbnail is base64-encoded into coverThumb
    // if embedded art is found.  Pass false for non-representative album tracks
    // to avoid redundant image processing.
    static TrackInfo read(const QString &filePath, bool generateCoverThumb = true);

    // Extract the raw (full-resolution) embedded cover art from a file.
    // Returns the image bytes as-is (JPEG or PNG), or an empty QByteArray if
    // no embedded cover is found. Safe to call from any thread.
    static QByteArray readRawCover(const QString &filePath);

private:
    // Returns the byte offset of the first MPEG audio frame (= end of ID3 tag).
    static bool readId3v2(QFile &f, TrackInfo &info,
                          bool generateCoverThumb, qint64 &id3End);

    static bool readFlac(QFile &f, TrackInfo &info, bool generateCoverThumb);

    // Estimate MP3 duration from MPEG frame header / Xing VBR header.
    static void estimateMp3Duration(QFile &f, qint64 audioStart, TrackInfo &info);

    // Decode a 4-byte ID3v2 syncsafe integer (each byte uses 7 bits).
    static quint32 syncsafeToInt(const uchar *buf);

    // Decode an ID3v2 text frame (encoding byte + content).
    static QString decodeTextFrame(const QByteArray &data);

    // Parse TCON genre string: strip "(N)" numeric genre codes, return text form.
    static QString parseGenreTcon(const QString &raw);

    // Parse APIC frame payload; returns raw image bytes (empty on failure).
    static QByteArray parseApicFrame(const QByteArray &data, quint8 id3Version);

    // Scale imageData to a 160×160 JPEG and return it as a base64 string.
    static QString makeCoverThumb(const QByteArray &imageData);
};
