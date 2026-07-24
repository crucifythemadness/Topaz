#include "appconfig.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QStandardPaths>
#include <QUrl>
#include <cmath>

AppConfig::AppConfig(QObject *parent)
    : QObject(parent)
{
    load();
}

// ── Paths ─────────────────────────────────────────────────────────────────

QString AppConfig::configFilePath() const
{
    const QString dir =
        QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/Topaz.config");
}

// ── Accessors ─────────────────────────────────────────────────────────────

QStringList AppConfig::genres() const
{
    return m_genres;
}

QVariantList AppConfig::folders() const
{
    return m_folders;
}

// ── Genre operations ──────────────────────────────────────────────────────

void AppConfig::addGenre(const QString &name)
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty())
        return;
    // Case-insensitive duplicate check
    for (const QString &g : std::as_const(m_genres)) {
        if (g.compare(trimmed, Qt::CaseInsensitive) == 0)
            return;
    }
    m_genres.append(trimmed);
    emit genresChanged();
    save();
}

void AppConfig::removeGenreAt(int index)
{
    if (index < 0 || index >= m_genres.size())
        return;
    m_genres.removeAt(index);
    emit genresChanged();
    save();
}

void AppConfig::clearGenres()
{
    if (m_genres.isEmpty())
        return;
    m_genres.clear();
    emit genresChanged();
    save();
}

// ── Folder operations ─────────────────────────────────────────────────────

void AppConfig::addFolder(const QString &rawPath, bool includeSubfolders)
{
    // Accept both plain paths and file:// URLs
    QUrl url(rawPath);
    const QString path = url.isLocalFile() ? url.toLocalFile() : rawPath.trimmed();
    if (path.isEmpty())
        return;

    // Deduplicate
    for (const QVariant &v : std::as_const(m_folders)) {
        if (v.toMap().value(QStringLiteral("path")).toString() == path)
            return;
    }

    QVariantMap entry;
    entry[QStringLiteral("path")]              = path;
    entry[QStringLiteral("includeSubfolders")] = includeSubfolders;
    m_folders.append(entry);
    emit foldersChanged();
    save();
}

void AppConfig::removeFolderAt(int index)
{
    if (index < 0 || index >= m_folders.size())
        return;
    m_folders.removeAt(index);
    emit foldersChanged();
    save();
}

void AppConfig::clearFolders()
{
    if (m_folders.isEmpty())
        return;
    m_folders.clear();
    emit foldersChanged();
    save();
}

void AppConfig::setFolderSubfolders(int index, bool includeSubfolders)
{
    if (index < 0 || index >= m_folders.size())
        return;
    QVariantMap entry = m_folders.at(index).toMap();
    entry[QStringLiteral("includeSubfolders")] = includeSubfolders;
    m_folders[index] = entry;
    emit foldersChanged();
    save();
}

// ── Layout persistence ────────────────────────────────────────────────

void AppConfig::saveLayout(int windowWidth, int windowHeight,
                            int libraryTreeWidth, int playbackQueueWidth,
                            int nowPlayingWidth)
{
    m_windowWidth        = windowWidth;
    m_windowHeight       = windowHeight;
    m_libraryTreeWidth   = libraryTreeWidth;
    m_playbackQueueWidth = playbackQueueWidth;
    m_nowPlayingWidth    = nowPlayingWidth;
    save();
}

// ── Crossfade operations ──────────────────────────────────────────────────

void AppConfig::setCrossfadeEnabled(bool enabled)
{
    if (m_crossfadeEnabled == enabled) return;
    m_crossfadeEnabled = enabled;
    emit crossfadeChanged();
    save();
}

void AppConfig::setCrossfadeSeconds(double seconds)
{
    seconds = qBound(2.0, seconds, 10.0);
    seconds = std::round(seconds * 2.0) / 2.0;   // snap to nearest 0.5 s
    if (qFuzzyCompare(m_crossfadeSeconds, seconds)) return;
    m_crossfadeSeconds = seconds;
    emit crossfadeChanged();
    save();
}

// ── Persistence ───────────────────────────────────────────────────────────

void AppConfig::load()
{
    QFile f(configFilePath());
    if (!f.open(QIODevice::ReadOnly))
        return;

    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    f.close();

    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return;

    const QJsonObject root = doc.object();

    m_genres.clear();
    const QJsonArray genresArr = root[QStringLiteral("genres")].toArray();
    for (const QJsonValue &v : genresArr)
        m_genres.append(v.toString());

    m_folders.clear();
    const QJsonArray foldersArr = root[QStringLiteral("folders")].toArray();
    for (const QJsonValue &v : foldersArr) {
        const QJsonObject fo = v.toObject();
        QVariantMap entry;
        entry[QStringLiteral("path")]              = fo[QStringLiteral("path")].toString();
        entry[QStringLiteral("includeSubfolders")] = fo[QStringLiteral("includeSubfolders")].toBool(false);
        m_folders.append(entry);
    }

    // Layout state — fall back to defaults when key is absent
    m_windowWidth        = root[QStringLiteral("windowWidth")].toInt(1920);
    m_windowHeight       = root[QStringLiteral("windowHeight")].toInt(1080);
    m_libraryTreeWidth   = root[QStringLiteral("libraryTreeWidth")].toInt(286);
    m_playbackQueueWidth = root[QStringLiteral("playbackQueueWidth")].toInt(374);
    m_nowPlayingWidth    = root[QStringLiteral("nowPlayingWidth")].toInt(359);

    m_crossfadeEnabled = root[QStringLiteral("crossfadeEnabled")].toBool(false);
    m_crossfadeSeconds = root[QStringLiteral("crossfadeSeconds")].toDouble(5.0);
}

void AppConfig::save()
{
    QJsonObject root;

    QJsonArray genresArr;
    for (const QString &g : std::as_const(m_genres))
        genresArr.append(g);
    root[QStringLiteral("genres")] = genresArr;

    QJsonArray foldersArr;
    for (const QVariant &v : std::as_const(m_folders)) {
        const QVariantMap m = v.toMap();
        QJsonObject fo;
        fo[QStringLiteral("path")]              = m[QStringLiteral("path")].toString();
        fo[QStringLiteral("includeSubfolders")] = m[QStringLiteral("includeSubfolders")].toBool();
        foldersArr.append(fo);
    }
    root[QStringLiteral("folders")] = foldersArr;

    root[QStringLiteral("windowWidth")]        = m_windowWidth;
    root[QStringLiteral("windowHeight")]       = m_windowHeight;
    root[QStringLiteral("libraryTreeWidth")]   = m_libraryTreeWidth;
    root[QStringLiteral("playbackQueueWidth")] = m_playbackQueueWidth;
    root[QStringLiteral("nowPlayingWidth")]    = m_nowPlayingWidth;

    root[QStringLiteral("crossfadeEnabled")] = m_crossfadeEnabled;
    root[QStringLiteral("crossfadeSeconds")] = m_crossfadeSeconds;

    QFile f(configFilePath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    f.close();
}
