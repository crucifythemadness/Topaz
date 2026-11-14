#include "audiovisualizercontroller.h"

#include "third_party/kissfft/kiss_fftr.h"

#include <QAudioFormat>
#include <QDebug>
#include <cmath>

namespace {
constexpr float kPi = 3.14159265358979323846f;
}

// ── Constructor / Destructor ──────────────────────────────────────────────

AudioVisualizerController::AudioVisualizerController(QObject *parent)
    : QObject(parent)
{
    m_fftCfg = kiss_fftr_alloc(kFftSize, 0, nullptr, nullptr);

    m_updateTimer = new QTimer(this);
    m_updateTimer->setInterval(33); // ~30fps — decoupled from raw buffer-arrival rate
    connect(m_updateTimer, &QTimer::timeout, this, &AudioVisualizerController::onUpdateTick);
    m_updateTimer->start();
    m_clock.start();
}

AudioVisualizerController::~AudioVisualizerController()
{
    if (m_fftCfg) kiss_fftr_free(m_fftCfg);
}

// ── Properties ────────────────────────────────────────────────────────────

void AudioVisualizerController::setEngine(PlaybackEngine *engine)
{
    if (m_engine == engine) return;
    if (m_engine) m_engine->disconnect(this);
    m_engine = engine;
    if (m_engine) {
        connect(m_engine, &PlaybackEngine::audioBufferAvailable,
                this, &AudioVisualizerController::onAudioBufferAvailable);
    }
    emit engineChanged();
}

void AudioVisualizerController::setAppConfig(AppConfig *cfg)
{
    if (m_appConfig == cfg) return;
    m_appConfig = cfg;
    emit appConfigChanged();
}

// ── Audio pipeline ────────────────────────────────────────────────────────

void AudioVisualizerController::onAudioBufferAvailable(const QAudioBuffer &buffer)
{
    // BASS spectrum source in effect: no KissFFT work at all (the PCM tap
    // itself keeps running for Milkdrop). See updateSource().
    if (m_backendSpectrum) return;
    // A late buffer queued just before stop/pause must not lift the bars
    // again while releaseToZero() is emptying them.
    if (!m_engine || !m_engine->isPlaying()) return;
    appendSamples(buffer);
}

bool AudioVisualizerController::wantsBackendSpectrum() const
{
    return m_appConfig && m_engine
        && m_appConfig->audioVisualizerSpectrumSource() == QStringLiteral("bass")
        && m_engine->spectrumFromBackend();
}

void AudioVisualizerController::updateSource()
{
    const bool backend = wantsBackendSpectrum();
    if (backend == m_backendSpectrum) return;
    m_backendSpectrum = backend;
    // Neither path may continue from the other's leftovers: a half-filled
    // KissFFT queue would otherwise be analysed seconds later.
    m_sampleBuffer.clear();
    m_lastBackendReadMs = -1;
    emit sourceNameChanged();
}

void AudioVisualizerController::readBackendSpectrum()
{
    // Only called while playing (onUpdateTick); stopped/paused is releaseToZero().
    int sampleRate = 0;
    if (!m_engine->readDeckSpectrum(m_backendMags, sampleRate) || sampleRate <= 0) return;

    // Decay runs per update here (~33 ms) instead of per KissFFT block
    // (kFftSize samples, ~23 ms at 44.1 kHz) -- scale it by the real elapsed
    // time so Decay Speed feels the same in both modes.
    const qint64 now = m_clock.elapsed();
    const double dtSec = (m_lastBackendReadMs < 0)
        ? m_updateTimer->interval() / 1000.0
        : qBound(0.0, double(now - m_lastBackendReadMs) / 1000.0, 0.1);
    m_lastBackendReadMs = now;
    const float blockSec = float(kFftSize) / float(sampleRate);

    for (float &m : m_backendMags) m *= kBassCalibration;
    applySpectrum(m_backendMags.constData(), int(m_backendMags.size()), sampleRate,
                  float(dtSec) / blockSec);
}

void AudioVisualizerController::appendSamples(const QAudioBuffer &buffer)
{
    const QAudioFormat fmt = buffer.format();
    const int channels = fmt.channelCount();
    const int frames   = int(buffer.frameCount());
    if (channels <= 0 || frames <= 0) return;

    if (!m_loggedFirstBuffer) {
        m_loggedFirstBuffer = true;
        qInfo() << "AudioVisualizerController: first audio buffer:" << fmt.sampleRate() << "Hz,"
                << channels << "channels, sample format" << fmt.sampleFormat() << "," << frames << "frames";
    }

    m_sampleBuffer.reserve(m_sampleBuffer.size() + frames);

    // Deliberate simplification for a first version: only the two sample
    // formats actually produced in practice by Qt Multimedia's FFmpeg backend
    // are handled (Float32 and Int16, both interleaved). Anything else is
    // silently skipped rather than attempting a generic conversion — see
    // UC-19's "Known limitations".
    if (fmt.sampleFormat() == QAudioFormat::Float) {
        const float *data = buffer.constData<float>();
        for (int f = 0; f < frames; ++f) {
            float sum = 0.0f;
            for (int c = 0; c < channels; ++c)
                sum += data[f * channels + c];
            m_sampleBuffer.append(sum / float(channels));
        }
    } else if (fmt.sampleFormat() == QAudioFormat::Int16) {
        const qint16 *data = buffer.constData<qint16>();
        for (int f = 0; f < frames; ++f) {
            int sum = 0;
            for (int c = 0; c < channels; ++c)
                sum += data[f * channels + c];
            m_sampleBuffer.append((float(sum) / float(channels)) / 32768.0f);
        }
    } else {
        if (!m_warnedUnsupportedFormat) {
            m_warnedUnsupportedFormat = true;
            qWarning() << "AudioVisualizerController: unsupported sample format" << fmt.sampleFormat()
                       << "-- audio in this format is skipped, so no bars will move";
        }
        return;
    }

    // SCOPE style (only while a SCOPE view exists): keep the newest mono
    // samples in a ring buffer -- the frames just appended above.
    if (m_waveformUsers > 0) {
        const int first = int(m_sampleBuffer.size()) - frames;
        for (int i = qMax(0, first); i < m_sampleBuffer.size(); ++i) {
            m_ring[m_ringPos] = m_sampleBuffer[i];
            m_ringPos = (m_ringPos + 1) % kRingSize;
        }
    }

    const int sampleRate = fmt.sampleRate();
    while (m_sampleBuffer.size() >= kFftSize) {
        processBlock(m_sampleBuffer.constData(), sampleRate);
        m_sampleBuffer.remove(0, kFftSize);
    }
}

void AudioVisualizerController::processBlock(const float *samples, int sampleRate)
{
    if (!m_fftCfg || sampleRate <= 0) return;

    // Hann window — standard for spectrum analysis, reduces spectral leakage
    // from analyzing a finite, non-periodic block of audio.
    float windowed[kFftSize];
    for (int i = 0; i < kFftSize; ++i) {
        const float w = 0.5f - 0.5f * std::cos(2.0f * kPi * float(i) / float(kFftSize - 1));
        windowed[i] = samples[i] * w;
    }

    kiss_fft_cpx freq[kFftSize / 2 + 1];
    kiss_fftr(m_fftCfg, windowed, freq);

    // Normalized magnitudes -- kiss_fftr performs no scaling of its own.
    float mags[kFftSize / 2 + 1];
    for (int k = 0; k <= kFftSize / 2; ++k)
        mags[k] = std::sqrt(freq[k].r * freq[k].r + freq[k].i * freq[k].i) / float(kFftSize);

    applySpectrum(mags, kFftSize / 2 + 1, sampleRate, 1.0f);
}

// Shared by both spectrum sources (KissFFT above, BASS in onUpdateTick()), so
// every Setup option -- bar count, sensitivity, decay, peak hold -- behaves
// identically whichever one is in use. mags: normalized magnitude per bin of
// a kFftSize-point FFT (bin k = k * sampleRate / kFftSize Hz). decayScale:
// how many KissFFT blocks' worth of time this update stands for (1 on the
// KissFFT path, which runs once per block).
void AudioVisualizerController::applySpectrum(const float *mags, int binCount,
                                              int sampleRate, float decayScale)
{
    if (sampleRate <= 0 || binCount <= 1) return;

    const int barCount = m_appConfig ? m_appConfig->audioVisualizerBarCount() : 24;
    ensureBarCount(barCount);

    // Logarithmically-spaced bands — matches how the spectrum is perceived
    // (linear bin->bar mapping would crush the whole low end into a handful
    // of bars while treble smears across dozens).
    const float minFreq = 40.0f;
    const float maxFreq = qMin(float(sampleRate) / 2.0f, 16000.0f);
    const float binHz   = float(sampleRate) / float(kFftSize);
    const int   maxBin  = qMin(kFftSize / 2, binCount - 1);

    const float decaySetting  = m_appConfig ? float(m_appConfig->audioVisualizerDecaySpeed()) : 0.5f;
    const float decayRate     = (0.04f + decaySetting * 0.20f) * decayScale;
    const float peakDecayRate = decayRate * 0.15f;

    // Gain offset applied before dB normalization below — 0.5 (default) is
    // "no change" from the original hardcoded mapping; the ±18dB range lets
    // the user compensate for how much headroom typical music leaves below
    // 0dBFS (which varies a lot by mastering, hence exposing an offset rather
    // than just picking a different fixed ceiling).
    const float sensitivity = m_appConfig ? float(m_appConfig->audioVisualizerSensitivity()) : 0.5f;
    const float gainDb      = (sensitivity - 0.5f) * 2.0f * kMaxSensitivityBoostDb;

    for (int b = 0; b < barCount; ++b) {
        const float loF = minFreq * std::pow(maxFreq / minFreq, float(b) / float(barCount));
        const float hiF = minFreq * std::pow(maxFreq / minFreq, float(b + 1) / float(barCount));
        const int loBin = qMax(1, int(loF / binHz));
        const int hiBin = qMax(loBin, qMin(maxBin, int(hiF / binHz)));

        float mag = 0.0f;
        int   n   = 0;
        for (int k = loBin; k <= hiBin; ++k) {
            mag += mags[k];
            ++n;
        }
        if (n > 0) mag /= float(n);

        // dB-scale and clamp into [0,1]. Floor/ceiling chosen empirically for
        // typical music playback levels; gainDb (user Sensitivity setting)
        // shifts where a given signal lands within that fixed range.
        const float db    = 20.0f * std::log10(mag + 1.0e-6f) + gainDb;
        const float level = qBound(0.0f, (db + 60.0f) / 60.0f, 1.0f);

        float &bar = m_barLevels[b];
        bar = qMax(level, bar - decayRate);

        float &peak = m_peakLevels[b];
        peak = (level > peak) ? level : qMax(0.0f, peak - peakDecayRate);

        if (!m_loggedFirstNonZeroLevel && level > 0.0f) {
            m_loggedFirstNonZeroLevel = true;
            qInfo() << "AudioVisualizerController: first non-zero bar level computed (bar" << b
                    << "=" << level << ") -- audio analysis is working; if the pane is still blank, "
                       "the problem is on the drawing side";
        }
    }

    m_dirty = true;
}

// Stopped or paused: no more audio arrives on either path, so without this
// the bars would freeze at the last analysed frame. Instead they fall to
// empty at the Decay Speed setting (peaks at their own slower rate) -- the
// same release the Audio Meter does when playback stops.
void AudioVisualizerController::releaseToZero()
{
    const qint64 now = m_clock.elapsed();
    if (m_lastIdleMs < 0) {
        // Just stopped: drop any half-filled KissFFT block, it must not be
        // analysed when playback resumes; the BASS path restarts its clock.
        m_sampleBuffer.clear();
        m_lastBackendReadMs = -1;
    }
    const double dtSec = (m_lastIdleMs < 0)
        ? m_updateTimer->interval() / 1000.0
        : qBound(0.0, double(now - m_lastIdleMs) / 1000.0, 0.1);
    m_lastIdleMs = now;

    // Same rates as applySpectrum(), expressed per KissFFT block at 44.1 kHz.
    const float decayScale    = float(dtSec) / (float(kFftSize) / 44100.0f);
    const float decaySetting  = m_appConfig ? float(m_appConfig->audioVisualizerDecaySpeed()) : 0.5f;
    const float decayRate     = (0.04f + decaySetting * 0.20f) * decayScale;
    const float peakDecayRate = decayRate * 0.15f;

    bool changed = false;
    for (float &bar : m_barLevels) {
        if (bar <= 0.0f) continue;
        bar = qMax(0.0f, bar - decayRate);
        changed = true;
    }
    for (float &peak : m_peakLevels) {
        if (peak <= 0.0f) continue;
        peak = qMax(0.0f, peak - peakDecayRate);
        changed = true;
    }
    if (changed) m_dirty = true;   // publishes until everything is at zero, then idles
}

void AudioVisualizerController::ensureBarCount(int count)
{
    count = qMax(1, count);
    if (m_barLevels.size() == count) return;
    m_barLevels.resize(count);
    m_peakLevels.resize(count);
}

// ── Publish tick ──────────────────────────────────────────────────────────

void AudioVisualizerController::onUpdateTick()
{
    // Engine/setting can change at any time (Setup, backend switch, BASS
    // missing) -- re-checked every tick, a few pointer reads.
    updateSource();
    const bool playing = m_engine && m_engine->isPlaying();
    if (playing) {
        m_lastIdleMs = -1;
        if (m_backendSpectrum) readBackendSpectrum();
    } else {
        releaseToZero();
    }
    if (m_waveformUsers > 0) updateWaveform(playing);

    if (!m_dirty) return;
    m_dirty = false;

    QVariantList barsOut;
    QVariantList peaksOut;
    barsOut.reserve(m_barLevels.size());
    peaksOut.reserve(m_peakLevels.size());
    for (float v : std::as_const(m_barLevels))  barsOut.append(v);
    for (float v : std::as_const(m_peakLevels)) peaksOut.append(v);

    m_barLevelsOut  = barsOut;
    m_peakLevelsOut = peaksOut;
    m_barLevelsPub  = m_barLevels;    // plain-float copies for VisualizerShapeItem
    m_peakLevelsPub = m_peakLevels;
    emit barLevelsChanged();
}

// ── SCOPE waveform ────────────────────────────────────────────────────────

void AudioVisualizerController::acquireWaveform()
{
    if (m_waveformUsers++ == 0) {
        m_ring.fill(0.0f, kRingSize);
        m_ringPos = 0;
        m_waveformOut.fill(0.0f, kWaveformPoints);
    }
}

void AudioVisualizerController::releaseWaveform()
{
    if (m_waveformUsers > 0) --m_waveformUsers;
}

// Newest kRingSize mono samples (TOPAZ: the ring buffer filled from the PCM
// tap; BASS: read straight from the playing deck(s) -- what is audible now),
// a rising-zero-crossing trigger for a steady picture, then the SCOPE level
// (Setup > STYLE & COLOR, not Sensitivity): Auto Level keeps the music's
// peaks at Size (peak envelope, instant attack, ~-6 dB per 1.5 s release,
// floor 0.03 so silence isn't blown up into noise); off, Size is a plain
// gain (1.0 = full scale fills the height). Peaks above 90 % are soft-limited
// instead of clipped flat. Then 2:1 down to kWaveformPoints.
// Stopped/paused: shrinks to a flat line, and the envelope starts afresh.
void AudioVisualizerController::updateWaveform(bool playing)
{
    if (!playing) {
        m_scopeEnv = 0.0f;
        m_lastScopeMs = -1;
        bool any = false;
        for (float &v : m_waveformOut) {
            v *= 0.7f;
            if (std::fabs(v) < 0.002f) v = 0.0f; else any = true;
        }
        if (any || m_waveformLive) { m_waveformLive = any; emit waveformChanged(); }
        return;
    }

    float samples[kRingSize];
    if (m_backendSpectrum) {
        if (!m_engine->readDeckWaveform(samples, kRingSize)) return;
    } else {
        for (int i = 0; i < kRingSize; ++i)
            samples[i] = m_ring[(m_ringPos + i) % kRingSize];   // oldest -> newest
    }

    const int window = kWaveformPoints * 2;            // samples shown
    int start = 0;
    for (int i = 1; i < kRingSize - window; ++i) {
        if (samples[i - 1] < 0.0f && samples[i] >= 0.0f) { start = i; break; }
    }

    const bool  autoLevel = m_appConfig ? m_appConfig->audioVisualizerScopeAutoLevel() : true;
    const float size      = m_appConfig ? float(m_appConfig->audioVisualizerScopeSize()) : 0.7f;
    float gain = size;
    if (autoLevel) {
        float peak = 0.0f;
        for (int i = start; i < start + window; ++i)
            peak = qMax(peak, std::fabs(samples[i]));
        const qint64 now = m_clock.elapsed();
        const float dtSec = (m_lastScopeMs < 0)
            ? 0.0f : qBound(0.0f, float(now - m_lastScopeMs) / 1000.0f, 0.1f);
        m_lastScopeMs = now;
        m_scopeEnv *= std::pow(0.5f, dtSec / 1.5f);       // release: -6 dB per 1.5 s
        m_scopeEnv = qMax(m_scopeEnv, peak);               // attack: instant
        gain = size / qMax(m_scopeEnv, 0.03f);
    }
    constexpr float kKnee = 0.9f;
    for (int k = 0; k < kWaveformPoints; ++k) {
        const float s = 0.5f * (samples[start + 2 * k] + samples[start + 2 * k + 1]) * gain;
        const float a = std::fabs(s);
        m_waveformOut[k] = (a <= kKnee) ? s
            : std::copysign(kKnee + (1.0f - kKnee) * std::tanh((a - kKnee) / (1.0f - kKnee)), s);
    }
    m_waveformLive = true;
    emit waveformChanged();
}
