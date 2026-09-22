#include "bassaudiodeck.h"

#include "loudnesslog.h"

#include <QAudioFormat>
#include <QFile>
#include <QMetaObject>
#include <QTimer>

#include <cmath>
#include <string>

namespace {
// Much tighter than m_pollTimer's 100ms -- 1024 samples at 44.1kHz is
// ~23ms, so a visualizer-quality tap needs roughly this cadence. See class
// doc comment point 3.
constexpr int kBufferTapIntervalMs = 25;

// Smooth loudness-gain change (UC-35): linear in dB over ~1.2 s.
constexpr int kGainRampTickMs = 30;
constexpr int kGainRampTotalMs = 1200;

}

BassAudioDeck::BassAudioDeck(QObject *parent)
    : AudioDeck(parent)
{
    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(100);
    connect(m_pollTimer, &QTimer::timeout, this, &BassAudioDeck::pollPosition);

    m_gainRampTimer = new QTimer(this);
    m_gainRampTimer->setInterval(kGainRampTickMs);
    connect(m_gainRampTimer, &QTimer::timeout, this, &BassAudioDeck::onGainRampTick);

    m_bufferTapTimer = new QTimer(this);
    m_bufferTapTimer->setInterval(kBufferTapIntervalMs);
    connect(m_bufferTapTimer, &QTimer::timeout, this, &BassAudioDeck::pollAudioBuffer);
}

BassAudioDeck::~BassAudioDeck()
{
    if (m_stream)
        BassLibrary::instance().BASS_StreamFree(m_stream);
}

void BassAudioDeck::setSource(const QString &filePath)
{
    auto &bass = BassLibrary::instance();

    m_pollTimer->stop();
    m_bufferTapTimer->stop();
    m_streamFreq  = 0;
    m_streamChans = 0;
    if (m_stream) {
        bass.BASS_StreamFree(m_stream);   // also frees any effect attached to it
        m_stream = 0;
    }
    m_compressorFx = 0;

    // A new stream starts at BASS's default volume (1.0) with no loudness
    // correction, exactly as before the feature existed; PlaybackEngine sets
    // the track's gain (and a crossfade's volume) right after this call. The
    // compressor Trim (m_compTrimDb*) is NOT reset here -- it is a deck-level
    // setting, not a per-track one, so a ramp in progress for it survives a
    // track change; the shared timer is only stopped if that ramp has already
    // finished (it is unconditionally restarted below via applyCompressor()
    // if the compressor is wanted, which needs no ramp of its own here).
    m_fadeVolume    = 1.0f;
    m_gainDbTarget  = 0.0;
    m_gainDbCurrent = 0.0;
    if (m_compTrimDbCurrent == m_compTrimDbTarget) m_gainRampTimer->stop();

#if defined(_WIN32)
    // BASS_UNICODE tells BASS the filename is UTF-16 (WCHAR*) rather than ANSI.
    const std::wstring wpath = filePath.toStdWString();
    m_stream = bass.BASS_StreamCreateFile(0, wpath.c_str(), 0, 0, BASS_UNICODE);
#else
    // Non-Windows BASS takes plain UTF-8 filenames, no BASS_UNICODE
    // equivalent -- see basslibrary.cpp's plugin-loading code for the same pattern.
    const QByteArray upath = QFile::encodeName(filePath);
    m_stream = bass.BASS_StreamCreateFile(0, upath.constData(), 0, 0, 0);
#endif
    if (!m_stream) {
        m_lastKnownDuration = 0;
        emit durationChanged();
        return;
    }

    // See class doc comment for why this callback can't touch Qt state directly.
    bass.BASS_ChannelSetSync(m_stream, BASS_SYNC_END, 0, &BassAudioDeck::syncEndProc, this);

    if (m_compressorWanted) applyCompressor();

    const BASS_QWORD lenBytes = bass.BASS_ChannelGetLength(m_stream, BASS_POS_BYTE);
    m_lastKnownDuration = static_cast<qint64>(bass.BASS_ChannelBytes2Seconds(m_stream, lenBytes) * 1000.0);
    emit durationChanged();
    emit positionChanged();

    // Cache freq/chans once for the buffer tap -- static for a stream's
    // lifetime (see class doc comment point 3). Sanity-checked since there's
    // no local bass.h to verify BASS_CHANNELINFO's layout against; a
    // failure here just leaves the tap silent (pollAudioBuffer() no-ops),
    // not a crash.
    BASS_CHANNELINFO info{};
    if (bass.BASS_ChannelGetInfo(m_stream, &info)
        && info.freq >= 8000 && info.freq <= 192000
        && info.chans >= 1 && info.chans <= 8) {
        m_streamFreq  = info.freq;
        m_streamChans = info.chans;
        // Sized to comfortably cover one tap tick's worth of audio at this
        // rate, with margin -- minor overlap between consecutive reads is
        // expected/harmless for this kind of visualization tap.
        const int bytesPerFrame = static_cast<int>(m_streamChans) * static_cast<int>(sizeof(float));
        const int frames = static_cast<int>(m_streamFreq) * kBufferTapIntervalMs * 3 / 1000;
        m_tapScratch.resize(frames * bytesPerFrame);
    } else {
        m_tapScratch.clear();
    }
}

void BassAudioDeck::play()
{
    if (!m_stream) return;
    BassLibrary::instance().BASS_ChannelPlay(m_stream, 0);
    m_pollTimer->start();
    if (m_streamFreq && m_streamChans) m_bufferTapTimer->start();
    emit playingChanged(true);
}

void BassAudioDeck::pause()
{
    if (!m_stream) return;
    BassLibrary::instance().BASS_ChannelPause(m_stream);
    m_pollTimer->stop();
    m_bufferTapTimer->stop();
    emit playingChanged(false);
}

void BassAudioDeck::stop()
{
    if (!m_stream) return;
    BassLibrary::instance().BASS_ChannelStop(m_stream);
    m_pollTimer->stop();
    m_bufferTapTimer->stop();
    emit playingChanged(false);
}

qint64 BassAudioDeck::position() const
{
    if (!m_stream) return 0;
    auto &bass = BassLibrary::instance();
    const BASS_QWORD posBytes = bass.BASS_ChannelGetPosition(m_stream, BASS_POS_BYTE);
    return static_cast<qint64>(bass.BASS_ChannelBytes2Seconds(m_stream, posBytes) * 1000.0);
}

void BassAudioDeck::setPosition(qint64 ms)
{
    if (!m_stream) return;
    auto &bass = BassLibrary::instance();
    const BASS_QWORD posBytes = bass.BASS_ChannelSeconds2Bytes(m_stream, static_cast<double>(ms) / 1000.0);
    bass.BASS_ChannelSetPosition(m_stream, posBytes, BASS_POS_BYTE);
    emit positionChanged();
}

qint64 BassAudioDeck::duration() const { return m_lastKnownDuration; }

bool BassAudioDeck::isPlaying() const
{
    if (!m_stream) return false;
    return BassLibrary::instance().BASS_ChannelIsActive(m_stream) == BASS_ACTIVE_PLAYING;
}

void BassAudioDeck::setVolume(float volume)
{
    m_fadeVolume = volume;
    applyVolume();
}

void BassAudioDeck::applyVolume()
{
    if (!m_stream) return;
    // 0 dB is exactly 1.0 (no pow() rounding), so with the feature off the
    // attribute is bit-identical to what setVolume() was given.
    const float gain = (m_gainDbCurrent == 0.0)
        ? 1.0f : float(std::pow(10.0, m_gainDbCurrent / 20.0));
    BassLibrary::instance().BASS_ChannelSetAttribute(m_stream, BASS_ATTRIB_VOL, m_fadeVolume * gain);
}

void BassAudioDeck::setLoudnessGainDb(float db, bool smooth)
{
    m_gainDbTarget = double(db);
    if (!smooth || !m_stream || m_gainDbTarget == m_gainDbCurrent) {
        m_gainDbCurrent = m_gainDbTarget;
        applyVolume();
        qCInfo(lcLoudness, "deck gain %.2f dB set", m_gainDbCurrent);
        // Shared ramp timer: only stop it if the compressor Trim ramp isn't
        // also using it right now (see onGainRampTick()).
        if (m_compTrimDbCurrent == m_compTrimDbTarget) m_gainRampTimer->stop();
        return;
    }
    m_gainDbStep = (m_gainDbTarget - m_gainDbCurrent) / double(kGainRampTotalMs / kGainRampTickMs);
    m_gainRampTimer->start();
    qCInfo(lcLoudness, "deck gain ramping %.2f -> %.2f dB", m_gainDbCurrent, m_gainDbTarget);
}

void BassAudioDeck::setCompressorTrimDb(float db, bool smooth)
{
    m_compTrimDbTarget = double(db);
    if (!smooth || m_compTrimDbTarget == m_compTrimDbCurrent) {
        m_compTrimDbCurrent = m_compTrimDbTarget;
        applyCompressor();
        qCInfo(lcLoudness, "compressor trim %.2f dB set", m_compTrimDbCurrent);
        if (m_gainDbCurrent == m_gainDbTarget) m_gainRampTimer->stop();
        return;
    }
    m_compTrimDbStep = (m_compTrimDbTarget - m_compTrimDbCurrent) / double(kGainRampTotalMs / kGainRampTickMs);
    m_gainRampTimer->start();
    qCInfo(lcLoudness, "compressor trim ramping %.2f -> %.2f dB", m_compTrimDbCurrent, m_compTrimDbTarget);
}

// Drives both ramps below off one shared timer (loudness gain and compressor
// Trim are independent settings -- one per-track, one deck-level -- but both
// are just "linear in dB over ~1.2s", so one timer/tick serves both; it keeps
// running while either is still short of its target).
void BassAudioDeck::onGainRampTick()
{
    bool stillRamping = false;

    if (m_gainDbCurrent != m_gainDbTarget) {
        m_gainDbCurrent += m_gainDbStep;
        const bool reached = (m_gainDbStep > 0.0) ? (m_gainDbCurrent >= m_gainDbTarget)
                                                  : (m_gainDbCurrent <= m_gainDbTarget);
        if (reached) m_gainDbCurrent = m_gainDbTarget; else stillRamping = true;
        applyVolume();
    }
    if (m_compTrimDbCurrent != m_compTrimDbTarget) {
        m_compTrimDbCurrent += m_compTrimDbStep;
        const bool reached = (m_compTrimDbStep > 0.0) ? (m_compTrimDbCurrent >= m_compTrimDbTarget)
                                                       : (m_compTrimDbCurrent <= m_compTrimDbTarget);
        if (reached) m_compTrimDbCurrent = m_compTrimDbTarget; else stillRamping = true;
        applyCompressor();
    }
    if (!stillRamping) m_gainRampTimer->stop();
}

void BassAudioDeck::setCompressorEnabled(bool on)
{
    if (m_compressorWanted == on) return;
    m_compressorWanted = on;
    applyCompressor();
}

void BassAudioDeck::applyCompressor()
{
    if (!m_stream) return;
    auto &bass = BassLibrary::instance();

    if (!m_compressorWanted) {
        if (m_compressorFx) {
            bass.BASS_ChannelRemoveFX(m_stream, m_compressorFx);
            m_compressorFx = 0;
        }
        return;
    }
    if (!m_compressorFx) {
        // Never fatal: without bass_fx (or if BASS refuses the effect)
        // playback simply carries on uncompressed.
        if (!bass.loadFx()) return;
        m_compressorFx = bass.BASS_ChannelSetFX(m_stream, BASS_FX_BFX_COMPRESSOR2, 0);
        if (!m_compressorFx) {
            qWarning("BassAudioDeck: compressor effect could not be added, BASS error %d",
                     bass.BASS_ErrorGetCode());
            return;
        }
    }
    // Reached whenever the effect is (re-)added AND whenever just the Trim
    // changes while it's already attached (see setCompressorTrimDb()) -- the
    // struct is always sent in full; BASS_FXSetParameters has no "just one
    // field" form.
    BASS_BFX_COMPRESSOR2 p{};
    p.fGain      = kCompMakeupDb + float(m_compTrimDbCurrent);
    p.fThreshold = kCompThresholdDb;
    p.fRatio     = kCompRatio;
    p.fAttack    = kCompAttackMs;
    p.fRelease   = kCompReleaseMs;
    p.lChannel   = BASS_BFX_CHANALL;
    if (!bass.BASS_FXSetParameters(m_compressorFx, &p)) {
        qWarning("BassAudioDeck: compressor parameters rejected, BASS error %d", bass.BASS_ErrorGetCode());
        bass.BASS_ChannelRemoveFX(m_stream, m_compressorFx);
        m_compressorFx = 0;
    }
}

void BassAudioDeck::pollPosition()
{
    emit positionChanged();
}

void BassAudioDeck::pollAudioBuffer()
{
    if (!m_stream || m_streamFreq == 0 || m_streamChans == 0) return;

    auto &bass = BassLibrary::instance();
    const BASS_DWORD requestBytes = static_cast<BASS_DWORD>(m_tapScratch.size());
    const BASS_DWORD got = bass.BASS_ChannelGetData(m_stream, m_tapScratch.data(),
                                                     requestBytes | BASS_DATA_FLOAT);
    // (BASS_DWORD)-1 signals an error (e.g. the channel has already ended --
    // possible in the narrow window before handleStreamEnded()'s queued
    // invokeMethod from syncEndProc() has actually stopped this timer).
    if (got == static_cast<BASS_DWORD>(-1) || got == 0) return;

    // Truncate to a whole number of frames -- BASS can legitimately return
    // less than requested (e.g. right after play(), before its buffer has
    // filled), and a partial trailing frame would misalign the interleaved
    // sample math both consumers (AudioVisualizerController/MilkdropView) do.
    const BASS_DWORD bytesPerFrame = m_streamChans * static_cast<BASS_DWORD>(sizeof(float));
    const BASS_DWORD usableBytes = (got / bytesPerFrame) * bytesPerFrame;
    if (usableBytes == 0) return;

    QAudioFormat format;
    format.setSampleRate(static_cast<int>(m_streamFreq));
    format.setChannelCount(static_cast<int>(m_streamChans));
    format.setSampleFormat(QAudioFormat::Float);

    QAudioBuffer buffer(m_tapScratch.left(static_cast<int>(usableBytes)), format);
    emit audioBufferReceived(buffer);
}

void BASSCALL BassAudioDeck::syncEndProc(BASS_HANDLE /*handle*/, BASS_DWORD /*channel*/,
                                          BASS_DWORD /*data*/, void *user)
{
    // Called on BASS's own internal thread -- must not touch Qt/QObject state
    // here. Marshal to the deck's own thread via a queued invokeMethod;
    // handleStreamEnded() does the real work once there.
    auto *self = static_cast<BassAudioDeck *>(user);
    QMetaObject::invokeMethod(self, &BassAudioDeck::handleStreamEnded, Qt::QueuedConnection);
}

void BassAudioDeck::handleStreamEnded()
{
    m_pollTimer->stop();
    m_bufferTapTimer->stop();
    emit endOfMedia();
}
