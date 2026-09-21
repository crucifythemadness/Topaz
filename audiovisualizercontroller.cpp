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
    appendSamples(buffer);
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

    const int barCount = m_appConfig ? m_appConfig->audioVisualizerBarCount() : 24;
    ensureBarCount(barCount);

    // Logarithmically-spaced bands — matches how the spectrum is perceived
    // (linear bin->bar mapping would crush the whole low end into a handful
    // of bars while treble smears across dozens).
    const float minFreq = 40.0f;
    const float maxFreq = qMin(float(sampleRate) / 2.0f, 16000.0f);
    const float binHz   = float(sampleRate) / float(kFftSize);
    const int   maxBin  = kFftSize / 2;

    const float decaySetting  = m_appConfig ? float(m_appConfig->audioVisualizerDecaySpeed()) : 0.5f;
    const float decayRate     = 0.04f + decaySetting * 0.20f;
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
            const float re = freq[k].r;
            const float im = freq[k].i;
            mag += std::sqrt(re * re + im * im);
            ++n;
        }
        if (n > 0) mag /= float(n);
        mag /= float(kFftSize);   // kiss_fftr performs no scaling of its own

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
    emit barLevelsChanged();
}
