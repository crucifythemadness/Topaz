#pragma once

#include "audiodeck.h"

#include <QAudioBuffer>
#include <QAudioBufferOutput>
#include <QAudioOutput>
#include <QMediaPlayer>

// ── FfmpegAudioDeck ───────────────────────────────────────────────────────
// Wraps one QMediaPlayer + QAudioOutput pair -- functionally identical to
// PlaybackEngine's pre-abstraction behavior (see UC-15 "Step 2a": this class
// is a mechanical extraction, not a rewrite). Also owns the
// QAudioBufferOutput tap for the Audio Visualizer (UC-19)/Milkdrop (UC-20),
// re-emitted through the inherited AudioDeck::audioBufferReceived signal --
// see AudioDeck's own doc comment ("Step 3").
class FfmpegAudioDeck : public AudioDeck
{
    Q_OBJECT

public:
    explicit FfmpegAudioDeck(QObject *parent = nullptr);

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
    QMediaPlayer       *m_player;
    QAudioOutput       *m_audioOutput;
    QAudioBufferOutput *m_audioBufferOutput;
};
