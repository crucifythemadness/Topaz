#include "playlistmanager.h"
#include "tagreader.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QUrl>
#include <QXmlStreamReader>
#include <QXmlStreamWriter>
#include <algorithm>

// ── Internal XML helpers ──────────────────────────────────────────────────
namespace {

struct XspfEntry {
    QString location, title, creator, album, trackNum, duration;
};

// Parse all <track> entries from an XSPF file.
// Also fills outTitle with the playlist <title>.
QList<XspfEntry> parseXspfFile(const QString &path, QString &outTitle)
{
    QList<XspfEntry> result;
    outTitle.clear();

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return result;

    QXmlStreamReader xml(&f);
    bool     inTrack = false;
    XspfEntry cur;

    while (!xml.atEnd()) {
        xml.readNext();
        if (xml.isStartElement()) {
            const auto n = xml.name();
            if (n == QLatin1String("track")) {
                inTrack = true;
                cur = {};
            } else if (inTrack) {
                if      (n == QLatin1String("location")) cur.location = xml.readElementText();
                else if (n == QLatin1String("title"))    cur.title    = xml.readElementText();
                else if (n == QLatin1String("creator"))  cur.creator  = xml.readElementText();
                else if (n == QLatin1String("album"))    cur.album    = xml.readElementText();
                else if (n == QLatin1String("trackNum")) cur.trackNum = xml.readElementText();
                else if (n == QLatin1String("duration")) cur.duration = xml.readElementText();
            } else if (n == QLatin1String("title")) {
                outTitle = xml.readElementText();
            }
        } else if (xml.isEndElement()
                   && xml.name() == QLatin1String("track")
                   && inTrack) {
            result.append(cur);
            inTrack = false;
        }
    }
    return result;
}

// Write a complete XSPF file from a list of entries.
bool writeXspfFile(const QString &path,
                    const QString &title,
                    const QList<XspfEntry> &entries)
{
    QByteArray buf;
    QXmlStreamWriter xml(&buf);
    xml.setAutoFormatting(true);
    xml.setAutoFormattingIndent(2);
    xml.writeStartDocument(QStringLiteral("1.0"));

    xml.writeStartElement(QStringLiteral("playlist"));
    xml.writeAttribute(QStringLiteral("version"), QStringLiteral("1"));
    xml.writeAttribute(QStringLiteral("xmlns"),
                       QStringLiteral("http://xspf.org/ns/0/"));

    xml.writeTextElement(QStringLiteral("title"), title);
    xml.writeStartElement(QStringLiteral("trackList"));

    for (const XspfEntry &e : entries) {
        xml.writeStartElement(QStringLiteral("track"));
        if (!e.location.isEmpty())
            xml.writeTextElement(QStringLiteral("location"), e.location);
        if (!e.title.isEmpty())
            xml.writeTextElement(QStringLiteral("title"), e.title);
        if (!e.creator.isEmpty())
            xml.writeTextElement(QStringLiteral("creator"), e.creator);
        if (!e.album.isEmpty())
            xml.writeTextElement(QStringLiteral("album"), e.album);
        if (!e.trackNum.isEmpty())
            xml.writeTextElement(QStringLiteral("trackNum"), e.trackNum);
        if (!e.duration.isEmpty())
            xml.writeTextElement(QStringLiteral("duration"), e.duration);
        xml.writeEndElement(); // </track>
    }

    xml.writeEndElement(); // </trackList>
    xml.writeEndElement(); // </playlist>
    xml.writeEndDocument();

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    f.write(buf);
    return true;
}

} // namespace

// ── resolveLocation (file-level helper) ─────────────────────────────────
// Resolves a stored XSPF location to an absolute local path.
// Locations are stored without a drive letter (e.g. "/Music/foo.flac").
// Checks every mounted volume on the system and returns the first path
// that actually exists on disk.  Returns an empty string when not found.
static QString resolveLocation(const QString &location)
{
    if (location.isEmpty()) return {};

    // Already absolute with drive letter — validate and return
    if (location.length() >= 2 && location[1] == QChar(':')) {
        return QFile::exists(location) ? location : QString{};
    }

    // Relative path — probe each mounted volume (QStorageInfo covers all real drives)
    const QList<QStorageInfo> volumes = QStorageInfo::mountedVolumes();
    for (const QStorageInfo &vol : volumes) {
        if (!vol.isValid() || !vol.isReady())
            continue;
        QString root = vol.rootPath();
        // rootPath() ends with '/' or '\\' on Windows — strip it to avoid double slash
        if (root.endsWith('/') || root.endsWith('\\')
            ) root.chop(1);
        const QString candidate = root + location;
        if (QFile::exists(candidate))
            return candidate;
    }
    return {};
}

PlaylistManager::PlaylistManager(QObject *parent)
    : QObject(parent)
{
}

// ── Directory ─────────────────────────────────────────────────────────────

QString PlaylistManager::playlistDirectory() const
{
    const QString dir =
        QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation)
        + QStringLiteral("/playlists");
    QDir().mkpath(dir);
    return dir;
}

// ── Queries ───────────────────────────────────────────────────────────────

bool PlaylistManager::playlistExists(const QString &name) const
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty())
        return false;
    return QFile::exists(playlistDirectory() + QChar('/')
                         + trimmed + QStringLiteral(".xml"));
}

// ── Create ────────────────────────────────────────────────────────────────

QString PlaylistManager::createPlaylist(const QString &name,
                                         const QVariantList &tracks)
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty())
        return QStringLiteral("Playlist name cannot be empty.");

    const QString path = playlistDirectory() + QChar('/')
                         + trimmed + QStringLiteral(".xml");
    if (QFile::exists(path))
        return QStringLiteral("A playlist named \"%1\" already exists.").arg(trimmed);

    const QByteArray xml = buildXspf(trimmed, tracks);

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return QStringLiteral("Could not write playlist file:\n%1").arg(f.errorString());

    f.write(xml);
    f.close();
    return {};   // empty string = success
}

// ── Private helpers ───────────────────────────────────────────────────────

// static
QString PlaylistManager::locationForPath(const QString &filePath)
{
    // Strip Windows drive letter so the path starts with "/"
    // e.g. "C:/Music/foo.flac" → "/Music/foo.flac"
    if (filePath.length() >= 2 && filePath[1] == QChar(':'))
        return filePath.mid(2);
    return filePath;
}

QByteArray PlaylistManager::buildXspf(const QString &title,
                                       const QVariantList &tracks) const
{
    QByteArray buf;
    QXmlStreamWriter xml(&buf);
    xml.setAutoFormatting(true);
    xml.setAutoFormattingIndent(2);

    xml.writeStartDocument(QStringLiteral("1.0"));

    // Root <playlist> element with XSPF namespace
    xml.writeStartElement(QStringLiteral("playlist"));
    xml.writeAttribute(QStringLiteral("version"), QStringLiteral("1"));
    xml.writeAttribute(QStringLiteral("xmlns"),
                       QStringLiteral("http://xspf.org/ns/0/"));

    xml.writeTextElement(QStringLiteral("title"), title);

    xml.writeStartElement(QStringLiteral("trackList"));
    for (const QVariant &v : tracks) {
        const QVariantMap m = v.toMap();

        xml.writeStartElement(QStringLiteral("track"));

        // <location> — relative path without drive letter
        const QString fp = m.value(QStringLiteral("filePath")).toString();
        if (!fp.isEmpty())
            xml.writeTextElement(QStringLiteral("location"),
                                 locationForPath(fp));

        // <title>
        const QString t = m.value(QStringLiteral("title")).toString();
        if (!t.isEmpty())
            xml.writeTextElement(QStringLiteral("title"), t);

        // <creator> = artist (XSPF maps creator → track artist)
        const QString artist = m.value(QStringLiteral("artist")).toString();
        if (!artist.isEmpty())
            xml.writeTextElement(QStringLiteral("creator"), artist);

        // <album>
        const QString album = m.value(QStringLiteral("album")).toString();
        if (!album.isEmpty())
            xml.writeTextElement(QStringLiteral("album"), album);

        // <trackNum>
        const int trackNum = m.value(QStringLiteral("trackNumber")).toInt();
        if (trackNum > 0)
            xml.writeTextElement(QStringLiteral("trackNum"),
                                 QString::number(trackNum));

        // <duration> — milliseconds as required by XSPF
        const qint64 dur = m.value(QStringLiteral("durationMs")).toLongLong();
        if (dur > 0)
            xml.writeTextElement(QStringLiteral("duration"),
                                 QString::number(dur));

        xml.writeEndElement(); // </track>
    }
    xml.writeEndElement(); // </trackList>
    xml.writeEndElement(); // </playlist>
    xml.writeEndDocument();

    return buf;
}

// ── appendTrack ───────────────────────────────────────────────────────────

bool PlaylistManager::appendTrack(const QString &nameWithExt,
                                    const QVariantMap &map)
{
    const QString path = playlistDirectory() + QChar('/') + nameWithExt.trimmed();
    QString title;
    QList<XspfEntry> entries = parseXspfFile(path, title);

    XspfEntry e;
    e.location = locationForPath(map.value(QStringLiteral("filePath")).toString());

    const QString t = map.value(QStringLiteral("title")).toString();
    e.title = t.isEmpty()
              ? map.value(QStringLiteral("fileName")).toString()
              : t;

    // creator — prefer albumArtist, fallback to artist
    e.creator = map.value(QStringLiteral("albumArtist"),
                           map.value(QStringLiteral("artist"))).toString();
    if (e.creator.isEmpty())
        e.creator = map.value(QStringLiteral("artist")).toString();

    e.album = map.value(QStringLiteral("album")).toString();

    // Accept both "trackNumber" (from trackList()) and "number" (from filteredAlbums())
    const int trackNum = map.value(QStringLiteral("trackNumber"),
                                    map.value(QStringLiteral("number"))).toInt();
    if (trackNum > 0)
        e.trackNum = QString::number(trackNum);

    const qint64 dur = map.value(QStringLiteral("durationMs")).toLongLong();
    if (dur > 0)
        e.duration = QString::number(dur);

    entries.append(e);
    return writeXspfFile(path, title, entries);
}

// ── removeTrackByPath ─────────────────────────────────────────────────────

bool PlaylistManager::removeTrackByPath(const QString &nameWithExt,
                                          const QString &filePath)
{
    const QString path = playlistDirectory() + QChar('/') + nameWithExt.trimmed();
    QString title;
    QList<XspfEntry> entries = parseXspfFile(path, title);

    const QString loc = locationForPath(filePath);
    const int before  = entries.size();

    entries.erase(
        std::remove_if(entries.begin(), entries.end(),
                       [&loc](const XspfEntry &e) { return e.location == loc; }),
        entries.end());

    if (entries.size() == before)
        return false; // nothing matched

    return writeXspfFile(path, title, entries);
}
// ── rewritePlaylist ─────────────────────────────────────────────────

bool PlaylistManager::rewritePlaylist(const QString &nameWithExt,
                                       const QVariantList &tracks)
{
    const QString path = playlistDirectory() + QChar('/') + nameWithExt.trimmed();
    // Preserve the playlist <title> stored in the file (= user-given name without .xml).
    const QString title = QFileInfo(nameWithExt).completeBaseName();
    const QByteArray xml = buildXspf(title, tracks);
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    f.write(xml);
    return true;
}
// ── loadPlaylist ──────────────────────────────────────────────────────────

QVariantMap PlaylistManager::loadPlaylist(const QString &filePath)
{
    QVariantMap result;
    result[QStringLiteral("tracks")] = QVariantList{};

    // Accept both file:// URLs and plain local paths
    QUrl url(filePath);
    const QString localPath = url.isLocalFile() ? url.toLocalFile() : filePath;

    result[QStringLiteral("fileName")] = QFileInfo(localPath).fileName();

    QString xspfTitle;
    const QList<XspfEntry> entries = parseXspfFile(localPath, xspfTitle);

    QVariantList tracks;
    for (const XspfEntry &e : entries) {
        const QString resolved = resolveLocation(e.location);
        if (resolved.isEmpty())
            continue;   // file not found on any mounted volume — skip silently

        QVariantMap m;
        m[QStringLiteral("filePath")]    = resolved;

        // Read actual tag data from the file (no cover thumbnail needed).
        // This fills in bitrate, duration, and any XSPF fields that were empty.
        const TrackInfo tag = TagReader::read(resolved, false);

        // Prefer tag data; fall back to what was stored in the XSPF
        m[QStringLiteral("title")]       = tag.title.isEmpty()  ? e.title   : tag.title;
        m[QStringLiteral("artist")]      = tag.artist.isEmpty() ? e.creator : tag.artist;
        m[QStringLiteral("albumArtist")] = tag.albumArtist.isEmpty() ? e.creator : tag.albumArtist;
        m[QStringLiteral("album")]       = tag.album.isEmpty()  ? e.album   : tag.album;
        m[QStringLiteral("genre")]       = tag.genre;
        m[QStringLiteral("year")]        = tag.year;

        const int tn = tag.track > 0 ? tag.track : e.trackNum.toInt();
        m[QStringLiteral("number")]      = tn;
        m[QStringLiteral("trackNumber")] = tn;

        // bitrate comes from the actual file — not stored in XSPF
        m[QStringLiteral("bitrate")]     = tag.bitrate;

        const qint64 dur = tag.duration > 0 ? tag.duration : e.duration.toLongLong();
        m[QStringLiteral("durationMs")]  = dur;
        tracks.append(m);
    }
    result[QStringLiteral("tracks")] = tracks;
    return result;
}
