#pragma once

#include "playlistmanager.h"
#include "trackinfo.h"

#include <QAbstractListModel>
#include <QQmlEngine>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QFutureWatcher>

// ── PlaybackEngine ────────────────────────────────────────────────────────
// QAbstractListModel that IS the playback queue model.
// Wraps QMediaPlayer + QAudioOutput and exposes queue state to QML.
//
// Track maps accepted by addTrack / addTracks must contain at minimum:
//   filePath (string), title (string), artist (string),
//   albumArtist (string), album (string), bitrate (int),
//   durationMs (int/qint64), coverSource (string — data: URL or empty).
//
// Queue roles exported to QML match the role names expected by
// PlaybackQueue.qml: pos, trackName, subLabel, kbps, playing.
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
    Q_PROPERTY(QString currentFormat    READ currentFormat    NOTIFY currentTrackChanged)
    Q_PROPERTY(int     currentBitrate   READ currentBitrate   NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentCoverSource      READ currentCoverSource      NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentLargeCoverSource READ currentLargeCoverSource NOTIFY currentLargeCoverSourceChanged)
    Q_PROPERTY(int     queueCount             READ queueCount              NOTIFY queueCountChanged)
    Q_PROPERTY(QString activePlaylistName     READ activePlaylistName      NOTIFY activePlaylistNameChanged)
    Q_PROPERTY(bool    playlistLocked          READ playlistLocked          WRITE setPlaylistLocked NOTIFY playlistLockedChanged)
    Q_PROPERTY(PlaylistManager* playlistManager READ playlistManager WRITE setPlaylistManager NOTIFY playlistManagerChanged)

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
    QString currentFormat()     const;
    int     currentBitrate()    const;
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

    // Sets the active playlist name (called from QML after creating/loading a playlist).
    Q_INVOKABLE void setActivePlaylistName(const QString &name);
    // Locks or unlocks playlist sync.  When unlocked, the XSPF is immediately
    // rewritten to reflect the current queue.
    Q_INVOKABLE void setPlaylistLocked(bool locked);

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
    void currentLargeCoverSourceChanged();
    void queueCountChanged();
    void activePlaylistNameChanged();
    void playlistLockedChanged();
    void playlistManagerChanged();

private:
    void loadTrack(int index);
    void advanceToNext();

    static QString msToString(qint64 ms);
    static QString formatFromPath(const QString &path);
    static TrackInfo trackFromMap(const QVariantMap &map);

    QList<TrackInfo>          m_queue;
    int                       m_currentIndex       = -1;
    QString                   m_largeCoverSource;
    QString                   m_activePlaylistName;
    bool                      m_playlistLocked    = false;
    PlaylistManager          *m_playlistManager    = nullptr;
    QMediaPlayer             *m_player           = nullptr;
    QAudioOutput             *m_audioOutput      = nullptr;
    QFutureWatcher<QByteArray> m_coverWatcher;
};
