#pragma once

#include "appconfig.h"
#include "playbackengine.h"

// Full headers (not forward declarations) required here — see
// AutoPlayController's header comment for why (Q_PROPERTY pointer types need
// complete types wherever registered).
#include <projectM-4/projectM.h>
#include <projectM-4/playlist.h>

#include <QQuickItem>
#include <QQmlEngine>
#include <QOpenGLContext>
#include <QWindow>
#include <QImage>
#include <QSize>
#include <QTimer>
#include <QVector>
#include <QStringList>

// ── MilkdropView ────────────────────────────────────────────────────────
// Renders a Milkdrop-compatible visualization (via projectM,
// github.com/projectM-visualizer/projectm) for the currently playing track.
// Unlike AudioVisualizerController (a non-visual controller feeding small
// numeric arrays to separate QML-drawn bars), this class *is* the render
// surface, instantiated directly inside MilkdropWindow.qml rather than
// shared/owned by Main.qml. See UC-20 in the architecture doc for the full
// pipeline and the reasoning behind the offscreen-render/readback approach.
//
// projectM's renderer issues raw OpenGL calls and needs its own current GL
// context — it cannot be mixed directly into Qt Quick's own scenegraph,
// which defaults to the Direct3D11 RHI backend on Windows (see UC-17's
// WindowChrome note). Instead, this class owns a fully independent
// QOpenGLContext rendering onto a real, never-shown QWindow (not
// QOffscreenSurface — its own framebuffer pixels are explicitly documented
// as inaccessible, and projectM 4.1.7 always renders to framebuffer 0, so
// that framebuffer must be a genuine, readable native surface — see
// ensureInitialized()/onRenderTick()). Every render tick, projectM renders
// directly into that window's own default framebuffer, the result is read
// back via glReadPixels into a QImage, and uploaded as an ordinary
// QSGTexture — Quick's own backend never sees a raw GL call.
//
// Instantiated directly in MilkdropWindow.qml:
//   MilkdropView { anchors.fill: parent; engine: engine; appConfig: appConfig }
class MilkdropView : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(PlaybackEngine* engine    READ engine    WRITE setEngine    NOTIFY engineChanged)
    Q_PROPERTY(AppConfig*      appConfig READ appConfig WRITE setAppConfig NOTIFY appConfigChanged)
    // True if the offscreen OpenGL context or the projectM instance itself
    // failed to initialize (e.g. this system's GPU/driver doesn't support the
    // required OpenGL 3.3 core profile) — lets MilkdropWindow.qml show an
    // explicit "unavailable" message instead of an unexplained blank pane.
    Q_PROPERTY(bool initFailed READ initFailed NOTIFY initFailedChanged)
    // Filename (no directory, no .milk extension) of the currently active
    // preset, updated from the preset-switched callback in ensureInitialized().
    // Empty until the first preset actually switches in.
    Q_PROPERTY(QString currentPresetName READ currentPresetName NOTIFY currentPresetNameChanged)

public:
    explicit MilkdropView(QQuickItem *parent = nullptr);
    ~MilkdropView() override;

    PlaybackEngine *engine()    const { return m_engine; }
    AppConfig      *appConfig() const { return m_appConfig; }
    bool            initFailed() const { return m_initFailed; }
    QString         currentPresetName() const { return m_currentPresetName; }

    void setEngine(PlaybackEngine *engine);
    void setAppConfig(AppConfig *cfg);

signals:
    void engineChanged();
    void appConfigChanged();
    void initFailedChanged();
    void currentPresetNameChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *data) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private slots:
    // Runs on the GUI thread — PlaybackEngine::audioBufferAvailable is emitted
    // from the FFmpeg decode thread, but Qt::AutoConnection already queues
    // delivery onto this object's thread, same as AudioVisualizerController.
    void onAudioBufferAvailable(const QAudioBuffer &buffer);
    // ~30fps QTimer tick (also GUI thread, so never overlaps the slot above):
    // makes the offscreen context current, renders one projectM frame into
    // the FBO, reads it back, and requests a scenegraph update.
    void onRenderTick();

private:
    // Creates the offscreen GL context/surface and the projectM + playlist
    // instances. No-ops if already initialized or if window()/size aren't
    // ready yet; safe to call from both itemChange and geometryChange.
    void ensureInitialized();
    // Pushes current AppConfig values into projectM. Cheap; called every
    // render tick rather than wired to milkdropChanged(), matching the
    // "read live, never cached" convention PlaybackEngine/AudioVisualizerController
    // already use for their own settings.
    void applyAppConfigSettings();
    // Rescans AppConfig's preset folders into the playlist, but only when the
    // folder list actually changed since last applied — folder scanning is
    // real filesystem I/O, unlike the cheap parameter setters above.
    void rebuildPresetList();
    // Resizes the render window itself (device-pixel-ratio corrected)
    // and tells projectM about the new size; no-ops if unchanged.
    void resizeSurface(const QSize &pixelSize);
    void teardown();
    // Diagnostic-only, not a hot path: writes to qWarning() (visible only if
    // a console/debugger is attached) AND appends to a plain-text log file
    // next to Topaz.exe, so behavior can be inspected after the fact
    // regardless of how the app was launched. Added after several rounds of
    // "still doesn't render" reports with no way to see what was actually
    // happening — see UC-20's "Known limitations".
    void logDiagnostic(const QString &message);

    PlaybackEngine *m_engine    = nullptr;
    AppConfig      *m_appConfig = nullptr;

    QOpenGLContext *m_glContext    = nullptr;
    QWindow        *m_renderWindow = nullptr;   // real, never-shown native window — see class comment
    QSize           m_renderSize;               // current render-window / projectM window size

    projectm_handle          m_projectM = nullptr;
    projectm_playlist_handle m_playlist = nullptr;

    QVector<float> m_sampleBuffer;   // reused scratch buffer for downmixed samples
    QImage         m_latestFrame;
    bool           m_frameDirty = false;

    QTimer     *m_renderTimer = nullptr;
    QStringList m_appliedPresetFolders;   // last folder list actually applied to the playlist
    int         m_tickCount = 0;          // throttles the periodic render-tick diagnostic log

    bool m_initFailed = false;

    QString m_currentPresetName;
};
