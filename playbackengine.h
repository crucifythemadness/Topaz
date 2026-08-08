#pragma once

#include "playlistmanager.h"
#include "trackinfo.h"

#include <QAbstractListModel>
#include <QQmlEngine>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QAudioBufferOutput>
#include <QAudioBuffer>
#include <QFutureWatcher>
#include <QTimer>

class AppConfig;

// ── PlaybackEngine ────────────────────────────────────────────────────────
// QAbstractListModel that IS the playback queue model.
// Wraps QMediaPlayer + QAudioOutput and exposes queue state to QML.
//
// Track maps accepted by addTrack / addTracks must contain at minimum:
//   filePath (string), title (string), artist (string),
//   albumArtist (string), album (string), genre (string), bitrate (int),
//   durationMs (int/qint64), coverSource (string — data: URL or empty).
// rating/ratingId are deliberately NOT read from the map — loadTrack() always
// (re-)resolves them from Topaz.rating.json via TrackInfo::computeRatingId(),
// the single canonical point regardless of how a track reached the queue.
//
// Queue roles exported to QML match the role names expected by
// PlaybackQueue.qml: pos, trackName, subLabel, kbps, playing.
//
// ── Dual-deck crossfade ───────────────────────────────────────────────────
// Two independent QMediaPlayer/QAudioOutput pairs ("decks") back playback so a
// track can fade in on one deck while the previous track fades out on the
// other — Qt Multimedia cannot play two sources from a single player. m_player
// / m_audioOutput are alias pointers that always point at whichever deck is
// m_activeDeck, so every pre-existing single-deck code path (position(),
// duration(), seek(), etc.) keeps working unchanged; only the crossfade logic
// itself (loadTrack()/startCrossfade()/onFadeTick()/cancelCrossfade()) needs
// to reason about both decks explicitly. See UC-15 in the architecture doc.
// Crossfade only engages when a transition's current AND next tracks both
// have a duration longer than the configured crossfade length — a track
// shorter than that can supply neither a valid fade-out nor fade-in window,
// which is what makes short tracks (and the track immediately following one)
// play as a plain hard cut.
class PlaybackEngine : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int     currentIndex     READ currentIndex     NOTIFY currentIndexChanged)
    Q_PROPERTY(bool    isPlaying        READ isPlaying        NOTIFY isPlayingChanged)
    Q_PROPERTY(qint64  position         READ position         NOTIFY positionChanged)
    Q_PROPERTY(qint64  duration         READ duration         NOTIFY durationChanged)
    Q_PROPERTY(QString positionString   READ positionString   NOTIFY positionChanged)
    Q_PROPERTY(QString durationString   READ durationString   NOTIFY durationChanged)
    Q_PROPERTY(QString currentTitle     READ currentTitle     NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentArtist    READ currentArtist    NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentAlbum     READ currentAlbum     NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentAlbumArtist READ currentAlbumArtist NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentGenre     READ currentGenre     NOTIFY currentTrackChanged)
    Q_PROPERTY(int     currentYear      READ currentYear      NOTIFY currentTrackChanged)
    Q_PROPERTY(int     currentTrackNumber READ currentTrackNumber NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentFormat    READ currentFormat    NOTIFY currentTrackChanged)
    Q_PROPERTY(int     currentBitrate   READ currentBitrate   NOTIFY currentTrackChanged)
    Q_PROPERTY(int     currentRating    READ currentRating    NOTIFY currentRatingChanged)
    Q_PROPERTY(QString currentCoverSource      READ currentCoverSource      NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentLargeCoverSource READ currentLargeCoverSource NOTIFY currentLargeCoverSourceChanged)
    Q_PROPERTY(int     queueCount             READ queueCount              NOTIFY queueCountChanged)
    Q_PROPERTY(QString activePlaylistName     READ activePlaylistName      NOTIFY activePlaylistNameChanged)
    Q_PROPERTY(bool    playlistLocked          READ playlistLocked          WRITE setPlaylistLocked NOTIFY playlistLockedChanged)
    Q_PROPERTY(PlaylistManager* playlistManager READ playlistManager WRITE setPlaylistManager NOTIFY playlistManagerChanged)
    Q_PROPERTY(AppConfig* appConfig READ appConfig WRITE setAppConfig NOTIFY appConfigChanged)

public:
    enum QueueRole {
        PosRole            = Qt::UserRole + 1,
        TrackNameRole,      // display title ("trackName" in QML)
        SubLabelRole,       // "ARTIST • ALBUM" uppercase ("subLabel")
        ArtistRole,
        AlbumRole,
        BitrateRole,        // kbps int ("kbps")
        FormatRole,
        FilePathRole,
        IsPlayingRole,      // bool ("playing")
        DurationStringRole,
        CoverSourceRole
    };
    Q_ENUM(QueueRole)

    explicit PlaybackEngine(QObject *parent = nullptr);
    ~PlaybackEngine() override;

    // ── QAbstractListModel ────────────────────────────────────────────────
    int      rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // ── Properties ────────────────────────────────────────────────────────
    int     currentIndex()      const { return m_currentIndex; }
    bool    isPlaying()         const;
    qint64  position()          const;
    qint64  duration()          const;
    QString positionString()    const;
    QString durationString()    const;
    QString currentTitle()      const;
    QString currentArtist()     const;
    QString currentAlbum()      const;
    QString currentAlbumArtist() const;
    QString currentGenre()      const;
    int     currentYear()       const;
    int     currentTrackNumber() const;
    QString currentFormat()     const;
    int     currentBitrate()    const;
    int     currentRating()     const;   // 0-10; 0 if no track loaded or unrated
    QString currentCoverSource()      const;
    QString currentLargeCoverSource()  const { return m_largeCoverSource; }
    int     queueCount()               const { return m_queue.size(); }
    QString activePlaylistName()        const { return m_activePlaylistName; }
    bool    playlistLocked()             const { return m_playlistLocked; }
    PlaylistManager* playlistManager()  const { return m_playlistManager; }
    void setPlaylistManager(PlaylistManager *pm) {
        if (m_playlistManager == pm) return;
        m_playlistManager = pm;
        emit playlistManagerChanged();
    }

    // Bound from Main.qml. Crossfade settings are always read live from here
    // (never cached), so a change in Setup takes effect on the next transition.
    AppConfig* appConfig() const { return m_appConfig; }
    void setAppConfig(AppConfig *cfg) {
        if (m_appConfig == cfg) return;
        m_appConfig = cfg;
        emit appConfigChanged();
    }

    // Sets the active playlist name (called from QML after creating/loading a playlist).
    Q_INVOKABLE void setActivePlaylistName(const QString &name);
    // Locks or unlocks playlist sync.  When unlocked, the XSPF is immediately
    // rewritten to reflect the current queue.
    Q_INVOKABLE void setPlaylistLocked(bool locked);

    // Sets the rating (1-10) for the currently playing track and persists it
    // immediately to Topaz.rating.json via RatingCache::setRating(). No-op if no
    // track is loaded or the value is out of range.
    Q_INVOKABLE void setCurrentRating(int rating);

    // ── Queue management (callable from QML) ──────────────────────────────
    Q_INVOKABLE void addTrack(const QVariantMap  &track);
    Q_INVOKABLE void addTracks(const QVariantList &tracks);
    Q_INVOKABLE void removeAt(int index);
    Q_INVOKABLE void moveUp(int index);
    Q_INVOKABLE void moveDown(int index);
    Q_INVOKABLE void moveTrack(int from, int to);
    Q_INVOKABLE void clearQueue();

    // Returns all queued tracks as a list of maps suitable for PlaylistManager.
    // Each map contains: filePath, title, artist, albumArtist, album,
    //                    trackNumber, durationMs.
    Q_INVOKABLE QVariantList trackList() const;

    // Cursor helpers — wrap QGuiApplication::setOverrideCursor so QML can
    // set a global drag cursor that overrides all local MouseArea shapes.
    Q_INVOKABLE void setDragCopyCursor();
    Q_INVOKABLE void restoreOverrideCursor();

    // ── Transport (callable from QML) ─────────────────────────────────────
    Q_INVOKABLE void playAt(int index);
    Q_INVOKABLE void togglePlay();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seek(qint64 ms);

signals:
    void currentIndexChanged();
    void isPlayingChanged();
    void positionChanged();
    void durationChanged();
    void currentTrackChanged();
    void currentRatingChanged();
    void currentLargeCoverSourceChanged();
    void queueCountChanged();
    void activePlaylistNameChanged();
    void playlistLockedChanged();
    void playlistManagerChanged();
    void appConfigChanged();

    // Emitted only on NATURAL track completion (reaching end-of-media, whether
    // via a hard cut or a crossfade), never on manual next()/previous() — the
    // signal AutoPlayController uses to build its "already played" history.
    void trackPlayedToCompletion(const QString &filePath);
    // Emitted when playback stalls at the end of the queue (advanceToNext()
    // has no next track to load) — nothing else notifies of this state, since
    // neither queueCountChanged nor currentIndexChanged fires in that branch.
    void queueExhausted();

    // Decoded PCM audio for whichever deck is currently active (m_activeDeck),
    // for AudioVisualizerController to consume — see UC-19. Not QML-facing (no
    // Q_PROPERTY), just a plain C++ signal; QAudioBuffer needs no meta-type
    // registration since only a C++ slot connects to it. During a crossfade the
    // standby deck's buffers are silently dropped (see UC-19's "Known
    // limitations" — a deliberate simplification, not an oversight).
    void audioBufferAvailable(const QAudioBuffer &buffer);

private:
    void loadTrack(int index);
    void advanceToNext();
    void clearCoverSource();

    // Metadata-only bookkeeping for "index becomes current": updates
    // m_currentIndex, resolves rating/ratingId, kicks off the cover fetch,
    // refreshes IsPlayingRole, emits the current* signals. Does NOT touch any
    // player's source/playback state — used both by loadTrack() (hard cut) and
    // by the crossfade midpoint (audio is already transitioning independently).
    void switchCurrentIndexTo(int index);

    // ── Crossfade ──────────────────────────────────────────────────────────
    void startCrossfade();
    void cancelCrossfade();
    void onFadeTick();
    // deckIndex-aware handlers shared by both decks' signal connections.
    void onDeckPositionChanged(int deckIndex);
    void onDeckMediaStatusChanged(int deckIndex, QMediaPlayer::MediaStatus status);

    static QString msToString(qint64 ms);
    static QString formatFromPath(const QString &path);
    static TrackInfo trackFromMap(const QVariantMap &map);

    QList<TrackInfo>          m_queue;
    int                       m_currentIndex       = -1;
    QString                   m_largeCoverSource;
    QString                   m_activePlaylistName;
    bool                      m_playlistLocked    = false;
    PlaylistManager          *m_playlistManager    = nullptr;
    AppConfig                 *m_appConfig          = nullptr;

    // Dual-deck playback. m_player/m_audioOutput always alias
    // m_players[m_activeDeck]/m_audioOutputs[m_activeDeck].
    QMediaPlayer              *m_players[2]        = { nullptr, nullptr };
    QAudioOutput               *m_audioOutputs[2]   = { nullptr, nullptr };
    // Parallel to m_audioOutputs — decoded-buffer tap for the visualizer.
    // Independent of m_audioOutputs (a player can have both simultaneously);
    // doesn't touch normal playback in any way.
    QAudioBufferOutput         *m_audioBufferOutputs[2] = { nullptr, nullptr };
    int                         m_activeDeck        = 0;
    QMediaPlayer              *m_player            = nullptr;
    QAudioOutput               *m_audioOutput       = nullptr;

    bool    m_crossfading       = false;
    bool    m_fadeMidpointFired = false;
    int     m_fadeTargetIndex   = -1;
    qint64  m_fadeElapsedMs     = 0;
    QTimer *m_fadeTimer         = nullptr;
    // Fixed for the duration of one fade (captured in startCrossfade()) so the
    // volume ramp keeps targeting the same two decks regardless of when
    // m_activeDeck itself gets swapped (at the midpoint — see onFadeTick()).
    int     m_fadeOutDeck       = -1;
    int     m_fadeInDeck        = -1;
    // Captured at startCrossfade() time — the outgoing track's queue index,
    // needed by trackPlayedToCompletion() at fade-completion since m_currentIndex
    // has already swapped to the incoming track by the midpoint.
    int     m_fadeOutIndex      = -1;

    QFutureWatcher<QByteArray> m_coverWatcher;
};
