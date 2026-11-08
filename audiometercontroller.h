#pragma once

#include "appconfig.h"
#include "playbackengine.h"

#include <QElapsedTimer>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>

// Full headers (not forward declarations) required here -- same reason as
// AudioVisualizerController's header comment (Q_PROPERTY pointer types).

// ── AudioMeterController ──────────────────────────────────────────────────
// Level analysis for the Audio Meter pane (UC-37). Two sources, chosen live
// on every tick:
//   1. BASS (when BASS is the active backend and bass.dll exports
//      BASS_ChannelGetLevelEx): PlaybackEngine::readDeckLevels() -- what BASS
//      itself measures on the playing deck(s), incl. volume/crossfade.
//   2. Fallback (FFmpeg backend, or an old bass.dll): Topaz's own analysis of
//      PlaybackEngine::audioBufferAvailable -- per-side peak (max |sample|)
//      and RMS over a sliding ~300 ms window.
// Both feed the same 90s-style ballistics (instant attack, slow release,
// peak hold) so every meter style looks identical whichever source is used.
// Scale: dBFS (0 dB = digital full scale). OVER latches for 2 s when a peak
// reaches full scale.
//
// Instantiated once in Main.qml:
//   AudioMeterController { id: audioMeter; engine: engine; appConfig: appConfig }
// Meter views call acquire()/release(); the 30 fps timer only runs while at
// least one exists, so the controller costs nothing while no meter is shown.
class AudioMeterController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(PlaybackEngine* engine    READ engine    WRITE setEngine    NOTIFY engineChanged)
    Q_PROPERTY(AppConfig*      appConfig READ appConfig WRITE setAppConfig NOTIFY appConfigChanged)
    // True while at least one meter view is shown (see acquire()/release()).
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

    // All in dBFS, clamped to [kFloorDb, kCeilDb]; one NOTIFY at <= 30 fps.
    Q_PROPERTY(double peakLeftDb  READ peakLeftDb  NOTIFY levelsChanged)
    Q_PROPERTY(double peakRightDb READ peakRightDb NOTIFY levelsChanged)
    Q_PROPERTY(double rmsLeftDb   READ rmsLeftDb   NOTIFY levelsChanged)
    Q_PROPERTY(double rmsRightDb  READ rmsRightDb  NOTIFY levelsChanged)
    Q_PROPERTY(double holdLeftDb  READ holdLeftDb  NOTIFY levelsChanged)
    Q_PROPERTY(double holdRightDb READ holdRightDb NOTIFY levelsChanged)
    Q_PROPERTY(bool   over        READ over        NOTIFY levelsChanged)
    // "BASS" or "TOPAZ" -- which source is measuring right now.
    Q_PROPERTY(QString sourceName READ sourceName NOTIFY sourceNameChanged)
    Q_PROPERTY(double floorDb READ floorDb CONSTANT)

public:
    explicit AudioMeterController(QObject *parent = nullptr);

    static constexpr double kFloorDb = -60.0;
    static constexpr double kCeilDb  = 6.0;

    PlaybackEngine *engine()    const { return m_engine; }
    AppConfig      *appConfig() const { return m_appConfig; }
    bool active() const { return m_active; }
    void setEngine(PlaybackEngine *engine);
    void setAppConfig(AppConfig *cfg);

    // Every meter view calls acquire() when created and release() when
    // destroyed; the controller runs while the count is > 0. A count, not a
    // bool, because a pane moving between its floating window and a dock
    // area creates the new view before the old one is gone.
    Q_INVOKABLE void acquire();
    Q_INVOKABLE void release();

    double peakLeftDb()  const { return m_out[0].peak; }
    double peakRightDb() const { return m_out[1].peak; }
    double rmsLeftDb()   const { return m_out[0].rms;  }
    double rmsRightDb()  const { return m_out[1].rms;  }
    double holdLeftDb()  const { return m_out[0].hold; }
    double holdRightDb() const { return m_out[1].hold; }
    bool   over()        const { return m_over; }
    QString sourceName() const { return m_sourceName; }
    double floorDb()     const { return kFloorDb; }

signals:
    void engineChanged();
    void appConfigChanged();
    void activeChanged();
    void levelsChanged();
    void sourceNameChanged();

private slots:
    void onAudioBufferAvailable(const QAudioBuffer &buffer);
    void onTick();

private:
    struct Side {
        double peak = kFloorDb;   // displayed peak (ballistics applied)
        double rms  = kFloorDb;
        double hold = kFloorDb;   // peak-hold marker
        qint64 holdSinceMs = 0;
    };
    void setActive(bool on);
    void resetFallback();
    void applyBallistics(Side &s, double rawPeakDb, double rawRmsDb, double dt, qint64 nowMs);
    static double toDb(float linear);

    // 90s ballistics, see the class comment.
    static constexpr double kReleaseDbPerSec     = 24.0;
    static constexpr double kHoldMs              = 1500.0;
    static constexpr double kHoldFallDbPerSec    = 30.0;
    static constexpr double kRmsReleaseDbPerSec  = 18.0;
    static constexpr qint64 kOverHoldMs          = 2000;
    static constexpr float  kOverThreshold       = 0.9989f;  // -0.01 dBFS
    static constexpr int    kRmsWindowTicks      = 9;        // x 33 ms ≈ 300 ms

    PlaybackEngine *m_engine    = nullptr;
    AppConfig      *m_appConfig = nullptr;
    bool    m_active = false;
    int     m_users  = 0;
    QTimer *m_timer  = nullptr;
    QElapsedTimer m_clock;
    qint64  m_lastTickMs = 0;

    Side    m_out[2];
    bool    m_over = false;
    qint64  m_overUntilMs = 0;
    QString m_sourceName = QStringLiteral("TOPAZ");

    // Fallback accumulators (PCM tap), reset every tick.
    float   m_accPeak[2] = { 0.0f, 0.0f };
    double  m_accSumSq[2] = { 0.0, 0.0 };
    qint64  m_accFrames = 0;
    // Sliding RMS window: the last kRmsWindowTicks ticks' sums.
    double  m_winSumSq[kRmsWindowTicks][2] = {};
    qint64  m_winFrames[kRmsWindowTicks] = {};
    int     m_winPos = 0;
};
