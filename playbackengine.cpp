#include "playbackengine.h"
#include "ratingcache.h"
#include "tagreader.h"

#include <QCursor>
#include <QFileInfo>
#include <QGuiApplication>
#include <QUrl>
#include <QtConcurrent>

// ── Constructor / Destructor ──────────────────────────────────────────────

PlaybackEngine::PlaybackEngine(QObject *parent)
    : QAbstractListModel(parent)
    , m_player(new QMediaPlayer(this))
    , m_audioOutput(new QAudioOutput(this))
{
    m_player->setAudioOutput(m_audioOutput);
    m_audioOutput->setVolume(1.0f);

    connect(m_player, &QMediaPlayer::positionChanged,
            this, &PlaybackEngine::positionChanged);

    connect(m_player, &QMediaPlayer::durationChanged,
            this, &PlaybackEngine::durationChanged);

    connect(m_player, &QMediaPlayer::playbackStateChanged,
            this, [this](QMediaPlayer::PlaybackState) {
                emit isPlayingChanged();
                if (m_currentIndex >= 0 && m_currentIndex < m_queue.size()) {
                    const QModelIndex idx = index(m_currentIndex);
                    emit dataChanged(idx, idx, { IsPlayingRole });
                }
            });

    connect(m_player, &QMediaPlayer::mediaStatusChanged,
            this, [this](QMediaPlayer::MediaStatus status) {
                if (status == QMediaPlayer::EndOfMedia)
                    advanceToNext();
            });

    connect(&m_coverWatcher, &QFutureWatcher<QByteArray>::finished,
            this, [this]() {
                const QByteArray raw = m_coverWatcher.result();
                m_largeCoverSource = raw.isEmpty()
                    ? QString()
                    : QStringLiteral("data:image/jpeg;base64,") + raw.toBase64();
                emit currentLargeCoverSourceChanged();
            });
}

PlaybackEngine::~PlaybackEngine() = default;

// ── QAbstractListModel ────────────────────────────────────────────────────

int PlaybackEngine::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_queue.size();
}

QVariant PlaybackEngine::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_queue.size())
        return {};

    const TrackInfo &t = m_queue.at(index.row());

    switch (role) {
    case PosRole:
        return QString::number(index.row() + 1).rightJustified(2, '0');
    case TrackNameRole:
        return t.title.isEmpty() ? t.fileName : t.title;
    case SubLabelRole: {
        const QString artist = t.artist.isEmpty() ? t.albumArtist : t.artist;
        QString sub = artist.toUpper();
        if (!t.album.isEmpty()) sub += QStringLiteral(" \u2022 ") + t.album.toUpper();
        return sub;
    }
    case ArtistRole:
        return t.albumArtist.isEmpty() ? t.artist : t.albumArtist;
    case AlbumRole:
        return t.album;
    case BitrateRole:
        return t.bitrate;
    case FormatRole:
        return formatFromPath(t.filePath);
    case FilePathRole:
        return t.filePath;
    case IsPlayingRole:
        return (index.row() == m_currentIndex);
    case DurationStringRole:
        return msToString(t.duration);
    case CoverSourceRole:
        return t.coverThumb.isEmpty()
            ? QString()
            : QStringLiteral("data:image/jpeg;base64,") + t.coverThumb;
    default:
        return {};
    }
}

QHash<int, QByteArray> PlaybackEngine::roleNames() const
{
    return {
        { PosRole,           "pos"         },
        { TrackNameRole,     "trackName"   },
        { SubLabelRole,      "subLabel"    },
        { ArtistRole,        "artist"      },
        { AlbumRole,         "album"       },
        { BitrateRole,       "kbps"        },
        { FormatRole,        "format"      },
        { FilePathRole,      "filePath"    },
        { IsPlayingRole,     "playing"     },
        { DurationStringRole,"durationStr" },
        { CoverSourceRole,   "coverSource" }
    };
}

// ── Properties ────────────────────────────────────────────────────────────

bool PlaybackEngine::isPlaying() const
{
    return m_player->playbackState() == QMediaPlayer::PlayingState;
}

qint64 PlaybackEngine::position() const { return m_player->position(); }
qint64 PlaybackEngine::duration() const { return m_player->duration(); }

QString PlaybackEngine::positionString() const { return msToString(m_player->position()); }
QString PlaybackEngine::durationString() const { return msToString(m_player->duration()); }

QString PlaybackEngine::currentTitle() const
{
    if (m_currentIndex < 0 || m_currentIndex >= m_queue.size()) return {};
    const TrackInfo &t = m_queue.at(m_currentIndex);
    return t.title.isEmpty() ? t.fileName : t.title;
}

QString PlaybackEngine::currentArtist() const
{
    if (m_currentIndex < 0 || m_currentIndex >= m_queue.size()) return {};
    const TrackInfo &t = m_queue.at(m_currentIndex);
    return t.artist.isEmpty() ? t.albumArtist : t.artist;
}

QString PlaybackEngine::currentAlbum() const
{
    if (m_currentIndex < 0 || m_currentIndex >= m_queue.size()) return {};
    return m_queue.at(m_currentIndex).album;
}

QString PlaybackEngine::currentFormat() const
{
    if (m_currentIndex < 0 || m_currentIndex >= m_queue.size()) return {};
    return formatFromPath(m_queue.at(m_currentIndex).filePath);
}

int PlaybackEngine::currentBitrate() const
{
    if (m_currentIndex < 0 || m_currentIndex >= m_queue.size()) return 0;
    return m_queue.at(m_currentIndex).bitrate;
}

int PlaybackEngine::currentRating() const
{
    if (m_currentIndex < 0 || m_currentIndex >= m_queue.size()) return 0;
    return m_queue.at(m_currentIndex).rating;
}

QString PlaybackEngine::currentCoverSource() const
{
    if (m_currentIndex < 0 || m_currentIndex >= m_queue.size()) return {};
    const QString &thumb = m_queue.at(m_currentIndex).coverThumb;
    if (thumb.isEmpty()) return {};
    return QStringLiteral("data:image/jpeg;base64,") + thumb;
}

// ── Queue management ──────────────────────────────────────────────────────

TrackInfo PlaybackEngine::trackFromMap(const QVariantMap &map)
{
    TrackInfo t;
    t.filePath    = map.value(QStringLiteral("filePath")).toString();
    t.fileName    = QFileInfo(t.filePath).fileName();
    t.title       = map.value(QStringLiteral("title")).toString();
    t.artist      = map.value(QStringLiteral("artist")).toString();
    t.albumArtist = map.value(QStringLiteral("albumArtist"),
                               map.value(QStringLiteral("artist"))).toString();
    t.album       = map.value(QStringLiteral("album")).toString();
    t.genre       = map.value(QStringLiteral("genre")).toString();
    t.bitrate     = map.value(QStringLiteral("bitrate")).toInt();
    t.track       = map.value(QStringLiteral("number")).toString().toInt();
    t.duration    = map.value(QStringLiteral("durationMs")).toLongLong();

    // coverSource may be a "data:image/jpeg;base64,..." URL — strip the prefix
    QString cs = map.value(QStringLiteral("coverSource")).toString();
    const QString prefix = QStringLiteral("data:image/jpeg;base64,");
    if (cs.startsWith(prefix))
        t.coverThumb = cs.mid(prefix.length());
    else
        t.coverThumb = cs;

    return t;
}

void PlaybackEngine::addTrack(const QVariantMap &trackMap)
{
    const int row = m_queue.size();
    beginInsertRows({}, row, row);
    m_queue.append(trackFromMap(trackMap));
    endInsertRows();
    emit queueCountChanged();

    // Sync active playlist
    if (m_playlistManager && !m_activePlaylistName.isEmpty())
        m_playlistManager->appendTrack(m_activePlaylistName, trackMap);

    if (m_currentIndex < 0) {
        loadTrack(row);
        m_player->play();
    }
}

void PlaybackEngine::addTracks(const QVariantList &trackList)
{
    if (trackList.isEmpty()) return;
    const int first = m_queue.size();
    beginInsertRows({}, first, first + trackList.size() - 1);
    for (const QVariant &v : trackList)
        m_queue.append(trackFromMap(v.toMap()));
    endInsertRows();
    emit queueCountChanged();

    // Sync active playlist (skip when locked)
    if (m_playlistManager && !m_activePlaylistName.isEmpty() && !m_playlistLocked) {
        for (const QVariant &v : trackList)
            m_playlistManager->appendTrack(m_activePlaylistName, v.toMap());
    }

    if (m_currentIndex < 0) {
        loadTrack(first);
        m_player->play();
    }
}

void PlaybackEngine::removeAt(int idx)
{
    if (idx < 0 || idx >= m_queue.size()) return;
    const bool wasPlaying = (idx == m_currentIndex);
    const QString removedPath = m_queue.at(idx).filePath;  // capture before removal

    beginRemoveRows({}, idx, idx);
    m_queue.removeAt(idx);
    endRemoveRows();
    emit queueCountChanged();

    // Sync active playlist (skip when locked)
    if (m_playlistManager && !m_activePlaylistName.isEmpty() && !m_playlistLocked)
        m_playlistManager->removeTrackByPath(m_activePlaylistName, removedPath);

    if (wasPlaying) {
        m_player->stop();
        m_currentIndex = -1;
        if (idx < m_queue.size()) {
            loadTrack(idx);
            m_player->play();
        } else if (!m_queue.isEmpty()) {
            loadTrack(m_queue.size() - 1);
            m_player->play();
        } else {
            clearCoverSource();
            emit currentIndexChanged();
            emit currentTrackChanged();
            emit currentRatingChanged();
            emit isPlayingChanged();
        }
    } else if (idx < m_currentIndex) {
        m_currentIndex--;
        emit currentIndexChanged();
        // Refresh position numbers of all rows from idx onwards
        const QModelIndex from = index(idx);
        const QModelIndex last = index(m_queue.size() - 1);
        emit dataChanged(from, last, { PosRole });
    }
}

void PlaybackEngine::moveUp(int idx)
{
    if (idx <= 0 || idx >= m_queue.size()) return;
    if (!beginMoveRows({}, idx, idx, {}, idx - 1)) return;
    m_queue.move(idx, idx - 1);
    endMoveRows();

    if      (m_currentIndex == idx)     { m_currentIndex--; emit currentIndexChanged(); }
    else if (m_currentIndex == idx - 1) { m_currentIndex++; emit currentIndexChanged(); }

    const QModelIndex i1 = index(idx - 1);
    const QModelIndex i2 = index(idx);
    emit dataChanged(i1, i2, { PosRole, IsPlayingRole });

    // Sync active playlist (skip when locked)
    if (m_playlistManager && !m_activePlaylistName.isEmpty() && !m_playlistLocked)
        m_playlistManager->rewritePlaylist(m_activePlaylistName, trackList());
}

void PlaybackEngine::moveDown(int idx)
{
    if (idx < 0 || idx >= m_queue.size() - 1) return;
    if (!beginMoveRows({}, idx + 1, idx + 1, {}, idx)) return;
    m_queue.move(idx, idx + 1);
    endMoveRows();

    if      (m_currentIndex == idx)     { m_currentIndex++; emit currentIndexChanged(); }
    else if (m_currentIndex == idx + 1) { m_currentIndex--; emit currentIndexChanged(); }

    const QModelIndex i1 = index(idx);
    const QModelIndex i2 = index(idx + 1);
    emit dataChanged(i1, i2, { PosRole, IsPlayingRole });

    // Sync active playlist (skip when locked)
    if (m_playlistManager && !m_activePlaylistName.isEmpty() && !m_playlistLocked)
        m_playlistManager->rewritePlaylist(m_activePlaylistName, trackList());
}

void PlaybackEngine::moveTrack(int from, int to)
{
    if (from == to) return;
    if (from < 0 || from >= m_queue.size()) return;
    if (to   < 0 || to   >= m_queue.size()) return;
    if (from == m_currentIndex) return;   // playing track cannot be repositioned

    // beginMoveRows destination: row is inserted BEFORE this index.
    // If moving downward, destination = to + 1 (insert after target row).
    // If moving upward,   destination = to     (insert before target row).
    const int dest = (to > from) ? to + 1 : to;
    if (!beginMoveRows({}, from, from, {}, dest)) return;
    m_queue.move(from, to);
    endMoveRows();

    // Adjust currentIndex if it falls in the range that shifted.
    if (from < to) {
        // Rows [from+1 .. to] shifted up by one.
        if (m_currentIndex > from && m_currentIndex <= to) {
            --m_currentIndex;
            emit currentIndexChanged();
        }
    } else {
        // Rows [to .. from-1] shifted down by one.
        if (m_currentIndex >= to && m_currentIndex < from) {
            ++m_currentIndex;
            emit currentIndexChanged();
        }
    }

    const QModelIndex lo = index(qMin(from, to));
    const QModelIndex hi = index(qMax(from, to));
    emit dataChanged(lo, hi, { PosRole, IsPlayingRole });

    // Sync active playlist (skip when locked)
    if (m_playlistManager && !m_activePlaylistName.isEmpty() && !m_playlistLocked)
        m_playlistManager->rewritePlaylist(m_activePlaylistName, trackList());
}

void PlaybackEngine::clearQueue()
{
    if (m_queue.isEmpty()) return;
    m_player->stop();
    m_currentIndex = -1;
    clearCoverSource();
    beginResetModel();
    m_queue.clear();
    endResetModel();
    emit currentIndexChanged();
    emit currentTrackChanged();
    emit currentRatingChanged();
    emit queueCountChanged();
    emit isPlayingChanged();
    if (!m_activePlaylistName.isEmpty()) {
        m_activePlaylistName.clear();
        emit activePlaylistNameChanged();
    }
    if (m_playlistLocked) {
        m_playlistLocked = false;
        emit playlistLockedChanged();
    }
}

void PlaybackEngine::setActivePlaylistName(const QString &name)
{
    if (m_activePlaylistName == name) return;
    m_activePlaylistName = name;
    emit activePlaylistNameChanged();
    // Reset lock whenever a new playlist becomes active
    if (m_playlistLocked) {
        m_playlistLocked = false;
        emit playlistLockedChanged();
    }
}

void PlaybackEngine::setPlaylistLocked(bool locked)
{
    if (m_playlistLocked == locked) return;
    m_playlistLocked = locked;
    emit playlistLockedChanged();
    // When unlocking, immediately rewrite the XSPF to reflect any changes
    // that were made while locked.
    if (!locked && m_playlistManager && !m_activePlaylistName.isEmpty())
        m_playlistManager->rewritePlaylist(m_activePlaylistName, trackList());
}

void PlaybackEngine::setCurrentRating(int rating)
{
    if (m_currentIndex < 0 || m_currentIndex >= m_queue.size()) return;
    if (rating < 1 || rating > 10) return;

    TrackInfo &t = m_queue[m_currentIndex];
    if (t.ratingId.isNull())
        t.ratingId = TrackInfo::computeRatingId(t.albumArtist, t.artist, t.album, t.title);
    t.rating = rating;

    RatingCache::setRating(t.genre, t.ratingId, t.rating);
    emit currentRatingChanged();
}

QVariantList PlaybackEngine::trackList() const
{
    QVariantList result;
    result.reserve(m_queue.size());
    for (const TrackInfo &t : m_queue) {
        QVariantMap m;
        m[QStringLiteral("filePath")]    = t.filePath;
        m[QStringLiteral("title")]       = t.title.isEmpty() ? t.fileName : t.title;
        m[QStringLiteral("artist")]      = t.albumArtist.isEmpty() ? t.artist : t.albumArtist;
        m[QStringLiteral("albumArtist")] = t.albumArtist;
        m[QStringLiteral("album")]       = t.album;
        m[QStringLiteral("trackNumber")] = t.track;
        m[QStringLiteral("durationMs")]  = t.duration;
        result.append(m);
    }
    return result;
}
void PlaybackEngine::setDragCopyCursor()
{
    QGuiApplication::setOverrideCursor(Qt::DragCopyCursor);
}

void PlaybackEngine::restoreOverrideCursor()
{
    QGuiApplication::restoreOverrideCursor();
}
// ── Transport ─────────────────────────────────────────────────────────────

void PlaybackEngine::playAt(int idx)
{
    if (idx < 0 || idx >= m_queue.size()) return;
    loadTrack(idx);
    m_player->play();
}

void PlaybackEngine::togglePlay()
{
    if (m_queue.isEmpty()) return;
    if (m_currentIndex < 0) {
        loadTrack(0);
        m_player->play();
        return;
    }
    if (m_player->playbackState() == QMediaPlayer::PlayingState)
        m_player->pause();
    else
        m_player->play();
}

void PlaybackEngine::next()
{
    if (m_currentIndex < 0 || m_currentIndex >= m_queue.size() - 1) return;
    loadTrack(m_currentIndex + 1);
    m_player->play();
}

void PlaybackEngine::previous()
{
    // If more than 3 s in, restart; otherwise go to the previous track
    if (m_player->position() > 3000 || m_currentIndex <= 0) {
        m_player->setPosition(0);
        return;
    }
    loadTrack(m_currentIndex - 1);
    m_player->play();
}

void PlaybackEngine::seek(qint64 ms)
{
    if (m_currentIndex >= 0)
        m_player->setPosition(ms);
}

// ── Private helpers ───────────────────────────────────────────────────────

void PlaybackEngine::loadTrack(int idx)
{
    if (idx < 0 || idx >= m_queue.size()) return;

    const int oldIndex = m_currentIndex;
    m_currentIndex = idx;
    m_player->setSource(QUrl::fromLocalFile(m_queue.at(idx).filePath));

    // Resolve this track's rating identity/value now — the single canonical
    // point every playback path (queue add, playlist load) funnels through —
    // rather than trying to carry rating/ratingId through every map conversion.
    {
        TrackInfo &cur = m_queue[idx];
        if (cur.ratingId.isNull())
            cur.ratingId = TrackInfo::computeRatingId(cur.albumArtist, cur.artist,
                                                        cur.album, cur.title);
        cur.rating = RatingCache::load().value(cur.ratingId, 0);
    }

    // Kick off async full-resolution cover load
    m_coverWatcher.cancel();
    m_largeCoverSource.clear();
    emit currentLargeCoverSourceChanged();
    const QString fp = m_queue.at(idx).filePath;
    m_coverWatcher.setFuture(
        QtConcurrent::run([fp]() -> QByteArray {
            return TagReader::readRawCover(fp);
        })
    );

    // Refresh IsPlayingRole for old and new rows
    if (oldIndex >= 0 && oldIndex < m_queue.size()) {
        const QModelIndex mi = index(oldIndex);
        emit dataChanged(mi, mi, { IsPlayingRole });
    }
    const QModelIndex mi = index(m_currentIndex);
    emit dataChanged(mi, mi, { IsPlayingRole });

    emit currentIndexChanged();
    emit currentTrackChanged();
    emit currentRatingChanged();
}

void PlaybackEngine::clearCoverSource()
{
    m_coverWatcher.cancel();
    if (m_largeCoverSource.isEmpty()) return;
    m_largeCoverSource.clear();
    emit currentLargeCoverSourceChanged();
}

void PlaybackEngine::advanceToNext()
{
    if (m_currentIndex < m_queue.size() - 1) {
        loadTrack(m_currentIndex + 1);
        m_player->play();
    } else {
        // End of queue — stay on last track, stopped
        emit isPlayingChanged();
    }
}

QString PlaybackEngine::msToString(qint64 ms)
{
    if (ms <= 0) return QStringLiteral("0:00");
    const int totalSecs = static_cast<int>(ms / 1000);
    return QString("%1:%2")
        .arg(totalSecs / 60)
        .arg(totalSecs % 60, 2, 10, QChar('0'));
}

QString PlaybackEngine::formatFromPath(const QString &path)
{
    const QString ext = QFileInfo(path).suffix().toUpper();
    if (ext == QStringLiteral("FLAC")) return QStringLiteral("FLAC");
    if (ext == QStringLiteral("MP3"))  return QStringLiteral("MP3");
    return ext;
}
