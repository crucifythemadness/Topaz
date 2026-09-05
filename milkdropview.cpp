// GL/glew.h must be included before any other header that might pull in
// gl.h (Qt's OpenGL headers, included transitively via milkdropview.h) —
// GLEW's own ordering requirement, avoids type/macro redefinition conflicts.
#include <GL/glew.h>

#include "milkdropview.h"

#include <QSGSimpleTextureNode>
#include <QQuickWindow>
#include <QAudioFormat>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QCoreApplication>
#include <QFileInfo>
#include <QtMath>

// ── Constructor / Destructor ──────────────────────────────────────────────

MilkdropView::MilkdropView(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(QQuickItem::ItemHasContents, true);

    m_renderTimer = new QTimer(this);
    m_renderTimer->setInterval(33); // ~30fps — a full readback+upload per tick
                                     // costs more than AudioVisualizerController's
                                     // plain QVariantList publish, so this stays
                                     // deliberately modest for a first version.
    connect(m_renderTimer, &QTimer::timeout, this, &MilkdropView::onRenderTick);
    m_renderTimer->start();
}

MilkdropView::~MilkdropView()
{
    teardown();
}

void MilkdropView::teardown()
{
    if (m_glContext && m_renderWindow) {
        m_glContext->makeCurrent(m_renderWindow);
        if (m_playlist) {
            projectm_playlist_destroy(m_playlist);
            m_playlist = nullptr;
        }
        if (m_projectM) {
            projectm_destroy(m_projectM);
            m_projectM = nullptr;
        }
        m_glContext->doneCurrent();
    }
    delete m_glContext;
    m_glContext = nullptr;
    delete m_renderWindow;
    m_renderWindow = nullptr;
}

void MilkdropView::logDiagnostic(const QString &message)
{
    qWarning() << "MilkdropView:" << message;

    static const QString logPath = QCoreApplication::applicationDirPath() + "/milkdrop_debug.log";
    QFile f(logPath);
    if (f.open(QIODevice::Append | QIODevice::Text)) {
        QTextStream out(&f);
        out << QDateTime::currentDateTime().toString(Qt::ISODate) << "  " << message << '\n';
    }
}

// ── Properties ────────────────────────────────────────────────────────────

void MilkdropView::setEngine(PlaybackEngine *engine)
{
    if (m_engine == engine) return;
    if (m_engine) m_engine->disconnect(this);
    m_engine = engine;
    if (m_engine) {
        connect(m_engine, &PlaybackEngine::audioBufferAvailable,
                this, &MilkdropView::onAudioBufferAvailable);
    }
    emit engineChanged();
}

void MilkdropView::setAppConfig(AppConfig *cfg)
{
    if (m_appConfig == cfg) return;
    m_appConfig = cfg;
    emit appConfigChanged();
}

// ── Lifecycle ─────────────────────────────────────────────────────────────

void MilkdropView::itemChange(ItemChange change, const ItemChangeData &value)
{
    QQuickItem::itemChange(change, value);
    if (change == QQuickItem::ItemSceneChange && value.window
        && width() > 0 && height() > 0) {
        ensureInitialized();
    }
}

void MilkdropView::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (!window() || newGeometry.width() <= 0 || newGeometry.height() <= 0)
        return;

    ensureInitialized();

    const qreal dpr = window()->devicePixelRatio();
    resizeSurface(QSize(qCeil(newGeometry.width() * dpr), qCeil(newGeometry.height() * dpr)));
}

void MilkdropView::ensureInitialized()
{
    if (m_projectM || m_initFailed || !window() || width() <= 0 || height() <= 0)
        return;

    QSurfaceFormat format;
    format.setRenderableType(QSurfaceFormat::OpenGL);
    format.setProfile(QSurfaceFormat::CoreProfile);
    format.setVersion(3, 3);
    format.setDepthBufferSize(24);
    format.setStencilBufferSize(8);

    // window() is guaranteed non-null here (checked above).
    const qreal dpr = window()->devicePixelRatio();
    m_renderSize = QSize(qCeil(width() * dpr), qCeil(height() * dpr));

    // A real QWindow, never shown — not QOffscreenSurface. Qt's own docs
    // state QOffscreenSurface's framebuffer pixels are "not accessible";
    // projectM 4.1.7 always renders its final output to framebuffer 0 (see
    // onRenderTick()), so that framebuffer needs to be a genuine, readable
    // native surface. create() allocates the native window/pixel format
    // without ever mapping it on screen — visibility and "having a real
    // renderable surface" are independent in Qt.
    m_renderWindow = new QWindow();
    m_renderWindow->setSurfaceType(QWindow::OpenGLSurface);
    m_renderWindow->setFormat(format);
    m_renderWindow->setGeometry(0, 0, m_renderSize.width(), m_renderSize.height());
    m_renderWindow->create();

    m_glContext = new QOpenGLContext(this);
    m_glContext->setFormat(format);
    if (!m_glContext->create() || !m_glContext->makeCurrent(m_renderWindow)) {
        logDiagnostic(QStringLiteral("failed to create the offscreen OpenGL context"));
        m_initFailed = true;
        emit initFailedChanged();
        return;
    }
    logDiagnostic(QStringLiteral("offscreen OpenGL context created, format: %1.%2 profile=%3")
                       .arg(m_glContext->format().majorVersion())
                       .arg(m_glContext->format().minorVersion())
                       .arg(m_glContext->format().profile()));

    // libprojectM's own renderer resolves every extended OpenGL call (FBOs,
    // shaders, textures) through GLEW's global function-pointer table, but
    // does not call glewInit() itself — the embedding application must, per
    // projectM's own SDL2 reference frontend. Skipping this makes every such
    // call jump through an uninitialized (null) function pointer — a hard
    // crash on the very first render, regardless of presets. See UC-20.
    glewExperimental = GL_TRUE;
    const GLenum glewResult = glewInit();
    if (glewResult != GLEW_OK) {
        logDiagnostic(QStringLiteral("glewInit() failed: %1")
                           .arg(reinterpret_cast<const char *>(glewGetErrorString(glewResult))));
        m_glContext->doneCurrent();
        m_initFailed = true;
        emit initFailedChanged();
        return;
    }
    logDiagnostic(QStringLiteral("glewInit() OK, version %1")
                       .arg(reinterpret_cast<const char *>(glewGetString(GLEW_VERSION))));

    m_projectM = projectm_create();
    if (!m_projectM) {
        logDiagnostic(QStringLiteral("projectm_create() failed"));
        m_glContext->doneCurrent();
        m_initFailed = true;
        emit initFailedChanged();
        return;
    }
    logDiagnostic(QStringLiteral("projectm_create() OK"));

    m_playlist = projectm_playlist_create(m_projectM);

    projectm_playlist_set_preset_switched_event_callback(
        m_playlist,
        [](bool isHardCut, unsigned int index, void *userData) {
            auto *self = static_cast<MilkdropView *>(userData);
            self->logDiagnostic(QStringLiteral("preset switched OK, index=%1 hardCut=%2")
                                     .arg(index).arg(isHardCut));

            if (char *presetPath = projectm_playlist_item(self->m_playlist, index)) {
                const QString name = QFileInfo(QString::fromUtf8(presetPath)).completeBaseName();
                projectm_playlist_free_string(presetPath);

                // This event fires the instant a switch is *requested*, not
                // once the new preset actually fills the screen. A soft cut
                // blends the old/new preset over projectm_get_soft_cut_duration()
                // seconds, during which the screen still shows a mix of both --
                // updating the name immediately made the toast visibly precede
                // the preset it names. Delay by the same duration so the toast
                // lands once the crossfade is done; a hard cut has no blend, so
                // it updates right away.
                //
                // Switches aren't always this single, tidy sequence, though:
                // with Hard Cuts enabled, projectM's own beat-driven hard-cut
                // logic can fire a second, independent switch just 0-2s after
                // a duration-triggered soft cut (confirmed in practice via
                // milkdrop_debug.log -- e.g. a hardCut=0 switch immediately
                // followed by a hardCut=1 switch to a different preset). Since
                // the soft cut's toast is still pending its ~3s delay when
                // that happens, it would otherwise land right after the hard
                // cut's, naming a preset that never actually finished showing.
                // The generation counter makes a deferred update a no-op once
                // a newer switch has superseded it.
                const int generation = ++self->m_presetSwitchGeneration;
                const double delaySeconds =
                    isHardCut ? 0.0 : projectm_get_soft_cut_duration(self->m_projectM);
                QTimer::singleShot(qRound(delaySeconds * 1000), self, [self, name, generation]() {
                    if (self->m_presetSwitchGeneration != generation)
                        return;
                    self->m_currentPresetName = name;
                    emit self->currentPresetNameChanged();
                });
            }
        },
        this);
    projectm_playlist_set_preset_switch_failed_event_callback(
        m_playlist,
        [](const char *presetFilename, const char *message, void *userData) {
            auto *self = static_cast<MilkdropView *>(userData);
            self->logDiagnostic(QStringLiteral("preset switch FAILED: %1 -- %2")
                                     .arg(QString::fromUtf8(presetFilename), QString::fromUtf8(message)));
        },
        this);

    resizeSurface(m_renderSize);

    applyAppConfigSettings();
    rebuildPresetList();

    m_glContext->doneCurrent();
}

void MilkdropView::resizeSurface(const QSize &pixelSize)
{
    if (!m_glContext || !m_renderWindow || pixelSize.isEmpty())
        return;

    if (m_renderSize != pixelSize) {
        // No custom FBO involved — projectM renders directly into this
        // window's own default framebuffer; see onRenderTick() for why a
        // separate custom FBO can't be used with the pinned projectM version.
        m_renderWindow->resize(pixelSize);
        m_renderSize = pixelSize;
    }

    if (m_projectM)
        projectm_set_window_size(m_projectM, size_t(pixelSize.width()), size_t(pixelSize.height()));
}

// ── Settings / preset list ────────────────────────────────────────────────

void MilkdropView::applyAppConfigSettings()
{
    if (!m_projectM || !m_appConfig)
        return;

    projectm_set_beat_sensitivity(m_projectM, float(m_appConfig->milkdropBeatSensitivity()));
    projectm_set_preset_duration(m_projectM, m_appConfig->milkdropPresetDuration());
    projectm_set_hard_cut_enabled(m_projectM, m_appConfig->milkdropHardCutsEnabled());
    projectm_set_hard_cut_sensitivity(m_projectM, float(m_appConfig->milkdropHardCutSensitivity()));
    projectm_set_preset_locked(m_projectM, m_appConfig->milkdropPresetLocked());

    if (m_playlist)
        projectm_playlist_set_shuffle(m_playlist, m_appConfig->milkdropShuffleEnabled());
}

void MilkdropView::rebuildPresetList()
{
    if (!m_playlist || !m_appConfig)
        return;

    QStringList folders;
    for (const QVariant &v : m_appConfig->milkdropPresetFolders()) {
        const QVariantMap m = v.toMap();
        if (!m.value(QStringLiteral("active"), true).toBool())
            continue;
        folders.append(m.value(QStringLiteral("path")).toString());
    }
    if (folders == m_appliedPresetFolders)
        return;

    // Preset packs commonly ship a sibling "Textures" folder next to the
    // preset folder itself (e.g. Presets/ + Textures/) for presets that
    // reference custom textures — probe for one alongside each configured
    // folder. Includes the preset folders themselves too, harmless if they
    // don't contain any textures directly.
    QStringList textureSearchPaths = folders;
    for (const QString &folder : folders) {
        const QDir dir(folder);
        for (const QString &candidate : {QStringLiteral("Textures"), QStringLiteral("textures")}) {
            const QString texturePath = dir.filePath(candidate);
            if (QDir(texturePath).exists()) {
                textureSearchPaths.append(texturePath);
                break;
            }
        }
    }

    QVector<QByteArray> textureSearchPathsUtf8;
    QVector<const char *> textureSearchPathPtrs;
    textureSearchPathsUtf8.reserve(textureSearchPaths.size());
    textureSearchPathPtrs.reserve(textureSearchPaths.size());
    for (const QString &path : textureSearchPaths)
        textureSearchPathsUtf8.append(path.toUtf8());
    for (const QByteArray &bytes : textureSearchPathsUtf8)
        textureSearchPathPtrs.append(bytes.constData());
    projectm_set_texture_search_paths(m_projectM, textureSearchPathPtrs.data(),
                                       size_t(textureSearchPathPtrs.size()));

    projectm_playlist_clear(m_playlist);
    for (const QString &folder : folders)
        projectm_playlist_add_path(m_playlist, folder.toUtf8().constData(),
                                    /*recurse_subdirs=*/true, /*allow_duplicates=*/false);
    m_appliedPresetFolders = folders;

    const uint32_t presetCount = projectm_playlist_size(m_playlist);
    logDiagnostic(QStringLiteral("playlist now has %1 preset(s) after scanning %2")
                       .arg(presetCount).arg(folders.join(QStringLiteral(", "))));

    // Populating the playlist only makes presets available — it doesn't load
    // or display any of them. projectM's own SDL2 reference frontend has a
    // dedicated "DisplayInitialPreset()" step for exactly this; without it,
    // no preset is ever active and there's nothing to render each frame.
    if (presetCount > 0) {
        if (m_appConfig->milkdropShuffleEnabled())
            projectm_playlist_play_next(m_playlist, /*hard_cut=*/true);
        else
            projectm_playlist_set_position(m_playlist, 0, /*hard_cut=*/true);
    }
}

// ── Audio feed ────────────────────────────────────────────────────────────

void MilkdropView::onAudioBufferAvailable(const QAudioBuffer &buffer)
{
    if (!m_projectM)
        return;

    const QAudioFormat fmt = buffer.format();
    const int channels = fmt.channelCount();
    const int frames   = int(buffer.frameCount());
    if (channels <= 0 || frames <= 0)
        return;

    m_sampleBuffer.resize(frames);

    // Same "only Float32/Int16, downmixed to mono" simplification as
    // AudioVisualizerController::appendSamples — see UC-20's "Known limitations".
    if (fmt.sampleFormat() == QAudioFormat::Float) {
        const float *data = buffer.constData<float>();
        for (int f = 0; f < frames; ++f) {
            float sum = 0.0f;
            for (int c = 0; c < channels; ++c)
                sum += data[f * channels + c];
            m_sampleBuffer[f] = sum / float(channels);
        }
    } else if (fmt.sampleFormat() == QAudioFormat::Int16) {
        const qint16 *data = buffer.constData<qint16>();
        for (int f = 0; f < frames; ++f) {
            int sum = 0;
            for (int c = 0; c < channels; ++c)
                sum += data[f * channels + c];
            m_sampleBuffer[f] = (float(sum) / float(channels)) / 32768.0f;
        }
    } else {
        return;
    }

    projectm_pcm_add_float(m_projectM, m_sampleBuffer.constData(), frames, PROJECTM_MONO);
}

// ── Render tick ───────────────────────────────────────────────────────────

void MilkdropView::onRenderTick()
{
    if (!m_projectM || !m_glContext || m_renderSize.isEmpty() || !isVisible() || !window())
        return;

    m_glContext->makeCurrent(m_renderWindow);

    applyAppConfigSettings();
    rebuildPresetList();

    // No custom FBO here (deliberately — see the header comment): projectM
    // 4.1.7's plain projectm_opengl_render_frame() unconditionally rebinds
    // framebuffer 0 at the end of its own render pass
    // (glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0) in ProjectM.cpp — confirmed
    // by reading the actual source), so any custom FBO bound beforehand
    // never receives the real output. Rendering straight to this offscreen
    // surface's own default framebuffer (FBO 0) is what projectM's own
    // render call already targets, so no explicit bind is needed at all.
    projectm_opengl_render_frame(m_projectM);

    const int w = m_renderSize.width();
    const int h = m_renderSize.height();
    QImage frame(w, h, QImage::Format_RGBA8888);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, frame.bits());
    // OpenGL's origin is bottom-left, QImage's is top-left.
    m_latestFrame = frame.flipped(Qt::Vertical);
    m_frameDirty = true;

    m_glContext->doneCurrent();

    // Periodic (not per-tick — would spam the log) diagnostic: samples a
    // couple of pixels from our own readback so a "still blank" report can
    // tell whether the FBO/QImage pipeline is producing real varying content
    // or a solid color, without needing to open the debug .bmp dump.
    ++m_tickCount;
    if (m_tickCount == 1 || m_tickCount % 150 == 0) {
        const QColor center = m_latestFrame.pixelColor(m_latestFrame.width() / 2, m_latestFrame.height() / 2);
        const QColor corner = m_latestFrame.pixelColor(2, 2);
        logDiagnostic(QStringLiteral("render tick #%1, frame %2x%3, center=%4 corner=%5")
                           .arg(m_tickCount)
                           .arg(m_latestFrame.width()).arg(m_latestFrame.height())
                           .arg(center.name(QColor::HexArgb), corner.name(QColor::HexArgb)));
    }

    update();
}

QSGNode *MilkdropView::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    // Qt Quick calls updatePaintNode() on any ItemHasContents item as soon as
    // it's added to the scene — not only after update() is explicitly
    // requested — so this can run before onRenderTick() has ever produced a
    // first frame. Returning a QSGSimpleTextureNode with no texture ever set
    // crashes the scene graph (null texture dereference) — nullptr means
    // "nothing to paint yet" and is picked back up once onRenderTick() calls
    // update() after the first successful render.
    if (!oldNode && m_latestFrame.isNull())
        return nullptr;

    auto *node = static_cast<QSGSimpleTextureNode *>(oldNode);
    if (!node) {
        node = new QSGSimpleTextureNode();
        node->setOwnsTexture(true);
    }

    if (m_frameDirty && !m_latestFrame.isNull()) {
        node->setTexture(window()->createTextureFromImage(m_latestFrame));
        m_frameDirty = false;
    }
    node->setRect(boundingRect());
    return node;
}
