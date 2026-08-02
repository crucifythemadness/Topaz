#include "playbackengine.h"
#include "appconfig.h"
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
{
    for (int d = 0; d < 2; ++d) {
        m_players[d]      = new QMediaPlayer(this);
        m_audioOutputs[d] = new QAudioOutput(this);
        m_players[d]->setAudioOutput(m_audioOutputs[d]);
        m_audioOutputs[d]->setVolume(1.0f);

        connect(m_players[d], &QMediaPlayer::positionChanged,
                this, [this, d](qint64) { onDeckPositionChanged(d); });
        connect(m_players[d], &QMediaPlayer::durationChanged,
                this, [this, d](qint64) {
                    if (d == m_activeDeck) emit durationChanged();
                });
        connect(m_players[d], &QMediaPlayer::playbackStateChanged,
                this, [this, d](QMediaPlayer::PlaybackState) {
                    if (d != m_activeDeck) return;
                    emit isPlayingChanged();
                    if (m_currentIndex >= 0 && m_currentIndex < m_queue.size()) {
                        const QModelIndex idx = index(m_currentIndex);
                        emit dataChanged(idx, idx, { IsPlayingRole });
                    }
                });
        connect(m_players[d], &QMediaPlayer::mediaStatusChanged,
                this, [this, d](QMediaPlayer::MediaStatus status) {
                    onDeckMediaStatusChanged(d, status);
                });
    }

    m_player      = m_players[m_activeDeck];
    m_audioOutput = m_audioOutputs[m_activeDeck];

    m_fadeTimer = new QTimer(this);
    m_fadeTimer->setInterval(40); // ~25 volume updates/sec — smooth enough for a linear fade
    connect(m_fadeTimer, &QTimer::timeout, this, &PlaybackEngine::onFadeTick);

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
        if (!t.album.isEmpty()) sub += QStringLiteral(" • ") + t.album.toUpper();
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
    cancelCrossfade();
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
    }

    // Position numbers (#, "pos" role) are derived from each row's index, so
    // every row from the removal point onward needs a refresh regardless of
    // which branch above ran — beginRemoveRows/endRemoveRows only tells the
    // view a row disappeared, it doesn't imply role data changed for rows
    // that shifted into new positions.
    if (idx < m_queue.size()) {
        const QModelIndex from = index(idx);
        const QModelIndex last = index(m_queue.size() - 1);
        emit dataChanged(from, last, { PosRole });
    }
}

void PlaybackEngine::moveUp(int idx)
{
    if (idx <= 0 || idx >= m_queue.size()) return;
    cancelCrossfade();
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
    cancelCrossfade();
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
    cancelCrossfade();

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
    cancelCrossfade();
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
    const bool playing = (m_player->playbackState() == QMediaPlayer::PlayingState);
    if (playing) {
        m_player->pause();
        // Keep both decks in lockstep while a crossfade is in progress —
        // otherwise the standby deck would keep fading in while paused.
        if (m_crossfading) m_players[1 - m_activeDeck]->pause();
    } else {
        m_player->play();
        if (m_crossfading) m_players[1 - m_activeDeck]->play();
    }
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
    if (m_currentIndex < 0) return;
    // A manual seek abandons any automatic crossfade in progress — reconciling
    // a seek on the fading-out deck with the independently-playing standby
    // deck isn't worth the complexity for what is a rare, few-second window.
    cancelCrossfade();
    m_player->setPosition(ms);
}

// ── Private helpers ───────────────────────────────────────────────────────

void PlaybackEngine::loadTrack(int idx)
{
    if (idx < 0 || idx >= m_queue.size()) return;

    cancelCrossfade();
    m_audioOutput->setVolume(1.0f);   // in case a fade left this deck's volume < 1
    m_player->setSource(QUrl::fromLocalFile(m_queue.at(idx).filePath));

    switchCurrentIndexTo(idx);
}

void PlaybackEngine::switchCurrentIndexTo(int idx)
{
    if (idx < 0 || idx >= m_queue.size()) return;

    const int oldIndex = m_currentIndex;
    m_currentIndex = idx;

    // Resolve this track's rating identity/value now — the single canonical
    // point every playback path (queue add, playlist load, crossfade) funnels
    // through — rather than trying to carry rating/ratingId through every map
    // conversion.
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
    if (m_currentIndex >= 0 && m_currentIndex < m_queue.size())
        emit trackPlayedToCompletion(m_queue.at(m_currentIndex).filePath);

    if (m_currentIndex < m_queue.size() - 1) {
        loadTrack(m_currentIndex + 1);
        m_player->play();
    } else {
        // End of queue — stay on last track, stopped
        emit isPlayingChanged();
        emit queueExhausted();
    }
}

// ── Crossfade ──────────────────────────────────────────────────────────────

void PlaybackEngine::onDeckPositionChanged(int deckIndex)
{
    if (deckIndex == m_activeDeck)
        emit positionChanged();

    if (deckIndex != m_activeDeck || m_crossfading) return;
    if (!m_appConfig || !m_appConfig->crossfadeEnabled()) return;
    if (m_currentIndex < 0 || m_currentIndex >= m_queue.size() - 1) return; // no next track

    QMediaPlayer *active = m_players[m_activeDeck];
    const qint64 dur = active->duration();
    const qint64 pos = active->position();
    if (dur <= 0) return;

    const qint64 fadeMs = qint64(m_appConfig->crossfadeSeconds() * 1000);
    const TrackInfo &next = m_queue.at(m_currentIndex + 1);

    // Eligibility: both the current (live) and next (tag) duration must exceed
    // the fade window, or neither a valid fade-out nor fade-in window exists.
    if (dur <= fadeMs || next.duration <= fadeMs) return;

    if (pos >= dur - fadeMs)
        startCrossfade();
}

void PlaybackEngine::onDeckMediaStatusChanged(int deckIndex, QMediaPlayer::MediaStatus status)
{
    if (deckIndex != m_activeDeck || m_crossfading) return;
    if (status == QMediaPlayer::EndOfMedia)
        advanceToNext();
}

void PlaybackEngine::startCrossfade()
{
    const int nextIdx = m_currentIndex + 1;

    // Fixed for this fade's whole lifetime — the volume ramp always targets
    // these two decks, independent of when m_activeDeck itself gets swapped.
    m_fadeOutDeck  = m_activeDeck;
    m_fadeInDeck   = 1 - m_activeDeck;
    m_fadeOutIndex = m_currentIndex;

    m_players[m_fadeInDeck]->setSource(QUrl::fromLocalFile(m_queue.at(nextIdx).filePath));
    m_audioOutputs[m_fadeInDeck]->setVolume(0.0f);
    m_players[m_fadeInDeck]->play();

    m_crossfading       = true;
    m_fadeMidpointFired = false;
    m_fadeTargetIndex   = nextIdx;
    m_fadeElapsedMs     = 0;
    m_fadeTimer->start();
}

void PlaybackEngine::onFadeTick()
{
    if (!m_appConfig) { cancelCrossfade(); return; }

    m_fadeElapsedMs += m_fadeTimer->interval();
    const qint64 fadeMs = qMax<qint64>(1, qint64(m_appConfig->crossfadeSeconds() * 1000));
    const double frac = qMin(1.0, double(m_fadeElapsedMs) / double(fadeMs));

    m_audioOutputs[m_fadeOutDeck]->setVolume(float(1.0 - frac));
    m_audioOutputs[m_fadeInDeck]->setVolume(float(frac));

    if (!m_fadeMidpointFired && frac >= 0.5) {
        m_fadeMidpointFired = true;

        // Switch the UI-facing alias now too, so duration/position/isPlaying
        // (progress bar, length label, play/pause icon) switch to the incoming
        // track together with title/artist/cover/rating, all at the midpoint.
        m_activeDeck  = m_fadeInDeck;
        m_player      = m_players[m_activeDeck];
        m_audioOutput = m_audioOutputs[m_activeDeck];

        switchCurrentIndexTo(m_fadeTargetIndex);
        emit durationChanged();
        emit positionChanged();
        emit isPlayingChanged();
    }

    if (frac >= 1.0) {
        m_fadeTimer->stop();
        // m_fadeOutDeck is no longer m_activeDeck (swapped at the midpoint above),
        // so its playbackStateChanged from this stop() is correctly suppressed by
        // the per-deck signal guards instead of stomping on isPlaying.
        m_players[m_fadeOutDeck]->stop();
        m_audioOutputs[m_fadeOutDeck]->setVolume(1.0f);   // reset for reuse
        m_crossfading = false;

        if (m_fadeOutIndex >= 0 && m_fadeOutIndex < m_queue.size())
            emit trackPlayedToCompletion(m_queue.at(m_fadeOutIndex).filePath);
    }
}

void PlaybackEngine::cancelCrossfade()
{
    if (!m_crossfading) return;
    m_fadeTimer->stop();
    const int standbyDeck = 1 - m_activeDeck;
    m_players[standbyDeck]->stop();
    m_audioOutputs[standbyDeck]->setVolume(1.0f);
    m_audioOutputs[m_activeDeck]->setVolume(1.0f);
    m_crossfading   = false;
    m_fadeElapsedMs = 0;
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
    if (ext == QStringLiteral("OPUS")) return QStringLiteral("OPUS");
    return ext;
}
