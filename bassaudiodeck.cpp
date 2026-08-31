#include "bassaudiodeck.h"

#include <QAudioFormat>
#include <QMetaObject>
#include <QTimer>

#include <string>

namespace {
// Much tighter than m_pollTimer's 100ms -- 1024 samples at 44.1kHz is
// ~23ms, so a visualizer-quality tap needs roughly this cadence. See class
// doc comment point 3.
constexpr int kBufferTapIntervalMs = 25;
}

BassAudioDeck::BassAudioDeck(QObject *parent)
    : AudioDeck(parent)
{
    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(100);
    connect(m_pollTimer, &QTimer::timeout, this, &BassAudioDeck::pollPosition);

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
        bass.BASS_StreamFree(m_stream);
        m_stream = 0;
    }

    // BASS_UNICODE tells BASS the filename is UTF-16 (WCHAR*) rather than ANSI.
    const std::wstring wpath = filePath.toStdWString();
    m_stream = bass.BASS_StreamCreateFile(0, wpath.c_str(), 0, 0, BASS_UNICODE);
    if (!m_stream) {
        m_lastKnownDuration = 0;
        emit durationChanged();
        return;
    }

    // See class doc comment for why this callback can't touch Qt state directly.
    bass.BASS_ChannelSetSync(m_stream, BASS_SYNC_END, 0, &BassAudioDeck::syncEndProc, this);

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
    if (!m_stream) return;
    BassLibrary::instance().BASS_ChannelSetAttribute(m_stream, BASS_ATTRIB_VOL, volume);
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
