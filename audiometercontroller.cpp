#include "audiometercontroller.h"

#include <QAudioFormat>
#include <cmath>

AudioMeterController::AudioMeterController(QObject *parent)
    : QObject(parent)
{
    m_timer = new QTimer(this);
    m_timer->setInterval(33);   // ~30 fps, same cadence as the visualizer
    connect(m_timer, &QTimer::timeout, this, &AudioMeterController::onTick);
    m_clock.start();
}

void AudioMeterController::setEngine(PlaybackEngine *engine)
{
    if (m_engine == engine) return;
    if (m_engine) m_engine->disconnect(this);
    m_engine = engine;
    if (m_engine) {
        connect(m_engine, &PlaybackEngine::audioBufferAvailable,
                this, &AudioMeterController::onAudioBufferAvailable);
    }
    emit engineChanged();
}

void AudioMeterController::setAppConfig(AppConfig *cfg)
{
    if (m_appConfig == cfg) return;
    m_appConfig = cfg;
    emit appConfigChanged();
}

void AudioMeterController::acquire()
{
    ++m_users;
    setActive(true);
}

void AudioMeterController::release()
{
    m_users = qMax(0, m_users - 1);
    if (m_users == 0) setActive(false);
}

void AudioMeterController::setActive(bool on)
{
    if (m_active == on) return;
    m_active = on;
    resetFallback();
    if (on) {
        m_lastTickMs = m_clock.elapsed();
        m_timer->start();
    } else {
        m_timer->stop();
        for (Side &s : m_out) s = Side{};
        m_over = false;
        emit levelsChanged();
    }
    emit activeChanged();
}

void AudioMeterController::resetFallback()
{
    m_accPeak[0] = m_accPeak[1] = 0.0f;
    m_accSumSq[0] = m_accSumSq[1] = 0.0;
    m_accFrames = 0;
    for (int i = 0; i < kRmsWindowTicks; ++i) {
        m_winSumSq[i][0] = m_winSumSq[i][1] = 0.0;
        m_winFrames[i] = 0;
    }
    m_winPos = 0;
}

double AudioMeterController::toDb(float linear)
{
    if (linear <= 1e-6f) return kFloorDb;
    const double db = 20.0 * std::log10(double(linear));
    return qBound(kFloorDb, db, kCeilDb);
}

// ── Fallback source: Topaz's own analysis of the PCM tap ─────────────────

void AudioMeterController::onAudioBufferAvailable(const QAudioBuffer &buffer)
{
    if (!m_active) return;   // costs nothing while no meter is shown
    const QAudioFormat fmt = buffer.format();
    const int channels = fmt.channelCount();
    const int frames   = int(buffer.frameCount());
    if (channels <= 0 || frames <= 0) return;

    // Left = channel 0, right = channel 1 (mono: both the same). Same two
    // sample formats the visualizer handles (UC-19); anything else is skipped.
    const int rightCh = channels > 1 ? 1 : 0;
    auto accumulate = [&](float l, float r) {
        l = std::fabs(l); r = std::fabs(r);
        if (l > m_accPeak[0]) m_accPeak[0] = l;
        if (r > m_accPeak[1]) m_accPeak[1] = r;
        m_accSumSq[0] += double(l) * l;
        m_accSumSq[1] += double(r) * r;
    };
    if (fmt.sampleFormat() == QAudioFormat::Float) {
        const float *d = buffer.constData<float>();
        for (int f = 0; f < frames; ++f)
            accumulate(d[f * channels], d[f * channels + rightCh]);
    } else if (fmt.sampleFormat() == QAudioFormat::Int16) {
        const qint16 *d = buffer.constData<qint16>();
        for (int f = 0; f < frames; ++f)
            accumulate(d[f * channels] / 32768.0f, d[f * channels + rightCh] / 32768.0f);
    } else {
        return;
    }
    m_accFrames += frames;
}

// ── Tick: read the source, apply ballistics, publish ─────────────────────

void AudioMeterController::applyBallistics(Side &s, double rawPeakDb, double rawRmsDb,
                                           double dt, qint64 nowMs)
{
    // Peak: instant attack, slow release (90s HiFi feel).
    s.peak = rawPeakDb >= s.peak ? rawPeakDb
                                 : qMax(rawPeakDb, s.peak - kReleaseDbPerSec * dt);
    s.rms  = rawRmsDb >= s.rms ? rawRmsDb
                               : qMax(rawRmsDb, s.rms - kRmsReleaseDbPerSec * dt);
    // Peak hold: jumps up with the peak, stays kHoldMs, then falls (never
    // below the moving peak).
    if (s.peak >= s.hold) {
        s.hold = s.peak;
        s.holdSinceMs = nowMs;
    } else if (nowMs - s.holdSinceMs > kHoldMs) {
        s.hold = qMax(s.peak, s.hold - kHoldFallDbPerSec * dt);
    }
}

void AudioMeterController::onTick()
{
    const qint64 now = m_clock.elapsed();
    const double dt = qBound(0.0, double(now - m_lastTickMs) / 1000.0, 0.25);
    m_lastTickMs = now;

    const bool playing = m_engine && m_engine->isPlaying();
    const bool fromBackend = m_engine && m_engine->levelsFromBackend();
    const QString source = fromBackend ? QStringLiteral("BASS") : QStringLiteral("TOPAZ");
    if (source != m_sourceName) {
        m_sourceName = source;
        emit sourceNameChanged();
    }

    float peak[2] = { 0.0f, 0.0f };
    float rms[2]  = { 0.0f, 0.0f };
    DeckLevels lv;
    if (playing && fromBackend && m_engine->readDeckLevels(lv)) {
        peak[0] = lv.peakL; peak[1] = lv.peakR;
        rms[0]  = lv.rmsL;  rms[1]  = lv.rmsR;
    } else if (playing) {
        // Fallback: this tick's peak, RMS over the sliding window.
        m_winSumSq[m_winPos][0] = m_accSumSq[0];
        m_winSumSq[m_winPos][1] = m_accSumSq[1];
        m_winFrames[m_winPos]   = m_accFrames;
        m_winPos = (m_winPos + 1) % kRmsWindowTicks;
        double sum[2] = { 0.0, 0.0 };
        qint64 frames = 0;
        for (int i = 0; i < kRmsWindowTicks; ++i) {
            sum[0] += m_winSumSq[i][0];
            sum[1] += m_winSumSq[i][1];
            frames += m_winFrames[i];
        }
        peak[0] = m_accPeak[0]; peak[1] = m_accPeak[1];
        if (frames > 0) {
            rms[0] = float(std::sqrt(sum[0] / double(frames)));
            rms[1] = float(std::sqrt(sum[1] / double(frames)));
        }
    }
    m_accPeak[0] = m_accPeak[1] = 0.0f;
    m_accSumSq[0] = m_accSumSq[1] = 0.0;
    m_accFrames = 0;
    if (!playing) resetFallback();

    if (peak[0] >= kOverThreshold || peak[1] >= kOverThreshold)
        m_overUntilMs = now + kOverHoldMs;
    const bool over = now < m_overUntilMs;

    const Side before[2] = { m_out[0], m_out[1] };
    for (int c = 0; c < 2; ++c)
        applyBallistics(m_out[c], toDb(peak[c]), toDb(rms[c]), dt, now);

    // Only notify on a visible change, so a silent/paused meter stops
    // re-binding QML 30 times a second.
    bool changed = over != m_over;
    for (int c = 0; c < 2 && !changed; ++c) {
        changed = std::fabs(before[c].peak - m_out[c].peak) > 0.05
               || std::fabs(before[c].rms  - m_out[c].rms)  > 0.05
               || std::fabs(before[c].hold - m_out[c].hold) > 0.05;
    }
    m_over = over;
    if (changed) emit levelsChanged();
}
