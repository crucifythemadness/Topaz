#pragma once

#include <QString>

// ── MilkdropPresetChecker ────────────────────────────────────────────────
// Extensible engine that checks a single MilkDrop preset file for known
// incompatibilities with Topaz's projectM-based Milkdrop integration (see
// UC-20/UC-25). Extend checkFile() whenever a new incompatible pattern is
// discovered -- add a table row to kUnsupportedFunctions for a new
// substring-based rule, or a new branch for a structurally different one.
// Static-methods-only, no QObject -- same convention as TagReader/RatingCache.
struct MilkdropCompatibilityResult
{
    bool compatible;
    QString reason; // empty when compatible
};

class MilkdropPresetChecker
{
public:
    // Checks one preset file. Never throws; returns compatible=true for
    // anything it doesn't specifically recognize as broken (an unreadable
    // file is treated as compatible -- this engine only flags *known*
    // incompatibilities, it doesn't validate general file health).
    static MilkdropCompatibilityResult checkFile(const QString &filePath);
};
