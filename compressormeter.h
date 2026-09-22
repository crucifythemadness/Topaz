#pragma once

// ── CompressorMeter ────────────────────────────────────────────────────────
// A live ESTIMATE of the dB "Consistent Background Music" (UC-35) is
// currently adding/removing, for NowPlaying's badge. BASS_FX's compressor
// exposes no gain-reduction read-back -- only BASS_FXSetParameters/
// BASS_FXGetParameters, the static configuration -- so this is Topaz's own
// parallel calculation, run off the same decoded PCM already tapped for the
// Audio Visualizer/Milkdrop (see UC-19/UC-20), using the exact same
// threshold/ratio/attack/release the real BASS_FX_BFX_COMPRESSOR2 effect is
// configured with (BassAudioDeck::kComp*, see bassaudiodeck.h -- one source
// of truth, so this can never silently drift from what's actually playing).
// It will not be bit-exact to BASS_FX's own internal detector, but tracks it
// closely since it uses the same parameters.
//
// Plain C++, no QObject/Qt threading -- deliberately, like LoudnessMeter
// (loudnessanalyzer.h), so it can be driven and unit-tested with synthetic
// signals in isolation. PlaybackEngine owns one instance and drives it from
// its own audioBufferAvailable signal; see playbackengine.h/.cpp.
//
// Standard feed-forward compressor structure, matching the field semantics
// BASS's own BASS_DX8_COMPRESSOR doc uses ("attack: time for compression to
// reach full strength", "release: speed at which compression stops after
// input drops below threshold"): a static curve computes the TARGET gain
// reduction from the current peak level, then attack/release smooths that
// reduction (not the input level -- the perceptually-correct place for the
// time constants) toward the target.
class CompressorMeter
{
public:
    // Clears the smoothed reduction back to 0 (i.e. currentGainDb() reports
    // plain make-up+trim, same as true silence). Call on every new track and
    // whenever Auto Loudness Correction's settings change, so no stale value
    // leaks across a boundary that wasn't actually heard.
    void reset() { m_reductionDb = 0.0; }

    // Interleaved float32 samples, `frames` frames. Cheap: one peak scan plus
    // one exponential-smoothing step per call: safe to call on every ~25ms
    // buffer tap.
    void process(const float *interleaved, int frames, int channels, int sampleRate);

    // (makeupDb + trimDb) - the current smoothed reduction -- the net dB
    // being added/removed right now, the same concept the Audiophile
    // strategy's static value represents, just continuously updating.
    double currentGainDb(double makeupDb, double trimDb) const
    {
        return makeupDb + trimDb - m_reductionDb;
    }

private:
    double m_reductionDb = 0.0;   // smoothed toward the target each process() call
};
