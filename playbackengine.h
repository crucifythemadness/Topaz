#pragma once

#include "audiodeck.h"
#include "playlistmanager.h"
#include "trackinfo.h"

#include <QAbstractListModel>
#include <QQmlEngine>
#include <QAudioBuffer>
#include <QFutureWatcher>
#include <QTimer>

class AppConfig;

// ── PlaybackEngine ────────────────────────────────────────────────────────
// QAbstractListModel that IS the playback queue model.
// Wraps two AudioDeck instances (FFmpeg- or BASS-backed, see UC-15) and
// exposes queue state to QML.
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
// Two independent AudioDeck instances ("decks") back playback so a track can
// fade in on one deck while the previous track fades out on the other --
// neither backend (see AudioDeck) can play two sources from one instance.
// m_deck is an alias pointer that always points at whichever deck is
// m_activeDeck, so every pre-existing single-deck code path (position(),
// duration(), seek(), etc.) keeps working unchanged; only the crossfade logic
// itself (loadTrack()/startCrossfade()/onFadeTick()/cancelCrossfade()) needs
// to reason about both decks explicitly. See UC-15 in the architecture doc
// ("Step 2") for why this orchestration never needed to know which concrete
// AudioDeck implementation it's driving.
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
    Q_PROPERTY(bool    userPaused       READ userPaused       NOTIFY userPausedChanged)
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
    // Which concrete AudioDeck is actually backing playback THIS session --
    // "FFmpeg" or "BASS Audio Library", or an empty string before decks
    // exist. Distinct from AppConfig.audioBackend (the stored preference for
    // the *next* launch): if BASS was selected but createDecksIfNeeded()
    // couldn't actually use it, this reports what's really running while
    // audioBackend gets silently corrected back to "ffmpeg" -- see UC-15
    // "Step 2b". Shown in SetupDialog's PLAYBACK tab so switching backends
    // can be confirmed before testing playback.
    Q_PROPERTY(QString activeBackendName READ activeBackendName NOTIFY activeBackendNameChanged)

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
        CoverSourceRole,
        IsAutoPlayAddedRole // bool ("autoPlayAdded") -- see UC-16
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
    // True only while the current track is paused via togglePlay()'s
    // explicit pause branch -- never for any other "not playing" state
    // (queue finished, mid-transition, etc.). See UC-07.
    bool    userPaused()        const { return m_userPaused; }
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
    // True when every track in the queue has already played through to its
    // natural end (see UC-16) -- lets AutoPlayController::start() know
    // whether it should also play immediately, same as an empty queue.
    // Plain C++ getter, not QML-facing (no Q_PROPERTY/Q_INVOKABLE needed).
    bool    queueFinished()            const { return m_queueFinished; }
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
    // Also the trigger for createDecksIfNeeded() -- see its own doc comment.
    AppConfig* appConfig() const { return m_appConfig; }
    void setAppConfig(AppConfig *cfg);

    // "FFmpeg" or "BASS Audio Library" once createDecksIfNeeded() has run,
    // otherwise an empty string. See the activeBackendName Q_PROPERTY doc
    // comment above.
    QString activeBackendName() const;

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
    // autoPlayAdded is set only by AutoPlayController's 3 add call sites
    // (start()/maybeFillHorizon()/onQueueExhausted()) -- see UC-16. Default
    // keeps every other caller (manual drag/double-click, playlist load)
    // unchanged.
    Q_INVOKABLE void addTrack(const QVariantMap  &track, bool autoPlayAdded = false);
    Q_INVOKABLE void addTracks(const QVariantList &tracks);
    Q_INVOKABLE void removeAt(int index);
    Q_INVOKABLE void moveUp(int index);
    Q_INVOKABLE void moveDown(int index);
    Q_INVOKABLE void moveTrack(int from, int to);
    Q_INVOKABLE void clearQueue();

    // Replaces the entire queue with `tracks` -- used exclusively by the
    // "load a playlist" flows (NowPlaying / PlaylistViewer LOAD buttons).
    // Behaves exactly like clearQueue() followed by addTracks(tracks)
    // UNLESS AppConfig.crossfadeEnabled() is true AND a track is currently
    // playing, in which case the currently-playing track crossfades
    // directly into the first track of `tracks` (dual-deck, reusing the
    // same fade machinery as the natural end-of-track crossfade -- see
    // UC-15) instead of a hard stop-then-restart; the remaining tracks
    // become the queue behind it. Falls back to the instant clearQueue()+
    // addTracks() behavior if either the outgoing or incoming track is too
    // short for the configured crossfade length (same eligibility rule as
    // the natural crossfade). No other queue-mutating path is affected by
    // any of this -- see UC-23.
    Q_INVOKABLE void loadPlaylistTracks(const QVariantList &tracks);

    // Returns all queued tracks as a list of maps suitable for PlaylistManager.
    // Each map contains: filePath, title, artist, albumArtist, album,
    //                    trackNumber, durationMs.
    Q_INVOKABLE QVariantList trackList() const;

    // Cursor helpers — wrap QGuiApplication's override-cursor stack so QML
    // can set a global drag cursor that overrides all local MouseArea
    // shapes (a cursorShape binding on a MouseArea only applies while the
    // mouse stays inside that MouseArea's bounds, which doesn't hold once
    // the drag leaves it).
    //
    // beginDragCursor() pushes exactly one override (Qt::ForbiddenCursor,
    // the default "not over a valid drop target" state) at drag start;
    // setDragCursorAllowed() then only changes that same override's shape
    // as the drag enters/exits PlaybackQueue's DropArea, via
    // QGuiApplication::changeOverrideCursor() rather than pushing a second
    // override — so exactly one restoreOverrideCursor() call at drag end
    // still correctly pops it back to normal.
    Q_INVOKABLE void beginDragCursor();
    Q_INVOKABLE void setDragCursorAllowed(bool allowed);
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
    void userPausedChanged();
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
    void activeBackendNameChanged();
    // Fired once, at most, per launch -- only when BASS was the stored
    // preference but createDecksIfNeeded() couldn't actually use it (DLLs
    // missing/removed, or BassLibrary::load() failed), so it silently fell
    // back to FfmpegAudioDeck and corrected the persisted setting. See
    // UC-15 "Step 2b" and Main.qml's bassFallbackNoticeBox.
    void bassUnavailableFallback();

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
    // Constructs m_decks[0]/[1] the first time m_appConfig becomes non-null
    // (called from setAppConfig()) -- deferred out of the constructor since
    // deciding FfmpegAudioDeck vs BassAudioDeck needs AppConfig.audioBackend()/
    // bassLibraryAvailable(), neither available yet at construction time. Only
    // ever runs once per PlaybackEngine instance: the backend choice is read
    // once per app launch, not hot-swapped -- see UC-15 "Step 2".
    void createDecksIfNeeded();

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
    // Connected to each AudioDeck's endOfMedia() -- equivalent of the old
    // QMediaPlayer::mediaStatusChanged(EndOfMedia) check, now unambiguous
    // since the signal itself only ever means that.
    void onDeckEnded(int deckIndex);

    static QString msToString(qint64 ms);
    static QString formatFromPath(const QString &path);
    static TrackInfo trackFromMap(const QVariantMap &map);

    QList<TrackInfo>          m_queue;
    int                       m_currentIndex       = -1;
    QString                   m_largeCoverSource;
    QString                   m_activePlaylistName;
    bool                      m_playlistLocked    = false;
    // True from the moment advanceToNext() finds no next track (natural
    // end-of-queue) until the next loadTrack() call of any kind. Lets
    // addTrack()/addTracks() tell "queue finished naturally" apart from
    // "current track is merely paused" -- both otherwise look identical
    // (m_currentIndex unchanged, isPlaying() false). See UC-16/UC-06.
    bool                      m_queueFinished      = false;
    // True only while the current track is paused via togglePlay()'s
    // explicit pause branch -- never for any other "not playing" state.
    // Cleared by resuming the same track (togglePlay()), any new track
    // becoming current (switchCurrentIndexTo(), shared by hard cuts and
    // crossfade), or clearQueue(). Drives NowPlaying's Play/Pause button
    // blink -- see UC-07.
    bool                      m_userPaused         = false;
    PlaylistManager          *m_playlistManager    = nullptr;
    AppConfig                 *m_appConfig          = nullptr;

    // Dual-deck playback. m_deck always aliases m_decks[m_activeDeck]. See
    // createDecksIfNeeded() for construction timing/backend choice, and
    // AudioDeck's own doc comment for why the audio-buffer visualizer tap
    // isn't part of this array (FfmpegAudioDeck-specific, wired up
    // separately in createDecksIfNeeded()).
    AudioDeck                 *m_decks[2]          = { nullptr, nullptr };
    int                         m_activeDeck        = 0;
    AudioDeck                  *m_deck              = nullptr;

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

    // Set only by loadPlaylistTracks() when it starts a queue-replacing
    // crossfade (see UC-23); onFadeTick() checks this to know whether its
    // midpoint should advance to the next slot in the *same* queue (the
    // natural crossfade — startCrossfade() never touches these three
    // members, so they stay at their defaults for every such fade) or
    // replace m_queue wholesale with m_pendingQueue. Reset by
    // cancelCrossfade() and at normal fade completion so an interrupted
    // queue-replacing fade can never leak into a later, unrelated crossfade.
    bool             m_crossfadeReplacesQueue = false;
    QList<TrackInfo> m_pendingQueue;
    QString          m_fadeOutFilePath;

    QFutureWatcher<QByteArray> m_coverWatcher;
};
