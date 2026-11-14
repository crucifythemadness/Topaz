#pragma once

#include <QQuickImageProvider>

// ── VizStyleImageProvider ─────────────────────────────────────────────────
// Tiny generated textures for the Audio Visualizer's LED and GRADIENT styles
// (UC-19, AudioVisualizerView.qml). Each bar is a single tiled Image cut off
// at the bar's height, so a style costs the same per frame as the plain
// TOPAZ bars (one item per bar, one shared texture -> batched), instead of
// many segment items or a Canvas. Images are only (re)generated when the id
// changes (colour / pane height), never per frame.
//
// Ids (registered as "vizstyle" in main.cpp):
//   led/<rrggbb>/<segmentPx>/<gapPx>   1 px wide: <gapPx> transparent on top,
//                                     <segmentPx> of colour below -- tiled
//                                     bottom-aligned, it forms LED segments
//   gradient/<c0>-<c1>-<c2>-<c3>/<spanPermille>/<heightPx>
//                                    1 px wide, <heightPx> tall: c0 (bottom) ->
//                                    c1 (55 %) -> c2 (85 %) -> c3 (top) over
//                                    span x height, padded above. Colours are
//                                    bare hex, chosen in QML (the Audio Meter's
//                                    HIFI or TOPAZ scheme); span from Setup's
//                                    Colour Shift (1000 = original gradient)
class VizStyleImageProvider : public QQuickImageProvider
{
public:
    VizStyleImageProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
