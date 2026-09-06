#include "ratingcache.h"

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

QString RatingCache::cacheFilePath()
{
    return appDataDir() + QStringLiteral("/Topaz.rating.json");
}

// ── Shared JSON <-> Entry list ───────────────────────────────────────────

QList<RatingCache::Entry> RatingCache::loadEntries()
{
    QFile f(cacheFilePath());
    if (!f.open(QIODevice::ReadOnly)) return {};
    const QByteArray json = f.readAll();
    f.close();
    return parseEntries(json);
}

QList<RatingCache::Entry> RatingCache::parseEntries(const QByteArray &json)
{
    QList<Entry> entries;

    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) return entries;

    const QJsonObject root = doc.object();
    const QJsonArray  arr  = root[QStringLiteral("ratings")].toArray();

    entries.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        const QUuid id = QUuid::fromString(o[QStringLiteral("ratingId")].toString());
        const int   r  = o[QStringLiteral("rating")].toInt();
        if (id.isNull() || r < 1 || r > 10) continue; // skip invalid entries defensively
        entries.append({ o[QStringLiteral("genre")].toString(), id, r });
    }
    return entries;
}

bool RatingCache::saveEntries(const QList<Entry> &entries)
{
    QJsonArray arr;
    for (const Entry &e : entries) {
        QJsonObject o;
        o[QStringLiteral("genre")]    = e.genre;
        o[QStringLiteral("ratingId")] = e.ratingId.toString(QUuid::WithoutBraces);
        o[QStringLiteral("rating")]   = e.rating;
        arr.append(o);
    }

    QJsonObject root;
    root[QStringLiteral("version")] = 1;
    root[QStringLiteral("ratings")] = arr;

    const QString tmpPath = cacheFilePath() + QStringLiteral(".tmp");
    QFile tmp(tmpPath);
    if (!tmp.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    tmp.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    tmp.close();

    // Atomic replace
    QFile::remove(cacheFilePath());
    return tmp.rename(cacheFilePath());
}

// ─────────────────────────────────────────────────────────────────────────

QHash<QUuid, int> RatingCache::load()
{
    QHash<QUuid, int> ratings;
    const QList<Entry> entries = loadEntries();
    ratings.reserve(entries.size());
    for (const Entry &e : entries)
        ratings.insert(e.ratingId, e.rating);
    return ratings;
}

bool RatingCache::save(const QList<TrackInfo> &tracks)
{
    QList<Entry> entries;
    entries.reserve(tracks.size());
    for (const TrackInfo &t : tracks) {
        if (t.rating < 1 || t.rating > 10) continue; // only persist actually-rated tracks
        entries.append({ t.genre, t.ratingId, t.rating });
    }
    return saveEntries(entries);
}

bool RatingCache::setRating(const QString &genre, const QUuid &ratingId, int rating)
{
    if (ratingId.isNull() || rating < 1 || rating > 10) return false;

    QList<Entry> entries = loadEntries();
    bool found = false;
    for (Entry &e : entries) {
        if (e.ratingId == ratingId) {
            e.genre  = genre;
            e.rating = rating;
            found = true;
            break;
        }
    }
    if (!found) entries.append({ genre, ratingId, rating });

    return saveEntries(entries);
}
