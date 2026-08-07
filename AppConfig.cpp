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

// ── AUTO PLAY operations ──────────────────────────────────────────────────

void AppConfig::setAutoPlayQueueHorizon(int tracks)
{
    tracks = qBound(1, tracks, 15);
    if (m_autoPlayQueueHorizon == tracks) return;
    m_autoPlayQueueHorizon = tracks;
    emit autoPlayQueueHorizonChanged();
    save();
}

void AppConfig::setAutoPlayTitleAddingIntervalSeconds(int seconds)
{
    seconds = qBound(5, seconds, 90);
    if (m_autoPlayTitleAddingIntervalSeconds == seconds) return;
    m_autoPlayTitleAddingIntervalSeconds = seconds;
    emit autoPlayTitleAddingIntervalSecondsChanged();
    save();
}

void AppConfig::setAutoPlayConsiderGenre(bool enabled)
{
    if (m_autoPlayConsiderGenre == enabled) return;
    m_autoPlayConsiderGenre = enabled;
    emit autoPlayConsiderGenreChanged();
    save();
}

void AppConfig::setAutoPlayConsiderRating(bool enabled)
{
    if (m_autoPlayConsiderRating == enabled) return;
    m_autoPlayConsiderRating = enabled;
    emit autoPlayConsiderRatingChanged();
    save();
}

void AppConfig::setAutoPlayMinimumRating(int rating)
{
    rating = qBound(1, rating, 10);
    if (m_autoPlayMinimumRating == rating) return;
    m_autoPlayMinimumRating = rating;
    emit autoPlayMinimumRatingChanged();
    save();
}

void AppConfig::setAutoPlayAllowManualModification(bool enabled)
{
    if (m_autoPlayAllowManualModification == enabled) return;
    m_autoPlayAllowManualModification = enabled;
    emit autoPlayAllowManualModificationChanged();
    save();
}

void AppConfig::setAutoPlaySongRepeat(const QString &mode)
{
    static const QStringList kAllowed = {
        QStringLiteral("once"), QStringLiteral("twice"),
        QStringLiteral("twiceIfNoneAvailable"), QStringLiteral("several")
    };
    if (!kAllowed.contains(mode)) return;
    if (m_autoPlaySongRepeat == mode) return;
    m_autoPlaySongRepeat = mode;
    emit autoPlaySongRepeatChanged();
    save();
}

void AppConfig::setAutoPlayTransportAccess(const QString &mode)
{
    static const QStringList kAllowed = {
        QStringLiteral("nothing"), QStringLiteral("playPause"),
        QStringLiteral("playPauseAndSelect")
    };
    if (!kAllowed.contains(mode)) return;
    if (m_autoPlayTransportAccess == mode) return;
    m_autoPlayTransportAccess = mode;
    emit autoPlayTransportAccessChanged();
    save();
}

// ── Big cover pane geometry ─────────────────────────────────────────────────

void AppConfig::saveBigCoverPaneGeometry(int x, int y, int width, int height,
                                          const QString &screenName)
{
    m_bigCoverPaneConfigured = true;
    m_bigCoverPaneX          = x;
    m_bigCoverPaneY          = y;
    m_bigCoverPaneWidth      = width;
    m_bigCoverPaneHeight     = height;
    m_bigCoverPaneScreenName = screenName;
    emit bigCoverPaneChanged();
    save();
}

// ── Tag info pane geometry ──────────────────────────────────────────────────

void AppConfig::saveTagInfoPaneGeometry(int x, int y, int width, int height,
                                         const QString &screenName)
{
    m_tagInfoPaneConfigured = true;
    m_tagInfoPaneX          = x;
    m_tagInfoPaneY          = y;
    m_tagInfoPaneWidth      = width;
    m_tagInfoPaneHeight     = height;
    m_tagInfoPaneScreenName = screenName;
    emit tagInfoPaneChanged();
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

    const QJsonObject crossfade = root[QStringLiteral("crossfade")].toObject();
    m_crossfadeEnabled = crossfade[QStringLiteral("enabled")].toBool(false);
    m_crossfadeSeconds = crossfade[QStringLiteral("seconds")].toDouble(5.0);

    const QJsonObject autoPlay = root[QStringLiteral("autoPlay")].toObject();
    m_autoPlayQueueHorizon   = autoPlay[QStringLiteral("queueHorizon")].toInt(5);
    m_autoPlayTitleAddingIntervalSeconds =
        autoPlay[QStringLiteral("titleAddingIntervalSeconds")].toInt(30);
    m_autoPlayConsiderGenre  = autoPlay[QStringLiteral("considerGenre")].toBool(false);
    m_autoPlayConsiderRating = autoPlay[QStringLiteral("considerRating")].toBool(false);
    m_autoPlayMinimumRating  = autoPlay[QStringLiteral("minimumRating")].toInt(5);
    m_autoPlayAllowManualModification =
        autoPlay[QStringLiteral("allowManualModification")].toBool(false);
    m_autoPlaySongRepeat =
        autoPlay[QStringLiteral("songRepeat")].toString(QStringLiteral("once"));
    m_autoPlayTransportAccess =
        autoPlay[QStringLiteral("transportAccess")].toString(QStringLiteral("nothing"));

    // Key presence, not a stored bool, is the "configured" signal — absence
    // means the pane has never been positioned yet (first-ever open).
    m_bigCoverPaneConfigured = root.contains(QStringLiteral("bigCoverPane"));
    const QJsonObject bigCoverPane = root[QStringLiteral("bigCoverPane")].toObject();
    m_bigCoverPaneX          = bigCoverPane[QStringLiteral("x")].toInt(0);
    m_bigCoverPaneY          = bigCoverPane[QStringLiteral("y")].toInt(0);
    m_bigCoverPaneWidth      = bigCoverPane[QStringLiteral("width")].toInt(400);
    m_bigCoverPaneHeight     = bigCoverPane[QStringLiteral("height")].toInt(400);
    m_bigCoverPaneScreenName = bigCoverPane[QStringLiteral("screenName")].toString();

    m_tagInfoPaneConfigured = root.contains(QStringLiteral("tagInfoPane"));
    const QJsonObject tagInfoPane = root[QStringLiteral("tagInfoPane")].toObject();
    m_tagInfoPaneX          = tagInfoPane[QStringLiteral("x")].toInt(0);
    m_tagInfoPaneY          = tagInfoPane[QStringLiteral("y")].toInt(0);
    m_tagInfoPaneWidth      = tagInfoPane[QStringLiteral("width")].toInt(500);
    m_tagInfoPaneHeight     = tagInfoPane[QStringLiteral("height")].toInt(230);
    m_tagInfoPaneScreenName = tagInfoPane[QStringLiteral("screenName")].toString();
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

    QJsonObject crossfade;
    crossfade[QStringLiteral("enabled")] = m_crossfadeEnabled;
    crossfade[QStringLiteral("seconds")] = m_crossfadeSeconds;
    root[QStringLiteral("crossfade")] = crossfade;

    QJsonObject autoPlay;
    autoPlay[QStringLiteral("queueHorizon")]   = m_autoPlayQueueHorizon;
    autoPlay[QStringLiteral("titleAddingIntervalSeconds")] = m_autoPlayTitleAddingIntervalSeconds;
    autoPlay[QStringLiteral("considerGenre")]  = m_autoPlayConsiderGenre;
    autoPlay[QStringLiteral("considerRating")] = m_autoPlayConsiderRating;
    autoPlay[QStringLiteral("minimumRating")]  = m_autoPlayMinimumRating;
    autoPlay[QStringLiteral("allowManualModification")] = m_autoPlayAllowManualModification;
    autoPlay[QStringLiteral("songRepeat")] = m_autoPlaySongRepeat;
    autoPlay[QStringLiteral("transportAccess")] = m_autoPlayTransportAccess;
    root[QStringLiteral("autoPlay")] = autoPlay;

    if (m_bigCoverPaneConfigured) {
        QJsonObject bigCoverPane;
        bigCoverPane[QStringLiteral("x")]          = m_bigCoverPaneX;
        bigCoverPane[QStringLiteral("y")]          = m_bigCoverPaneY;
        bigCoverPane[QStringLiteral("width")]      = m_bigCoverPaneWidth;
        bigCoverPane[QStringLiteral("height")]     = m_bigCoverPaneHeight;
        bigCoverPane[QStringLiteral("screenName")] = m_bigCoverPaneScreenName;
        root[QStringLiteral("bigCoverPane")] = bigCoverPane;
    }

    if (m_tagInfoPaneConfigured) {
        QJsonObject tagInfoPane;
        tagInfoPane[QStringLiteral("x")]          = m_tagInfoPaneX;
        tagInfoPane[QStringLiteral("y")]          = m_tagInfoPaneY;
        tagInfoPane[QStringLiteral("width")]      = m_tagInfoPaneWidth;
        tagInfoPane[QStringLiteral("height")]     = m_tagInfoPaneHeight;
        tagInfoPane[QStringLiteral("screenName")] = m_tagInfoPaneScreenName;
        root[QStringLiteral("tagInfoPane")] = tagInfoPane;
    }

    QFile f(configFilePath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    f.close();
}
