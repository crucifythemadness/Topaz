#include "librarycache.h"
#include "volumepath.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QStorageInfo>

// ─────────────────────────────────────────────────────────────────────────
static QString appDataDir()
{
    const QString dir =
        QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(dir);
    return dir;
}

QString LibraryCache::cacheFilePath()
{
    return appDataDir() + QStringLiteral("/Topaz.library.json");
}

// ─────────────────────────────────────────────────────────────────────────

QList<TrackInfo> LibraryCache::load()
{
    QFile f(cacheFilePath());
    if (!f.open(QIODevice::ReadOnly)) return {};

    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    f.close();

    if (err.error != QJsonParseError::NoError || !doc.isObject()) return {};

    const QJsonObject root = doc.object();
    const QJsonArray  arr  = root[QStringLiteral("tracks")].toArray();

    QList<TrackInfo> tracks;
    tracks.reserve(arr.size());

    // Fetched once for the whole batch — see the class-comment note on why
    // this must stay filesystem-I/O-free at 12K+ track scale.
    const QList<QStorageInfo> mounted = QStorageInfo::mountedVolumes();

    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();

        const VolumePath vp = VolumePath::fromVariantMap(o.toVariantMap());
        const QString filePath = vp.quickPath(mounted);
        if (filePath.isEmpty())
            continue; // volume not currently mounted — skip, like a deleted file

        TrackInfo t;
        t.id           = QUuid::fromString(o[QStringLiteral("id")].toString());
        if (t.id.isNull()) t.id = QUuid::createUuid();
        t.filePath     = filePath;
        t.fileName     = o[QStringLiteral("fileName")].toString();
        t.title        = o[QStringLiteral("title")].toString();
        t.artist       = o[QStringLiteral("artist")].toString();
        t.albumArtist  = o[QStringLiteral("albumArtist")].toString();
        t.album        = o[QStringLiteral("album")].toString();
        t.genre        = o[QStringLiteral("genre")].toString();
        t.track        = o[QStringLiteral("track")].toInt();
        t.year         = o[QStringLiteral("year")].toInt();
        t.duration     = static_cast<qint64>(o[QStringLiteral("duration")].toDouble());
        t.bitrate      = o[QStringLiteral("bitrate")].toInt();
        t.fileSize     = static_cast<qint64>(o[QStringLiteral("fileSize")].toDouble());
        t.lastModified = static_cast<qint64>(o[QStringLiteral("lastModified")].toDouble());
        t.coverThumb   = o[QStringLiteral("coverThumb")].toString();
        t.rating       = o[QStringLiteral("rating")].toInt();
        t.ratingId     = QUuid::fromString(o[QStringLiteral("ratingId")].toString());
        tracks.append(t);
    }
    return tracks;
}

bool LibraryCache::save(const QList<TrackInfo> &tracks)
{
    QJsonArray arr;

    for (const TrackInfo &t : tracks) {
        // t.filePath is always a live, just-scanned absolute path here, so this
        // capture is always accurate (unlike load(), which must resolve it back).
        const VolumePath vp = VolumePath::fromAbsolutePath(t.filePath);

        QJsonObject o = QJsonObject::fromVariantMap(vp.toVariantMap());
        o[QStringLiteral("id")]           = t.id.toString(QUuid::WithoutBraces);
        o[QStringLiteral("fileName")]     = t.fileName;
        o[QStringLiteral("title")]        = t.title;
        o[QStringLiteral("artist")]       = t.artist;
        o[QStringLiteral("albumArtist")]  = t.albumArtist;
        o[QStringLiteral("album")]        = t.album;
        o[QStringLiteral("genre")]        = t.genre;
        o[QStringLiteral("track")]        = t.track;
        o[QStringLiteral("year")]         = t.year;
        o[QStringLiteral("duration")]     = static_cast<double>(t.duration);
        o[QStringLiteral("bitrate")]      = t.bitrate;
        o[QStringLiteral("fileSize")]     = static_cast<double>(t.fileSize);
        o[QStringLiteral("lastModified")] = static_cast<double>(t.lastModified);
        o[QStringLiteral("coverThumb")]   = t.coverThumb;
        o[QStringLiteral("rating")]       = t.rating;
        o[QStringLiteral("ratingId")]     = t.ratingId.toString(QUuid::WithoutBraces);
        arr.append(o);
    }

    QJsonObject root;
    root[QStringLiteral("version")] = 1;
    root[QStringLiteral("tracks")]  = arr;

    const QString tmpPath = cacheFilePath() + QStringLiteral(".tmp");
    QFile tmp(tmpPath);
    if (!tmp.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    tmp.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    tmp.close();

    // Atomic replace
    QFile::remove(cacheFilePath());
    return tmp.rename(cacheFilePath());
}
