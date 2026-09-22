#pragma once

#include <QLoggingCategory>

// Logging category of the Auto Loudness Correction feature (UC-35): quiet by
// default (warnings only); enable the per-track detail with
//   QT_LOGGING_RULES="topaz.loudness.info=true"
// Defined in loudnessanalyzer.cpp.
Q_DECLARE_LOGGING_CATEGORY(lcLoudness)
