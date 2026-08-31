#pragma once

#include <QAudioBuffer>
#include <QObject>

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
