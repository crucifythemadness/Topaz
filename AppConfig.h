#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QStringList>
#include <QVariantList>

// AppConfig — persistent application configuration.
//
// Stored in:  QStandardPaths::AppConfigLocation / Topaz.config  (JSON)
// Schema:
//   {
//     "genres":  [ "Techno", "IDM", ... ],
//     "folders": [ { "path": "C:/Music", "includeSubfolders": true }, ... ],
//     "crossfadeEnabled": false,
//     "crossfadeSeconds": 5.0
//   }
//
// Instantiated in Main.qml as:  AppConfig { id: appConfig }
// Passed to LibraryData and SetupDialog via property binding.

class AppConfig : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QStringList  genres  READ genres  NOTIFY genresChanged)
    Q_PROPERTY(QVariantList folders READ folders NOTIFY foldersChanged)

    // ── Layout state (window size + panel widths) ─────────────────────────
    Q_PROPERTY(int windowWidth        READ windowWidth        NOTIFY windowGeometryChanged)
    Q_PROPERTY(int windowHeight       READ windowHeight       NOTIFY windowGeometryChanged)
    Q_PROPERTY(int libraryTreeWidth   READ libraryTreeWidth   NOTIFY panelWidthsChanged)
    Q_PROPERTY(int playbackQueueWidth READ playbackQueueWidth NOTIFY panelWidthsChanged)
    Q_PROPERTY(int nowPlayingWidth    READ nowPlayingWidth    NOTIFY panelWidthsChanged)

    // ── Crossfade settings ──────────────────────────────────────────────
    Q_PROPERTY(bool   crossfadeEnabled READ crossfadeEnabled NOTIFY crossfadeChanged)
    Q_PROPERTY(double crossfadeSeconds READ crossfadeSeconds NOTIFY crossfadeChanged)

public:
    explicit AppConfig(QObject *parent = nullptr);

    QStringList  genres()  const;
    QVariantList folders() const;

    int windowWidth()          const { return m_windowWidth;        }
    int windowHeight()         const { return m_windowHeight;       }
    int libraryTreeWidth()     const { return m_libraryTreeWidth;   }
    int playbackQueueWidth()   const { return m_playbackQueueWidth; }
    int nowPlayingWidth()      const { return m_nowPlayingWidth;    }

    bool   crossfadeEnabled() const { return m_crossfadeEnabled; }
    double crossfadeSeconds() const { return m_crossfadeSeconds; }

    // ── Genre operations ─────────────────────────────────────────────────
    Q_INVOKABLE void addGenre(const QString &name);
    Q_INVOKABLE void removeGenreAt(int index);
    Q_INVOKABLE void clearGenres();

    // ── Folder operations ────────────────────────────────────────────────
    // rawPath may be a plain path or a file:// URL — both are accepted.
    Q_INVOKABLE void addFolder(const QString &rawPath, bool includeSubfolders = true);
    Q_INVOKABLE void removeFolderAt(int index);
    Q_INVOKABLE void clearFolders();
    Q_INVOKABLE void setFolderSubfolders(int index, bool includeSubfolders);

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

    // ── Crossfade operations ─────────────────────────────────────────────
    Q_INVOKABLE void setCrossfadeEnabled(bool enabled);
    // Clamped to [2.0, 10.0] and snapped to the nearest 0.5 s increment.
    Q_INVOKABLE void setCrossfadeSeconds(double seconds);

    // ── Persistence ──────────────────────────────────────────────────────
    Q_INVOKABLE void save();

signals:
    void genresChanged();
    void foldersChanged();
    void windowGeometryChanged();
    void panelWidthsChanged();
    void crossfadeChanged();

private:
    void    load();
    QString configFilePath() const;

    QStringList  m_genres;
    // Each entry is a QVariantMap: { "path": QString, "includeSubfolders": bool }
    QVariantList m_folders;

    int m_windowWidth        = 1920;
    int m_windowHeight       = 1080;
    int m_libraryTreeWidth   = 286;
    int m_playbackQueueWidth = 374;
    int m_nowPlayingWidth    = 359;

    bool   m_crossfadeEnabled = false;
    double m_crossfadeSeconds = 5.0;
};
