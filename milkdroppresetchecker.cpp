#include "milkdroppresetchecker.h"

#include <QFile>
#include <QFileInfo>

namespace {

struct UnsupportedFunctionRule
{
    const char *needle; // substring to search for -- a function call, a call
                         // pattern, or (as of the double2/3/4 entries) a bare
                         // type keyword; not always literally "a function call"
    const char *description;
};

// Shader functions a preset's warp/composite code can call that projectM's
// vendored HLSL parser (vendor/hlslparser) doesn't implement -- calling any
// of these is an unconditional hard parse error there ("Undeclared
// identifier", HLSLParser.cpp's GetFunctionOverload()), which fails the
// whole shader and silently drops it (PerPixelMesh::CompileWarpShader()'s
// catch block only logs under a debug-only build flag). Two different
// reasons a function ends up on this list -- both equally fatal, so both
// belong in the same table:
//  - get_fft()/get_fft_hz()/get_bar_height() are MilkDrop3-only additions
//    that were never in projectM at all (confirmed via a full source grep,
//    including the shader-header include listing every built-in a preset's
//    custom shader code can call).
//  - tanh()/sinh()/cosh() are standard HLSL intrinsics real MilkDrop2/3
//    support (via the actual DirectX HLSL compiler) but are simply missing
//    from this vendored parser's intrinsic table (confirmed: sin/cos/exp2/
//    etc. are all there, the three hyperbolic functions aren't). tanh() in
//    particular is a very common Shadertoy-style tonemap idiom
//    ("o = tanh(o / N)") in modern ported presets -- found via "XorDev -
//    MilkDrop2077 - Flutter3.milk", whose entire warp shader (a raymarched
//    fractal, otherwise fully HLSL-parser-compatible) is dropped over this
//    one call, leaving only the near-static default warp + already-
//    invisible overlays.
//  - "mul(cross(" is a different kind of entry: mul() itself IS implemented
//    (projectM registers dozens of scalar/vector/matrix overloads for it),
//    but there is no mul(vector, vector) overload in HLSL at all -- real
//    DirectX would reject this too, it's not a projectM-specific gap. The
//    substring specifically targets mul() called directly on a cross()
//    result, since cross() always returns a vector: a plain "mul(" match
//    would be far too broad (the vast majority of mul() calls in presets
//    are valid vector*matrix/matrix*matrix uses) and would false-positive
//    constantly. Found identically in both "MilkDrop2077 - Lasers from the
//    Sky1.milk" and "...Sky2.milk"'s composite shader
//    (`mul(cross(ts,-t),screen3)`, almost certainly meant to be
//    dot(cross(ts,-t),screen3) -- a scalar depth value, which is what the
//    surrounding division expects), so it's not a one-off typo but at least
//    a shared-template bug across this preset family.
//  - double2/double3/double4 -- projectM's parser has no double-precision
//    support at all (confirmed: no "double" base type anywhere in its type
//    table), unlike real HLSL, which has had double since Shader Model 5.
//    MilkDrop preset shaders never legitimately need double precision, so
//    this is purely an authoring typo (almost certainly meant float2/3/4)
//    rather than a real feature gap. Found via "martin - a milkdrop edit of
//    XorDevs starship MilkDrop2077 rmx007.milk"'s warp shader
//    (`double3 crisp = tex2D(...)`) -- a single-token typo, not a recurring
//    pattern like the entries above, but narrow and safe enough to encode
//    directly (these compound tokens don't collide with ordinary preset
//    text the way bare "double" might).
// See UC-25.
const UnsupportedFunctionRule kUnsupportedFunctions[] = {
    { "get_fft(",        "Uses MilkDrop3-only shader function get_fft(), which is not implemented in projectM." },
    { "get_fft_hz(",     "Uses MilkDrop3-only shader function get_fft_hz(), which is not implemented in projectM." },
    { "get_bar_height(", "Uses MilkDrop3-only shader function get_bar_height(), which is not implemented in projectM." },
    { "tanh(",           "Uses the shader function tanh(), which projectM's HLSL parser does not implement." },
    { "sinh(",           "Uses the shader function sinh(), which projectM's HLSL parser does not implement." },
    { "cosh(",           "Uses the shader function cosh(), which projectM's HLSL parser does not implement." },
    { "mul(cross(",      "Calls mul() directly on a cross() result -- there is no mul(vector, vector) overload in HLSL (likely meant dot())." },
    { "double2",         "Uses the double2 type, which projectM's HLSL parser does not support (likely meant float2)." },
    { "double3",         "Uses the double3 type, which projectM's HLSL parser does not support (likely meant float3)." },
    { "double4",         "Uses the double4 type, which projectM's HLSL parser does not support (likely meant float4)." },
};

// Returns the numeric value of the first "key=..." occurrence that starts a
// line (the .milk format is line-oriented key=value pairs outside shader/
// equation blocks), or defaultValue if the key is absent or unparsable.
// defaultValue should always be chosen on the "don't flag" side for whatever
// rule calls this, since a missing key falling back to Milkdrop's own
// (unknown to us) built-in default must never be misread as "confirmed zero".
double keyValueOrDefault(const QByteArray &content, const QByteArray &key, double defaultValue)
{
    const QByteArray needle = key + "=";
    int searchFrom = 0;
    while (true) {
        const int idx = content.indexOf(needle, searchFrom);
        if (idx < 0) return defaultValue;
        if (idx == 0 || content.at(idx - 1) == '\n') {
            const int valueStart = idx + needle.size();
            int valueEnd = valueStart;
            while (valueEnd < content.size()
                   && content.at(valueEnd) != '\r' && content.at(valueEnd) != '\n')
                ++valueEnd;
            bool ok = false;
            const double value = content.mid(valueStart, valueEnd - valueStart).toDouble(&ok);
            if (ok) return value;
            return defaultValue;
        }
        searchFrom = idx + 1;
    }
}

// True if any custom shape (shapecode_N_enabled=1) or custom waveform
// (wavecode_N_enabled=1) is enabled -- a legitimate, separate content source
// from the built-in warp/composite shader and overlay system, confirmed via
// projectM's CustomShape.cpp/CustomWaveform.cpp key names. A preset relying
// on one of these must never be flagged by the "no visible content" rule
// below even if every other overlay is off.
bool hasEnabledCustomShapeOrWave(const QByteArray &content)
{
    for (int n = 0; n < 4; ++n) {
        if (content.contains("shapecode_" + QByteArray::number(n) + "_enabled=1")
            || content.contains("wavecode_" + QByteArray::number(n) + "_enabled=1"))
            return true;
    }
    return false;
}

// Concatenates just the warp_N/comp_N line values (mirroring projectM's own
// PresetFileParser::GetCode()'s numbered-key extraction) -- deliberately
// excludes per_frame_*/per_pixel_* equation code, which legitimately uses
// many of the same math functions checked below for entirely unrelated
// purposes (e.g. driving motion vectors), and would otherwise cause false
// positives on presets whose *shader* is trivial but whose *equations* are not.
QByteArray extractShaderCode(const QByteArray &content)
{
    QByteArray result;
    for (const QByteArray &line : content.split('\n')) {
        if (line.startsWith("warp_") || line.startsWith("comp_")) {
            const int eq = line.indexOf('=');
            if (eq >= 0) result += line.mid(eq + 1) + '\n';
        }
    }
    return result;
}

// Common HLSL constructs a shader needs to generate any real content from
// scratch (as opposed to just reading back a previous frame and applying a
// flat scalar decay/flip). If a preset's warp+composite shader code contains
// NONE of these, it isn't creating anything -- confirmed empirically: this
// exact check correctly excludes both a preset with a real (if short) noise-
// based shader and one relying on enabled custom waveforms instead, while
// still catching every confirmed "renders as solid black" case found so far.
const char *const kGenerativeShaderTokens[] = {
    "sampler_pw_", "sampler_fw_", "sampler_pc_", "sampler_fc_",
    "sampler_noise", "sampler_pfx", "sampler_blur",
    "rand_frame", "rand_preset", "sin(", "cos(", "noise",
    "for (", "while (", "float2", "float3", "float4",
    "saturate(", "pow(", "frac(", "lerp(", "dot(", "length(",
    "normalize(", "mod(", "step(", "smoothstep(", "atan",
    "sqrt(", "min(", "max(", "clamp(",
};

} // namespace

MilkdropCompatibilityResult MilkdropPresetChecker::checkFile(const QString &filePath)
{
    const QFileInfo info(filePath);

    // MilkDrop3's dual-preset ".milk2" format -- invisible to projectM's
    // playlist scanner and preset-format parser at any version (confirmed
    // via source, see UC-20). No file read needed to know this.
    if (info.suffix().compare(QStringLiteral("milk2"), Qt::CaseInsensitive) == 0) {
        return { false, QStringLiteral(
            "MilkDrop3's dual-preset (.milk2) format is not supported by projectM.") };
    }

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return { true, {} }; // unreadable -- not what this engine checks for

    // Read raw bytes, not decoded text -- every needle below is pure ASCII,
    // so a raw QByteArray::contains() sidesteps any embedded-NUL/non-UTF-8
    // author-comment byte entirely, cheaper and more robust than decoding first.
    const QByteArray content = file.readAll();
    for (const auto &rule : kUnsupportedFunctions) {
        if (content.contains(rule.needle))
            return { false, QString::fromLatin1(rule.description) };
    }

    // Rule 3: no visible content is possible anywhere in the render
    // pipeline -- every overlay that could draw new pixels (outer/inner
    // border, motion vectors, the built-in waveform) is off, no custom
    // shape/waveform is enabled either, and the warp+composite shader
    // contains no content-generating logic beyond reading back the previous
    // frame and applying a flat decay/flip. Found in a cluster of
    // MilkDrop3-era presets that apparently rely on a proprietary native
    // rendering feature (several carry an unrecognized "MD3<N>=<huge
    // number>" field, never referenced anywhere in projectM) with no
    // portable expression of their actual content -- these render as a
    // permanently solid-black screen in any engine that only understands
    // the standard preset format, not just projectM. See UC-25.
    //
    // A border counts as invisible if EITHER its alpha is ~0 OR its size is
    // ~0 -- confirmed against projectM's own Border::Draw() (Border.cpp):
    // the outer border's quad spans innerRadius=1-ob_size to outerRadius=1,
    // so ob_size=0 collapses it to a zero-area strip regardless of ob_a
    // (same for the inner border via ib_size). A preset with ob_a=1 but
    // ob_size=0 looked "visible" under an alpha-only check but draws
    // nothing -- caught via "XorDev - MilkDrop2077 - martin - Starship Red
    // Lines.milk", which also carries this rule's usual MD3<N>= marker and
    // an explicit preset-author comment ("This shader will work only with
    // md3"). Missing ob_size/ib_size keys default to 1.0 (a substantial
    // width), same "don't flag on an unknown value" bias as every other
    // default in this function.
    const bool outerBorderInvisible =
        keyValueOrDefault(content, "ob_a", 1.0)    <= 0.01 ||
        keyValueOrDefault(content, "ob_size", 1.0) <= 0.001;
    const bool innerBorderInvisible =
        keyValueOrDefault(content, "ib_a", 1.0)    <= 0.01 ||
        keyValueOrDefault(content, "ib_size", 1.0) <= 0.001;
    const bool overlaysInvisible =
        outerBorderInvisible &&
        innerBorderInvisible &&
        keyValueOrDefault(content, "mv_a", 1.0)        <= 0.01 &&
        keyValueOrDefault(content, "fWaveAlpha", 1.0)  <= 0.01;

    if (overlaysInvisible && !hasEnabledCustomShapeOrWave(content)) {
        const QByteArray shaderCode = extractShaderCode(content);
        bool hasGenerativeLogic = false;
        for (const char *token : kGenerativeShaderTokens) {
            if (shaderCode.contains(token)) { hasGenerativeLogic = true; break; }
        }
        if (!hasGenerativeLogic) {
            return { false, QStringLiteral(
                "No visible overlay is enabled and the warp/composite shader "
                "generates no content of its own -- this preset likely relies "
                "on a proprietary MilkDrop3 rendering feature with no portable "
                "expression of its actual content, and renders as a solid "
                "black screen.") };
        }
    }

    return { true, {} };
}
