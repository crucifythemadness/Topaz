#include "loudnessanalyzer.h"

#include "basslibrary.h"
#include "loudnesslog.h"
#include "tagreader.h"

#include <QDateTime>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QMutexLocker>
#include <QThread>

#include <algorithm>
#include <cmath>

#if defined(_WIN32)
#include <string>
#endif

// Quiet by default; enable with QT_LOGGING_RULES="topaz.loudness.info=true".
Q_LOGGING_CATEGORY(lcLoudness, "topaz.loudness", QtWarningMsg)

// ── LoudnessMeter ─────────────────────────────────────────────────────────

LoudnessMeter::LoudnessMeter(int sampleRate, int channels)
    : m_rate(sampleRate), m_chans(channels)
{
    constexpr double kPi = 3.14159265358979323846;

    // Stage 1: head-related high shelf (BS.1770-4, generalised to any rate).
    {
        const double f0 = 1681.974450955533, G = 3.999843853973347, Q = 0.7071752369554196;
        const double K  = std::tan(kPi * f0 / sampleRate);
        const double Vh = std::pow(10.0, G / 20.0);
        const double Vb = std::pow(Vh, 0.4996667741545416);
        const double a0 = 1.0 + K / Q + K * K;
        m_shelf.b0 = (Vh + Vb * K / Q + K * K) / a0;
        m_shelf.b1 = 2.0 * (K * K - Vh) / a0;
        m_shelf.b2 = (Vh - Vb * K / Q + K * K) / a0;
        m_shelf.a1 = 2.0 * (K * K - 1.0) / a0;
        m_shelf.a2 = (1.0 - K / Q + K * K) / a0;
    }
    // Stage 2: revised low-frequency B-curve, a 2nd-order high-pass.
    {
        const double f0 = 38.13547087602444, Q = 0.5003270373238773;
        const double K  = std::tan(kPi * f0 / sampleRate);
        const double a0 = 1.0 + K / Q + K * K;
        m_highpass.b0 = 1.0; m_highpass.b1 = -2.0; m_highpass.b2 = 1.0;
        m_highpass.a1 = 2.0 * (K * K - 1.0) / a0;
        m_highpass.a2 = (1.0 - K / Q + K * K) / a0;
    }

    m_shelfState.assign(size_t(channels), State{});
    m_hpState.assign(size_t(channels), State{});

    // BS.1770 channel weights G_i (applied to each channel's mean square):
    // L R C = 1.0, LFE = 0, Ls Rs = 1.41 (~ +1.5 dB). Mono counts twice
    // (dual mono).
    m_weight.assign(size_t(channels), 1.0);
    if (channels == 1) {
        m_weight[0] = 2.0;
    } else if (channels > 3) {
        m_weight[3] = 0.0;                                   // LFE
        for (int c = 4; c < channels && c < 6; ++c)
            m_weight[size_t(c)] = 1.41;                      // Ls, Rs
    }

    m_subLen = std::max(1, sampleRate / 10);                 // 100 ms
}

void LoudnessMeter::process(const float *in, int frames)
{
    for (int i = 0; i < frames; ++i) {
        for (int c = 0; c < m_chans; ++c) {
            const double x = double(in[size_t(i) * size_t(m_chans) + size_t(c)]);
            const double ax = std::fabs(x);
            if (ax > m_peak) m_peak = ax;
            const double y = run(m_highpass, m_hpState[size_t(c)],
                                 run(m_shelf, m_shelfState[size_t(c)], x));
            m_subEnergy += m_weight[size_t(c)] * y * y;
        }
        if (++m_subFill == m_subLen) {
            // A 400 ms block = the last four 100 ms sub-blocks (75 % overlap).
            m_recent[0] = m_recent[1]; m_recent[1] = m_recent[2];
            m_recent[2] = m_recent[3]; m_recent[3] = m_subEnergy;
            if (m_recentCount < 4) ++m_recentCount;
            if (m_recentCount == 4)
                m_blocks.push_back((m_recent[0] + m_recent[1] + m_recent[2] + m_recent[3])
                                   / (4.0 * m_subLen));
            m_subEnergy = 0.0;
            m_subFill = 0;
        }
    }
    m_frames += frames;
}

bool LoudnessMeter::integratedLufs(double *lufs) const
{
    // Absolute gate: -70 LUFS  <=>  mean square > 10^((-70 + 0.691) / 10).
    const double absGate = std::pow(10.0, (-70.0 + 0.691) / 10.0);
    double sum = 0.0;
    size_t n = 0;
    for (const double z : m_blocks)
        if (z > absGate) { sum += z; ++n; }
    if (n == 0) return false;

    // Relative gate: 10 LU below the mean of what passed the absolute gate.
    const double relGate = (sum / double(n)) * 0.1;
    double sum2 = 0.0;
    size_t n2 = 0;
    for (const double z : m_blocks)
        if (z > absGate && z > relGate) { sum2 += z; ++n2; }
    if (n2 == 0) return false;

    *lufs = -0.691 + 10.0 * std::log10(sum2 / double(n2));
    return true;
}

// ── LoudnessAnalyzer: worker thread plumbing ──────────────────────────────

class LoudnessAnalyzer::Thread final : public QThread
{
public:
    explicit Thread(LoudnessAnalyzer *owner) : m_owner(owner) {}
protected:
    void run() override { m_owner->workerLoop(); }
private:
    LoudnessAnalyzer *m_owner;
};

LoudnessAnalyzer::LoudnessAnalyzer(QObject *parent) : QObject(parent) {}

LoudnessAnalyzer::~LoudnessAnalyzer()
{
    m_quit = true;
    {
        QMutexLocker l(&m_mutex);
        m_cond.wakeAll();
    }
    if (m_thread) {
        m_thread->wait();      // the worker aborts a running pass promptly and flushes the JSON
        delete m_thread;
    }
}

void LoudnessAnalyzer::request(const Request &r, bool urgent)
{
    if (r.id.isNull() || r.filePath.isEmpty()) return;

    QMutexLocker l(&m_mutex);
    if (m_queued.contains(r.id)) {
        // A still-waiting job takes over the latest "always measure" setting
        // (it may have been toggled since the job was queued).
        for (auto *q : { &m_urgentQueue, &m_normalQueue })
            for (Job &j : *q)
                if (j.r.id == r.id) j.r.alwaysMeasure = r.alwaysMeasure;
        if (urgent) {
            // Promote an already-queued normal job (an in-flight one is
            // already being worked on; nothing to do for it).
            for (auto it = m_normalQueue.begin(); it != m_normalQueue.end(); ++it) {
                if (it->r.id == r.id) {
                    Job j = *it;
                    j.urgent = true;
                    m_normalQueue.erase(it);
                    m_urgentQueue.push_back(j);
                    m_cond.wakeOne();
                    break;
                }
            }
        }
        return;
    }
    m_queued.insert(r.id);
    (urgent ? m_urgentQueue : m_normalQueue).push_back({ r, urgent });

    if (!m_thread) {
        m_thread = new Thread(this);
        m_thread->start(QThread::LowPriority);   // never compete with the audio/GUI threads
    }
    m_cond.wakeOne();
}

bool LoudnessAnalyzer::hasUrgentPending()
{
    QMutexLocker l(&m_mutex);
    return !m_urgentQueue.empty();
}

void LoudnessAnalyzer::workerLoop()
{
    if (!m_cacheLoaded) {
        m_cache = VolumeNormalizationCache::load();
        m_cacheLoaded = true;
        qCInfo(lcLoudness, "loaded %lld normalization entries", qint64(m_cache.size()));
    }
    m_lastFlushMs = QDateTime::currentMSecsSinceEpoch();

    while (true) {
        Job job;
        bool have = false;
        bool idleFlush = false;
        {
            QMutexLocker l(&m_mutex);
            while (true) {
                if (m_quit) { l.unlock(); flushCache(); return; }
                if (!m_urgentQueue.empty()) {
                    job = m_urgentQueue.front(); m_urgentQueue.pop_front(); have = true; break;
                }
                if (!m_normalQueue.empty()) {
                    job = m_normalQueue.front(); m_normalQueue.pop_front(); have = true; break;
                }
                if (m_dirty) {
                    // Idle with unsaved results: wait a little for more work,
                    // then flush (debounce).
                    if (!m_cond.wait(&m_mutex, 3000)) { idleFlush = true; break; }
                } else {
                    m_cond.wait(&m_mutex);
                }
            }
        }
        if (!have) {
            if (idleFlush) flushCache();
            continue;
        }

        process(job);

        // Long batches never go idle: also flush every ~20 s of work.
        if (m_dirty && QDateTime::currentMSecsSinceEpoch() - m_lastFlushMs > 20000)
            flushCache();
    }
}

void LoudnessAnalyzer::flushCache()
{
    if (!m_dirty) return;
    if (VolumeNormalizationCache::save(m_cache))
        qCInfo(lcLoudness, "saved %lld normalization entries", qint64(m_cache.size()));
    else
        qWarning("LoudnessAnalyzer: could not write Topaz.volumeNormalization.json");
    m_dirty = false;
    m_lastFlushMs = QDateTime::currentMSecsSinceEpoch();
}

void LoudnessAnalyzer::storeEntry(const Request &r, double gainDb, const QString &source, double peak)
{
    VolumeNormalizationCache::Entry e;
    e.genre = r.genre; e.id = r.id; e.dB = gainDb; e.source = source;
    e.peak = peak; e.fileSize = r.fileSize;
    m_cache.insert(r.id, e);
    m_dirty = true;
}

double LoudnessAnalyzer::limitGain(double gainDb, double peakLinear)
{
    double g = std::clamp(gainDb, kMinGainDb, kMaxGainDb);
    if (peakLinear > 0.0) {
        const double maxByPeak = -20.0 * std::log10(peakLinear);   // peak x gain <= 1.0
        if (g > maxByPeak) g = maxByPeak;
    }
    g = std::clamp(g, kMinGainDb, kMaxGainDb);
    // 0.01 dB: exactly what Topaz.volumeNormalization.json stores, so a value
    // reads back identically (and displays identically) after a restart.
    return std::round(g * 100.0) / 100.0;
}

void LoudnessAnalyzer::process(const Job &job)
{
    Request r = job.r;
    // The caller leaves fileSize 0 so a big playlist load does no file I/O on
    // the GUI thread; the size is what makes a stored entry "still this file".
    if (r.fileSize <= 0) r.fileSize = QFileInfo(r.filePath).size();
    QElapsedTimer timer;
    timer.start();

    const ReferenceResult result = determineReferenceGain(r.filePath, r.id, r.fileSize, m_cache,
        [&]() {
            if (m_quit) return false;
            // A normal job yields to an urgent one that arrived meanwhile
            // (its progress is discarded; it goes back to the queue).
            if (!job.urgent && hasUrgentPending()) return false;
            return true;
        }, r.alwaysMeasure);

    if (result.aborted) {
        // fall through: neither stored nor emitted, requeued below.
    } else if (result.ok) {
        storeEntry(r, result.gainDb, result.source, result.peak);
        qCInfo(lcLoudness, "%s: %s %.2f dB (%.0f ms)", qPrintable(r.filePath),
               qPrintable(result.source), result.gainDb, double(timer.elapsed()));
        emit loudnessReady(r.filePath, result.gainDb);
    } else {
        qCInfo(lcLoudness, "%s: no usable reference", qPrintable(r.filePath));
    }

    QMutexLocker l(&m_mutex);
    if (result.aborted && !m_quit) {
        m_normalQueue.push_front(job);   // still in m_queued
    } else {
        m_queued.remove(r.id);
    }
}

LoudnessAnalyzer::ReferenceResult LoudnessAnalyzer::determineReferenceGain(
    const QString &filePath, const QUuid &id, qint64 fileSize,
    const QHash<QUuid, VolumeNormalizationCache::Entry> &cache,
    const ContinueFn &shouldContinue, bool alwaysMeasure)
{
    ReferenceResult result;

    // 1. Cached value -- valid only for the same file (size). With
    // alwaysMeasure, a value that came from a tag is ignored too, so it gets
    // re-measured (and overwritten as "measured") without deleting the JSON.
    const auto it = cache.constFind(id);
    if (it != cache.constEnd() && it->fileSize == fileSize
        && !(alwaysMeasure && it->source == QStringLiteral("tag"))) {
        result.ok     = true;
        result.gainDb = it->dB;
        result.peak   = it->peak;
        result.source = QStringLiteral("cache");
        return result;
    }

    // 2. ReplayGain / R128 tag -- skipped entirely with alwaysMeasure.
    const TagReader::ReplayGain rg = alwaysMeasure ? TagReader::ReplayGain{}
                                                   : TagReader::readReplayGain(filePath);
    if (rg.valid) {
        result.ok     = true;
        result.gainDb = limitGain(rg.trackGainDb, rg.trackPeak);
        result.peak   = rg.trackPeak;
        result.source = QStringLiteral("tag");
        return result;
    }

    // 3. Own measurement.
    bool aborted = false;
    const MeasureResult m = measureFile(filePath,
        [&](const LoudnessMeter &, double) {
            if (shouldContinue && !shouldContinue()) { aborted = true; return false; }
            return true;
        });
    if (aborted) { result.aborted = true; return result; }
    if (m.aborted || !m.ok) return result;   // ok == false: no usable measurement

    result.ok     = true;
    result.gainDb = limitGain(kTargetLufs - m.lufs, m.peak);
    result.peak   = m.peak;
    result.source = QStringLiteral("measured");
    return result;
}

// ── One BASS decode pass ──────────────────────────────────────────────────

LoudnessAnalyzer::MeasureResult
LoudnessAnalyzer::measureFile(const QString &path, const ProgressFn &progress)
{
    MeasureResult res;
    auto &bass = BassLibrary::instance();
    if (!bass.isLoaded()) return res;

    // DECODE stream: nothing is played and no output device is involved; the
    // file is only read. Float samples so the K-weighting sees full precision.
#if defined(_WIN32)
    const std::wstring wpath = path.toStdWString();
    const BASS_HANDLE h = bass.BASS_StreamCreateFile(0, wpath.c_str(), 0, 0,
        BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT | BASS_UNICODE);
#else
    const QByteArray upath = QFile::encodeName(path);
    const BASS_HANDLE h = bass.BASS_StreamCreateFile(0, upath.constData(), 0, 0,
        BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT);
#endif
    if (!h) return res;

    BASS_CHANNELINFO info{};
    if (!bass.BASS_ChannelGetInfo(h, &info)
        || info.freq < 8000 || info.freq > 192000 || info.chans < 1 || info.chans > 8) {
        bass.BASS_StreamFree(h);
        return res;
    }
    const int chans = int(info.chans);
    const int rate  = int(info.freq);

    LoudnessMeter meter(rate, chans);
    constexpr int kChunkBytes = 65536;
    std::vector<float> buf(kChunkBytes / sizeof(float));
    const int chunkFrames = int(buf.size()) / chans;

    while (true) {
        // Whole frames only: ask for exactly chunkFrames x chans floats.
        const BASS_DWORD want = BASS_DWORD(chunkFrames) * BASS_DWORD(chans) * BASS_DWORD(sizeof(float));
        const quint32 got = quint32(bass.BASS_ChannelGetData(h, buf.data(), want | BASS_DATA_FLOAT));
        // (DWORD)-1 = error / ended; compared as 32 bit since BASS_DWORD is
        // 64 bit on Linux and only the low half is meaningful.
        if (got == 0xFFFFFFFFu || got == 0) break;
        const int frames = int(got / (sizeof(float) * size_t(chans)));
        if (frames <= 0) break;
        meter.process(buf.data(), frames);
        const double seconds = double(meter.framesProcessed()) / double(rate);
        if (progress && !progress(meter, seconds)) { res.aborted = true; break; }
    }
    bass.BASS_StreamFree(h);

    res.seconds = double(meter.framesProcessed()) / double(rate);
    res.peak = meter.samplePeak();
    if (!res.aborted) res.ok = meter.integratedLufs(&res.lufs);
    return res;
}
