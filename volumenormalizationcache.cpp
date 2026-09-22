#include "volumenormalizationcache.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

#include <QtNumeric>

#include <algorithm>
#include <cmath>

QString VolumeNormalizationCache::cacheFilePath()
{
    const QString dir =
        QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/Topaz.volumeNormalization.json");
}

QHash<QUuid, VolumeNormalizationCache::Entry> VolumeNormalizationCache::load()
{
    QHash<QUuid, Entry> entries;

    QFile f(cacheFilePath());
    if (!f.open(QIODevice::ReadOnly)) return entries;
    const QByteArray json = f.readAll();
    f.close();

    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) return entries;

    const QJsonArray arr = doc.object()[QStringLiteral("normalizations")].toArray();
    entries.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        Entry e;
        e.id = QUuid::fromString(o[QStringLiteral("normalizationId")].toString());
        e.dB = o[QStringLiteral("dB")].toDouble(qQNaN());
        if (e.id.isNull() || std::isnan(e.dB) || e.dB < -60.0 || e.dB > 60.0)
            continue;   // skip invalid entries defensively
        e.genre    = o[QStringLiteral("genre")].toString();
        e.source   = o[QStringLiteral("source")].toString();
        e.peak     = o[QStringLiteral("peak")].toDouble(0.0);
        e.fileSize = qint64(o[QStringLiteral("fileSize")].toDouble(0.0));
        entries.insert(e.id, e);
    }
    return entries;
}

bool VolumeNormalizationCache::save(const QHash<QUuid, Entry> &entries)
{
    // Stable order (by id) so the file doesn't reshuffle on every save.
    QList<Entry> sorted = entries.values();
    std::sort(sorted.begin(), sorted.end(),
              [](const Entry &a, const Entry &b) { return a.id < b.id; });

    QJsonArray arr;
    for (const Entry &e : std::as_const(sorted)) {
        QJsonObject o;
        o[QStringLiteral("genre")]           = e.genre;
        o[QStringLiteral("normalizationId")] = e.id.toString(QUuid::WithoutBraces);
        o[QStringLiteral("dB")]              = std::round(e.dB * 100.0) / 100.0;
        o[QStringLiteral("source")]          = e.source;
        o[QStringLiteral("peak")]            = std::round(e.peak * 10000.0) / 10000.0;
        o[QStringLiteral("fileSize")]        = double(e.fileSize);   // exact up to 2^53 bytes
        arr.append(o);
    }

    QJsonObject root;
    root[QStringLiteral("version")]        = 1;
    root[QStringLiteral("normalizations")] = arr;

    const QString tmpPath = cacheFilePath() + QStringLiteral(".tmp");
    QFile tmp(tmpPath);
    if (!tmp.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    tmp.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    tmp.close();

    // Atomic replace
    QFile::remove(cacheFilePath());
    return tmp.rename(cacheFilePath());
}
