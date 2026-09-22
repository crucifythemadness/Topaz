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
    // "Consistent Background Music" compressor (BASS_FX Compressor 2). Tuned
    // for leveling, not for transparency: everything above -20 dBFS is
    // squeezed 4:1, and +6 dB make-up brings the quieter passages up. Worst
    // case a 0 dBFS peak comes out at -20 + 20/4 + 6 = -9 dBFS, so the
    // make-up can't clip *by default* -- the user's own "Trim" slider
    // (Setup > PLAYBACK, UC-35) is added on top of this make-up gain and can
    // push it into clipping on purpose, same as the Audiophile strategy's
    // Trim. Public (not local to the .cpp) because CompressorMeter
    // (compressormeter.h) -- the live NowPlaying estimate for this strategy,
    // since BASS_FX itself exposes no gain-reduction read-back -- must use
    // these exact same numbers, never a separately-tuned copy.
    static constexpr float kCompThresholdDb = -20.0f;
    static constexpr float kCompRatio       = 4.0f;
    static constexpr float kCompAttackMs    = 5.0f;
    static constexpr float kCompReleaseMs   = 250.0f;
    static constexpr float kCompMakeupDb    = 6.0f;

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

    // Auto Loudness Correction (UC-35), see AudioDeck. The stream's
    // BASS_ATTRIB_VOL is always m_fadeVolume x gain, so the crossfade ramp
    // and the loudness gain never overwrite each other; with a 0 dB gain the
    // attribute is exactly what setVolume() was given, as before the feature.
    void setLoudnessGainDb(float db, bool smooth) override;
    void setCompressorEnabled(bool on) override;
    void setCompressorTrimDb(float db, bool smooth) override;

private:
    // Writes m_fadeVolume x linear(m_gainDbCurrent) to BASS_ATTRIB_VOL.
    void applyVolume();
    // Shared tick for both ramps below (loudness gain, compressor trim) --
    // each advances independently; the timer keeps running while either is
    // still short of its target and stops once both have arrived.
    void onGainRampTick();
    // Adds/removes the BASS_FX compressor on the current stream to match
    // m_compressorWanted (no-op without a stream; failures are logged only).
    // Also (re-)applies m_compTrimDbCurrent -- called both when the effect is
    // (re-)added and when just the trim changes while it's already active.
    void applyCompressor();

    static void BASSCALL syncEndProc(BASS_HANDLE handle, BASS_DWORD channel, BASS_DWORD data, void *user);
    void handleStreamEnded();
    void pollPosition();
    // ~25ms tap: pulls PCM via BASS_ChannelGetData() and emits
    // audioBufferReceived() -- see class doc comment point 3.
    void pollAudioBuffer();

    BASS_HANDLE m_stream            = 0;
    qint64      m_lastKnownDuration = 0;
    QTimer     *m_pollTimer;

    // Loudness correction / compressor state (see setLoudnessGainDb()).
    float       m_fadeVolume      = 1.0f;   // last setVolume() (crossfade level)
    double      m_gainDbTarget    = 0.0;
    double      m_gainDbCurrent   = 0.0;
    double      m_gainDbStep      = 0.0;    // per ramp tick
    QTimer     *m_gainRampTimer   = nullptr;
    bool        m_compressorWanted = false;
    BASS_HANDLE m_compressorFx    = 0;      // HFX on m_stream, 0 = none
    // Manual "Trim" on top of the compressor's make-up gain (UC-35) -- a
    // deck-level setting (NOT reset by setSource(), unlike m_gainDb*).
    double      m_compTrimDbTarget  = 0.0;
    double      m_compTrimDbCurrent = 0.0;
    double      m_compTrimDbStep    = 0.0;

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
