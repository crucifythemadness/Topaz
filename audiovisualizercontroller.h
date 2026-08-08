#pragma once

#include "appconfig.h"
#include "playbackengine.h"

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVector>
#include <QTimer>

// Full headers (not forward declarations) required here — see
// AutoPlayController's header comment for why (Q_PROPERTY pointer types need
// complete types wherever registered, and AUTOMOC's alphabetical
// mocs_compilation.cpp ordering can't be relied on to pull them in first).

struct kiss_fftr_state;
typedef struct kiss_fftr_state *kiss_fftr_cfg;

// ── AudioVisualizerController ─────────────────────────────────────────────
// Owns the audio-analysis pipeline for the bar visualizer pane: consumes
// PlaybackEngine::audioBufferAvailable(), runs a real FFT (KissFFT, vendored
// under third_party/kissfft/) over fixed-size blocks of the decoded PCM, and
// exposes per-bar magnitude levels to QML. Depends on PlaybackEngine +
// AppConfig; neither of those classes knows this one exists — same
// "controller subscribes to PlaybackEngine's signals" split AutoPlayController
// already uses. See UC-19 in the architecture doc for the full pipeline.
//
// Instantiated once in Main.qml:
//   AudioVisualizerController { id: audioVisualizer; engine: engine; appConfig: appConfig }
class AudioVisualizerController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(PlaybackEngine* engine    READ engine    WRITE setEngine    NOTIFY engineChanged)
    Q_PROPERTY(AppConfig*      appConfig READ appConfig WRITE setAppConfig NOTIFY appConfigChanged)

    // Current normalized (0.0-1.0) magnitude per bar, length ==
    // appConfig->audioVisualizerBarCount(). Updated at ~30fps (decoupled from
    // the raw, much-higher-frequency buffer arrival rate) via an internal
    // QTimer, not on every single audio buffer.
    Q_PROPERTY(QVariantList barLevels  READ barLevels  NOTIFY barLevelsChanged)
    // Slowly-decaying peak-hold marker per bar, same length/update cadence.
    // Harmless to always compute; QML only draws it when the AppConfig
    // peak-hold setting is on.
    Q_PROPERTY(QVariantList peakLevels READ peakLevels NOTIFY barLevelsChanged)

public:
    explicit AudioVisualizerController(QObject *parent = nullptr);
    ~AudioVisualizerController() override;

    PlaybackEngine *engine()    const { return m_engine; }
    AppConfig      *appConfig() const { return m_appConfig; }
    QVariantList    barLevels()  const { return m_barLevelsOut; }
    QVariantList    peakLevels() const { return m_peakLevelsOut; }

    void setEngine(PlaybackEngine *engine);
    void setAppConfig(AppConfig *cfg);

signals:
    void engineChanged();
    void appConfigChanged();
    void barLevelsChanged();

private slots:
    void onAudioBufferAvailable(const QAudioBuffer &buffer);
    void onUpdateTick();

private:
    // Resizes m_barLevels/m_peakLevels (preserving existing values) if
    // appConfig's bar count has changed since the last buffer. Cheap check,
    // avoids needing a dedicated changed-signal listener for one setting —
    // same "read live, never cached" convention used throughout this codebase.
    void ensureBarCount(int count);
    // Extracts mono float samples from buffer (Float32 or Int16 interleaved —
    // the two formats actually encountered from the FFmpeg backend in
    // practice; anything else is silently skipped, a deliberate simplification
    // for a first version — see UC-19's "Known limitations"), appends to
    // m_sampleBuffer, and runs processBlock() for every complete FFT-sized
    // block accumulated.
    void appendSamples(const QAudioBuffer &buffer);
    // Windows + FFTs exactly kFftSize samples (already removed from the front
    // of m_sampleBuffer by the caller), groups bins into log-spaced bands, and
    // updates m_barLevels/m_peakLevels with decay applied.
    void processBlock(const float *samples, int sampleRate);

    static constexpr int   kFftSize = 1024;
    // Max boost/cut applied by the Sensitivity setting at its extremes — see
    // processBlock()'s gainDb computation.
    static constexpr float kMaxSensitivityBoostDb = 18.0f;

    PlaybackEngine *m_engine    = nullptr;
    AppConfig      *m_appConfig = nullptr;

    kiss_fftr_cfg m_fftCfg = nullptr;
    QVector<float> m_sampleBuffer;   // accumulates decoded samples until kFftSize is reached

    QVector<float> m_barLevels;      // internal working values (decayed each block)
    QVector<float> m_peakLevels;     // internal working values (slow-decayed)
    QVariantList   m_barLevelsOut;   // published copy, refreshed on the update timer
    QVariantList   m_peakLevelsOut;

    bool    m_dirty = false;         // true when m_barLevels changed since the last publish
    QTimer *m_updateTimer = nullptr; // ~30fps publish cadence
};
