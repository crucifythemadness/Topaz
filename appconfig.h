#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class QJsonObject;

// AppConfig — persistent application configuration.
//
// Stored in:  QStandardPaths::AppConfigLocation / Topaz.config  (JSON)
// Schema:
//   {
//     "genres":  [ "Techno", "IDM", ... ],
//     "enabledGenres": [ "Techno", ... ],   // subset of "genres", <= 40 entries,
//                                           // shown as buttons in GenreBar (see
//                                           // UC-03). Missing key (older config
//                                           // files) means "enable every genre up
//                                           // to 40", preserving pre-existing
//                                           // behavior.
//     "folders": [ { "volume": "MusicDrive", "relPath": "/Music", "rawPath": "D:/Music",
//                    "includeSubfolders": true, "active": true }, ... ],
//                  // "active" (default true when absent, for pre-existing configs)
//                  // gates whether this folder is scanned at all -- see UC-04/UC-05.
//                  // Anchored on the volume label (VolumePath, see volumepath.h) rather
//                  // than a drive letter, so a folder still resolves after the disk is
//                  // reassigned a different letter or remounted elsewhere (incl. Linux).
//                  // "path" and "available" are NOT persisted — folders() computes them
//                  // fresh from currently mounted volumes on every call.
//     "playback": { "crossfadeEnabled": false, "crossfadeSeconds": 5.0,
//                   "audioBackend": "ffmpeg",
//                   "autoLoudnessCorrection": false,
//                   "loudnessStrategy": "audiophile",
//                   "audiophileTrimDb": 0.0, "backgroundTrimDb": 0.0,
//                   "loudnessAlwaysMeasure": false },
//                  // autoLoudnessCorrection/loudnessStrategy: Setup > PLAYBACK,
//                  // BASS only (UC-35). Strategy is "audiophile" (per-track gain)
//                  // or "background" (compressor); anything else reads as
//                  // "audiophile". *TrimDb: user-set manual correction ("Trim")
//                  // on top of the automatic one, [-15, 15], 0.5 dB steps,
//                  // default 0 -- never written to Topaz.volumeNormalization.json,
//                  // only ever applied live (PlaybackEngine).
//                  // loudnessAlwaysMeasure: "audiophile" ignores ReplayGain /
//                  // R128 tags and always measures (default false).
//                  // Object/key names match the PLAYBACK tab and the
//                  // crossfadeEnabled/crossfadeSeconds Q_PROPERTYs exactly. Used
//                  // to be called "crossfade"/"enabled"/"seconds" -- kept that way
//                  // for a while specifically to avoid a migration path for
//                  // existing config files, but renamed for consistency since
//                  // (no dual-key-reading fallback; old files just get the
//                  // defaults below). audioBackend backs the PLAYBACK tab's
//                  // "Playback with" choice ("ffmpeg" or "bass"); missing key or
//                  // any other value defaults to "ffmpeg". Selecting "bass" is
//                  // only honored once bassLibraryAvailable() is true
//                  // (bass.dll/bassflac.dll/bassopus.dll present next to
//                  // Topaz.exe) -- see UC-15.
//     "autoPlay":  { "queueHorizon": 5, "titleAddingIntervalSeconds": 30,
//                    "considerGenre": false,
//                    "considerRating": false, "minimumRating": 5,
//                    "allowManualModification": false, "songRepeat": "once",
//                    "transportAccess": "nothing", "flickerNewTracks": false },
//     "bigCoverPane": { "x": 100, "y": 100, "width": 400, "height": 400,
//                       "screenName": "DISPLAY1" },
//     "tagInfoPane": { "x": 100, "y": 100, "width": 500, "height": 230,
//                      "screenName": "DISPLAY1" },
//     "audioVisualizer": { "barCount": 24, "color": "#00DAF3",
//                           "decaySpeed": 0.5, "peakHoldEnabled": true,
//                           "paneOpacity": 1.0, "sensitivity": 0.5 },
//     "audioVisualizerPane": { "x": 100, "y": 100, "width": 500, "height": 260,
//                              "screenName": "DISPLAY1" },
//     "milkdrop": { "presetFolders": [ { "path": "C:/Presets", "active": true } ],
//                   // "active" (default true when absent, for pre-existing
//                   // configs) gates whether a folder's presets are loaded
//                   // into the projectM playlist at all -- see UC-20/UC-25.
//                   // Deliberately narrower than "folders" above: no
//                   // VolumePath-style volume/relPath tracking, since preset
//                   // packs aren't expected to need drive-letter-reassignment
//                   // portability the way music library folders do.
//                   "shuffleEnabled": true,
//                   "presetDuration": 20.0, "beatSensitivity": 1.0,
//                   "hardCutsEnabled": false, "hardCutSensitivity": 0.6,
//                   "presetLocked": false, "showPresetName": true },
//     "milkdropPane": { "x": 100, "y": 100, "width": 560, "height": 360,
//                        "screenName": "DISPLAY1" }
//   }
// autoPlaySongRepeat allowed values: "once", "twice", "twiceIfNoneAvailable", "several".
// autoPlayTransportAccess allowed values: "nothing", "playPause", "playPauseAndSelect"
// (only consulted while autoPlayAllowManualModification is false).
// Settings are grouped into a nested object per SetupDialog tab (playback, autoPlay);
// genres/folders/window-layout stay flat at the top level. bigCoverPane is also
// nested (its presence in the file means "has been positioned before" — absence
// means first-ever open, so QML uses a centered default instead of x/y).
//
// The main window's own geometry follows the same flat convention as
// windowWidth/windowHeight: "windowX"/"windowY"/"windowScreenName" (last
// windowed, i.e. non-fullscreen, position) plus a flat
// "windowPositionConfigured" bool (same "never positioned yet" vs "restore
// this" distinction as bigCoverPaneConfigured, just flat instead of
// presence-of-a-nested-object, to match window-layout's existing flat
// style). screenName also picks which monitor Main.qml enters
// Window.FullScreen on at startup when startFullscreen is set.
//
// Instantiated in Main.qml as:  AppConfig { id: appConfig }
// Passed to LibraryData and SetupDialog via property binding.

class AppConfig : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QStringList  genres  READ genres  NOTIFY genresChanged)
    // Subset of genres (<= kMaxEnabledGenres) shown as GenreBar buttons; order
    // always follows genres' order. See UC-03.
    Q_PROPERTY(QStringList  enabledGenres READ enabledGenres NOTIFY enabledGenresChanged)
    Q_PROPERTY(QVariantList folders READ folders NOTIFY foldersChanged)

    // ── Layout state (window size + panel widths) ─────────────────────────
    Q_PROPERTY(int windowWidth        READ windowWidth        NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowHeight       READ windowHeight       NOTIFY windowGeometryChanged)
    // Last windowed (non-fullscreen) position + which monitor it was on.
    // windowPositionConfigured distinguishes "never positioned yet" (fresh
    // config) from "restore to this position" -- same reason
    // bigCoverPaneConfigured exists below, just flat instead of nested to
    // match window-layout's existing flat style.
    Q_PROPERTY(bool windowPositionConfigured READ windowPositionConfigured NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowX            READ windowX             NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowY            READ windowY             NOTIFY windowGeometryChanged)
    Q_PROPERTY(QString windowScreenName READ windowScreenName  NOTIFY windowGeometryChanged)
    Q_PROPERTY(int libraryTreeWidth   READ libraryTreeWidth   NOTIFY panelWidthsChanged)
    Q_PROPERTY(int playbackQueueWidth READ playbackQueueWidth NOTIFY panelWidthsChanged)
    Q_PROPERTY(int nowPlayingWidth    READ nowPlayingWidth    NOTIFY panelWidthsChanged)

    // Startup fullscreen/windowed preference (Setup > MISC). Default false
    // (Windowed) -- see Main.qml's `visibility` binding.
    Q_PROPERTY(bool startFullscreen READ startFullscreen NOTIFY startFullscreenChanged)

    // Opt-in SCAN FOLDERS progress dialog (Setup > MISC). Default false --
    // see ScanFoldersDialog.qml/LibraryModel's currentScanFolder/recentScanFiles.
    Q_PROPERTY(bool visualFolderScanning READ visualFolderScanning NOTIFY visualFolderScanningChanged)

    // "Modify the Rating for the Track currently playing" (Setup > MISC).
    // Default true. Off: NowPlaying's stars and trash-bin button stay
    // visible (the stars still show the rating) but are disabled, and
    // PlaybackEngine refuses rating changes. JSON key
    // "modifyCurrentRatingEnabled"; the 1.0.0 key "deleteCurrentRatingEnabled"
    // (trash bin only) is deliberately not migrated. See UC-29.
    Q_PROPERTY(bool modifyCurrentRatingEnabled READ modifyCurrentRatingEnabled NOTIFY modifyCurrentRatingEnabledChanged)

    // Sort order for AlbumBrowser/Search result album cards (Setup > MISC).
    // "artistYearAlbum" (default) = Artist asc -> Year desc -> Album asc;
    // "artistAlbum" = Artist asc -> Album asc. Invalid values are silently
    // ignored by the setter, same convention as autoPlaySongRepeat.
    Q_PROPERTY(QString albumBrowserSortOrder READ albumBrowserSortOrder NOTIFY albumBrowserSortOrderChanged)

    // ── Crossfade settings (PLAYBACK tab) ────────────────────────────────
    Q_PROPERTY(bool   crossfadeEnabled READ crossfadeEnabled NOTIFY crossfadeChanged)
    Q_PROPERTY(double crossfadeSeconds READ crossfadeSeconds NOTIFY crossfadeChanged)
    // "ffmpeg" (default) or "bass" -- see the schema comment above and UC-15.
    Q_PROPERTY(QString audioBackend    READ audioBackend    NOTIFY audioBackendChanged)
    // Auto Loudness Correction (UC-35): checkbox + strategy radios under the
    // "Playback with" row. Only ever acts while the RUNNING engine is BASS.
    Q_PROPERTY(bool    autoLoudnessCorrection READ autoLoudnessCorrection NOTIFY loudnessSettingsChanged)
    // "audiophile" (default) | "background"
    Q_PROPERTY(QString loudnessStrategy       READ loudnessStrategy       NOTIFY loudnessSettingsChanged)
    // Manual "Trim" sliders, one per strategy (UC-35): a user correction on top
    // of the automatic one. Never written to Topaz.volumeNormalization.json.
    Q_PROPERTY(double  audiophileTrimDb READ audiophileTrimDb NOTIFY loudnessSettingsChanged)
    Q_PROPERTY(double  backgroundTrimDb READ backgroundTrimDb NOTIFY loudnessSettingsChanged)
    // Audiophile strategy: skip the ReplayGain / R128 tag tier and always
    // measure (also honoured by the Export's Replay Gain Normalization, UC-26).
    Q_PROPERTY(bool    loudnessAlwaysMeasure READ loudnessAlwaysMeasure NOTIFY loudnessSettingsChanged)

    // ── AUTO PLAY settings ────────────────────────────────────────────────
    Q_PROPERTY(int  autoPlayQueueHorizon             READ autoPlayQueueHorizon             NOTIFY autoPlayQueueHorizonChanged)
    Q_PROPERTY(int  autoPlayTitleAddingIntervalSeconds READ autoPlayTitleAddingIntervalSeconds NOTIFY autoPlayTitleAddingIntervalSecondsChanged)
    Q_PROPERTY(bool autoPlayConsiderGenre            READ autoPlayConsiderGenre            NOTIFY autoPlayConsiderGenreChanged)
    Q_PROPERTY(bool autoPlayConsiderRating           READ autoPlayConsiderRating           NOTIFY autoPlayConsiderRatingChanged)
    Q_PROPERTY(int  autoPlayMinimumRating            READ autoPlayMinimumRating            NOTIFY autoPlayMinimumRatingChanged)
    Q_PROPERTY(bool autoPlayAllowManualModification  READ autoPlayAllowManualModification  NOTIFY autoPlayAllowManualModificationChanged)
    Q_PROPERTY(QString autoPlaySongRepeat            READ autoPlaySongRepeat               NOTIFY autoPlaySongRepeatChanged)
    Q_PROPERTY(QString autoPlayTransportAccess       READ autoPlayTransportAccess          NOTIFY autoPlayTransportAccessChanged)
    // Whether a track PlaybackEngine::addTrack() just added on AUTO PLAY's
    // behalf briefly flickers its PlaybackQueue row (see UC-16).
    Q_PROPERTY(bool autoPlayFlickerNewTracks         READ autoPlayFlickerNewTracks         NOTIFY autoPlayFlickerNewTracksChanged)

    // ── Detachable "big cover" pane geometry (see FloatingPane.qml / BigCoverWindow.qml) ──
    // READ-only + a single Q_INVOKABLE setter (saveBigCoverPaneGeometry), matching
    // this codebase's established convention — never Q_PROPERTY WRITE (see the
    // OS-volume work's Q_PROPERTY-WRITE gotcha: a WRITE-only function isn't itself
    // callable as obj.setX() from QML unless also Q_INVOKABLE).
    Q_PROPERTY(bool bigCoverPaneConfigured READ bigCoverPaneConfigured NOTIFY bigCoverPaneChanged)
    Q_PROPERTY(int  bigCoverPaneX          READ bigCoverPaneX          NOTIFY bigCoverPaneChanged)
    Q_PROPERTY(int  bigCoverPaneY          READ bigCoverPaneY          NOTIFY bigCoverPaneChanged)
    Q_PROPERTY(int  bigCoverPaneWidth      READ bigCoverPaneWidth      NOTIFY bigCoverPaneChanged)
    Q_PROPERTY(int  bigCoverPaneHeight     READ bigCoverPaneHeight     NOTIFY bigCoverPaneChanged)

    // ── Detachable "tag info" pane geometry (see FloatingPane.qml / TagInfoWindow.qml) ──
    // Same READ-only + Q_INVOKABLE-setter convention as bigCoverPane above.
    Q_PROPERTY(bool tagInfoPaneConfigured READ tagInfoPaneConfigured NOTIFY tagInfoPaneChanged)
    Q_PROPERTY(int  tagInfoPaneX          READ tagInfoPaneX          NOTIFY tagInfoPaneChanged)
    Q_PROPERTY(int  tagInfoPaneY          READ tagInfoPaneY          NOTIFY tagInfoPaneChanged)
    Q_PROPERTY(int  tagInfoPaneWidth      READ tagInfoPaneWidth      NOTIFY tagInfoPaneChanged)
    Q_PROPERTY(int  tagInfoPaneHeight     READ tagInfoPaneHeight     NOTIFY tagInfoPaneChanged)

    // ── Audio visualizer settings (see AudioVisualizerController / UC-19) ──
    Q_PROPERTY(int    audioVisualizerBarCount       READ audioVisualizerBarCount       NOTIFY audioVisualizerChanged)
    Q_PROPERTY(QString audioVisualizerColor         READ audioVisualizerColor          NOTIFY audioVisualizerChanged)
    Q_PROPERTY(double  audioVisualizerDecaySpeed    READ audioVisualizerDecaySpeed     NOTIFY audioVisualizerChanged)
    // Gain offset applied before dB normalization — 0.5 is "no change" (today's
    // default response); 1.0 boosts by +18dB, 0.0 cuts by -18dB. See
    // AudioVisualizerController::processBlock.
    Q_PROPERTY(double  audioVisualizerSensitivity   READ audioVisualizerSensitivity    NOTIFY audioVisualizerChanged)
    Q_PROPERTY(bool    audioVisualizerPeakHoldEnabled READ audioVisualizerPeakHoldEnabled NOTIFY audioVisualizerChanged)
    // Background-only opacity for the pane window itself (Window.color alpha) —
    // never applied to the bars/peak ticks, which stay fully opaque regardless.
    // See AudioVisualizerWindow.qml.
    Q_PROPERTY(double  audioVisualizerPaneOpacity     READ audioVisualizerPaneOpacity    NOTIFY audioVisualizerChanged)
    // Foreground-only opacity for the bars/peak ticks themselves, independent
    // of audioVisualizerPaneOpacity above. See AudioVisualizerWindow.qml.
    Q_PROPERTY(double  audioVisualizerBarOpacity      READ audioVisualizerBarOpacity     NOTIFY audioVisualizerChanged)

    // ── Detachable "audio visualizer" pane geometry (see FloatingPane.qml / AudioVisualizerWindow.qml) ──
    // Same READ-only + Q_INVOKABLE-setter convention as bigCoverPane/tagInfoPane above.
    Q_PROPERTY(bool audioVisualizerPaneConfigured READ audioVisualizerPaneConfigured NOTIFY audioVisualizerPaneChanged)
    Q_PROPERTY(int  audioVisualizerPaneX          READ audioVisualizerPaneX          NOTIFY audioVisualizerPaneChanged)
    Q_PROPERTY(int  audioVisualizerPaneY          READ audioVisualizerPaneY          NOTIFY audioVisualizerPaneChanged)
    Q_PROPERTY(int  audioVisualizerPaneWidth      READ audioVisualizerPaneWidth      NOTIFY audioVisualizerPaneChanged)
    Q_PROPERTY(int  audioVisualizerPaneHeight     READ audioVisualizerPaneHeight     NOTIFY audioVisualizerPaneChanged)

    // ── Milkdrop visualizer settings (see MilkdropView / UC-20) ────────────
    Q_PROPERTY(QVariantList milkdropPresetFolders    READ milkdropPresetFolders    NOTIFY milkdropChanged)
    Q_PROPERTY(bool         milkdropShuffleEnabled   READ milkdropShuffleEnabled   NOTIFY milkdropChanged)
    Q_PROPERTY(double       milkdropPresetDuration   READ milkdropPresetDuration   NOTIFY milkdropChanged)
    Q_PROPERTY(double       milkdropBeatSensitivity  READ milkdropBeatSensitivity  NOTIFY milkdropChanged)
    Q_PROPERTY(bool         milkdropHardCutsEnabled  READ milkdropHardCutsEnabled  NOTIFY milkdropChanged)
    Q_PROPERTY(double       milkdropHardCutSensitivity READ milkdropHardCutSensitivity NOTIFY milkdropChanged)
    Q_PROPERTY(bool         milkdropPresetLocked     READ milkdropPresetLocked     NOTIFY milkdropChanged)
    Q_PROPERTY(bool         milkdropShowPresetName   READ milkdropShowPresetName   NOTIFY milkdropChanged)

    // ── Detachable "milkdrop" pane geometry (see FloatingPane.qml / MilkdropWindow.qml) ──
    // Same READ-only + Q_INVOKABLE-setter convention as audioVisualizerPane above.
    Q_PROPERTY(bool milkdropPaneConfigured READ milkdropPaneConfigured NOTIFY milkdropPaneChanged)
    Q_PROPERTY(int  milkdropPaneX          READ milkdropPaneX          NOTIFY milkdropPaneChanged)
    Q_PROPERTY(int  milkdropPaneY          READ milkdropPaneY          NOTIFY milkdropPaneChanged)
    Q_PROPERTY(int  milkdropPaneWidth      READ milkdropPaneWidth      NOTIFY milkdropPaneChanged)
    Q_PROPERTY(int  milkdropPaneHeight     READ milkdropPaneHeight     NOTIFY milkdropPaneChanged)

public:
    explicit AppConfig(QObject *parent = nullptr);

    QStringList  genres()  const;
    QStringList  enabledGenres() const;
    QVariantList folders() const;

    int windowWidth()          const { return m_windowWidth;        }
    int windowHeight()         const { return m_windowHeight;       }
    bool windowPositionConfigured() const { return m_windowPositionConfigured; }
    int windowX()               const { return m_windowX;             }
    int windowY()               const { return m_windowY;             }
    QString windowScreenName()  const { return m_windowScreenName;    }
    int libraryTreeWidth()     const { return m_libraryTreeWidth;   }
    int playbackQueueWidth()   const { return m_playbackQueueWidth; }
    int nowPlayingWidth()      const { return m_nowPlayingWidth;    }
    bool startFullscreen()     const { return m_startFullscreen;   }
    bool visualFolderScanning() const { return m_visualFolderScanning; }
    bool modifyCurrentRatingEnabled() const { return m_modifyCurrentRatingEnabled; }
    QString albumBrowserSortOrder() const { return m_albumBrowserSortOrder; }

    bool    crossfadeEnabled() const { return m_crossfadeEnabled; }
    double  crossfadeSeconds() const { return m_crossfadeSeconds; }
    QString audioBackend()     const { return m_audioBackend;     }
    bool    autoLoudnessCorrection() const { return m_autoLoudnessCorrection; }
    QString loudnessStrategy()       const { return m_loudnessStrategy;       }
    double  audiophileTrimDb() const { return m_audiophileTrimDb; }
    double  backgroundTrimDb() const { return m_backgroundTrimDb; }
    bool    loudnessAlwaysMeasure() const { return m_loudnessAlwaysMeasure; }

    int  autoPlayQueueHorizon()            const { return m_autoPlayQueueHorizon;            }
    int  autoPlayTitleAddingIntervalSeconds() const { return m_autoPlayTitleAddingIntervalSeconds; }
    bool autoPlayConsiderGenre()           const { return m_autoPlayConsiderGenre;           }
    bool autoPlayConsiderRating()          const { return m_autoPlayConsiderRating;          }
    int  autoPlayMinimumRating()           const { return m_autoPlayMinimumRating;           }
    bool autoPlayAllowManualModification() const { return m_autoPlayAllowManualModification; }
    QString autoPlaySongRepeat()           const { return m_autoPlaySongRepeat;              }
    QString autoPlayTransportAccess()      const { return m_autoPlayTransportAccess;         }
    bool autoPlayFlickerNewTracks()        const { return m_autoPlayFlickerNewTracks;        }

    bool bigCoverPaneConfigured() const { return m_bigCoverPaneConfigured; }
    int  bigCoverPaneX()          const { return m_bigCoverPaneX;          }
    int  bigCoverPaneY()          const { return m_bigCoverPaneY;          }
    int  bigCoverPaneWidth()      const { return m_bigCoverPaneWidth;      }
    int  bigCoverPaneHeight()     const { return m_bigCoverPaneHeight;     }

    bool tagInfoPaneConfigured() const { return m_tagInfoPaneConfigured; }
    int  tagInfoPaneX()          const { return m_tagInfoPaneX;          }
    int  tagInfoPaneY()          const { return m_tagInfoPaneY;          }
    int  tagInfoPaneWidth()      const { return m_tagInfoPaneWidth;      }
    int  tagInfoPaneHeight()     const { return m_tagInfoPaneHeight;     }

    int     audioVisualizerBarCount()         const { return m_audioVisualizerBarCount;         }
    QString audioVisualizerColor()            const { return m_audioVisualizerColor;            }
    double  audioVisualizerDecaySpeed()       const { return m_audioVisualizerDecaySpeed;       }
    double  audioVisualizerSensitivity()      const { return m_audioVisualizerSensitivity;      }
    bool    audioVisualizerPeakHoldEnabled()  const { return m_audioVisualizerPeakHoldEnabled;  }
    double  audioVisualizerPaneOpacity()      const { return m_audioVisualizerPaneOpacity;      }
    double  audioVisualizerBarOpacity()       const { return m_audioVisualizerBarOpacity;       }

    bool audioVisualizerPaneConfigured() const { return m_audioVisualizerPaneConfigured; }
    int  audioVisualizerPaneX()          const { return m_audioVisualizerPaneX;          }
    int  audioVisualizerPaneY()          const { return m_audioVisualizerPaneY;          }
    int  audioVisualizerPaneWidth()      const { return m_audioVisualizerPaneWidth;      }
    int  audioVisualizerPaneHeight()     const { return m_audioVisualizerPaneHeight;     }

    QVariantList milkdropPresetFolders()      const { return m_milkdropPresetFolders;      }
    bool         milkdropShuffleEnabled()     const { return m_milkdropShuffleEnabled;     }
    double       milkdropPresetDuration()     const { return m_milkdropPresetDuration;     }
    double       milkdropBeatSensitivity()    const { return m_milkdropBeatSensitivity;    }
    bool         milkdropHardCutsEnabled()    const { return m_milkdropHardCutsEnabled;    }
    double       milkdropHardCutSensitivity() const { return m_milkdropHardCutSensitivity; }
    bool         milkdropPresetLocked()       const { return m_milkdropPresetLocked;       }
    bool         milkdropShowPresetName()     const { return m_milkdropShowPresetName;     }

    bool milkdropPaneConfigured() const { return m_milkdropPaneConfigured; }
    int  milkdropPaneX()          const { return m_milkdropPaneX;          }
    int  milkdropPaneY()          const { return m_milkdropPaneY;          }
    int  milkdropPaneWidth()      const { return m_milkdropPaneWidth;      }
    int  milkdropPaneHeight()     const { return m_milkdropPaneHeight;     }

    // ── Genre operations ─────────────────────────────────────────────────
    // Silently rejected (no-op) once genres() would exceed kMaxGenres --
    // mirrors the existing silent-duplicate-reject convention below.
    Q_INVOKABLE void addGenre(const QString &name);
    Q_INVOKABLE void removeGenreAt(int index);
    // Reorders the configured genre list: the entry at `from` ends up at index
    // `to`, everything between them shifts by one -- a move on a dense list, so
    // it can never open a hole. Silent no-op for out-of-range indices or
    // from == to, same convention as removeGenreAt above. Drives both the
    // SetupDialog GENRES grid order and, via the derived enabledGenres(), the
    // GenreBar button order. See UC-33.
    Q_INVOKABLE void moveGenre(int from, int to);
    Q_INVOKABLE void clearGenres();

    // ── GenreBar visibility (enabled-genre subset, see UC-03) ─────────────
    Q_INVOKABLE bool isGenreEnabled(const QString &name) const;
    // Returns false (no-op) if enabling would exceed kMaxEnabledGenres;
    // otherwise mutates, auto-saves, and returns true.
    Q_INVOKABLE bool setGenreEnabled(const QString &name, bool enabled);
    Q_INVOKABLE int  maxGenres()        const { return kMaxGenres;        }
    Q_INVOKABLE int  maxEnabledGenres() const { return kMaxEnabledGenres; }

    // ── Folder operations ────────────────────────────────────────────────
    // rawPath may be a plain path or a file:// URL — both are accepted.
    Q_INVOKABLE void addFolder(const QString &rawPath, bool includeSubfolders = true);
    Q_INVOKABLE void removeFolderAt(int index);
    Q_INVOKABLE void clearFolders();
    Q_INVOKABLE void setFolderSubfolders(int index, bool includeSubfolders);
    // Gates whether this folder is scanned at all -- see UC-04/UC-05. Takes
    // effect on the next scan (manual rescan or app restart), same as every
    // other folder-list mutation here; no change is applied immediately.
    Q_INVOKABLE void setFolderActive(int index, bool active);

    // Forces every `folders` binding to re-evaluate (re-resolving each
    // entry's live path/available via VolumePath) with no underlying
    // m_folders data having changed. Called by LibraryModel after a scan
    // completes so a folder that disappeared/reappeared while Topaz was
    // running is reflected immediately in Setup Dialog's FILE MONITORING
    // list, not only after the next restart. Deliberately NOT something
    // SetupDialog's _foldersDirty tracking reacts to -- see UC-04/UC-07.
    Q_INVOKABLE void refreshFolderAvailability() { emit foldersChanged(); }

    // ── Layout persistence ────────────────────────────────────────────────
    // Saves window size and all resizable panel widths in one atomic write.
    // Call from QML via a debounce timer on resize events.
    // windowWidth/windowHeight should be the actual window dimensions; pass
    // the stored values (appConfig.windowWidth/Height) when in fullscreen to
    // avoid overwriting with the screen resolution.
    Q_INVOKABLE void saveLayout(int windowWidth, int windowHeight,
                                int libraryTreeWidth,
                                int playbackQueueWidth,
                                int nowPlayingWidth);

    // Persists the main window's last windowed (non-fullscreen) position and
    // which monitor it was on -- same calling convention as
    // saveBigCoverPaneGeometry() below. Call from QML via the same debounce
    // timer as saveLayout(). screenName is also consulted on the next
    // startup to pick which monitor to enter Window.FullScreen on when
    // startFullscreen is set (see Main.qml).
    Q_INVOKABLE void saveWindowPosition(int x, int y, const QString &screenName);

    Q_INVOKABLE void setStartFullscreen(bool enabled);
    Q_INVOKABLE void setVisualFolderScanning(bool enabled);
    Q_INVOKABLE void setModifyCurrentRatingEnabled(bool enabled);
    // Ignores anything other than "artistYearAlbum"/"artistAlbum" (no-op) --
    // same validation convention as setAutoPlaySongRepeat().
    Q_INVOKABLE void setAlbumBrowserSortOrder(const QString &mode);

    // ── Crossfade operations ─────────────────────────────────────────────
    Q_INVOKABLE void setCrossfadeEnabled(bool enabled);
    // Clamped to [2.0, 10.0] and snapped to the nearest 0.5 s increment.
    Q_INVOKABLE void setCrossfadeSeconds(double seconds);

    // ── Playback backend (PLAYBACK tab) ──────────────────────────────────
    // Ignored (no-op) unless mode is "ffmpeg" or "bass".
    Q_INVOKABLE void setAudioBackend(const QString &mode);
    // True only if bass.dll, bassflac.dll, and bassopus.dll are all present
    // next to the running executable -- see UC-15. Checked by SetupDialog
    // before allowing "bass" to actually be selected.
    Q_INVOKABLE bool bassLibraryAvailable() const;

    // ── Auto Loudness Correction (PLAYBACK tab, UC-35) ────────────────────
    Q_INVOKABLE void setAutoLoudnessCorrection(bool on);
    // Ignored unless "audiophile" or "background".
    Q_INVOKABLE void setLoudnessStrategy(const QString &strategy);
    // True if bass_fx.dll / libbass_fx.so is present next to the executable
    // (the "Consistent Background Music" compressor needs it). Like the other
    // BASS libraries it is never bundled -- the user supplies it.
    Q_INVOKABLE bool bassFxAvailable() const;
    // Clamped to [-15, 15] and snapped to the nearest 0.5 dB, matching
    // setCrossfadeSeconds()'s convention.
    Q_INVOKABLE void setAudiophileTrimDb(double db);
    Q_INVOKABLE void setBackgroundTrimDb(double db);
    Q_INVOKABLE void setLoudnessAlwaysMeasure(bool on);

    // ── AUTO PLAY operations ─────────────────────────────────────────────
    // Clamped to [1, 15].
    Q_INVOKABLE void setAutoPlayQueueHorizon(int tracks);
    // Clamped to [5, 90].
    Q_INVOKABLE void setAutoPlayTitleAddingIntervalSeconds(int seconds);
    Q_INVOKABLE void setAutoPlayConsiderGenre(bool enabled);
    Q_INVOKABLE void setAutoPlayConsiderRating(bool enabled);
    // Clamped to [1, 10].
    Q_INVOKABLE void setAutoPlayMinimumRating(int rating);
    Q_INVOKABLE void setAutoPlayAllowManualModification(bool enabled);
    // Ignored (no-op) unless mode is one of: "once", "twice",
    // "twiceIfNoneAvailable", "several".
    Q_INVOKABLE void setAutoPlaySongRepeat(const QString &mode);
    // Ignored (no-op) unless mode is one of: "nothing", "playPause",
    // "playPauseAndSelect".
    Q_INVOKABLE void setAutoPlayTransportAccess(const QString &mode);
    Q_INVOKABLE void setAutoPlayFlickerNewTracks(bool enabled);

    // ── Big cover pane geometry ──────────────────────────────────────────
    // Called from Main.qml's Loader whenever FloatingPane.geometrySettled()
    // fires (debounced there, not here). screenName is persisted for
    // debugging/completeness but not re-exposed as its own Q_PROPERTY —
    // nothing currently needs to read it back into QML.
    Q_INVOKABLE void saveBigCoverPaneGeometry(int x, int y, int width, int height,
                                               const QString &screenName);

    // ── Tag info pane geometry ───────────────────────────────────────────
    // Same calling convention as saveBigCoverPaneGeometry above.
    Q_INVOKABLE void saveTagInfoPaneGeometry(int x, int y, int width, int height,
                                              const QString &screenName);

    // ── Audio visualizer operations ──────────────────────────────────────
    // Clamped to [8, 64].
    Q_INVOKABLE void setAudioVisualizerBarCount(int count);
    // No validation beyond non-empty — QML supplies a preset hex color string.
    Q_INVOKABLE void setAudioVisualizerColor(const QString &color);
    // Clamped to [0.0, 1.0].
    Q_INVOKABLE void setAudioVisualizerDecaySpeed(double speed);
    // Clamped to [0.0, 1.0]; 0.5 is "no change" — see the Q_PROPERTY comment above.
    Q_INVOKABLE void setAudioVisualizerSensitivity(double sensitivity);
    Q_INVOKABLE void setAudioVisualizerPeakHoldEnabled(bool enabled);
    // Background-only pane opacity; clamped to [0.0, 1.0]. Never applied to the
    // bars/peak ticks — see AudioVisualizerWindow.qml.
    Q_INVOKABLE void setAudioVisualizerPaneOpacity(double opacity);
    // Foreground-only bar opacity; clamped to [0.0, 1.0]. Independent of
    // setAudioVisualizerPaneOpacity above — see AudioVisualizerWindow.qml.
    Q_INVOKABLE void setAudioVisualizerBarOpacity(double opacity);

    // ── Audio visualizer pane geometry ───────────────────────────────────
    // Same calling convention as saveBigCoverPaneGeometry above.
    Q_INVOKABLE void saveAudioVisualizerPaneGeometry(int x, int y, int width, int height,
                                                      const QString &screenName);

    // ── Milkdrop operations ──────────────────────────────────────────────
    // rawPath may be a plain path or a file:// URL — both are accepted, same
    // as addFolder above. Always scanned recursively by MilkdropView; no
    // per-folder subfolder toggle for this first version.
    Q_INVOKABLE void addMilkdropPresetFolder(const QString &rawPath);
    Q_INVOKABLE void removeMilkdropPresetFolderAt(int index);
    Q_INVOKABLE void clearMilkdropPresetFolders();
    // Gates whether this folder's presets are loaded into the projectM
    // playlist at all -- same convention as setFolderActive() above.
    Q_INVOKABLE void setMilkdropPresetFolderActive(int index, bool active);
    Q_INVOKABLE void setMilkdropShuffleEnabled(bool enabled);
    // Seconds a preset is shown before an automatic soft cut. Clamped to [10, 150].
    Q_INVOKABLE void setMilkdropPresetDuration(double seconds);
    // Clamped to [0.0, 4.0] — projectM's own beat-detection sensitivity scale.
    Q_INVOKABLE void setMilkdropBeatSensitivity(double sensitivity);
    Q_INVOKABLE void setMilkdropHardCutsEnabled(bool enabled);
    // Volume-difference threshold that triggers a hard cut; clamped to [0.0, 1.0].
    Q_INVOKABLE void setMilkdropHardCutSensitivity(double sensitivity);
    // Disables all automatic preset transitions (hard and soft cuts) while true.
    Q_INVOKABLE void setMilkdropPresetLocked(bool locked);
    // Whether MilkdropWindow.qml shows the fading current-preset-name toast.
    Q_INVOKABLE void setMilkdropShowPresetName(bool enabled);

    // ── Milkdrop pane geometry ───────────────────────────────────────────
    // Same calling convention as saveBigCoverPaneGeometry above.
    Q_INVOKABLE void saveMilkdropPaneGeometry(int x, int y, int width, int height,
                                               const QString &screenName);

    // ── Persistence ──────────────────────────────────────────────────────
    Q_INVOKABLE void save();

    // Applies a full Topaz.config JSON blob (e.g. extracted from a backup
    // zip by BackupRestoreController::restoreConfig()) to this AppConfig
    // live, except audioBackend -- preserved from the currently running
    // value, since switching FFmpeg/BASS requires re-initializing the
    // playback deck, not safe to do mid-session (see Setup > PLAYBACK to
    // change it manually afterward). Persists the result via save() and
    // emits every NOTIFY signal except audioBackendChanged, so every
    // existing live-reactive consumer (GenreBar, AUTO PLAY, crossfade,
    // audio visualizer, Milkdrop, folders' auto-rescan via SetupDialog,
    // etc.) picks it up immediately, same as an ordinary Setup Dialog
    // edit would. Returns {success, error}.
    Q_INVOKABLE QVariantMap restoreFromJson(const QByteArray &json);

signals:
    void genresChanged();
    void enabledGenresChanged();
    void foldersChanged();
    void windowGeometryChanged();
    void panelWidthsChanged();
    void startFullscreenChanged();
    void visualFolderScanningChanged();
    void modifyCurrentRatingEnabledChanged();
    void albumBrowserSortOrderChanged();
    void crossfadeChanged();
    void audioBackendChanged();
    void loudnessSettingsChanged();
    void autoPlayQueueHorizonChanged();
    void autoPlayTitleAddingIntervalSecondsChanged();
    void autoPlayConsiderGenreChanged();
    void autoPlayConsiderRatingChanged();
    void autoPlayMinimumRatingChanged();
    void autoPlayAllowManualModificationChanged();
    void autoPlaySongRepeatChanged();
    void autoPlayTransportAccessChanged();
    void autoPlayFlickerNewTracksChanged();
    void bigCoverPaneChanged();
    void tagInfoPaneChanged();
    void audioVisualizerChanged();
    void audioVisualizerPaneChanged();
    void milkdropChanged();
    void milkdropPaneChanged();

private:
    void    load();
    // Populates every member from a parsed Topaz.config JSON object --
    // shared by load() (reads the file from disk) and restoreFromJson()
    // (reads a backup zip's extracted bytes instead). Does not save() or
    // emit any signals itself; callers own that.
    void    applyJson(const QJsonObject &root);
    QString configFilePath() const;

    // 48 = the Setup GENRES grid (6 columns x 8 rows); 40 = GenreBar's
    // 10 buttons per row x 4 rows. See UC-03.
    static constexpr int kMaxGenres        = 48;
    static constexpr int kMaxEnabledGenres = 40;

    QStringList  m_genres;
    // Membership only -- display order is always derived fresh from m_genres'
    // own order (enabledGenres()), never stored separately, so it can never
    // desync from add/remove/reorder of m_genres itself.
    QSet<QString> m_enabledGenreSet;
    // Each entry is a QVariantMap: { "path": QString, "includeSubfolders": bool }
    QVariantList m_folders;

    int m_windowWidth        = 1920;
    int m_windowHeight       = 1080;
    bool    m_windowPositionConfigured = false;
    int     m_windowX               = 0;
    int     m_windowY               = 0;
    QString m_windowScreenName;
    int m_libraryTreeWidth   = 286;
    int m_playbackQueueWidth = 374;
    int m_nowPlayingWidth    = 359;
    bool m_startFullscreen   = false;
    bool m_visualFolderScanning = false;
    bool m_modifyCurrentRatingEnabled = true;
    QString m_albumBrowserSortOrder = QStringLiteral("artistYearAlbum");

    bool    m_crossfadeEnabled = false;
    double  m_crossfadeSeconds = 5.0;
    QString m_audioBackend     = QStringLiteral("ffmpeg");
    bool    m_autoLoudnessCorrection = false;
    QString m_loudnessStrategy = QStringLiteral("audiophile");
    double  m_audiophileTrimDb = 0.0;
    double  m_backgroundTrimDb = 0.0;
    bool    m_loudnessAlwaysMeasure = false;

    int  m_autoPlayQueueHorizon             = 5;
    int  m_autoPlayTitleAddingIntervalSeconds = 30;
    bool m_autoPlayConsiderGenre            = false;
    bool m_autoPlayConsiderRating           = false;
    int  m_autoPlayMinimumRating            = 5;
    bool m_autoPlayAllowManualModification  = false;
    QString m_autoPlaySongRepeat            = QStringLiteral("once");
    QString m_autoPlayTransportAccess       = QStringLiteral("nothing");
    bool m_autoPlayFlickerNewTracks         = false;

    bool    m_bigCoverPaneConfigured = false;
    int     m_bigCoverPaneX          = 0;
    int     m_bigCoverPaneY          = 0;
    int     m_bigCoverPaneWidth      = 400;
    int     m_bigCoverPaneHeight     = 400;
    QString m_bigCoverPaneScreenName;

    bool    m_tagInfoPaneConfigured = false;
    int     m_tagInfoPaneX          = 0;
    int     m_tagInfoPaneY          = 0;
    int     m_tagInfoPaneWidth      = 500;
    int     m_tagInfoPaneHeight     = 230;
    QString m_tagInfoPaneScreenName;

    int     m_audioVisualizerBarCount        = 24;
    QString m_audioVisualizerColor           = QStringLiteral("#00DAF3");
    double  m_audioVisualizerDecaySpeed      = 0.5;
    double  m_audioVisualizerSensitivity     = 0.5;
    bool    m_audioVisualizerPeakHoldEnabled = true;
    double  m_audioVisualizerPaneOpacity     = 1.0;
    double  m_audioVisualizerBarOpacity      = 1.0;

    bool    m_audioVisualizerPaneConfigured = false;
    int     m_audioVisualizerPaneX          = 0;
    int     m_audioVisualizerPaneY          = 0;
    int     m_audioVisualizerPaneWidth      = 500;
    int     m_audioVisualizerPaneHeight     = 260;
    QString m_audioVisualizerPaneScreenName;

    // Each entry is a QVariantMap { "path": QString, "active": bool } --
    // narrower than m_folders (no volume/relPath/rawPath VolumePath
    // tracking; preset packs aren't expected to need drive-letter-
    // reassignment portability the way music library folders do).
    QVariantList m_milkdropPresetFolders;
    bool         m_milkdropShuffleEnabled     = true;
    double       m_milkdropPresetDuration     = 20.0;
    double       m_milkdropBeatSensitivity    = 1.0;
    bool         m_milkdropHardCutsEnabled    = false;
    double       m_milkdropHardCutSensitivity = 0.6;
    bool         m_milkdropPresetLocked       = false;
    bool         m_milkdropShowPresetName     = true;

    bool    m_milkdropPaneConfigured = false;
    int     m_milkdropPaneX          = 0;
    int     m_milkdropPaneY          = 0;
    int     m_milkdropPaneWidth      = 560;
    int     m_milkdropPaneHeight     = 360;
    QString m_milkdropPaneScreenName;
};
