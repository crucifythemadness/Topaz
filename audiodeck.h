#pragma once

#include <QAudioBuffer>
#include <QObject>

// Instantaneous output levels of one deck for the Audio Meter (UC-37),
// linear amplitude, 1.0 = 0 dBFS (can exceed 1.0 with float processing).
struct DeckLevels {
    float peakL = 0.0f, peakR = 0.0f;
    float rmsL  = 0.0f, rmsR  = 0.0f;
};

// ── AudioDeck ─────────────────────────────────────────────────────────────
// Abstract playback backend for one deck of PlaybackEngine's dual-deck
// design. PlaybackEngine's crossfade orchestration (timer-driven fade,
// eligibility checks, deck-index bookkeeping in startCrossfade()/
// onFadeTick()/cancelCrossfade()) is entirely backend-agnostic and talks
// only through this interface -- see FfmpegAudioDeck (today's
// QMediaPlayer/QAudioOutput behavior, unchanged) and BassAudioDeck. See
// UC-15 in the architecture doc, "Step 2".
//
// Both concrete decks provide decoded PCM via audioBufferReceived() for the
// Audio Visualizer (UC-19) and Milkdrop (UC-20), which both subscribe to
// PlaybackEngine::audioBufferAvailable -- see "Step 3" in the architecture
// doc. FfmpegAudioDeck sources it from QAudioBufferOutput; BassAudioDeck
// polls BASS_ChannelGetData() on a timer, since BASS has no push-based
// buffer notification.
class AudioDeck : public QObject
{
    Q_OBJECT

public:
    explicit AudioDeck(QObject *parent = nullptr) : QObject(parent) {}
    ~AudioDeck() override = default;

    virtual void setSource(const QString &filePath) = 0;
    virtual void play()  = 0;
    virtual void pause() = 0;
    virtual void stop()  = 0;

    virtual qint64 position() const = 0;
    virtual void   setPosition(qint64 ms) = 0;
    virtual qint64 duration() const = 0;
    virtual bool   isPlaying() const = 0;

    // Linear 0.0-1.0, same scale QAudioOutput::setVolume() already used --
    // PlaybackEngine::onFadeTick()'s crossfade ramp math is unchanged
    // regardless of which backend is behind this call.
    virtual void setVolume(float volume) = 0;

    // Auto Loudness Correction (UC-35) -- BASS only. Both default to "do
    // nothing", so FfmpegAudioDeck (and any deck when the feature is off)
    // behaves exactly as before.
    //
    // A static loudness correction in dB (negative = quieter) applied ON TOP of
    // whatever setVolume() last set: the deck multiplies the two, so the
    // crossfade ramp in PlaybackEngine::onFadeTick() stays untouched. smooth
    // ramps to the new value over ~1.2 s instead of jumping (a correction
    // that arrives while the track is already audible). Reset to 0 dB by
    // setSource().
    virtual void setLoudnessGainDb(float db, bool smooth) { Q_UNUSED(db) Q_UNUSED(smooth) }
    // "Consistent Background Music": a compressor on the deck's stream that
    // evens out the volume as it plays. Survives setSource().
    virtual void setCompressorEnabled(bool on) { Q_UNUSED(on) }
    // Manual "Trim" on top of the compressor's own make-up gain (Setup >
    // PLAYBACK, UC-35) -- a deck-level setting, unlike setLoudnessGainDb()'s
    // per-track one, so (unlike that one) it survives setSource(). smooth
    // ramps it like setLoudnessGainDb() does.
    virtual void setCompressorTrimDb(float db, bool smooth) { Q_UNUSED(db) Q_UNUSED(smooth) }

    // Audio Meter (UC-37): the deck's current output levels straight from the
    // backend, if it can measure them itself. Default: false = "can't", and
    // AudioMeterController then analyses the PCM tap instead (the FFmpeg
    // path). BassAudioDeck answers via BASS_ChannelGetLevelEx() while playing.
    virtual bool readLevels(DeckLevels &out) const { Q_UNUSED(out) return false; }

    // Audio Visualizer (UC-19), optional "BASS" spectrum source: a 1024-point
    // FFT of what the deck is playing right now -- kSpectrumBins magnitudes
    // into mags, the stream's sample rate, and the deck's crossfade level
    // (0..1, pre loudness gain) as weight. Default: false = "can't" (FFmpeg);
    // AudioVisualizerController then uses its own KissFFT analysis.
    static constexpr int kSpectrumBins = 512;
    virtual bool readSpectrum(float *mags, int &sampleRate, float &weight) const
    { Q_UNUSED(mags) Q_UNUSED(sampleRate) Q_UNUSED(weight) return false; }

    // Audio Visualizer SCOPE style with the BASS source: the newest n mono
    // samples of what the deck is playing right now (-1..1) plus its crossfade
    // level as weight. Default: false (FFmpeg -- the controller then uses its
    // own ring buffer from the PCM tap).
    virtual bool readWaveform(float *mono, int n, float &weight) const
    { Q_UNUSED(mono) Q_UNUSED(n) Q_UNUSED(weight) return false; }

signals:
    // Fired whenever position advances during playback (poll-driven for
    // BassAudioDeck, native for FfmpegAudioDeck) -- drives both
    // PlaybackEngine::positionChanged() and the natural-crossfade proximity
    // check in onDeckPositionChanged().
    void positionChanged();
    void durationChanged();
    // Simplified from QMediaPlayer::PlaybackState -- PlaybackEngine never
    // needed the Paused/Stopped distinction, only "is it playing right now."
    void playingChanged(bool playing);
    // Fired once when the track reaches its natural end -- equivalent of
    // QMediaPlayer::mediaStatusChanged(EndOfMedia), the only MediaStatus
    // value PlaybackEngine ever actually checked.
    void endOfMedia();
    // Decoded PCM for the Audio Visualizer (UC-19) / Milkdrop (UC-20) -- see
    // class doc comment above. PlaybackEngine::createDecksIfNeeded() connects
    // this uniformly for every deck and only forwards it into
    // PlaybackEngine::audioBufferAvailable while the deck is the active one.
    void audioBufferReceived(const QAudioBuffer &buffer);
};
