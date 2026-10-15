#include "playlistmanager.h"
#include "tagreader.h"
#include "volumepath.h"

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
    QString location, volume, title, creator, album, trackNum, duration;
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
                else if (n == QLatin1String("volume"))   cur.volume   = xml.readElementText();
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
        if (!e.volume.isEmpty())
            xml.writeTextElement(QStringLiteral("volume"), e.volume);
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

QVariantList PlaylistManager::listPlaylists() const
{
    const QFileInfoList files = QDir(playlistDirectory())
        .entryInfoList(QStringList{QStringLiteral("*.xml")}, QDir::Files);

    QVariantList result;
    result.reserve(files.size());
    for (const QFileInfo &fi : files) {
        QVariantMap m;
        m[QStringLiteral("fileName")]    = fi.fileName();
        m[QStringLiteral("displayName")] = fi.completeBaseName();
        result.append(m);
    }

    std::sort(result.begin(), result.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("displayName")).toString()
                   .compare(b.toMap().value(QStringLiteral("displayName")).toString(),
                            Qt::CaseInsensitive) < 0;
    });
    return result;
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

        // <location>/<volume> — volume-relative path, see VolumePath (volumepath.h)
        const QString fp = m.value(QStringLiteral("filePath")).toString();
        if (!fp.isEmpty()) {
            const VolumePath vp = VolumePath::fromAbsolutePath(fp);
            xml.writeTextElement(QStringLiteral("location"),
                                 vp.relativePath.isEmpty() ? vp.rawPath : vp.relativePath);
            if (!vp.volumeName.isEmpty())
                xml.writeTextElement(QStringLiteral("volume"), vp.volumeName);
        }

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
    {
        const VolumePath vp = VolumePath::fromAbsolutePath(
            map.value(QStringLiteral("filePath")).toString());
        e.location = vp.relativePath.isEmpty() ? vp.rawPath : vp.relativePath;
        e.volume   = vp.volumeName;
    }

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

    const VolumePath vp = VolumePath::fromAbsolutePath(filePath);
    const QString loc = vp.relativePath.isEmpty() ? vp.rawPath : vp.relativePath;
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
    result[QStringLiteral("tracks")]  = QVariantList{};
    result[QStringLiteral("missing")] = QVariantList{};

    // Accept both file:// URLs and plain local paths
    QUrl url(filePath);
    const QString localPath = url.isLocalFile() ? url.toLocalFile() : filePath;

    result[QStringLiteral("fileName")] = QFileInfo(localPath).fileName();

    QString xspfTitle;
    const QList<XspfEntry> entries = parseXspfFile(localPath, xspfTitle);

    // Fetched once for the whole playlist, not per track.
    const QList<QStorageInfo> mounted = QStorageInfo::mountedVolumes();

    QVariantList tracks;
    QVariantList missing;
    for (const XspfEntry &e : entries) {
        VolumePath vp;
        vp.volumeName   = e.volume;
        vp.relativePath = e.location;
        vp.rawPath      = e.location; // in case it was written as a raw fallback path
        const QString resolved = vp.resolve(mounted);
        if (resolved.isEmpty()) {
            // File doesn't exist anywhere currently mounted -- report it
            // using only what the XSPF itself stored (there's no file left
            // to re-read tags from). See UC-10/UC-22.
            QVariantMap mm;
            mm[QStringLiteral("artist")]   = e.creator;
            mm[QStringLiteral("album")]    = e.album;
            mm[QStringLiteral("title")]    = e.title;
            mm[QStringLiteral("location")] = e.volume.isEmpty()
                                              ? e.location
                                              : e.volume + QStringLiteral(":") + e.location;
            missing.append(mm);
            continue;
        }

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
        m[QStringLiteral("vbr")]         = tag.vbr;

        const qint64 dur = tag.duration > 0 ? tag.duration : e.duration.toLongLong();
        m[QStringLiteral("durationMs")]  = dur;
        tracks.append(m);
    }
    result[QStringLiteral("tracks")]  = tracks;
    result[QStringLiteral("missing")] = missing;
    return result;
}

bool PlaylistManager::deletePlaylist(const QString &nameWithExt)
{
    return QFile::remove(playlistDirectory() + QChar('/') + nameWithExt);
}

// ── Import (see UC-30) ───────────────────────────────────────────────────

QVariantMap PlaylistManager::classifyPlaylistSource(const QString &pathOrUrl) const
{
    const QUrl url(pathOrUrl);
    const QString localPath = url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
    const QString fileName  = QFileInfo(localPath).fileName();

    const QString sourceDir = QFileInfo(localPath).absolutePath();
    const QString targetDir = QDir(playlistDirectory()).absolutePath();
    const bool inFolder = sourceDir.compare(targetDir, Qt::CaseInsensitive) == 0;

    QVariantMap result;
    result[QStringLiteral("fileName")] = fileName;
    result[QStringLiteral("alreadyInPlaylistDirectory")] = inFolder;
    result[QStringLiteral("collidesWithExisting")] =
        !inFolder && QFile::exists(playlistDirectory() + QChar('/') + fileName);
    return result;
}

bool PlaylistManager::importPlaylistFile(const QString &sourcePathOrUrl,
                                          const QString &fileName) const
{
    const QUrl url(sourcePathOrUrl);
    const QString sourcePath = url.isLocalFile() ? url.toLocalFile() : sourcePathOrUrl;
    const QString destPath   = playlistDirectory() + QChar('/') + fileName;

    if (QFile::exists(destPath))
        QFile::remove(destPath);
    return QFile::copy(sourcePath, destPath);
}

QString PlaylistManager::findAvailableCopyName(const QString &nameWithExt) const
{
    const int dot = nameWithExt.lastIndexOf(QChar('.'));
    const QString base = dot >= 0 ? nameWithExt.left(dot) : nameWithExt;
    const QString ext  = dot >= 0 ? nameWithExt.mid(dot)  : QString();
    const QString dir  = playlistDirectory();

    for (int n = 1; n <= 9; ++n) {
        const QString candidate = QStringLiteral("%1-%2%3").arg(base, QString::number(n), ext);
        if (!QFile::exists(dir + QChar('/') + candidate))
            return candidate;
    }
    return QString();
}
