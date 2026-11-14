#include "visualizershapeitem.h"

#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>
#include <cmath>
#include <cstring>
#include <vector>

namespace {

constexpr float kPi = 3.14159265358979323846f;

struct Pt { float x, y; };

inline Pt operator+(Pt a, Pt b) { return { a.x + b.x, a.y + b.y }; }
inline Pt operator-(Pt a, Pt b) { return { a.x - b.x, a.y - b.y }; }
inline Pt operator*(Pt a, float s) { return { a.x * s, a.y * s }; }

inline Pt normalized(Pt d)
{
    const float len = std::sqrt(d.x * d.x + d.y * d.y);
    return len > 1e-5f ? Pt{ d.x / len, d.y / len } : Pt{ 0.0f, 0.0f };
}

// Premultiplied RGBA, as QSGVertexColorMaterial expects.
struct Rgba { uchar r, g, b, a; };

inline Rgba premul(const QColor &c, float alpha)
{
    const float a = qBound(0.0f, float(c.alphaF()) * alpha, 1.0f);
    return { uchar(std::lround(c.redF() * a * 255.0f)), uchar(std::lround(c.greenF() * a * 255.0f)),
             uchar(std::lround(c.blueF() * a * 255.0f)), uchar(std::lround(a * 255.0f)) };
}

// Collects triangles (non-indexed) for one QSGGeometry, in drawing order.
class Builder
{
public:
    std::vector<QSGGeometry::ColoredPoint2D> v;

    void vertex(Pt p, Rgba c)
    {
        QSGGeometry::ColoredPoint2D cp;
        cp.set(p.x, p.y, c.r, c.g, c.b, c.a);
        v.push_back(cp);
    }
    // Corners in order around the quad.
    void quad(Pt p0, Pt p1, Pt p2, Pt p3, Rgba c0, Rgba c1, Rgba c2, Rgba c3)
    {
        vertex(p0, c0); vertex(p1, c1); vertex(p2, c2);
        vertex(p0, c0); vertex(p2, c2); vertex(p3, c3);
    }

    // Polyline of the given width with feathered (alpha -> 0) edges and
    // mitred joints (miter length capped at 2x).
    void stroke(const std::vector<Pt> &pts, float width, float feather,
                const QColor &color, float alpha, bool closed = false)
    {
        const int n = int(pts.size());
        if (n < 2) return;
        const Rgba on  = premul(color, alpha);
        const Rgba off = premul(color, 0.0f);

        std::vector<Pt> offs(n);
        for (int i = 0; i < n; ++i) {
            const bool hasPrev = i > 0 || closed;
            const bool hasNext = i < n - 1 || closed;
            const Pt prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
            Pt nPrev{ 0, 0 }, nNext{ 0, 0 };
            if (hasPrev) { const Pt d = normalized(cur - prev); nPrev = { -d.y, d.x }; }
            if (hasNext) { const Pt d = normalized(next - cur); nNext = { -d.y, d.x }; }
            if (!hasPrev) nPrev = nNext;
            if (!hasNext) nNext = nPrev;
            Pt nrm = normalized(nPrev + nNext);
            if (nrm.x == 0.0f && nrm.y == 0.0f) nrm = nPrev;
            const float dot = nrm.x * nPrev.x + nrm.y * nPrev.y;
            const float miter = qMin(2.0f, 1.0f / qMax(0.5f, dot));
            offs[i] = nrm * miter;
        }

        const float hw = width * 0.5f, outer = hw + feather;
        const int segs = closed ? n : n - 1;
        for (int i = 0; i < segs; ++i) {
            const int j = (i + 1) % n;
            const Pt li = pts[i] + offs[i] * hw,    lj = pts[j] + offs[j] * hw;
            const Pt ri = pts[i] - offs[i] * hw,    rj = pts[j] - offs[j] * hw;
            const Pt lo = pts[i] + offs[i] * outer, ljo = pts[j] + offs[j] * outer;
            const Pt ro = pts[i] - offs[i] * outer, rjo = pts[j] - offs[j] * outer;
            if (feather > 0.0f) quad(lo, ljo, lj, li, off, off, on, on);
            quad(li, lj, rj, ri, on, on, on, on);
            if (feather > 0.0f) quad(ri, rj, rjo, ro, on, on, off, off);
        }
    }
};

// Catmull-Rom through pts, `sub` points per segment (endpoints kept).
std::vector<Pt> catmullRom(const std::vector<Pt> &pts, int sub)
{
    const int n = int(pts.size());
    if (n < 3 || sub <= 1) return pts;
    std::vector<Pt> out;
    out.reserve(size_t((n - 1) * sub + 1));
    for (int i = 0; i < n - 1; ++i) {
        const Pt p0 = pts[qMax(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[qMin(n - 1, i + 2)];
        for (int s = 0; s < sub; ++s) {
            const float t = float(s) / float(sub), t2 = t * t, t3 = t2 * t;
            out.push_back({
                0.5f * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                        + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
                0.5f * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                        + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3) });
        }
    }
    out.push_back(pts.back());
    return out;
}

} // namespace

// ── Construction / properties ─────────────────────────────────────────────

VisualizerShapeItem::VisualizerShapeItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

VisualizerShapeItem::~VisualizerShapeItem()
{
    if (m_holdsWaveform && m_viz) m_viz->releaseWaveform();
}

void VisualizerShapeItem::setVisualizer(AudioVisualizerController *viz)
{
    if (m_viz == viz) return;
    if (m_viz) {
        if (m_holdsWaveform) { m_viz->releaseWaveform(); m_holdsWaveform = false; }
        disconnect(m_viz, nullptr, this, nullptr);
    }
    m_viz = viz;
    if (m_viz) {
        connect(m_viz, &AudioVisualizerController::barLevelsChanged, this, &VisualizerShapeItem::onLevels);
        connect(m_viz, &AudioVisualizerController::waveformChanged,  this, &VisualizerShapeItem::onWaveform);
        m_levels = m_viz->barLevelsVec();
        m_peaks  = m_viz->peakLevelsVec();
    }
    syncWaveformSubscription();
    emit visualizerChanged();
    update();
}

void VisualizerShapeItem::setMode(const QString &mode)
{
    if (m_mode == mode) return;
    m_mode = mode;
    syncWaveformSubscription();
    emit modeChanged();
    update();
}

void VisualizerShapeItem::setColor(const QColor &color)
{
    if (m_color == color) return;
    m_color = color;
    emit colorChanged();
    update();
}

void VisualizerShapeItem::setPeakColor(const QColor &color)
{
    if (m_peakColor == color) return;
    m_peakColor = color;
    emit peakColorChanged();
    update();
}

void VisualizerShapeItem::setPeakHoldEnabled(bool on)
{
    if (m_peakHold == on) return;
    m_peakHold = on;
    emit peakHoldEnabledChanged();
    update();
}

void VisualizerShapeItem::syncWaveformSubscription()
{
    const bool want = m_viz && m_mode == QLatin1String("scope");
    if (want == m_holdsWaveform) return;
    if (want) { m_viz->acquireWaveform(); m_wave = m_viz->waveform(); }
    else if (m_viz) m_viz->releaseWaveform();
    m_holdsWaveform = want;
}

void VisualizerShapeItem::onLevels()
{
    if (m_mode == QLatin1String("scope") || !m_viz) return;
    m_levels = m_viz->barLevelsVec();
    m_peaks  = m_viz->peakLevelsVec();
    update();
}

void VisualizerShapeItem::onWaveform()
{
    if (m_mode != QLatin1String("scope") || !m_viz) return;
    m_wave = m_viz->waveform();
    update();
}

void VisualizerShapeItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) update();
}

// ── Drawing ───────────────────────────────────────────────────────────────

QSGNode *VisualizerShapeItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    auto *node = static_cast<QSGGeometryNode *>(oldNode);
    if (!node) {
        node = new QSGGeometryNode;
        auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), 0);
        geometry->setDrawingMode(QSGGeometry::DrawTriangles);
        geometry->setVertexDataPattern(QSGGeometry::StreamPattern);   // rebuilt ~30x/s
        node->setGeometry(geometry);
        node->setFlag(QSGNode::OwnsGeometry);
        node->setMaterial(new QSGVertexColorMaterial);
        node->setFlag(QSGNode::OwnsMaterial);
    }

    const float w = float(width()), h = float(height());
    Builder b;

    if (w > 2.0f && h > 2.0f) {
        if (m_mode == QLatin1String("scope")) {
            // Faint centre line, then glow + core of the waveform.
            b.stroke({ { 0.0f, h * 0.5f }, { w, h * 0.5f } }, 1.0f, 0.5f, m_color, 0.12f);
            // At most one point per 2 px of width: a narrow (docked) pane
            // needs far fewer than the 512 waveform values -- same picture,
            // a fraction of the geometry (measured: SCOPE was the costliest
            // style before this cap).
            const int total = int(m_wave.size());
            const int m = qMin(total, qMax(2, int(w / 2.0f)));
            if (m >= 2 && total >= 2) {
                std::vector<Pt> pts(static_cast<size_t>(m));
                const float amp = h * 0.5f - 4.0f;
                for (int k = 0; k < m; ++k) {
                    const int src = int(std::lround(float(k) * float(total - 1) / float(m - 1)));
                    pts[size_t(k)] = { w * float(k) / float(m - 1), h * 0.5f - m_wave[src] * amp };
                }
                b.stroke(pts, 7.0f, 4.0f, m_color, 0.18f);
                b.stroke(pts, 2.0f, 1.0f, m_color, 1.0f);
            }
        } else if (m_mode == QLatin1String("radial")) {
            const int n = int(m_levels.size());
            const float cx = w * 0.5f, cy = h * 0.5f;
            const float R = qMin(w, h) * 0.5f - 3.0f;
            const float r0 = R * 0.28f;
            const float len = R - r0;
            if (n > 0 && len > 2.0f) {
                // Centre ring.
                std::vector<Pt> ring;
                ring.reserve(96);
                for (int i = 0; i < 96; ++i) {
                    const float a = 2.0f * kPi * float(i) / 96.0f;
                    ring.push_back({ cx + std::sin(a) * (r0 - 3.0f), cy - std::cos(a) * (r0 - 3.0f) });
                }
                b.stroke(ring, 1.2f, 1.0f, m_color, 0.35f, true);

                const float spokeW = qBound(1.5f, 0.55f * kPi * (r0 + len * 0.5f) / float(n), 14.0f);
                for (int i = 0; i < n; ++i) {
                    const float theta = kPi * (float(i) + 0.5f) / float(n);
                    const float lv = qBound(0.0f, m_levels[i], 1.0f);
                    const float pk = (i < m_peaks.size()) ? qBound(0.0f, m_peaks[i], 1.0f) : 0.0f;
                    for (int side = -1; side <= 1; side += 2) {
                        const Pt dir{ float(side) * std::sin(theta), -std::cos(theta) };
                        const Pt c{ cx, cy };
                        if (lv > 0.002f)
                            b.stroke({ c + dir * r0, c + dir * (r0 + lv * len) }, spokeW, 1.0f, m_color, 1.0f);
                        if (m_peakHold && pk > 0.01f) {
                            const float rp = r0 + pk * len;
                            b.stroke({ c + dir * (rp + 0.5f), c + dir * (rp + 2.5f) }, spokeW, 0.75f, m_peakColor, 1.0f);
                        }
                    }
                }
            }
        } else {   // "line"
            const int n = int(m_levels.size());
            if (n >= 2) {
                auto curve = [&](const QVector<float> &vals) {
                    std::vector<Pt> pts(static_cast<size_t>(n));
                    for (int i = 0; i < n; ++i)
                        pts[size_t(i)] = { w * float(i) / float(n - 1),
                                           h - qBound(0.0f, vals[i], 1.0f) * (h - 2.0f) - 1.0f };
                    std::vector<Pt> s = catmullRom(pts, 4);
                    for (Pt &p : s) p.y = qBound(1.0f, p.y, h - 1.0f);   // spline overshoot
                    return s;
                };
                const std::vector<Pt> line = curve(m_levels);

                // Area below the curve: alpha fades from 35 % at the curve to 0 at the bottom.
                const Rgba top = premul(m_color, 0.35f), bottom = premul(m_color, 0.0f);
                for (size_t i = 0; i + 1 < line.size(); ++i) {
                    const Pt a = line[i], c = line[i + 1];
                    b.quad(a, c, { c.x, h }, { a.x, h }, top, top, bottom, bottom);
                }
                b.stroke(line, 8.0f, 4.0f, m_color, 0.18f);   // glow
                b.stroke(line, 2.5f, 1.0f, m_color, 1.0f);    // core
                if (m_peakHold && m_peaks.size() == n)
                    b.stroke(curve(m_peaks), 1.2f, 1.0f, m_peakColor, 0.8f);
            }
        }
    }

    QSGGeometry *g = node->geometry();
    g->allocate(int(b.v.size()));
    if (!b.v.empty())
        std::memcpy(g->vertexDataAsColoredPoint2D(), b.v.data(),
                    b.v.size() * sizeof(QSGGeometry::ColoredPoint2D));
    node->markDirty(QSGNode::DirtyGeometry);
    return node;
}
