#pragma once

#include "volumenormalizationcache.h"

#include <QHash>
#include <QMutex>
#include <QObject>
#include <QSet>
#include <QString>
#include <QUuid>
#include <QWaitCondition>

#include <atomic>
#include <deque>
#include <functional>
#include <vector>

// ── LoudnessMeter ─────────────────────────────────────────────────────────
// Integrated loudness per ITU-R BS.1770-4 / EBU R128 (the method behind
// ReplayGain 2.0): K-weighting (a high-shelf + a high-pass filter), mean square
// over 400 ms blocks with 75 % overlap, an absolute gate at -70 LUFS and a
// relative gate 10 LU below the ungated result. Pure C++ (no BASS, no Qt
// state), so it can be checked against the EBU test signals on its own.
// Multi-channel layouts follow BASS's order (L R C LFE Ls Rs ...): the LFE is
// excluded and the surrounds weigh +1.5 dB; a mono file counts as dual mono
// (what actually comes out of two speakers).
class LoudnessMeter
{
public:
    LoudnessMeter(int sampleRate, int channels);

    // Interleaved float samples, `frames` frames.
    void process(const float *interleaved, int frames);

    // Gated integrated loudness of everything processed so far. False when no
    // block passed the gates yet (silence, or less than one 400 ms block).
    bool integratedLufs(double *lufs) const;

    double samplePeak() const { return m_peak; }          // linear, unfiltered
    qint64 framesProcessed() const { return m_frames; }
    int    sampleRate() const { return m_rate; }

private:
    struct Biquad { double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0; };
    struct State  { double z1 = 0, z2 = 0; };

    static double run(const Biquad &f, State &s, double x)
    {
        const double y = f.b0 * x + s.z1;           // transposed direct form II
        s.z1 = f.b1 * x - f.a1 * y + s.z2;
        s.z2 = f.b2 * x - f.a2 * y;
        return y;
    }

    int    m_rate;
    int    m_chans;
    Biquad m_shelf, m_highpass;
    std::vector<State>  m_shelfState, m_hpState;
    std::vector<double> m_weight;

    int     m_subLen;                // samples per 100 ms sub-block
    int     m_subFill = 0;
    double  m_subEnergy = 0.0;       // weighted sum of squares of the open sub-block
    double  m_recent[4] = {0, 0, 0, 0};
    int     m_recentCount = 0;
    std::vector<double> m_blocks;    // mean square of each 400 ms block

    double m_peak = 0.0;
    qint64 m_frames = 0;
};

// ── LoudnessAnalyzer ──────────────────────────────────────────────────────
// Background service behind "Auto Loudness Correction" (Setup > PLAYBACK, UC-35).
// Owns ONE low-priority worker thread; the GUI thread only ever calls
// request() (non-blocking) and receives loudnessReady() (queued). For each
// requested track the worker determines the static gain in this order:
//   1. Topaz.volumeNormalization.json (valid only while the file size matches)
//   2. a ReplayGain / R128 tag in the file (TagReader::readReplayGain)
//   3. an own measurement: one BASS *decode* pass over the file, K-weighted
//      gated loudness, gain = -18 LUFS - loudness.
// A new result is stored in the JSON (in memory, flushed debounced) and then
// used. The gain is clamped to [-20, +10] dB and limited so the known peak
// never clips. Audio files are only ever read.
// Urgent requests (the playing / next track) go first. Measured on real
// libraries a decode pass runs at 600-1200x real time, i.e. a whole 5 minute
// track is done in 0.2-0.45 s, so even a track that starts before its
// analysis finished is corrected (with one smooth ramp) within half a second;
// an early "first 30 s" estimate was tried and dropped: it can be several dB
// off for tracks with a quiet intro and would only add a second correction.
//
// Created lazily by PlaybackEngine, only when the running engine is BASS and
// Auto Loudness Correction is on; a disabled feature never starts a thread or
// touches the JSON. BassLibrary::load() must have succeeded.
class LoudnessAnalyzer : public QObject
{
    Q_OBJECT

public:
    struct Request {
        QString filePath;
        QUuid   id;          // TrackInfo::computeNormalizationId()
        QString genre;       // stored for readability only
        qint64  fileSize = 0;
    };

    // ReplayGain 2.0 reference level.
    static constexpr double kTargetLufs   = -18.0;
    static constexpr double kMinGainDb    = -20.0;
    static constexpr double kMaxGainDb    = 10.0;

    explicit LoudnessAnalyzer(QObject *parent = nullptr);
    ~LoudnessAnalyzer() override;

    // Queues a track (deduplicated by id; an urgent request promotes an
    // already-queued normal one). Non-blocking, GUI thread only.
    void request(const Request &r, bool urgent);

    // Applies the clamp and the no-clipping limit to a raw gain.
    static double limitGain(double gainDb, double peakLinear);

    struct MeasureResult {
        bool   ok      = false;
        double lufs    = 0.0;
        double peak    = 0.0;   // linear
        double seconds = 0.0;   // audio measured
        bool   aborted = false;
    };
    // Called after each decoded chunk with the meter so far and the audio
    // seconds measured; return false to stop.
    using ProgressFn = std::function<bool(const LoudnessMeter &meter, double audioSeconds)>;
    // One BASS decode pass over `path` (BassLibrary must be loaded). Runs on
    // the calling thread; the worker uses it, and so do the tests.
    static MeasureResult measureFile(const QString &path, const ProgressFn &progress = {});

signals:
    // Emitted from the worker thread (queued to receivers on the GUI thread).
    // gainDb is final: clamped and peak-limited, dB to add.
    void loudnessReady(const QString &filePath, double gainDb);

private:
    class Thread;
    struct Job { Request r; bool urgent = false; };

    void workerLoop();
    void process(const Job &job);
    bool hasUrgentPending();
    void storeEntry(const Request &r, double gainDb, const QString &source, double peak);
    void flushCache();

    QMutex m_mutex;
    QWaitCondition m_cond;
    std::deque<Job> m_urgentQueue;
    std::deque<Job> m_normalQueue;
    QSet<QUuid> m_queued;              // ids queued or in flight
    std::atomic<bool> m_quit{false};
    Thread *m_thread = nullptr;

    // Worker thread only:
    QHash<QUuid, VolumeNormalizationCache::Entry> m_cache;
    bool   m_cacheLoaded = false;
    bool   m_dirty = false;
    qint64 m_lastFlushMs = 0;
};
