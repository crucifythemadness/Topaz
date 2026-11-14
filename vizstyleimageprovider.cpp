#include "vizstyleimageprovider.h"

#include <QColor>
#include <QLinearGradient>
#include <QPainter>

VizStyleImageProvider::VizStyleImageProvider()
    : QQuickImageProvider(QQmlImageProviderBase::Image)
{
}

QImage VizStyleImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    Q_UNUSED(requestedSize)
    const QStringList parts = id.split(QLatin1Char('/'));
    QImage img;

    if (parts.size() == 4 && parts[0] == QLatin1String("led")) {
        // Colour arrives as bare hex ("00DAF3"): a '#' would start the URL's
        // fragment and never reach this provider.
        const QColor color(QLatin1Char('#') + parts[1]);
        const int seg = qBound(1, parts[2].toInt(), 256);
        const int gap = qBound(0, parts[3].toInt(), 256);
        img = QImage(1, seg + gap, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
        const QRgb c = (color.isValid() ? color : QColor(Qt::white)).rgba();
        for (int y = gap; y < seg + gap; ++y) img.setPixel(0, y, c);
    } else if (parts.size() == 4 && parts[0] == QLatin1String("gradient")) {
        // gradient/<low>-<mid>-<high>-<top>/<spanPermille>/<heightPx>
        const QStringList c = parts[1].split(QLatin1Char('-'));
        auto col = [&c](int i, const char *fallback) {
            const QColor q = (i < c.size()) ? QColor(QLatin1Char('#') + c[i]) : QColor();
            return q.isValid() ? q : QColor(QLatin1String(fallback));
        };
        const double span = qBound(0.1, parts[2].toInt() / 1000.0, 2.0);
        const int h = qBound(1, parts[3].toInt(), 8192);
        img = QImage(1, h, QImage::Format_ARGB32_Premultiplied);
        // The colour ramp covers span x the bar height from the bottom: span 1
        // = the original gradient (red exactly at the top), < 1 reaches the
        // warm colours at lower bars (red held above), > 1 stays greener.
        QLinearGradient g(0, h, 0, h - h * span);   // bottom -> top
        g.setSpread(QGradient::PadSpread);
        g.setColorAt(0.00, col(0, "#3DFF7A"));   // low   (green)
        g.setColorAt(0.55, col(1, "#FFE14A"));   // mid   (yellow)
        g.setColorAt(0.85, col(2, "#FF8A1F"));   // high  (orange)
        g.setColorAt(1.00, col(3, "#FF2D45"));   // top   (red)
        QPainter p(&img);
        p.fillRect(img.rect(), g);
    } else {
        img = QImage(1, 1, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
    }

    if (size) *size = img.size();
    return img;
}
