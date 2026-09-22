#include "tagwriter.h"

#include <QFile>
#include <QFileInfo>
#include <QList>

#include <algorithm>
#include <cstring>

namespace {

// ── Little/big-endian helpers ────────────────────────────────────────────

quint32 leU32(const uchar *p)
{
    return quint32(p[0]) | (quint32(p[1]) << 8) | (quint32(p[2]) << 16) | (quint32(p[3]) << 24);
}
void putLeU32(QByteArray &out, quint32 v)
{
    out.append(char(v & 0xFF)); out.append(char((v >> 8) & 0xFF));
    out.append(char((v >> 16) & 0xFF)); out.append(char((v >> 24) & 0xFF));
}
quint32 beU32(const uchar *p)
{
    return (quint32(p[0]) << 24) | (quint32(p[1]) << 16) | (quint32(p[2]) << 8) | quint32(p[3]);
}
void putBeU24(QByteArray &out, quint32 v)   // FLAC metadata-block-header length
{
    out.append(char((v >> 16) & 0xFF)); out.append(char((v >> 8) & 0xFF)); out.append(char(v & 0xFF));
}
// Extracts the ASCII-range bytes of an ID3v2 text string, for the sole
// purpose of a case-insensitive compare against a known ASCII key (never
// used to display the value). enc 0 (Latin-1) / 3 (UTF-8) are ASCII-
// compatible as-is; enc 1 (UTF-16 with a BOM, either endianness) and enc 2
// (UTF-16BE, no BOM) are down-sampled to their low byte per code unit.
QByteArray id3AsciiKey(const QByteArray &raw, quint8 enc)
{
    if (enc == 0 || enc == 3) return raw;
    if (enc == 1 || enc == 2) {
        bool little = (enc == 1);
        int start = 0;
        if (enc == 1 && raw.size() >= 2) {
            if (uchar(raw[0]) == 0xFF && uchar(raw[1]) == 0xFE) { little = true;  start = 2; }
            else if (uchar(raw[0]) == 0xFE && uchar(raw[1]) == 0xFF) { little = false; start = 2; }
        }
        QByteArray out;
        for (int i = start + (little ? 0 : 1); i < raw.size(); i += 2) out += raw[i];
        return out;
    }
    return raw;
}

// ID3v2 syncsafe (7 bits/byte, matches TagReader::syncsafeToInt's decoder).
quint32 syncsafeToInt(const uchar *p)
{
    return (quint32(p[0]) << 21) | (quint32(p[1]) << 14) | (quint32(p[2]) << 7) | quint32(p[3]);
}
void putSyncsafe(QByteArray &out, quint32 v)
{
    out.append(char((v >> 21) & 0x7F)); out.append(char((v >> 14) & 0x7F));
    out.append(char((v >> 7) & 0x7F));  out.append(char(v & 0x7F));
}

// ── Vorbis-comment-style list (shared by FLAC + Opus) ────────────────────
// "KEY=value" entries, case-insensitive key compare on removal, exact bytes
// otherwise preserved.

struct CommentList {
    QByteArray vendor;
    QList<QByteArray> comments;
};

// pos indexes into `data`; matches TagReader's scanVorbisCommentsForGain()
// layout (vendor length+string, then count x (length+"KEY=value")).
bool parseCommentList(const QByteArray &data, int pos, CommentList &out)
{
    auto need = [&](int n) { return pos + n <= data.size(); };
    if (!need(4)) return false;
    const quint32 vendorLen = leU32(reinterpret_cast<const uchar *>(data.constData() + pos));
    pos += 4;
    if (!need(int(vendorLen))) return false;
    out.vendor = data.mid(pos, int(vendorLen));
    pos += int(vendorLen);

    if (!need(4)) return false;
    const quint32 count = leU32(reinterpret_cast<const uchar *>(data.constData() + pos));
    pos += 4;
    for (quint32 i = 0; i < count; ++i) {
        if (!need(4)) return false;
        const quint32 len = leU32(reinterpret_cast<const uchar *>(data.constData() + pos));
        pos += 4;
        if (len > 64u * 1024u * 1024u || !need(int(len))) return false;
        out.comments.append(data.mid(pos, int(len)));
        pos += int(len);
    }
    return true;
}

QByteArray serializeCommentList(const CommentList &c)
{
    QByteArray out;
    putLeU32(out, quint32(c.vendor.size()));
    out += c.vendor;
    putLeU32(out, quint32(c.comments.size()));
    for (const QByteArray &comment : c.comments) {
        putLeU32(out, quint32(comment.size()));
        out += comment;
    }
    return out;
}

// Drops any existing REPLAYGAIN_TRACK_GAIN/_PEAK entries (case-insensitive
// key), then appends the fresh values. dropR128 additionally strips an
// R128_TRACK_GAIN comment -- Opus's own native convention (TagReader::
// readReplayGain() PREFERS it over REPLAYGAIN_TRACK_GAIN for .opus files), so
// a stale one left in place would silently shadow the value this function
// just wrote (found via the tagwriter harness against a real file that had
// one -- see the memory note).
void replaceGainComments(CommentList &c, const QByteArray &gainValue, const QByteArray &peakValue,
                          bool dropR128 = false)
{
    QList<QByteArray> kept;
    kept.reserve(c.comments.size() + 2);
    for (const QByteArray &comment : c.comments) {
        const int eq = comment.indexOf('=');
        const QByteArray key = (eq > 0 ? comment.left(eq) : comment).toUpper();
        if (key == "REPLAYGAIN_TRACK_GAIN" || key == "REPLAYGAIN_TRACK_PEAK") continue;
        if (dropR128 && key == "R128_TRACK_GAIN") continue;
        kept.append(comment);
    }
    kept.append(QByteArray("REPLAYGAIN_TRACK_GAIN=") + gainValue);
    if (!peakValue.isEmpty())
        kept.append(QByteArray("REPLAYGAIN_TRACK_PEAK=") + peakValue);
    c.comments = kept;
}

// ── Ogg CRC32 (RFC 3533 / libogg's ogg_page_checksum_set) ────────────────
// Poly 0x04c11db7, MSB-first, no reflection, no final XOR, init 0. Verified
// (see the tagwriter harness) against real pages' own stored CRC before this
// code ever writes one.

quint32 oggCrcTable[256];
bool oggCrcTableInit = false;

void initOggCrcTable()
{
    for (int i = 0; i < 256; ++i) {
        quint32 crc = quint32(i) << 24;
        for (int j = 0; j < 8; ++j)
            crc = (crc & 0x80000000u) ? ((crc << 1) ^ 0x04c11db7u) : (crc << 1);
        oggCrcTable[i] = crc;
    }
    oggCrcTableInit = true;
}

quint32 oggCrc32(const uchar *data, int len)
{
    if (!oggCrcTableInit) initOggCrcTable();
    quint32 crc = 0;
    for (int i = 0; i < len; ++i)
        crc = (crc << 8) ^ oggCrcTable[((crc >> 24) & 0xFF) ^ data[i]];
    return crc;
}

// Fills in an Ogg page's CRC field (bytes 22..25) in place, with that field
// zeroed during the calculation as the spec requires.
void setOggPageCrc(QByteArray &page)
{
    std::memset(page.data() + 22, 0, 4);
    const quint32 crc = oggCrc32(reinterpret_cast<const uchar *>(page.constData()), page.size());
    page[22] = char(crc & 0xFF); page[23] = char((crc >> 8) & 0xFF);
    page[24] = char((crc >> 16) & 0xFF); page[25] = char((crc >> 24) & 0xFF);
}

} // namespace

// ── Public entry point ───────────────────────────────────────────────────

bool TagWriter::writeReplayGain(const QString &filePath, double gainDb, double peakLinear)
{
    const QByteArray gainValue = QByteArray(QByteArray::number(gainDb, 'f', 2));
    QByteArray signedGain = gainValue;
    if (gainDb >= 0.0 && !signedGain.startsWith('+')) signedGain.prepend('+');
    signedGain += " dB";
    const QByteArray peakValue = peakLinear > 0.0
        ? QByteArray::number(peakLinear, 'f', 6) : QByteArray();

    const QString ext = QFileInfo(filePath).suffix().toLower();
    if (ext == QLatin1String("mp3"))  return writeMp3(filePath, signedGain, peakValue);
    if (ext == QLatin1String("flac")) return writeFlac(filePath, signedGain, peakValue);
    if (ext == QLatin1String("opus")) return writeOpus(filePath, signedGain, peakValue);
    return false;
}

bool TagWriter::atomicReplace(const QString &filePath, const QByteArray &data)
{
    const QString tmpPath = filePath + QStringLiteral(".tmp");
    QFile tmp(tmpPath);
    if (!tmp.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    const qint64 written = tmp.write(data);
    tmp.close();
    if (written != data.size()) { QFile::remove(tmpPath); return false; }

    QFile::remove(filePath);
    if (!tmp.rename(filePath)) { QFile::remove(tmpPath); return false; }
    return true;
}

// ── MP3 (ID3v2) ───────────────────────────────────────────────────────────
// Only ID3v2.3/2.4 tags are rewritten (TXXX frame layout differs in v2.2 --
// 3-char ids, no per-frame flags -- rare enough in practice to just decline).
// An unsynchronized tag is declined too, for the same reason TagReader never
// decodes one either: safer to leave the file untouched than guess wrong.

bool TagWriter::writeMp3(const QString &filePath, const QByteArray &gainValue, const QByteArray &peakValue)
{
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly)) return false;
    const QByteArray orig = f.readAll();
    f.close();
    if (orig.size() < 10) return false;

    const uchar *hdr = reinterpret_cast<const uchar *>(orig.constData());
    bool hasTag = (hdr[0] == 'I' && hdr[1] == 'D' && hdr[2] == '3' && hdr[3] >= 2 && hdr[3] != 0xFF);

    QByteArray extHeaderBytes;
    QList<QByteArray> keptFrames;   // each element: whole frame incl. its own header
    qint64 audioStart = 0;
    quint8 version = 3;

    if (hasTag) {
        version = hdr[3];
        if (version < 3) return false;              // ID3v2.2 -- declined, see comment above
        if (hdr[5] & 0x80) return false;             // unsynchronized -- declined
        const quint32 tagSize = syncsafeToInt(hdr + 6);
        if (tagSize == 0 || qint64(tagSize) > orig.size() - 10) return false;
        audioStart = 10 + qint64(tagSize);
        const QByteArray tag = orig.mid(10, int(tagSize));

        int pos = 0;
        if ((hdr[5] & 0x40) && tag.size() >= 4) {    // extended header -- kept verbatim, unparsed
            const uchar *e = reinterpret_cast<const uchar *>(tag.constData());
            // v2.4's extended-header-size field is syncsafe and already
            // counts itself; v2.3's is a plain BE32 that does NOT, hence +4
            // (matches TagReader::readReplayGain's identical calculation).
            const quint32 extLen = (version == 4) ? syncsafeToInt(e) : (beU32(e) + 4);
            pos = int(extLen);
            if (pos < 0 || pos > tag.size()) return false;
            extHeaderBytes = tag.left(pos);
        }

        const int frameHdrLen = 10;   // v2.3/2.4: 4-byte id + 4-byte size + 2-byte flags
        while (pos + frameHdrLen <= tag.size()) {
            const uchar *fh = reinterpret_cast<const uchar *>(tag.constData()) + pos;
            if (fh[0] == 0) break;    // padding begins
            const QByteArray id = tag.mid(pos, 4);
            const quint32 fsize = (version == 4) ? syncsafeToInt(fh + 4) : beU32(fh + 4);
            const int frameTotal = frameHdrLen + int(fsize);
            if (fsize == 0 || pos + frameTotal > tag.size()) break;

            bool drop = false;
            if (id == "TXXX" && fsize >= 2) {
                // Decode just enough to read the description (encoding byte +
                // NUL-terminated desc) -- same layout takeTxxxFrame() reads.
                const QByteArray body = tag.mid(pos + frameHdrLen, int(fsize));
                const quint8 enc = quint8(body[0]);
                const bool wide = (enc == 1 || enc == 2);
                int descEnd = -1;
                if (wide) {
                    for (int i = 1; i + 1 < body.size(); i += 2)
                        if (body[i] == 0 && body[i + 1] == 0) { descEnd = i; break; }
                } else {
                    descEnd = body.indexOf('\0', 1);
                }
                if (descEnd > 0) {
                    const QByteArray key = id3AsciiKey(body.mid(1, descEnd - 1), enc).trimmed().toUpper();
                    if (key == "REPLAYGAIN_TRACK_GAIN" || key == "REPLAYGAIN_TRACK_PEAK") drop = true;
                }
            }
            if (!drop) keptFrames.append(tag.mid(pos, frameTotal));
            pos += frameTotal;
        }
    }

    // Build the new TXXX frame(s), always Latin-1 (encoding 0) -- the value
    // is plain ASCII, valid unchanged across ID3v2.2 through 2.4 readers.
    auto buildTxxx = [&](const QByteArray &desc, const QByteArray &value) {
        QByteArray body;
        body.append(char(0));           // encoding: Latin-1
        body += desc; body.append(char(0));
        body += value;
        QByteArray frame = "TXXX";
        if (version == 4) putSyncsafe(frame, quint32(body.size()));
        else { frame.append(char((body.size() >> 24) & 0xFF)); frame.append(char((body.size() >> 16) & 0xFF));
               frame.append(char((body.size() >> 8) & 0xFF)); frame.append(char(body.size() & 0xFF)); }
        frame.append(char(0)); frame.append(char(0));   // flags
        frame += body;
        return frame;
    };

    QByteArray newTagBody = extHeaderBytes;
    for (const QByteArray &fr : std::as_const(keptFrames)) newTagBody += fr;
    newTagBody += buildTxxx("REPLAYGAIN_TRACK_GAIN", gainValue);
    if (!peakValue.isEmpty()) newTagBody += buildTxxx("REPLAYGAIN_TRACK_PEAK", peakValue);

    if (newTagBody.size() >= (1 << 28)) return false;   // won't fit in a syncsafe size

    QByteArray out;
    out.reserve(10 + newTagBody.size() + int(orig.size() - audioStart));
    out += "ID3";
    out.append(char(hasTag ? version : 3));
    out.append(char(0));                 // revision
    out.append(char(0));                 // flags (never unsynchronized, no ext header re-emitted)
    putSyncsafe(out, quint32(newTagBody.size()));
    out += newTagBody;
    out += orig.mid(int(audioStart));    // exact original audio bytes, verbatim

    return atomicReplace(filePath, out);
}

// ── FLAC (VORBIS_COMMENT metadata block) ─────────────────────────────────
// Always a full, simple rebuild of the metadata-block region (STREAMINFO +
// any other blocks, unchanged, plus the rewritten VORBIS_COMMENT) followed by
// the exact original audio-frame bytes -- no attempt to reuse an existing
// PADDING block's space in place; correctness over the extra few KB written.

bool TagWriter::writeFlac(const QString &filePath, const QByteArray &gainValue, const QByteArray &peakValue)
{
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly)) return false;
    const QByteArray orig = f.readAll();
    f.close();
    if (orig.size() < 4 || orig.left(4) != QByteArray("fLaC", 4)) return false;

    struct Block { quint8 type; QByteArray data; };
    QList<Block> blocks;
    int pos = 4;
    int commentIdx = -1;
    while (true) {
        if (pos + 4 > orig.size()) return false;
        const uchar *bh = reinterpret_cast<const uchar *>(orig.constData() + pos);
        const bool   last = (bh[0] & 0x80) != 0;
        const quint8 type = bh[0] & 0x7F;
        const quint32 len = (quint32(bh[1]) << 16) | (quint32(bh[2]) << 8) | quint32(bh[3]);
        pos += 4;
        if (pos + int(len) > orig.size()) return false;
        if (type == 4) commentIdx = blocks.size();
        blocks.append({ type, orig.mid(pos, int(len)) });
        pos += int(len);
        if (last) break;
    }
    const int audioStart = pos;

    CommentList c;
    if (commentIdx >= 0) {
        if (!parseCommentList(blocks[commentIdx].data, 0, c)) return false;
    } else {
        c.vendor = "Topaz";   // new block -- no prior vendor string to preserve
    }
    replaceGainComments(c, gainValue, peakValue);
    const QByteArray newCommentData = serializeCommentList(c);
    if (newCommentData.size() >= (1 << 24)) return false;   // won't fit a 24-bit block length

    if (commentIdx >= 0) {
        blocks[commentIdx].data = newCommentData;
    } else {
        // STREAMINFO (type 0) must be blocks[0] -- insert the new comment
        // block right after it, the conventional placement.
        if (blocks.isEmpty() || blocks[0].type != 0) return false;
        blocks.insert(1, { 4, newCommentData });
    }

    QByteArray out;
    out.reserve(4 + orig.size() - audioStart + newCommentData.size());
    out += "fLaC";
    for (int i = 0; i < blocks.size(); ++i) {
        const bool isLast = (i == blocks.size() - 1);
        const Block &b = blocks.at(i);
        if (b.data.size() >= (1 << 24)) return false;
        out.append(char((isLast ? 0x80 : 0x00) | (b.type & 0x7F)));
        putBeU24(out, quint32(b.data.size()));
        out += b.data;
    }
    out += orig.mid(audioStart);   // exact original audio frames, verbatim

    return atomicReplace(filePath, out);
}

// ── Opus (OpusTags packet, inside its Ogg container) ─────────────────────
// Scope, deliberately narrow: OpusHead (page 0, verbatim) is untouched. The
// OpusTags packet -- assumed (like TagReader::readOpus()/readOggPacket()
// already assume) to occupy page(s) 1..k with nothing else sharing page k --
// is rebuilt and re-paged. Every following page is then byte-identical
// EXCEPT its page_sequence_number (which must stay contiguous) and therefore
// its CRC (which covers the whole header). Declines (returns false, file
// untouched) on anything outside that shape: a second logical stream, a
// truncated/malformed page chain, or a page sharing OpusTags with audio.

namespace {

struct OggPage {
    qint64 fileOffset;
    QByteArray raw;               // this page's exact original bytes
    quint8  headerType;
    quint32 serial;
    quint32 seq;
    QList<quint8> segments;
    QByteArray payload;
};

bool readOggPage(const QByteArray &data, int pos, OggPage &page)
{
    if (pos + 27 > data.size()) return false;
    const uchar *h = reinterpret_cast<const uchar *>(data.constData() + pos);
    if (std::memcmp(h, "OggS", 4) != 0 || h[4] != 0) return false;
    page.headerType = h[5];
    page.serial = leU32(h + 14);
    page.seq    = leU32(h + 18);
    const quint8 segCount = h[26];
    if (pos + 27 + segCount > data.size()) return false;
    const uchar *segTable = h + 27;
    int payloadLen = 0;
    page.segments.clear();
    for (int i = 0; i < segCount; ++i) { page.segments.append(segTable[i]); payloadLen += segTable[i]; }
    const int headerLen = 27 + segCount;
    if (pos + headerLen + payloadLen > data.size()) return false;
    page.payload = data.mid(pos + headerLen, payloadLen);
    page.raw = data.mid(pos, headerLen + payloadLen);
    page.fileOffset = pos;
    return true;
}

// Packs `packet` into one or more fresh Ogg pages (255-byte lacing), starting
// at page_sequence_number `firstSeq`. `continued` is true when this packet is
// itself a continuation of one ending mid-page on a PRECEDING page (never the
// case here -- OpusTags always starts a fresh page) -- kept as a parameter
// for clarity/symmetry rather than hardcoding 0 inline.
QList<QByteArray> packPages(const QByteArray &packet, quint32 serial, quint32 firstSeq)
{
    QList<QByteArray> pages;
    int offset = 0;
    quint32 seq = firstSeq;
    const int maxPayload = 255 * 255;
    while (true) {
        const int remaining = packet.size() - offset;
        const int chunk = std::min(remaining, maxPayload);
        const bool isLastChunk = (offset + chunk >= packet.size());

        QList<quint8> segs;
        int left = chunk;
        while (left >= 255) { segs.append(255); left -= 255; }
        // A packet ending exactly on a 255-byte segment still needs a
        // terminating value (0) so decoders don't read it as "continues".
        if (isLastChunk) segs.append(quint8(left));
        else if (left > 0) segs.append(quint8(left));   // shouldn't happen (chunk is a multiple of 255 unless last)

        QByteArray page;
        page += "OggS";
        page.append(char(0));                                    // version
        page.append(char(offset > 0 ? 0x01 : 0x00));              // continued flag
        for (int i = 0; i < 8; ++i) page.append(char(0));         // granule position = 0
        putLeU32(page, serial);
        putLeU32(page, seq);
        putLeU32(page, 0);                                        // CRC placeholder
        page.append(char(segs.size()));
        for (quint8 s : segs) page.append(char(s));
        page += packet.mid(offset, chunk);
        setOggPageCrc(page);
        pages.append(page);

        offset += chunk;
        ++seq;
        if (isLastChunk) break;
    }
    return pages;
}

} // namespace

bool TagWriter::writeOpus(const QString &filePath, const QByteArray &gainValue, const QByteArray &peakValue)
{
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly)) return false;
    const QByteArray orig = f.readAll();
    f.close();

    OggPage head;
    if (!readOggPage(orig, 0, head)) return false;
    if (!(head.headerType & 0x02)) return false;                 // must be BOS
    if (head.payload.size() < 8 || head.payload.left(8) != QByteArray("OpusHead", 8)) return false;
    const quint32 serial = head.serial;

    // Assemble the OpusTags packet from page 1 onward; bail on anything that
    // doesn't match the narrow shape documented above.
    QByteArray tagsPacket;
    int pos = int(head.raw.size());
    int pagesConsumed = 0;
    quint32 expectedSeq = 1;
    bool foundEnd = false;
    while (!foundEnd) {
        OggPage p;
        if (!readOggPage(orig, pos, p)) return false;
        if (p.serial != serial || p.seq != expectedSeq) return false;   // multiplexed/gappy stream -- decline
        for (int i = 0; i < p.segments.size(); ++i) {
            const quint8 lac = p.segments.at(i);
            const int already = [&]{ int s = 0; for (int j = 0; j < i; ++j) s += p.segments.at(j); return s; }();
            tagsPacket += p.payload.mid(already, lac);
            if (lac < 255) {
                if (i != p.segments.size() - 1) return false;   // another packet trails on this page -- decline
                foundEnd = true;
            }
        }
        pos += int(p.raw.size());
        ++pagesConsumed;
        ++expectedSeq;
        if (pagesConsumed > 64) return false;   // sanity bound -- a comment header this large is not realistic
    }
    if (tagsPacket.size() < 8 || tagsPacket.left(8) != QByteArray("OpusTags", 8)) return false;

    CommentList c;
    if (!parseCommentList(tagsPacket, 8, c)) return false;
    replaceGainComments(c, gainValue, peakValue, /*dropR128=*/true);

    QByteArray newPacket = "OpusTags";
    newPacket += serializeCommentList(c);

    const QList<QByteArray> newPages = packPages(newPacket, serial, 1);
    // Signed: the new tags packet can need FEWER pages than the original
    // (e.g. a long stale tag replaced by a short one), so this can be
    // negative -- an unsigned subtraction here would silently wrap around
    // into a huge page_sequence_number for the rest of the stream.
    const qint64 seqDelta = qint64(newPages.size()) - qint64(expectedSeq - 1);

    QByteArray out;
    out.reserve(orig.size() + int(newPacket.size()));
    out += head.raw;
    for (const QByteArray &pg : newPages) out += pg;

    // Every remaining page, byte-identical except page_sequence_number (and
    // therefore its CRC, which covers the whole header).
    int rest = pos;
    while (rest < orig.size()) {
        OggPage p;
        if (!readOggPage(orig, rest, p)) return false;
        // A second logical stream (chained/multiplexed Ogg) has its own,
        // independent page numbering -- our seqDelta only applies to the
        // Opus stream we just re-paged, so decline rather than guess.
        if (p.serial != serial) return false;
        QByteArray page = p.raw;
        const quint32 newSeq = quint32(qint64(p.seq) + seqDelta);
        page[18] = char(newSeq & 0xFF); page[19] = char((newSeq >> 8) & 0xFF);
        page[20] = char((newSeq >> 16) & 0xFF); page[21] = char((newSeq >> 24) & 0xFF);
        setOggPageCrc(page);
        out += page;
        rest += int(p.raw.size());
    }

    return atomicReplace(filePath, out);
}
