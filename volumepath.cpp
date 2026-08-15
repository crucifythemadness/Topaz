#include "volumepath.h"

#include <QFileInfo>
#include <QStorageInfo>

namespace {

QString rootNoTrailingSlash(const QStorageInfo &vol)
{
    QString root = vol.rootPath();
    if (root.endsWith(QLatin1Char('/')) || root.endsWith(QLatin1Char('\\')))
        root.chop(1);
    return root;
}

} // namespace

// static
VolumePath VolumePath::fromAbsolutePath(const QString &absPath)
{
    VolumePath vp;
    vp.rawPath = absPath;

    const QStorageInfo si(absPath);
    if (si.isValid() && si.isReady()) {
        const QString root = rootNoTrailingSlash(si);
        if (absPath.startsWith(root, Qt::CaseInsensitive)) {
            QString rel = absPath.mid(root.length());
            rel.replace(QLatin1Char('\\'), QLatin1Char('/'));
            if (!rel.startsWith(QLatin1Char('/')))
                rel.prepend(QLatin1Char('/'));
            vp.relativePath = rel;
            vp.volumeName   = si.name(); // may be empty (unlabeled volume)
        }
    }
    return vp;
}

QString VolumePath::resolve(const QList<QStorageInfo> &mounted) const
{
    if (!relativePath.isEmpty()) {
        // Prefer the volume whose label matches (disambiguates volumes that
        // happen to share the same relative layout).
        if (!volumeName.isEmpty()) {
            for (const QStorageInfo &vol : mounted) {
                if (!vol.isValid() || !vol.isReady() || vol.name() != volumeName)
                    continue;
                const QString candidate = rootNoTrailingSlash(vol) + relativePath;
                if (QFileInfo::exists(candidate))
                    return candidate;
            }
        }
        // Label not found this boot (renamed/unlabeled/different machine) —
        // fall back to probing every mounted volume for the same relative path.
        for (const QStorageInfo &vol : mounted) {
            if (!vol.isValid() || !vol.isReady())
                continue;
            const QString candidate = rootNoTrailingSlash(vol) + relativePath;
            if (QFileInfo::exists(candidate))
                return candidate;
        }
    }
    // Nothing resolvable via a volume root — last resort, trust the raw path.
    if (!rawPath.isEmpty() && QFileInfo::exists(rawPath))
        return rawPath;
    return {};
}

QString VolumePath::quickPath(const QList<QStorageInfo> &mounted) const
{
    if (relativePath.isEmpty())
        return {};

    if (!volumeName.isEmpty()) {
        for (const QStorageInfo &vol : mounted) {
            if (!vol.isValid() || !vol.isReady() || vol.name() != volumeName)
                continue;
            return rootNoTrailingSlash(vol) + relativePath;
        }
        return {};
    }

    // Unlabeled volume — match by which mounted volume's root the raw path
    // currently falls under. Pure string comparison, no filesystem access.
    for (const QStorageInfo &vol : mounted) {
        if (!vol.isValid() || !vol.isReady())
            continue;
        const QString root = rootNoTrailingSlash(vol);
        if (rawPath.startsWith(root, Qt::CaseInsensitive))
            return root + relativePath;
    }
    return {};
}

QVariantMap VolumePath::toVariantMap() const
{
    QVariantMap m;
    m[QStringLiteral("volume")]  = volumeName;
    m[QStringLiteral("relPath")] = relativePath;
    m[QStringLiteral("rawPath")] = rawPath;
    return m;
}

// static
VolumePath VolumePath::fromVariantMap(const QVariantMap &m)
{
    VolumePath vp;
    vp.volumeName   = m.value(QStringLiteral("volume")).toString();
    vp.relativePath = m.value(QStringLiteral("relPath")).toString();
    vp.rawPath      = m.value(QStringLiteral("rawPath")).toString();
    return vp;
}
