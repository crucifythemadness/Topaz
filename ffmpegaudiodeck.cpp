#include "ffmpegaudiodeck.h"

#include <QUrl>

FfmpegAudioDeck::FfmpegAudioDeck(QObject *parent)
    : AudioDeck(parent)
{
    m_player      = new QMediaPlayer(this);
    m_audioOutput = new QAudioOutput(this);
    m_player->setAudioOutput(m_audioOutput);
    m_audioOutput->setVolume(1.0f);

    // Decoded-buffer tap for the audio visualizer (UC-19) -- independent of
    // setAudioOutput() above, doesn't affect normal playback.
    m_audioBufferOutput = new QAudioBufferOutput(this);
    m_player->setAudioBufferOutput(m_audioBufferOutput);
    connect(m_audioBufferOutput, &QAudioBufferOutput::audioBufferReceived,
            this, &AudioDeck::audioBufferReceived);

    connect(m_player, &QMediaPlayer::positionChanged,
            this, [this](qint64) { emit positionChanged(); });
    connect(m_player, &QMediaPlayer::durationChanged,
            this, [this](qint64) { emit durationChanged(); });
    connect(m_player, &QMediaPlayer::playbackStateChanged,
            this, [this](QMediaPlayer::PlaybackState state) {
                emit playingChanged(state == QMediaPlayer::PlayingState);
            });
    connect(m_player, &QMediaPlayer::mediaStatusChanged,
            this, [this](QMediaPlayer::MediaStatus status) {
                if (status == QMediaPlayer::EndOfMedia)
                    emit endOfMedia();
            });
}

void FfmpegAudioDeck::setSource(const QString &filePath)
{
    m_player->setSource(QUrl::fromLocalFile(filePath));
}

void FfmpegAudioDeck::play()  { m_player->play();  }
void FfmpegAudioDeck::pause() { m_player->pause(); }
void FfmpegAudioDeck::stop()  { m_player->stop();  }

qint64 FfmpegAudioDeck::position() const { return m_player->position(); }
void   FfmpegAudioDeck::setPosition(qint64 ms) { m_player->setPosition(ms); }
qint64 FfmpegAudioDeck::duration() const { return m_player->duration(); }
bool   FfmpegAudioDeck::isPlaying() const
{
    return m_player->playbackState() == QMediaPlayer::PlayingState;
}

void FfmpegAudioDeck::setVolume(float volume) { m_audioOutput->setVolume(volume); }
