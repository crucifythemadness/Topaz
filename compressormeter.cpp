#include "compressormeter.h"

#include "bassaudiodeck.h"

#include <algorithm>
#include <cmath>

void CompressorMeter::process(const float *interleaved, int frames, int channels, int sampleRate)
{
    if (frames <= 0 || channels <= 0 || sampleRate <= 0) return;

    // Peak level detector: the loudest sample across all channels in this
    // chunk. Simple and cheap -- a full RMS/lookahead detector would need
    // more state to replicate BASS_FX's own (unknown/proprietary) detector
    // faithfully, which this estimate never can be anyway (see class doc).
    float peak = 0.0f;
    const int total = frames * channels;
    for (int i = 0; i < total; ++i) {
        const float a = std::fabs(interleaved[i]);
        if (a > peak) peak = a;
    }

    // -120 dBFS floor for near-silence -- std::log10(0) is -inf, which would
    // otherwise make the very first (pre-playback) or a fully silent chunk's
    // level swing wildly negative for no audible reason.
    const double levelDb = peak > 1e-6f ? 20.0 * std::log10(double(peak)) : -120.0;

    const double targetReduction =
        std::max(0.0, (levelDb - double(BassAudioDeck::kCompThresholdDb))
                       * (1.0 - 1.0 / double(BassAudioDeck::kCompRatio)));

    // One-pole smoothing toward the target -- attack while MORE reduction is
    // needed (the signal just got louder), release while LESS is (it just
    // got quieter), matching BASS_DX8_COMPRESSOR's own field semantics.
    const double timeConstantMs = (targetReduction > m_reductionDb)
        ? double(BassAudioDeck::kCompAttackMs) : double(BassAudioDeck::kCompReleaseMs);
    const double chunkSeconds = double(frames) / double(sampleRate);
    const double alpha = 1.0 - std::exp(-chunkSeconds / (timeConstantMs / 1000.0));

    m_reductionDb += (targetReduction - m_reductionDb) * alpha;
}
