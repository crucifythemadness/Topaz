#pragma once

#include "audiovisualizercontroller.h"

#include <QColor>
#include <QPointer>
#include <QQuickItem>
#include <QVector>

// Full header (not a forward declaration) for the Q_PROPERTY pointer type --
// see AutoPlayController's header comment for why.

// ── VisualizerShapeItem ───────────────────────────────────────────────────
// Draws the Audio Visualizer's LINE, RADIAL and SCOPE styles (UC-19,
// AudioVisualizerView.qml) as ONE vertex-coloured scene-graph geometry
// (QSGVertexColorMaterial -> a single draw call), rebuilt only when the
// controller publishes new data (~30x/s), the size or a colour changes.
// Chosen over QML Canvas (CPU painting) and Shape (path rebuilt from JS
// arrays every frame): no per-bar items, no QVariant conversion -- it reads
// the controller's plain float vectors directly.
//
// Anti-aliasing without MSAA: every stroke gets 1 px feathered edges (outer
// vertices at alpha 0). Neon look: a wide, faint "glow" stroke under the
// core stroke. Colours are premultiplied, as QSGVertexColorMaterial expects.
//
//   line   spectrum curve through the bar levels (Catmull-Rom smoothed), glow,
//          area below with a vertical alpha fade; peak hold = thin line
//   radial bars as spokes around a centre ring, mirrored left/right (low
//          frequencies at the top); peak hold = a small mark per spoke
//   scope  the waveform (controller->waveform(), held via acquireWaveform()
//          only while mode == "scope"), centred, with glow
class VisualizerShapeItem : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(AudioVisualizerController* visualizer READ visualizer WRITE setVisualizer NOTIFY visualizerChanged)
    Q_PROPERTY(QString mode            READ mode            WRITE setMode            NOTIFY modeChanged)
    Q_PROPERTY(QColor  color           READ color           WRITE setColor           NOTIFY colorChanged)
    Q_PROPERTY(QColor  peakColor       READ peakColor       WRITE setPeakColor       NOTIFY peakColorChanged)
    Q_PROPERTY(bool    peakHoldEnabled READ peakHoldEnabled WRITE setPeakHoldEnabled NOTIFY peakHoldEnabledChanged)

public:
    explicit VisualizerShapeItem(QQuickItem *parent = nullptr);
    ~VisualizerShapeItem() override;

    AudioVisualizerController *visualizer() const { return m_viz; }
    QString mode()            const { return m_mode; }
    QColor  color()           const { return m_color; }
    QColor  peakColor()       const { return m_peakColor; }
    bool    peakHoldEnabled() const { return m_peakHold; }

    void setVisualizer(AudioVisualizerController *viz);
    void setMode(const QString &mode);
    void setColor(const QColor &color);
    void setPeakColor(const QColor &color);
    void setPeakHoldEnabled(bool on);

signals:
    void visualizerChanged();
    void modeChanged();
    void colorChanged();
    void peakColorChanged();
    void peakHoldEnabledChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *data) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void onLevels();
    void onWaveform();
    // Holds the controller's waveform (acquireWaveform) exactly while this
    // item is in "scope" mode with a controller set.
    void syncWaveformSubscription();

    QPointer<AudioVisualizerController> m_viz;
    QString m_mode = QStringLiteral("line");
    QColor  m_color = QColor(0x00, 0xDA, 0xF3);
    QColor  m_peakColor = QColor(0xE5, 0xE2, 0xE1);
    bool    m_peakHold = true;
    bool    m_holdsWaveform = false;

    // Copied on the GUI thread when the controller publishes; read in
    // updatePaintNode() (render thread, GUI thread blocked during sync).
    QVector<float> m_levels;
    QVector<float> m_peaks;
    QVector<float> m_wave;
};
