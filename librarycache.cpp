#include "librarycache.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

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

    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        TrackInfo t;
        t.id           = QUuid::fromString(o[QStringLiteral("id")].toString());
        if (t.id.isNull()) t.id = QUuid::createUuid();
        t.filePath     = o[QStringLiteral("filePath")].toString();
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
        tracks.append(t);
    }
    return tracks;
}

bool LibraryCache::save(const QList<TrackInfo> &tracks)
{
    QJsonArray arr;

    for (const TrackInfo &t : tracks) {
        QJsonObject o;
        o[QStringLiteral("id")]           = t.id.toString(QUuid::WithoutBraces);
        o[QStringLiteral("filePath")]     = t.filePath;
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
