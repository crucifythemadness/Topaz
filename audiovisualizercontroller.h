#pragma once

#include "appconfig.h"
#include "playbackengine.h"

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVector>
#include <QTimer>
#include <QElapsedTimer>

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
    // "BASS" or "TOPAZ" -- which analysis produces the bars right now (BASS
    // only when Setup chose it AND BASS is the active engine). Shown in Setup.
    Q_PROPERTY(QString sourceName READ sourceName NOTIFY sourceNameChanged)

public:
    explicit AudioVisualizerController(QObject *parent = nullptr);
    ~AudioVisualizerController() override;

    PlaybackEngine *engine()    const { return m_engine; }
    AppConfig      *appConfig() const { return m_appConfig; }
    QVariantList    barLevels()  const { return m_barLevelsOut; }
    QVariantList    peakLevels() const { return m_peakLevelsOut; }
    QString         sourceName() const
    { return m_backendSpectrum ? QStringLiteral("BASS") : QStringLiteral("TOPAZ"); }

    // For VisualizerShapeItem (LINE / RADIAL / SCOPE): the published levels
    // as plain floats (same values as barLevels/peakLevels, no QVariant), and
    // the SCOPE waveform (kWaveformPoints values in -1..1). The waveform is
    // only computed while at least one SCOPE view holds acquireWaveform().
    const QVector<float> &barLevelsVec()  const { return m_barLevelsPub; }
    const QVector<float> &peakLevelsVec() const { return m_peakLevelsPub; }
    const QVector<float> &waveform()      const { return m_waveformOut; }
    void acquireWaveform();
    void releaseWaveform();
    static constexpr int kWaveformPoints = 512;

    void setEngine(PlaybackEngine *engine);
    void setAppConfig(AppConfig *cfg);

signals:
    void engineChanged();
    void appConfigChanged();
    void barLevelsChanged();
    void sourceNameChanged();
    void waveformChanged();

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
    // Spectrum (normalized per-bin magnitudes of a kFftSize-point FFT) ->
    // log-spaced bars with sensitivity, decay and peak hold. Shared by both
    // sources, so every Setup option works identically in both.
    void applySpectrum(const float *mags, int binCount, int sampleRate, float decayScale);

    // Optional BASS spectrum source (Setup "Spectrum Analysis" = BASS):
    // wantsBackendSpectrum() = chosen AND the active engine can deliver it;
    // updateSource() switches m_backendSpectrum (falls back to KissFFT
    // silently, the saved choice stays); readBackendSpectrum() reads BASS's
    // FFT of what is audible right now, once per update tick.
    bool wantsBackendSpectrum() const;
    void updateSource();
    void readBackendSpectrum();
    // Stopped/paused: bars and peaks fall to empty at the Decay Speed rate
    // instead of freezing (like the Audio Meter's release).
    void releaseToZero();
    void updateWaveform(bool playing);

    static constexpr int   kFftSize = 1024;
    // Max boost/cut applied by the Sensitivity setting at its extremes — see
    // processBlock()'s gainDb computation.
    static constexpr float kMaxSensitivityBoostDb = 18.0f;
    // Scales BASS's FFT magnitudes onto the KissFFT path's |X|/N scale, so the
    // same Sensitivity gives the same bar height in both modes. Measured
    // 2026-11-14 with sine tones (63 Hz..9 kHz, 0/-12/-30 dBFS, mono+stereo)
    // through both paths: BASS = 4.00 x KissFFT everywhere (spread 0.005 dB).
    // See UC-19 "Spectrum source".
    static constexpr float kBassCalibration = 0.25f;

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

    bool           m_backendSpectrum   = false;  // BASS spectrum source in effect
    QVector<float> m_backendMags;                // reused per tick, no allocation
    QElapsedTimer  m_clock;
    qint64         m_lastBackendReadMs = -1;     // -1 = first read after (re)start
    qint64         m_lastIdleMs        = -1;     // -1 = playing / first idle tick

    QVector<float> m_barLevelsPub;               // published plain-float copies
    QVector<float> m_peakLevelsPub;

    // SCOPE waveform (see acquireWaveform()).
    static constexpr int kRingSize = 2048;
    int            m_waveformUsers = 0;
    QVector<float> m_ring;                       // newest mono samples (TOPAZ source)
    int            m_ringPos       = 0;
    QVector<float> m_waveformOut;
    bool           m_waveformLive  = false;      // last published waveform was not flat
    float          m_scopeEnv      = 0.0f;       // SCOPE Auto Level peak envelope (0 = reset)
    qint64         m_lastScopeMs   = -1;         // -1 = first waveform tick after (re)start

    // One-shot terminal diagnostics (see appendSamples()/processBlock()), so a
    // "pane opens but nothing moves" report can be split into "no audio ever
    // arrived" vs "audio arrived but the format was skipped" vs "bars computed
    // fine, so it's a drawing problem" without another debugging round-trip.
    bool m_loggedFirstBuffer       = false;
    bool m_loggedFirstNonZeroLevel = false;
    bool m_warnedUnsupportedFormat = false;
};
