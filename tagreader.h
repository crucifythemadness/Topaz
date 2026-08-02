#pragma once

#include "trackinfo.h"

#include <QFile>

// ── TagReader ─────────────────────────────────────────────────────────────
// Lightweight, dependency-free audio tag reader.
// Supports:
//   • MP3  – ID3v2.2, ID3v2.3, ID3v2.4  (text frames + APIC cover)
//           – MPEG frame header for bitrate; Xing/Info VBR header for duration
//   • FLAC – STREAMINFO (duration), VORBIS_COMMENT (tags), PICTURE (cover)
//   • Opus – Ogg container; OpusHead packet (pre-skip, for duration) +
//           OpusTags packet (Vorbis-comment-style tags, same field layout as
//           FLAC's VORBIS_COMMENT); duration derived from the last Ogg page's
//           granule position minus pre-skip; cover art via the
//           METADATA_BLOCK_PICTURE comment convention (base64 of the same
//           binary layout as FLAC's PICTURE block)
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

    static bool readOpus(QFile &f, TrackInfo &info, bool generateCoverThumb);

    // Reads one Ogg page's fixed header + segment table starting at the
    // file's current position. Returns false at EOF or on an invalid capture
    // pattern (i.e. not "OggS"). On success, the file position is left at the
    // start of the page's packet data; dataSize is the total payload size
    // (sum of the segment table) and granulePos is the page's granule
    // position field, both needed by readOpus() to locate packets and to
    // track duration across the whole stream. continuesPacket is true when
    // the segment table's last lacing value is 255 — the packet occupying
    // the end of this page is not yet complete and continues on the next
    // page (see readOggPacket()).
    static bool readOggPageHeader(QFile &f, quint32 &dataSize, qint64 &granulePos,
                                   bool &continuesPacket);

    // Reads one full logical Ogg packet, transparently concatenating page
    // payloads for as long as readOggPageHeader()'s continuesPacket is true.
    // Needed because a single page's payload is capped at ~64KB (255
    // segments x 255 bytes) — the OpusTags packet routinely exceeds that
    // once it embeds cover art, and would otherwise be silently truncated.
    // granulePos is left at the last page's granule position. Returns an
    // empty QByteArray on any read failure.
    static QByteArray readOggPacket(QFile &f, qint64 &granulePos);

    // Parses a FLAC-METADATA_BLOCK_PICTURE-formatted byte block (picture
    // type, MIME string, description string, dimensions, data length, data)
    // and returns the raw image bytes. Shared because this exact binary
    // layout is used both by FLAC's native PICTURE block and by Opus/Vorbis's
    // METADATA_BLOCK_PICTURE comment (once base64-decoded) — not incidental
    // duplication, the spec mandates the same layout in both places.
    static QByteArray parsePictureBlock(const QByteArray &block);

    // Always determines bitrate from the first MPEG frame header (ID3v2 has no
    // dedicated bitrate frame). Also fills in duration from the Xing/Info VBR
    // header or a CBR estimate, but only when info.duration is not already known
    // (e.g. from an ID3v2 TLEN frame read earlier).
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
