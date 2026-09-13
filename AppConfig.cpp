#include "appconfig.h"
#include "volumepath.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QStandardPaths>
#include <QStorageInfo>
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

QStringList AppConfig::enabledGenres() const
{
    QStringList result;
    for (const QString &g : m_genres) {
        if (m_enabledGenreSet.contains(g))
            result.append(g);
    }
    return result;
}

QVariantList AppConfig::folders() const
{
    // m_folders persists {volume, relPath, rawPath, includeSubfolders}; each
    // returned entry additionally carries a freshly resolved "path" (absolute,
    // empty if the volume isn't currently mounted) and "available" flag, so QML
    // and LibraryScanner keep seeing a ready-to-use absolute path.
    const QList<QStorageInfo> mounted = QStorageInfo::mountedVolumes();

    QVariantList result;
    result.reserve(m_folders.size());
    for (const QVariant &v : std::as_const(m_folders)) {
        QVariantMap entry = v.toMap();
        const VolumePath vp = VolumePath::fromVariantMap(entry);
        const QString path = vp.resolve(mounted);
        entry[QStringLiteral("path")]      = path;
        entry[QStringLiteral("available")] = !path.isEmpty();
        result.append(entry);
    }
    return result;
}

// ── Genre operations ──────────────────────────────────────────────────────

void AppConfig::addGenre(const QString &name)
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty())
        return;
    if (m_genres.size() >= kMaxGenres)
        return;
    // Case-insensitive duplicate check
    for (const QString &g : std::as_const(m_genres)) {
        if (g.compare(trimmed, Qt::CaseInsensitive) == 0)
            return;
    }
    m_genres.append(trimmed);
    // Default a new genre to enabled while under the cap -- preserves today's
    // behavior (every configured genre shows in GenreBar) for anyone who
    // never exceeds kMaxEnabledGenres.
    bool nowEnabled = false;
    if (m_enabledGenreSet.size() < kMaxEnabledGenres) {
        m_enabledGenreSet.insert(trimmed);
        nowEnabled = true;
    }
    emit genresChanged();
    if (nowEnabled) emit enabledGenresChanged();
    save();
}

void AppConfig::removeGenreAt(int index)
{
    if (index < 0 || index >= m_genres.size())
        return;
    const QString name = m_genres.at(index);
    m_genres.removeAt(index);
    const bool wasEnabled = m_enabledGenreSet.remove(name);
    emit genresChanged();
    if (wasEnabled) emit enabledGenresChanged();
    save();
}

void AppConfig::moveGenre(int from, int to)
{
    if (from == to)
        return;
    if (from < 0 || from >= m_genres.size())
        return;
    if (to   < 0 || to   >= m_genres.size())
        return;

    // enabledGenres() is derived from m_genres' order, so a reorder can
    // change its *value* without changing membership at all -- snapshot it
    // to avoid firing enabledGenresChanged (and resetting the live
    // genre/artist/album selection via LibraryData.rebuildGenreModel())
    // when only disabled genres moved past each other.
    const QStringList enabledBefore = enabledGenres();

    m_genres.move(from, to);

    emit genresChanged();
    if (enabledGenres() != enabledBefore)
        emit enabledGenresChanged();
    save();
}

void AppConfig::clearGenres()
{
    if (m_genres.isEmpty())
        return;
    m_genres.clear();
    const bool hadEnabled = !m_enabledGenreSet.isEmpty();
    m_enabledGenreSet.clear();
    emit genresChanged();
    if (hadEnabled) emit enabledGenresChanged();
    save();
}

bool AppConfig::isGenreEnabled(const QString &name) const
{
    return m_enabledGenreSet.contains(name);
}

bool AppConfig::setGenreEnabled(const QString &name, bool enabled)
{
    if (!m_genres.contains(name))
        return false;
    const bool currentlyEnabled = m_enabledGenreSet.contains(name);
    if (currentlyEnabled == enabled)
        return true;
    if (enabled && m_enabledGenreSet.size() >= kMaxEnabledGenres)
        return false;
    if (enabled) m_enabledGenreSet.insert(name);
    else         m_enabledGenreSet.remove(name);
    emit enabledGenresChanged();
    save();
    return true;
}

// ── Folder operations ─────────────────────────────────────────────────────

void AppConfig::addFolder(const QString &rawPath, bool includeSubfolders)
{
    // Accept both plain paths and file:// URLs
    QUrl url(rawPath);
    const QString path = url.isLocalFile() ? url.toLocalFile() : rawPath.trimmed();
    if (path.isEmpty())
        return;

    const VolumePath vp = VolumePath::fromAbsolutePath(path);

    // Deduplicate by (volume, relPath) — fall back to rawPath when relPath
    // couldn't be determined (no containing volume identified).
    for (const QVariant &v : std::as_const(m_folders)) {
        const QVariantMap existing = v.toMap();
        if (!vp.relativePath.isEmpty()) {
            if (existing.value(QStringLiteral("volume")).toString() == vp.volumeName
                && existing.value(QStringLiteral("relPath")).toString() == vp.relativePath)
                return;
        } else if (existing.value(QStringLiteral("rawPath")).toString() == vp.rawPath) {
            return;
        }
    }

    QVariantMap entry = vp.toVariantMap();
    entry[QStringLiteral("includeSubfolders")] = includeSubfolders;
    entry[QStringLiteral("active")] = true;
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

void AppConfig::setFolderActive(int index, bool active)
{
    if (index < 0 || index >= m_folders.size())
        return;
    QVariantMap entry = m_folders.at(index).toMap();
    entry[QStringLiteral("active")] = active;
    m_folders[index] = entry;
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
    seconds = qBound(2.0, seconds, 12.0);
    seconds = std::round(seconds * 2.0) / 2.0;   // snap to nearest 0.5 s
    if (qFuzzyCompare(m_crossfadeSeconds, seconds)) return;
    m_crossfadeSeconds = seconds;
    emit crossfadeChanged();
    save();
}

void AppConfig::setAudioBackend(const QString &mode)
{
    if (mode != QStringLiteral("ffmpeg") && mode != QStringLiteral("bass"))
        return;
    if (m_audioBackend == mode) return;
    m_audioBackend = mode;
    emit audioBackendChanged();
    save();
}

bool AppConfig::bassLibraryAvailable() const
{
    const QString dir = QCoreApplication::applicationDirPath();
#if defined(_WIN32)
    return QFile::exists(dir + QStringLiteral("/bass.dll"))
        && QFile::exists(dir + QStringLiteral("/bassflac.dll"))
        && QFile::exists(dir + QStringLiteral("/bassopus.dll"));
#else
    return QFile::exists(dir + QStringLiteral("/libbass.so"))
        && QFile::exists(dir + QStringLiteral("/libbassflac.so"))
        && QFile::exists(dir + QStringLiteral("/libbassopus.so"));
#endif
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

void AppConfig::setAutoPlayFlickerNewTracks(bool enabled)
{
    if (m_autoPlayFlickerNewTracks == enabled) return;
    m_autoPlayFlickerNewTracks = enabled;
    emit autoPlayFlickerNewTracksChanged();
    save();
}

void AppConfig::setStartFullscreen(bool enabled)
{
    if (m_startFullscreen == enabled) return;
    m_startFullscreen = enabled;
    emit startFullscreenChanged();
    save();
}

void AppConfig::setDeleteCurrentRatingEnabled(bool enabled)
{
    if (m_deleteCurrentRatingEnabled == enabled) return;
    m_deleteCurrentRatingEnabled = enabled;
    emit deleteCurrentRatingEnabledChanged();
    save();
}

void AppConfig::setAlbumBrowserSortOrder(const QString &mode)
{
    static const QStringList kAllowed = {
        QStringLiteral("artistYearAlbum"), QStringLiteral("artistAlbum")
    };
    if (!kAllowed.contains(mode)) return;
    if (m_albumBrowserSortOrder == mode) return;
    m_albumBrowserSortOrder = mode;
    emit albumBrowserSortOrderChanged();
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

// ── Audio visualizer settings ───────────────────────────────────────────────

void AppConfig::setAudioVisualizerBarCount(int count)
{
    count = qBound(8, count, 64);
    if (m_audioVisualizerBarCount == count) return;
    m_audioVisualizerBarCount = count;
    emit audioVisualizerChanged();
    save();
}

void AppConfig::setAudioVisualizerColor(const QString &color)
{
    if (color.isEmpty() || m_audioVisualizerColor == color) return;
    m_audioVisualizerColor = color;
    emit audioVisualizerChanged();
    save();
}

void AppConfig::setAudioVisualizerDecaySpeed(double speed)
{
    speed = qBound(0.0, speed, 1.0);
    if (qFuzzyCompare(m_audioVisualizerDecaySpeed, speed)) return;
    m_audioVisualizerDecaySpeed = speed;
    emit audioVisualizerChanged();
    save();
}

void AppConfig::setAudioVisualizerSensitivity(double sensitivity)
{
    sensitivity = qBound(0.0, sensitivity, 1.0);
    if (qFuzzyCompare(m_audioVisualizerSensitivity, sensitivity)) return;
    m_audioVisualizerSensitivity = sensitivity;
    emit audioVisualizerChanged();
    save();
}

void AppConfig::setAudioVisualizerPeakHoldEnabled(bool enabled)
{
    if (m_audioVisualizerPeakHoldEnabled == enabled) return;
    m_audioVisualizerPeakHoldEnabled = enabled;
    emit audioVisualizerChanged();
    save();
}

void AppConfig::setAudioVisualizerPaneOpacity(double opacity)
{
    opacity = qBound(0.0, opacity, 1.0);
    if (qFuzzyCompare(m_audioVisualizerPaneOpacity, opacity)) return;
    m_audioVisualizerPaneOpacity = opacity;
    emit audioVisualizerChanged();
    save();
}

void AppConfig::setAudioVisualizerBarOpacity(double opacity)
{
    opacity = qBound(0.0, opacity, 1.0);
    if (qFuzzyCompare(m_audioVisualizerBarOpacity, opacity)) return;
    m_audioVisualizerBarOpacity = opacity;
    emit audioVisualizerChanged();
    save();
}

// ── Audio visualizer pane geometry ──────────────────────────────────────────

void AppConfig::saveAudioVisualizerPaneGeometry(int x, int y, int width, int height,
                                                 const QString &screenName)
{
    m_audioVisualizerPaneConfigured = true;
    m_audioVisualizerPaneX          = x;
    m_audioVisualizerPaneY          = y;
    m_audioVisualizerPaneWidth      = width;
    m_audioVisualizerPaneHeight     = height;
    m_audioVisualizerPaneScreenName = screenName;
    emit audioVisualizerPaneChanged();
    save();
}

// ── Milkdrop settings ────────────────────────────────────────────────────────

void AppConfig::addMilkdropPresetFolder(const QString &rawPath)
{
    // Accept both plain paths and file:// URLs — same convention as addFolder.
    QUrl url(rawPath);
    const QString path = url.isLocalFile() ? url.toLocalFile() : rawPath.trimmed();
    if (path.isEmpty())
        return;

    for (const QVariant &v : std::as_const(m_milkdropPresetFolders)) {
        if (v.toMap().value(QStringLiteral("path")).toString() == path)
            return;
    }

    QVariantMap entry;
    entry[QStringLiteral("path")]   = path;
    entry[QStringLiteral("active")] = true;
    m_milkdropPresetFolders.append(entry);
    emit milkdropChanged();
    save();
}

void AppConfig::removeMilkdropPresetFolderAt(int index)
{
    if (index < 0 || index >= m_milkdropPresetFolders.size())
        return;
    m_milkdropPresetFolders.removeAt(index);
    emit milkdropChanged();
    save();
}

void AppConfig::clearMilkdropPresetFolders()
{
    if (m_milkdropPresetFolders.isEmpty())
        return;
    m_milkdropPresetFolders.clear();
    emit milkdropChanged();
    save();
}

void AppConfig::setMilkdropPresetFolderActive(int index, bool active)
{
    if (index < 0 || index >= m_milkdropPresetFolders.size())
        return;
    QVariantMap entry = m_milkdropPresetFolders.at(index).toMap();
    entry[QStringLiteral("active")] = active;
    m_milkdropPresetFolders[index] = entry;
    emit milkdropChanged();
    save();
}

void AppConfig::setMilkdropShuffleEnabled(bool enabled)
{
    if (m_milkdropShuffleEnabled == enabled) return;
    m_milkdropShuffleEnabled = enabled;
    emit milkdropChanged();
    save();
}

void AppConfig::setMilkdropPresetDuration(double seconds)
{
    seconds = qBound(10.0, seconds, 150.0);
    if (qFuzzyCompare(m_milkdropPresetDuration, seconds)) return;
    m_milkdropPresetDuration = seconds;
    emit milkdropChanged();
    save();
}

void AppConfig::setMilkdropBeatSensitivity(double sensitivity)
{
    sensitivity = qBound(0.0, sensitivity, 4.0);
    if (qFuzzyCompare(m_milkdropBeatSensitivity, sensitivity)) return;
    m_milkdropBeatSensitivity = sensitivity;
    emit milkdropChanged();
    save();
}

void AppConfig::setMilkdropHardCutsEnabled(bool enabled)
{
    if (m_milkdropHardCutsEnabled == enabled) return;
    m_milkdropHardCutsEnabled = enabled;
    emit milkdropChanged();
    save();
}

void AppConfig::setMilkdropHardCutSensitivity(double sensitivity)
{
    sensitivity = qBound(0.0, sensitivity, 1.0);
    if (qFuzzyCompare(m_milkdropHardCutSensitivity, sensitivity)) return;
    m_milkdropHardCutSensitivity = sensitivity;
    emit milkdropChanged();
    save();
}

void AppConfig::setMilkdropPresetLocked(bool locked)
{
    if (m_milkdropPresetLocked == locked) return;
    m_milkdropPresetLocked = locked;
    emit milkdropChanged();
    save();
}

void AppConfig::setMilkdropShowPresetName(bool enabled)
{
    if (m_milkdropShowPresetName == enabled) return;
    m_milkdropShowPresetName = enabled;
    emit milkdropChanged();
    save();
}

// ── Milkdrop pane geometry ───────────────────────────────────────────────────

void AppConfig::saveMilkdropPaneGeometry(int x, int y, int width, int height,
                                          const QString &screenName)
{
    m_milkdropPaneConfigured = true;
    m_milkdropPaneX          = x;
    m_milkdropPaneY          = y;
    m_milkdropPaneWidth      = width;
    m_milkdropPaneHeight     = height;
    m_milkdropPaneScreenName = screenName;
    emit milkdropPaneChanged();
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

    applyJson(doc.object());
}

void AppConfig::applyJson(const QJsonObject &root)
{
    m_genres.clear();
    const QJsonArray genresArr = root[QStringLiteral("genres")].toArray();
    for (const QJsonValue &v : genresArr)
        m_genres.append(v.toString());

    m_enabledGenreSet.clear();
    if (root.contains(QStringLiteral("enabledGenres"))) {
        const QJsonArray enabledArr = root[QStringLiteral("enabledGenres")].toArray();
        for (const QJsonValue &v : enabledArr) {
            const QString name = v.toString();
            // Defensive: ignore names no longer present in genres(), and never
            // load past kMaxEnabledGenres even if the file was hand-edited.
            if (m_genres.contains(name) && m_enabledGenreSet.size() < kMaxEnabledGenres)
                m_enabledGenreSet.insert(name);
        }
    } else {
        // Migration: no prior concept of enabled/disabled genres existed, so
        // every config file predating this feature implicitly had all its
        // genres shown in GenreBar. Preserve that behavior exactly.
        for (const QString &g : std::as_const(m_genres)) {
            if (m_enabledGenreSet.size() >= kMaxEnabledGenres) break;
            m_enabledGenreSet.insert(g);
        }
    }

    m_folders.clear();
    const QJsonArray foldersArr = root[QStringLiteral("folders")].toArray();
    for (const QJsonValue &v : foldersArr) {
        const QJsonObject fo = v.toObject();
        QVariantMap entry = fo.toVariantMap();
        entry[QStringLiteral("includeSubfolders")] = fo[QStringLiteral("includeSubfolders")].toBool(false);
        entry[QStringLiteral("active")] = fo[QStringLiteral("active")].toBool(true);
        m_folders.append(entry);
    }

    // Layout state — fall back to defaults when key is absent
    m_windowWidth        = root[QStringLiteral("windowWidth")].toInt(1920);
    m_windowHeight       = root[QStringLiteral("windowHeight")].toInt(1080);
    m_libraryTreeWidth   = root[QStringLiteral("libraryTreeWidth")].toInt(286);
    m_playbackQueueWidth = root[QStringLiteral("playbackQueueWidth")].toInt(374);
    m_nowPlayingWidth    = root[QStringLiteral("nowPlayingWidth")].toInt(359);
    m_startFullscreen    = root[QStringLiteral("startFullscreen")].toBool(false);
    m_deleteCurrentRatingEnabled =
        root[QStringLiteral("deleteCurrentRatingEnabled")].toBool(false);
    m_albumBrowserSortOrder =
        root[QStringLiteral("albumBrowserSortOrder")].toString(QStringLiteral("artistYearAlbum"));

    const QJsonObject playback = root[QStringLiteral("playback")].toObject();
    m_crossfadeEnabled = playback[QStringLiteral("crossfadeEnabled")].toBool(false);
    m_crossfadeSeconds = playback[QStringLiteral("crossfadeSeconds")].toDouble(5.0);
    const QString backend = playback[QStringLiteral("audioBackend")].toString();
    m_audioBackend = (backend == QStringLiteral("bass")) ? backend : QStringLiteral("ffmpeg");

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
    m_autoPlayFlickerNewTracks =
        autoPlay[QStringLiteral("flickerNewTracks")].toBool(false);

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

    const QJsonObject audioVisualizer = root[QStringLiteral("audioVisualizer")].toObject();
    m_audioVisualizerBarCount = audioVisualizer[QStringLiteral("barCount")].toInt(24);
    m_audioVisualizerColor =
        audioVisualizer[QStringLiteral("color")].toString(QStringLiteral("#00DAF3"));
    m_audioVisualizerDecaySpeed = audioVisualizer[QStringLiteral("decaySpeed")].toDouble(0.5);
    m_audioVisualizerSensitivity = audioVisualizer[QStringLiteral("sensitivity")].toDouble(0.5);
    m_audioVisualizerPeakHoldEnabled =
        audioVisualizer[QStringLiteral("peakHoldEnabled")].toBool(true);
    m_audioVisualizerPaneOpacity = audioVisualizer[QStringLiteral("paneOpacity")].toDouble(1.0);
    m_audioVisualizerBarOpacity  = audioVisualizer[QStringLiteral("barOpacity")].toDouble(1.0);

    m_audioVisualizerPaneConfigured = root.contains(QStringLiteral("audioVisualizerPane"));
    const QJsonObject audioVisualizerPane = root[QStringLiteral("audioVisualizerPane")].toObject();
    m_audioVisualizerPaneX          = audioVisualizerPane[QStringLiteral("x")].toInt(0);
    m_audioVisualizerPaneY          = audioVisualizerPane[QStringLiteral("y")].toInt(0);
    m_audioVisualizerPaneWidth      = audioVisualizerPane[QStringLiteral("width")].toInt(500);
    m_audioVisualizerPaneHeight     = audioVisualizerPane[QStringLiteral("height")].toInt(260);
    m_audioVisualizerPaneScreenName = audioVisualizerPane[QStringLiteral("screenName")].toString();

    m_milkdropPresetFolders.clear();
    const QJsonObject milkdrop = root[QStringLiteral("milkdrop")].toObject();
    const QJsonArray milkdropFoldersArr = milkdrop[QStringLiteral("presetFolders")].toArray();
    for (const QJsonValue &v : milkdropFoldersArr) {
        if (v.isString()) {
            // Pre-existing config file, written before per-folder "active"
            // existed -- migrate to the current object shape.
            QVariantMap entry;
            entry[QStringLiteral("path")]   = v.toString();
            entry[QStringLiteral("active")] = true;
            m_milkdropPresetFolders.append(entry);
        } else if (v.isObject()) {
            const QJsonObject fo = v.toObject();
            QVariantMap entry;
            entry[QStringLiteral("path")]   = fo[QStringLiteral("path")].toString();
            entry[QStringLiteral("active")] = fo[QStringLiteral("active")].toBool(true);
            m_milkdropPresetFolders.append(entry);
        }
        // Anything else (number, null, array) is malformed -- skip it rather
        // than produce a garbage entry.
    }
    m_milkdropShuffleEnabled = milkdrop[QStringLiteral("shuffleEnabled")].toBool(true);
    m_milkdropPresetDuration = milkdrop[QStringLiteral("presetDuration")].toDouble(20.0);
    m_milkdropBeatSensitivity = milkdrop[QStringLiteral("beatSensitivity")].toDouble(1.0);
    m_milkdropHardCutsEnabled = milkdrop[QStringLiteral("hardCutsEnabled")].toBool(false);
    m_milkdropHardCutSensitivity = milkdrop[QStringLiteral("hardCutSensitivity")].toDouble(0.6);
    m_milkdropPresetLocked = milkdrop[QStringLiteral("presetLocked")].toBool(false);
    m_milkdropShowPresetName = milkdrop[QStringLiteral("showPresetName")].toBool(true);

    m_milkdropPaneConfigured = root.contains(QStringLiteral("milkdropPane"));
    const QJsonObject milkdropPane = root[QStringLiteral("milkdropPane")].toObject();
    m_milkdropPaneX          = milkdropPane[QStringLiteral("x")].toInt(0);
    m_milkdropPaneY          = milkdropPane[QStringLiteral("y")].toInt(0);
    m_milkdropPaneWidth      = milkdropPane[QStringLiteral("width")].toInt(560);
    m_milkdropPaneHeight     = milkdropPane[QStringLiteral("height")].toInt(360);
    m_milkdropPaneScreenName = milkdropPane[QStringLiteral("screenName")].toString();
}

QVariantMap AppConfig::restoreFromJson(const QByteArray &json)
{
    QVariantMap result;

    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        result[QStringLiteral("success")] = false;
        result[QStringLiteral("error")]   = QStringLiteral("Not a valid config file.");
        return result;
    }

    // audioBackend is deliberately preserved from the currently running
    // config, not the backup's -- switching audio backend requires
    // re-initializing the playback deck, which isn't safe to do live from
    // here. See Setup > PLAYBACK to change it afterward if desired.
    const QString keepAudioBackend = m_audioBackend;
    applyJson(doc.object());
    m_audioBackend = keepAudioBackend;

    save();

    emit genresChanged();
    emit enabledGenresChanged();
    emit foldersChanged();
    emit windowGeometryChanged();
    emit panelWidthsChanged();
    emit startFullscreenChanged();
    emit deleteCurrentRatingEnabledChanged();
    emit albumBrowserSortOrderChanged();
    emit crossfadeChanged();
    // audioBackendChanged deliberately NOT emitted -- value is unchanged.
    emit autoPlayQueueHorizonChanged();
    emit autoPlayTitleAddingIntervalSecondsChanged();
    emit autoPlayConsiderGenreChanged();
    emit autoPlayConsiderRatingChanged();
    emit autoPlayMinimumRatingChanged();
    emit autoPlayAllowManualModificationChanged();
    emit autoPlaySongRepeatChanged();
    emit autoPlayTransportAccessChanged();
    emit autoPlayFlickerNewTracksChanged();
    emit bigCoverPaneChanged();
    emit tagInfoPaneChanged();
    emit audioVisualizerChanged();
    emit audioVisualizerPaneChanged();
    emit milkdropChanged();
    emit milkdropPaneChanged();

    result[QStringLiteral("success")] = true;
    result[QStringLiteral("error")]   = QString();
    return result;
}

void AppConfig::save()
{
    QJsonObject root;

    QJsonArray genresArr;
    for (const QString &g : std::as_const(m_genres))
        genresArr.append(g);
    root[QStringLiteral("genres")] = genresArr;

    QJsonArray enabledGenresArr;
    for (const QString &g : std::as_const(m_genres)) {
        if (m_enabledGenreSet.contains(g))
            enabledGenresArr.append(g);
    }
    root[QStringLiteral("enabledGenres")] = enabledGenresArr;

    QJsonArray foldersArr;
    for (const QVariant &v : std::as_const(m_folders))
        foldersArr.append(QJsonObject::fromVariantMap(v.toMap()));
    root[QStringLiteral("folders")] = foldersArr;

    root[QStringLiteral("windowWidth")]        = m_windowWidth;
    root[QStringLiteral("windowHeight")]       = m_windowHeight;
    root[QStringLiteral("libraryTreeWidth")]   = m_libraryTreeWidth;
    root[QStringLiteral("playbackQueueWidth")] = m_playbackQueueWidth;
    root[QStringLiteral("nowPlayingWidth")]    = m_nowPlayingWidth;
    root[QStringLiteral("startFullscreen")]    = m_startFullscreen;
    root[QStringLiteral("deleteCurrentRatingEnabled")] = m_deleteCurrentRatingEnabled;
    root[QStringLiteral("albumBrowserSortOrder")]      = m_albumBrowserSortOrder;

    QJsonObject playback;
    playback[QStringLiteral("crossfadeEnabled")] = m_crossfadeEnabled;
    playback[QStringLiteral("crossfadeSeconds")] = m_crossfadeSeconds;
    playback[QStringLiteral("audioBackend")]     = m_audioBackend;
    root[QStringLiteral("playback")] = playback;

    QJsonObject autoPlay;
    autoPlay[QStringLiteral("queueHorizon")]   = m_autoPlayQueueHorizon;
    autoPlay[QStringLiteral("titleAddingIntervalSeconds")] = m_autoPlayTitleAddingIntervalSeconds;
    autoPlay[QStringLiteral("considerGenre")]  = m_autoPlayConsiderGenre;
    autoPlay[QStringLiteral("considerRating")] = m_autoPlayConsiderRating;
    autoPlay[QStringLiteral("minimumRating")]  = m_autoPlayMinimumRating;
    autoPlay[QStringLiteral("allowManualModification")] = m_autoPlayAllowManualModification;
    autoPlay[QStringLiteral("songRepeat")] = m_autoPlaySongRepeat;
    autoPlay[QStringLiteral("transportAccess")] = m_autoPlayTransportAccess;
    autoPlay[QStringLiteral("flickerNewTracks")] = m_autoPlayFlickerNewTracks;
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

    QJsonObject audioVisualizer;
    audioVisualizer[QStringLiteral("barCount")]        = m_audioVisualizerBarCount;
    audioVisualizer[QStringLiteral("color")]           = m_audioVisualizerColor;
    audioVisualizer[QStringLiteral("decaySpeed")]      = m_audioVisualizerDecaySpeed;
    audioVisualizer[QStringLiteral("sensitivity")]     = m_audioVisualizerSensitivity;
    audioVisualizer[QStringLiteral("peakHoldEnabled")] = m_audioVisualizerPeakHoldEnabled;
    audioVisualizer[QStringLiteral("paneOpacity")]     = m_audioVisualizerPaneOpacity;
    audioVisualizer[QStringLiteral("barOpacity")]      = m_audioVisualizerBarOpacity;
    root[QStringLiteral("audioVisualizer")] = audioVisualizer;

    if (m_audioVisualizerPaneConfigured) {
        QJsonObject audioVisualizerPane;
        audioVisualizerPane[QStringLiteral("x")]          = m_audioVisualizerPaneX;
        audioVisualizerPane[QStringLiteral("y")]          = m_audioVisualizerPaneY;
        audioVisualizerPane[QStringLiteral("width")]      = m_audioVisualizerPaneWidth;
        audioVisualizerPane[QStringLiteral("height")]     = m_audioVisualizerPaneHeight;
        audioVisualizerPane[QStringLiteral("screenName")] = m_audioVisualizerPaneScreenName;
        root[QStringLiteral("audioVisualizerPane")] = audioVisualizerPane;
    }

    QJsonObject milkdrop;
    QJsonArray milkdropFoldersArr;
    for (const QVariant &v : std::as_const(m_milkdropPresetFolders))
        milkdropFoldersArr.append(QJsonObject::fromVariantMap(v.toMap()));
    milkdrop[QStringLiteral("presetFolders")]      = milkdropFoldersArr;
    milkdrop[QStringLiteral("shuffleEnabled")]     = m_milkdropShuffleEnabled;
    milkdrop[QStringLiteral("presetDuration")]     = m_milkdropPresetDuration;
    milkdrop[QStringLiteral("beatSensitivity")]    = m_milkdropBeatSensitivity;
    milkdrop[QStringLiteral("hardCutsEnabled")]    = m_milkdropHardCutsEnabled;
    milkdrop[QStringLiteral("hardCutSensitivity")] = m_milkdropHardCutSensitivity;
    milkdrop[QStringLiteral("presetLocked")]       = m_milkdropPresetLocked;
    milkdrop[QStringLiteral("showPresetName")]     = m_milkdropShowPresetName;
    root[QStringLiteral("milkdrop")] = milkdrop;

    if (m_milkdropPaneConfigured) {
        QJsonObject milkdropPane;
        milkdropPane[QStringLiteral("x")]          = m_milkdropPaneX;
        milkdropPane[QStringLiteral("y")]          = m_milkdropPaneY;
        milkdropPane[QStringLiteral("width")]      = m_milkdropPaneWidth;
        milkdropPane[QStringLiteral("height")]     = m_milkdropPaneHeight;
        milkdropPane[QStringLiteral("screenName")] = m_milkdropPaneScreenName;
        root[QStringLiteral("milkdropPane")] = milkdropPane;
    }

    QFile f(configFilePath());
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    f.close();
}
