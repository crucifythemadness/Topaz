#pragma once

#include "audiodeck.h"
#include "basslibrary.h"

#include <QByteArray>

class QTimer;

// ── BassAudioDeck ─────────────────────────────────────────────────────────
// AudioDeck backed by one BASS HSTREAM handle (see UC-15 "Step 2b"). Three
// things make this deck's internals different from FfmpegAudioDeck's, all
// consequences of BASS's plain C callback-based API rather than Qt signals:
//
// 1. BASS has no push-based position/duration notifications -- position()
//    is polled on a QTimer (~100ms) and re-emitted as positionChanged(),
//    which is what drives both the UI progress bar and PlaybackEngine's
//    natural-crossfade proximity check (identical to how FfmpegAudioDeck's
//    native QMediaPlayer::positionChanged already drove the same thing).
// 2. End-of-stream is reported via BASS_ChannelSetSync(..., BASS_SYNC_END,
//    ...), whose callback fires on BASS's OWN internal thread -- touching
//    any QObject/Qt state directly from it would be a cross-thread
//    violation. syncEndProc() only marshals to the deck's own thread via a
//    queued QMetaObject::invokeMethod(); handleStreamEnded() does the actual
//    work once there.
// 3. BASS has no push-based decoded-buffer notification either (see UC-15
//    "Step 3", audioBufferReceived() on AudioDeck) -- a second, much
//    tighter QTimer (~25ms, vs. the ~100ms position poll) pulls PCM via
//    BASS_ChannelGetData() and re-emits it as a QAudioBuffer for the Audio
//    Visualizer (UC-19)/Milkdrop (UC-20). Unlike syncEndProc(), this runs
//    entirely on the deck's own (Qt/GUI) thread -- it's driven by our own
//    QTimer, not a BASS-internal callback -- so no thread marshaling is
//    needed here.
class BassAudioDeck : public AudioDeck
{
    Q_OBJECT

public:
    explicit BassAudioDeck(QObject *parent = nullptr);
    ~BassAudioDeck() override;

    void setSource(const QString &filePath) override;
    void play()  override;
    void pause() override;
    void stop()  override;

    qint64 position() const override;
    void   setPosition(qint64 ms) override;
    qint64 duration() const override;
    bool   isPlaying() const override;

    void setVolume(float volume) override;

private:
    static void BASSCALL syncEndProc(BASS_HANDLE handle, BASS_DWORD channel, BASS_DWORD data, void *user);
    void handleStreamEnded();
    void pollPosition();
    // ~25ms tap: pulls PCM via BASS_ChannelGetData() and emits
    // audioBufferReceived() -- see class doc comment point 3.
    void pollAudioBuffer();

    BASS_HANDLE m_stream            = 0;
    qint64      m_lastKnownDuration = 0;
    QTimer     *m_pollTimer;

    // Cached at setSource() time -- static for a stream's lifetime, same
    // "cache what's static, poll what's dynamic" convention as
    // m_lastKnownDuration above. 0 means "not yet known" / sanity check
    // failed, in which case pollAudioBuffer() emits nothing.
    BASS_DWORD m_streamFreq  = 0;
    BASS_DWORD m_streamChans = 0;
    QTimer    *m_bufferTapTimer;
    // Reused scratch destination for BASS_ChannelGetData() -- sized in
    // setSource() from the cached freq/chans, avoiding a heap allocation on
    // every ~25ms tick.
    QByteArray m_tapScratch;
};
