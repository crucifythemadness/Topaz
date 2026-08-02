#include "tagreader.h"

#include <QBuffer>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QStringDecoder>

// ── ID3v1 genre table (192 entries) ──────────────────────────────────────
static const char *const kId3v1Genres[] = {
    "Blues","Classic Rock","Country","Dance","Disco","Funk","Grunge","Hip-Hop",
    "Jazz","Metal","New Age","Oldies","Other","Pop","R&B","Rap","Reggae","Rock",
    "Techno","Industrial","Alternative","Ska","Death Metal","Pranks","Soundtrack",
    "Euro-Techno","Ambient","Trip-Hop","Vocal","Jazz+Funk","Fusion","Trance",
    "Classical","Instrumental","Acid","House","Game","Sound Clip","Gospel","Noise",
    "Alternative Rock","Bass","Soul","Punk","Space","Meditative","Instrumental Pop",
    "Instrumental Rock","Ethnic","Gothic","Darkwave","Techno-Industrial","Electronic",
    "Pop-Folk","Eurodance","Dream","Southern Rock","Comedy","Cult","Gangsta","Top 40",
    "Christian Rap","Pop/Funk","Jungle","Native US","Cabaret","New Wave","Psychedelic",
    "Rave","Showtunes","Trailer","Lo-Fi","Tribal","Acid Punk","Acid Jazz","Polka",
    "Retro","Musical","Rock & Roll","Hard Rock",
    // Winamp extensions 80+
    "Folk","Folk-Rock","National Folk","Swing","Fast Fusion","Bebob","Latin","Revival",
    "Celtic","Bluegrass","Avantgarde","Gothic Rock","Progressive Rock","Psychedelic Rock",
    "Symphonic Rock","Slow Rock","Big Band","Chorus","Easy Listening","Acoustic","Humour",
    "Speech","Chanson","Opera","Chamber Music","Sonata","Symphony","Booty Bass","Primus",
    "Porn Groove","Satire","Slow Jam","Club","Tango","Samba","Folklore","Ballad",
    "Power Ballad","Rhythmic Soul","Freestyle","Duet","Punk Rock","Drum Solo","A cappella",
    "Euro-House","Dance Hall","Goa","Drum & Bass","Club-House","Hardcore","Terror","Indie",
    "BritPop","Negerpunk","Polsk Punk","Beat","Christian Gangsta Rap","Heavy Metal",
    "Black Metal","Crossover","Contemporary Christian","Christian Rock","Merengue","Salsa",
    "Thrash Metal","Anime","JPop","Synthpop",
    // ID3v2.4 extensions 148+
    "Abstract","Art Rock","Baroque","Bhangra","Big beat","Breakbeat","Chillout",
    "Downtempo","Dub","EBM","Eclectic","Electro","Electroclash","Emo","Experimental",
    "Garage","Global","IDM","Illbient","Industro-Goth","Jam Band","Krautrock",
    "Leftfield","Lounge","Math Rock","New Romantic","Nu-Breakz","Post-Punk","Post-Rock",
    "Psytrance","Shoegaze","Space Rock","Trop Rock","World Music","Neoclassical",
    "Audiobook","Audio Theatre","Neue Deutsche Welle","Podcast","Indie-Rock","G-Funk",
    "Dubstep","Garage Rock","Psybient"
};
static const int kId3v1GenreCount =
    static_cast<int>(sizeof(kId3v1Genres) / sizeof(kId3v1Genres[0]));

// ── Helpers ───────────────────────────────────────────────────────────────

quint32 TagReader::syncsafeToInt(const uchar *buf)
{
    return (quint32(buf[0]) << 21) | (quint32(buf[1]) << 14) |
           (quint32(buf[2]) <<  7) |  quint32(buf[3]);
}

QString TagReader::decodeTextFrame(const QByteArray &data)
{
    if (data.isEmpty()) return {};

    const quint8 enc = static_cast<quint8>(data[0]);
    QByteArray content = data.mid(1);

    // Strip trailing null bytes / null pairs
    if (enc == 0x01 || enc == 0x02) {
        while (content.size() >= 2
               && content[content.size()-1] == '\0'
               && content[content.size()-2] == '\0')
            content.chop(2);
    } else {
        while (!content.isEmpty() && content.back() == '\0')
            content.chop(1);
    }

    switch (enc) {
    case 0x00: return QString::fromLatin1(content);
    case 0x01: { auto d = QStringDecoder(QStringDecoder::Utf16);    return d(content); }
    case 0x02: { auto d = QStringDecoder(QStringDecoder::Utf16BE);  return d(content); }
    case 0x03: return QString::fromUtf8(content);
    default:   return QString::fromUtf8(content);
    }
}

QString TagReader::parseGenreTcon(const QString &raw)
{
    QString s = raw.trimmed();
    if (!s.isEmpty() && s[0] == '(') {
        const int close = s.indexOf(')');
        if (close > 0) {
            const QString after = s.mid(close + 1).trimmed();
            if (!after.isEmpty()) return after;          // "(N)Text" → Text
            const int n = s.mid(1, close - 1).toInt();
            if (n >= 0 && n < kId3v1GenreCount)
                return QString::fromLatin1(kId3v1Genres[n]);
        }
    }
    return s;
}

QByteArray TagReader::parseApicFrame(const QByteArray &data, quint8 /*id3Version*/)
{
    if (data.size() < 4) return {};
    const quint8 enc = static_cast<quint8>(data[0]);
    int pos = 1;

    // MIME type — always ASCII, single-byte null terminated
    while (pos < data.size() && data[pos] != '\0') ++pos;
    ++pos; // skip null

    if (pos >= data.size()) return {};
    // picture type: 3 = front cover (accept any)
    /*quint8 picType =*/ static_cast<quint8>(data[pos++]);

    // Skip description (encoding-aware null terminator)
    if (enc == 0x01 || enc == 0x02) {
        while (pos + 1 < data.size()
               && !(data[pos] == '\0' && data[pos+1] == '\0'))
            ++pos;
        pos += 2;
    } else {
        while (pos < data.size() && data[pos] != '\0') ++pos;
        ++pos;
    }

    if (pos >= data.size()) return {};
    return data.mid(pos);
}

QString TagReader::makeCoverThumb(const QByteArray &imageData)
{
    QImage img;
    if (!img.loadFromData(imageData) || img.isNull()) return {};

    // Scale to exactly 160×160 (center-crop)
    img = img.scaled(160, 160, Qt::KeepAspectRatioByExpanding,
                     Qt::SmoothTransformation);
    if (img.width() > 160 || img.height() > 160)
        img = img.copy((img.width()  - 160) / 2,
                       (img.height() - 160) / 2, 160, 160);

    QBuffer buf;
    buf.open(QIODevice::WriteOnly);
    if (!img.save(&buf, "JPEG", 80)) return {};
    return QString::fromLatin1(buf.data().toBase64());
}

// ── ID3v2 reader ──────────────────────────────────────────────────────────

bool TagReader::readId3v2(QFile &f, TrackInfo &info,
                          bool generateCoverThumb, qint64 &id3End)
{
    char hdr[10];
    if (f.read(hdr, 10) != 10) return false;
    if (hdr[0] != 'I' || hdr[1] != 'D' || hdr[2] != '3') return false;

    const quint8 version = static_cast<quint8>(hdr[3]);
    if (version == 0xFF || version < 2) return false;
    const quint8 flags = static_cast<quint8>(hdr[5]);

    const uchar *szBuf = reinterpret_cast<const uchar *>(hdr + 6);
    const quint32 tagSize = syncsafeToInt(szBuf); // excludes 10-byte header
    id3End = 10 + tagSize;

    // Skip extended header
    if (flags & 0x40) {
        uchar extBuf[4];
        if (f.read(reinterpret_cast<char*>(extBuf), 4) != 4) { f.seek(id3End); return false; }
        quint32 extSize = (quint32(extBuf[0]) << 24) | (quint32(extBuf[1]) << 16) |
                          (quint32(extBuf[2]) <<  8) |  quint32(extBuf[3]);
        if (version == 4) extSize = syncsafeToInt(extBuf); // v2.4: syncsafe, includes itself
        const qint64 skip = (version == 4) ? qint64(extSize) - 4 : qint64(extSize);
        f.seek(f.pos() + skip);
    }

    const bool isV22 = (version == 2);
    bool hasCover = false;

    while (f.pos() + (isV22 ? 6 : 10) <= id3End) {
        char fid[5] = {0};
        quint32 fsize = 0;

        if (isV22) {
            if (f.read(fid, 3) != 3) break;
            if (fid[0] == '\0') break;
            uchar s[3];
            if (f.read(reinterpret_cast<char*>(s), 3) != 3) break;
            fsize = (quint32(s[0]) << 16) | (quint32(s[1]) << 8) | quint32(s[2]);
        } else {
            if (f.read(fid, 4) != 4) break;
            if (fid[0] == '\0') break;
            uchar s[4];
            if (f.read(reinterpret_cast<char*>(s), 4) != 4) break;
            fsize = (version == 4) ? syncsafeToInt(s)
                                   : (quint32(s[0]) << 24) | (quint32(s[1]) << 16) |
                                     (quint32(s[2]) <<  8) |  quint32(s[3]);
            char flg[2];
            if (f.read(flg, 2) != 2) break; // skip frame flags
        }

        if (fsize == 0 || fsize > tagSize) break;
        if (f.pos() + fsize > id3End) break;

        const QByteArray fd = f.read(fsize);
        if (quint32(fd.size()) != fsize) break;

        const QLatin1String fn(fid);

        if      (fn == "TIT2" || fn == "TT2") info.title       = decodeTextFrame(fd);
        else if (fn == "TPE1" || fn == "TP1") info.artist      = decodeTextFrame(fd);
        else if (fn == "TPE2" || fn == "TP2") info.albumArtist = decodeTextFrame(fd);
        else if (fn == "TALB" || fn == "TAL") info.album       = decodeTextFrame(fd);
        else if (fn == "TRCK" || fn == "TRK") {
            info.track = decodeTextFrame(fd).split('/').constFirst().trimmed().toInt();
        }
        else if (fn == "TCON" || fn == "TCO") {
            info.genre = parseGenreTcon(decodeTextFrame(fd));
        }
        else if (fn == "TLEN") {
            info.duration = decodeTextFrame(fd).trimmed().toLongLong();
        }
        else if (fn == "TYER" || fn == "TYE") {
            info.year = decodeTextFrame(fd).trimmed().left(4).toInt();
        }
        else if (fn == "TDRC") {
            info.year = decodeTextFrame(fd).trimmed().left(4).toInt();
        }
        else if ((fn == "APIC" || fn == "PIC") && generateCoverThumb && !hasCover) {
            const QByteArray imgData = parseApicFrame(fd, version);
            if (!imgData.isEmpty()) {
                info.coverThumb = makeCoverThumb(imgData);
                hasCover = !info.coverThumb.isEmpty();
            }
        }
    }

    f.seek(id3End); // always land on the MPEG audio
    return true;
}

// ── MPEG duration estimator ───────────────────────────────────────────────

void TagReader::estimateMp3Duration(QFile &f, qint64 audioStart, TrackInfo &info)
{
    const bool needDuration = (info.duration == 0);

    f.seek(audioStart);
    const QByteArray buf = f.read(10240); // search window

    // Bitrate tables for MPEG1 / MPEG2-2.5, Layer 3
    static const int kBr1[] = {0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0};
    static const int kBr2[] = {0, 8,16,24,32,40,48,56, 64, 80, 96,112,128,144,160,0};
    // Sample-rate tables
    static const int kSr1[]  = {44100,48000,32000, 0};
    static const int kSr2[]  = {22050,24000,16000, 0};
    static const int kSr25[] = {11025,12000, 8000, 0};

    int syncPos = -1;
    for (int i = 0; i + 3 < buf.size(); ++i) {
        const uchar b0 = static_cast<uchar>(buf[i]);
        const uchar b1 = static_cast<uchar>(buf[i+1]);
        if (b0 != 0xFF || (b1 & 0xE0) != 0xE0) continue;
        // Layer 3: bits[2:1] of b1 = 01 → (b1 & 0x06) == 0x02
        if ((b1 & 0x06) != 0x02) continue;
        const int brIdx = (static_cast<uchar>(buf[i+2]) >> 4) & 0x0F;
        if (brIdx == 0 || brIdx == 0x0F) continue; // free/invalid
        syncPos = i;
        break;
    }
    if (syncPos < 0) return;

    const uchar b1 = static_cast<uchar>(buf[syncPos + 1]);
    const uchar b2 = static_cast<uchar>(buf[syncPos + 2]);
    const uchar b3 = static_cast<uchar>(buf[syncPos + 3]);

    const int versionBits = (b1 >> 3) & 0x03; // 3=MPEG1, 2=MPEG2, 0=MPEG2.5
    const int brIdx       = (b2 >> 4) & 0x0F;
    const int srIdx       = (b2 >> 2) & 0x03;
    const bool isMono     = ((b3 >> 6) & 0x03) == 3;

    const bool isMpeg1 = (versionBits == 3);

    const int bitrate = isMpeg1 ? kBr1[brIdx] : kBr2[brIdx];
    if (bitrate == 0) return;
    info.bitrate = bitrate;

    if (!needDuration) return; // TLEN frame already gave us an exact duration

    int sampleRate = 0;
    if (versionBits == 3)      sampleRate = kSr1[srIdx];
    else if (versionBits == 2)  sampleRate = kSr2[srIdx];
    else                        sampleRate = kSr25[srIdx];
    if (sampleRate == 0) return;

    // Check Xing / Info VBR header
    const int sideInfoSize = isMpeg1 ? (isMono ? 17 : 32) : (isMono ? 9 : 17);
    const int xingOff      = syncPos + 4 + sideInfoSize;
    if (xingOff + 8 <= buf.size()) {
        const QByteArray xingTag = buf.mid(xingOff, 4);
        if (xingTag == "Xing" || xingTag == "Info") {
            const uchar *xd = reinterpret_cast<const uchar *>(buf.constData() + xingOff + 4);
            const quint32 xflags = (quint32(xd[0]) << 24) | (quint32(xd[1]) << 16) |
                                   (quint32(xd[2]) <<  8) |  quint32(xd[3]);
            if (xflags & 0x01) { // frame count present
                const uchar *fc = xd + 4;
                const quint32 frames = (quint32(fc[0]) << 24) | (quint32(fc[1]) << 16) |
                                       (quint32(fc[2]) <<  8) |  quint32(fc[3]);
                const qint64 spf    = isMpeg1 ? 1152 : 576;
                info.duration       = frames * spf * 1000LL / sampleRate;
                return;
            }
        }
    }

    // CBR fallback: estimate from audio data size
    const qint64 audioBytes = info.fileSize - audioStart;
    if (audioBytes > 0)
        info.duration = audioBytes * 8LL * 1000LL / (bitrate * 1000LL);
}

// ── FLAC reader ───────────────────────────────────────────────────────────

bool TagReader::readFlac(QFile &f, TrackInfo &info, bool generateCoverThumb)
{
    char magic[4];
    if (f.read(magic, 4) != 4) return false;
    if (magic[0] != 'f' || magic[1] != 'L' || magic[2] != 'a' || magic[3] != 'C')
        return false;

    bool streamInfoOk = false;
    bool hasCover     = false;

    while (!f.atEnd()) {
        uchar bh[4];
        if (f.read(reinterpret_cast<char*>(bh), 4) != 4) break;
        const bool    lastBlock = (bh[0] & 0x80) != 0;
        const quint8  blockType =  bh[0] & 0x7F;
        const quint32 blockLen  = (quint32(bh[1]) << 16) |
                                  (quint32(bh[2]) <<  8) | quint32(bh[3]);

        if (blockType == 0) {
            // STREAMINFO (always 34 bytes)
            const QByteArray si = f.read(blockLen);
            if (si.size() >= 18) {
                const uchar *d = reinterpret_cast<const uchar *>(si.constData());
                const quint32 sampleRate =
                    (quint32(d[10]) << 12) | (quint32(d[11]) << 4) | (quint32(d[12]) >> 4);
                const qint64 totalSamples =
                    (qint64(d[13] & 0x0F) << 32) | (qint64(d[14]) << 24) |
                    (qint64(d[15])        << 16) | (qint64(d[16]) <<  8) | qint64(d[17]);
                if (sampleRate > 0 && totalSamples > 0)
                    info.duration = totalSamples * 1000LL / sampleRate;
                streamInfoOk = true;
            }
        }
        else if (blockType == 4) {
            // VORBIS_COMMENT
            const QByteArray vc = f.read(blockLen);
            int pos = 0;
            auto leU32 = [&]() -> quint32 {
                if (pos + 4 > vc.size()) return 0;
                const uchar *p = reinterpret_cast<const uchar *>(vc.constData() + pos);
                pos += 4;
                return quint32(p[0]) | (quint32(p[1]) << 8) |
                       (quint32(p[2]) << 16) | (quint32(p[3]) << 24);
            };
            // Split into two statements (not "pos += 4 + int(leU32())"): see
            // parsePictureBlock()'s comment — this combined form double-skips
            // 4 bytes past the vendor string under C++17 sequencing rules
            // (verified empirically), corrupting every tag field read below.
            const quint32 vendorLen = leU32(); // advances pos past the length field itself
            pos += int(vendorLen);             // now skip the vendor string content
            const quint32 count = leU32();
            for (quint32 i = 0; i < count && pos + 4 <= vc.size(); ++i) {
                const quint32 len = leU32();
                if (pos + int(len) > vc.size()) break;
                const QString comment = QString::fromUtf8(vc.constData() + pos, int(len));
                pos += int(len);
                const int eq = comment.indexOf('=');
                if (eq <= 0) continue;
                const QString key   = comment.left(eq).toUpper().trimmed();
                const QString value = comment.mid(eq + 1).trimmed();
                if      (key == "TITLE")                              info.title       = value;
                else if (key == "ARTIST")                             info.artist      = value;
                else if (key == "ALBUMARTIST" || key == "ALBUM ARTIST") info.albumArtist = value;
                else if (key == "ALBUM")                              info.album       = value;
                else if (key == "TRACKNUMBER" || key == "TRACK")
                    info.track = value.split('/').constFirst().trimmed().toInt();
                else if (key == "GENRE")                              info.genre       = value.trimmed();
                else if (key == "DATE"  || key == "YEAR")
                    info.year = value.trimmed().left(4).toInt();
            }
        }
        else if (blockType == 6) {
            // PICTURE
            const QByteArray pic = f.read(blockLen);
            if (!hasCover && generateCoverThumb) {
                const QByteArray imageBytes = parsePictureBlock(pic);
                if (!imageBytes.isEmpty()) {
                    info.coverThumb = makeCoverThumb(imageBytes);
                    hasCover = !info.coverThumb.isEmpty();
                }
            }
        }
        else {
            // Unrecognised block – skip
            if (!f.seek(f.pos() + blockLen)) break;
        }

        if (lastBlock) break;
    }

    return streamInfoOk;
}

// ── Shared picture-block parser (FLAC PICTURE / Opus+Vorbis METADATA_BLOCK_PICTURE) ──

QByteArray TagReader::parsePictureBlock(const QByteArray &block)
{
    if (quint32(block.size()) < 8) return {};
    int pos = 0;
    auto beU32 = [&]() -> quint32 {
        if (pos + 4 > block.size()) return 0;
        const uchar *p = reinterpret_cast<const uchar *>(block.constData() + pos);
        pos += 4;
        return (quint32(p[0]) << 24) | (quint32(p[1]) << 16) |
               (quint32(p[2]) <<  8) |  quint32(p[3]);
    };
    const quint32 picType = beU32();
    // Two explicit statements per skip (not "pos += 4 + int(beU32())"): since
    // C++17, a compound assignment's right operand — including beU32()'s own
    // pos-mutating side effect — is sequenced before the left operand's value
    // read, so a combined expression here would read the already-advanced
    // pos and double-skip 4 bytes past each field (verified empirically with
    // this project's exact compiler/standard — this was the actual bug
    // behind covers never showing up for Opus, and would equally have broken
    // FLAC's PICTURE block, which shares this function).
    const quint32 mimeLen = beU32();
    pos += int(mimeLen); // skip MIME string content
    const quint32 descLen = beU32();
    pos += int(descLen); // skip description string content
    beU32(); beU32(); beU32(); beU32(); // skip w/h/depth/colors
    const quint32 dataLen = beU32();
    if ((picType == 3 || picType == 0) && pos + int(dataLen) <= block.size())
        return block.mid(pos, int(dataLen));
    return {};
}

// ── Ogg page framing (shared by readOpus and readRawCover's opus branch) ─────

bool TagReader::readOggPageHeader(QFile &f, quint32 &dataSize, qint64 &granulePos,
                                   bool &continuesPacket)
{
    uchar hdr[27];
    if (f.read(reinterpret_cast<char *>(hdr), 27) != 27) return false;
    if (hdr[0] != 'O' || hdr[1] != 'g' || hdr[2] != 'g' || hdr[3] != 'S') return false;

    granulePos = 0;
    for (int i = 0; i < 8; ++i)
        granulePos |= qint64(hdr[6 + i]) << (8 * i); // little-endian, offset 6..13

    const quint8 numSegments = hdr[26];
    const QByteArray segmentTable = f.read(numSegments);
    if (segmentTable.size() != numSegments) return false;

    dataSize = 0;
    for (int i = 0; i < numSegments; ++i)
        dataSize += quint8(segmentTable.at(i));

    continuesPacket = numSegments > 0 && quint8(segmentTable.at(numSegments - 1)) == 255;

    return true;
}

QByteArray TagReader::readOggPacket(QFile &f, qint64 &granulePos)
{
    QByteArray packet;
    quint32 dataSize = 0;
    bool continuesPacket = false;
    do {
        if (!readOggPageHeader(f, dataSize, granulePos, continuesPacket)) return {};
        const QByteArray pageData = f.read(dataSize);
        if (quint32(pageData.size()) != dataSize) return {};
        packet += pageData;
    } while (continuesPacket);
    return packet;
}

// ── Opus reader (Ogg container) ──────────────────────────────────────────

bool TagReader::readOpus(QFile &f, TrackInfo &info, bool generateCoverThumb)
{
    // First page: OpusHead packet (always alone on page 1 per RFC 7845 §3,
    // so this is always exactly one page in practice).
    qint64 granulePos = 0;
    const QByteArray head = readOggPacket(f, granulePos);
    if (head.size() < 12 || head.left(8) != QByteArray("OpusHead", 8)) return false;
    // Byte 8 = version, byte 9 = channel count, bytes 10-11 = pre-skip (LE) — RFC 7845 §5.1.
    const quint16 preSkip = quint8(head.at(10)) | (quint16(quint8(head.at(11))) << 8);

    // OpusTags packet — same Vorbis-comment layout FLAC uses. Unlike
    // OpusHead, this routinely spans multiple pages once it embeds cover
    // art, which readOggPacket() handles transparently.
    const QByteArray tags = readOggPacket(f, granulePos);
    if (tags.size() < 8 || tags.left(8) != QByteArray("OpusTags", 8)) return false;

    int pos = 8;
    auto leU32 = [&]() -> quint32 {
        if (pos + 4 > tags.size()) return 0;
        const uchar *p = reinterpret_cast<const uchar *>(tags.constData() + pos);
        pos += 4;
        return quint32(p[0]) | (quint32(p[1]) << 8) |
               (quint32(p[2]) << 16) | (quint32(p[3]) << 24);
    };
    // Split into two statements (not "pos += 4 + int(leU32())"): since C++17,
    // a compound assignment's right operand — including leU32()'s own
    // pos-mutating side effect — is sequenced before the left operand's value
    // read, so a combined expression here would read the already-advanced
    // pos and double-skip 4 bytes past the vendor string.
    const quint32 vendorLen = leU32(); // advances pos past the length field itself
    pos += int(vendorLen);             // now skip the vendor string content
    const quint32 count = leU32();
    bool hasCover = false;
    for (quint32 i = 0; i < count && pos + 4 <= tags.size(); ++i) {
        const quint32 len = leU32();
        if (pos + int(len) > tags.size()) break;
        const QString comment = QString::fromUtf8(tags.constData() + pos, int(len));
        pos += int(len);
        const int eq = comment.indexOf('=');
        if (eq <= 0) continue;
        const QString key   = comment.left(eq).toUpper().trimmed();
        const QString value = comment.mid(eq + 1).trimmed();
        if      (key == "TITLE")                               info.title       = value;
        else if (key == "ARTIST")                              info.artist      = value;
        else if (key == "ALBUMARTIST" || key == "ALBUM ARTIST") info.albumArtist = value;
        else if (key == "ALBUM")                               info.album       = value;
        else if (key == "TRACKNUMBER" || key == "TRACK")
            info.track = value.split('/').constFirst().trimmed().toInt();
        else if (key == "GENRE")                               info.genre       = value.trimmed();
        else if (key == "DATE"  || key == "YEAR")
            info.year = value.trimmed().left(4).toInt();
        else if (key == "METADATA_BLOCK_PICTURE" && !hasCover && generateCoverThumb) {
            const QByteArray imageBytes = parsePictureBlock(QByteArray::fromBase64(value.toUtf8()));
            if (!imageBytes.isEmpty()) {
                info.coverThumb = makeCoverThumb(imageBytes);
                hasCover = !info.coverThumb.isEmpty();
            }
        }
    }

    // Remaining pages: skip payloads, tracking the last page's granule
    // position — that value (minus pre-skip) is the total sample count.
    // Packet boundaries don't matter here, only page granule positions, so
    // continuesPacket is unused.
    quint32 dataSize = 0;
    bool    continuesPacket = false;
    qint64  lastGranule = granulePos;
    while (readOggPageHeader(f, dataSize, granulePos, continuesPacket)) {
        lastGranule = granulePos;
        if (!f.seek(f.pos() + dataSize)) break;
    }

    if (lastGranule > preSkip)
        info.duration = (lastGranule - preSkip) * 1000LL / 48000LL;

    return true;
}

// ── Public entry point ────────────────────────────────────────────────────

TrackInfo TagReader::read(const QString &filePath, bool generateCoverThumb)
{
    TrackInfo info;
    const QFileInfo fi(filePath);
    info.filePath     = filePath;
    info.fileName     = fi.fileName();
    info.fileSize     = fi.size();
    info.lastModified = fi.lastModified().toMSecsSinceEpoch();

    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly)) return info;

    const QString ext = fi.suffix().toLower();
    if (ext == "mp3") {
        qint64 id3End = 0;
        readId3v2(f, info, generateCoverThumb, id3End);
        estimateMp3Duration(f, id3End, info); // always needed for bitrate, even when TLEN set duration
    } else if (ext == "flac") {
        readFlac(f, info, generateCoverThumb);
        // Approximate FLAC bitrate from file size + duration
        if (info.bitrate == 0 && info.duration > 0)
            info.bitrate = int(info.fileSize * 8LL / info.duration); // kbps
    } else if (ext == "opus") {
        readOpus(f, info, generateCoverThumb);
        // Opus has no fixed nominal-bitrate header field; approximate the
        // same way FLAC's bitrate is approximated when not explicitly known.
        if (info.bitrate == 0 && info.duration > 0)
            info.bitrate = int(info.fileSize * 8LL / info.duration); // kbps
    }

    f.close();

    // Fallbacks
    if (info.title.isEmpty())       info.title       = fi.completeBaseName();
    if (info.albumArtist.isEmpty()) info.albumArtist = info.artist;

    return info;
}

// ── readRawCover ──────────────────────────────────────────────────────────
// Extracts only the raw embedded image bytes without any scaling.
// Reuses the same private parse functions as read(), but discards all tags
// and returns the cover bytes directly.
QByteArray TagReader::readRawCover(const QString &filePath)
{
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly)) return {};

    const QString ext = QFileInfo(filePath).suffix().toLower();

    if (ext == QLatin1String("mp3")) {
        // Read ID3v2 header
        uchar hdr[10];
        if (f.read(reinterpret_cast<char*>(hdr), 10) < 10) return {};
        if (hdr[0] != 'I' || hdr[1] != 'D' || hdr[2] != '3') return {};
        const quint8 version = hdr[3];
        const bool unsync = hdr[5] & 0x80;
        Q_UNUSED(unsync)
        const quint32 tagSize = (quint32(hdr[6]) << 21)
                              | (quint32(hdr[7]) << 14)
                              | (quint32(hdr[8]) <<  7)
                              | quint32(hdr[9]);

        const QByteArray tagData = f.read(tagSize);
        int pos = 0;
        const int frameHdrSize = (version == 2) ? 6 : 10;

        while (pos + frameHdrSize <= int(tagSize)) {
            const char *fd = tagData.constData() + pos;
            QString frameId;
            quint32 frameSize = 0;

            if (version == 2) {
                frameId = QString::fromLatin1(fd, 3);
                frameSize = (quint8(fd[3]) << 16) | (quint8(fd[4]) << 8) | quint8(fd[5]);
            } else {
                frameId = QString::fromLatin1(fd, 4);
                frameSize = (version >= 4)
                    ? syncsafeToInt(reinterpret_cast<const uchar*>(fd + 4))
                    : ((quint32(quint8(fd[4])) << 24) | (quint32(quint8(fd[5])) << 16)
                       | (quint32(quint8(fd[6])) << 8) | quint32(quint8(fd[7])));
            }

            if (frameSize == 0) { ++pos; continue; }
            pos += frameHdrSize;
            if (pos + int(frameSize) > int(tagSize)) break;

            const bool isApic = (version == 2) ? (frameId == QLatin1String("PIC"))
                                               : (frameId == QLatin1String("APIC"));
            if (isApic) {
                return parseApicFrame(tagData.mid(pos, frameSize), version);
            }
            pos += frameSize;
        }
    } else if (ext == QLatin1String("flac")) {
        // Skip "fLaC" marker
        if (f.read(4) != QByteArray("fLaC", 4)) return {};

        while (!f.atEnd()) {
            uchar blkHdr[4];
            if (f.read(reinterpret_cast<char*>(blkHdr), 4) < 4) break;
            const bool isLast  = (blkHdr[0] & 0x80) != 0;
            const quint8 type  =  blkHdr[0] & 0x7F;
            const quint32 len  = (quint32(blkHdr[1]) << 16)
                               | (quint32(blkHdr[2]) <<  8)
                               |  quint32(blkHdr[3]);

            if (type == 6) { // PICTURE
                const QByteArray pic = f.read(len);
                int p = 0;
                auto readU32 = [&]() -> quint32 {
                    if (p + 4 > pic.size()) return 0;
                    quint32 v = (quint8(pic[p]) << 24) | (quint8(pic[p+1]) << 16)
                              | (quint8(pic[p+2]) << 8) | quint8(pic[p+3]);
                    p += 4;
                    return v;
                };
                /*quint32 picType =*/ readU32();
                quint32 mimeLen = readU32(); p += mimeLen;
                quint32 descLen = readU32(); p += descLen;
                p += 16; // width, height, depth, colors
                quint32 dataLen = readU32();
                if (p + int(dataLen) <= pic.size())
                    return pic.mid(p, int(dataLen));
                break;
            }

            if (isLast) break;
            f.seek(f.pos() + len);
        }
    } else if (ext == QLatin1String("opus")) {
        // First page: OpusHead — we only need to skip past it.
        qint64 granulePos = 0;
        readOggPacket(f, granulePos);

        // OpusTags — same Vorbis-comment layout as FLAC's VORBIS_COMMENT,
        // scan for a METADATA_BLOCK_PICTURE comment. May span multiple pages
        // once it embeds cover art, which readOggPacket() handles.
        const QByteArray tags = readOggPacket(f, granulePos);
        if (tags.size() < 8 || tags.left(8) != QByteArray("OpusTags", 8)) return {};

        int pos = 8;
        auto leU32 = [&]() -> quint32 {
            if (pos + 4 > tags.size()) return 0;
            const uchar *p = reinterpret_cast<const uchar *>(tags.constData() + pos);
            pos += 4;
            return quint32(p[0]) | (quint32(p[1]) << 8) |
                   (quint32(p[2]) << 16) | (quint32(p[3]) << 24);
        };
        const quint32 vendorLen = leU32(); // advances pos past the length field itself
        pos += int(vendorLen);             // now skip the vendor string content
        const quint32 count = leU32();
        for (quint32 i = 0; i < count && pos + 4 <= tags.size(); ++i) {
            const quint32 len = leU32();
            if (pos + int(len) > tags.size()) break;
            const QString comment = QString::fromUtf8(tags.constData() + pos, int(len));
            pos += int(len);
            const int eq = comment.indexOf('=');
            if (eq <= 0) continue;
            if (comment.left(eq).toUpper().trimmed() == QLatin1String("METADATA_BLOCK_PICTURE")) {
                const QByteArray decoded =
                    QByteArray::fromBase64(comment.mid(eq + 1).trimmed().toUtf8());
                const QByteArray imageBytes = parsePictureBlock(decoded);
                if (!imageBytes.isEmpty()) return imageBytes;
            }
        }
    }

    return {};
}
