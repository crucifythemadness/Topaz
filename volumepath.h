#pragma once

#include <QList>
#include <QString>
#include <QVariantMap>

class QStorageInfo;

// ── VolumePath ────────────────────────────────────────────────────────────
// A path anchored to a storage volume's label instead of a Windows drive
// letter or a Linux mount point, so persisted paths survive drive-letter
// reassignment / a disk being remounted elsewhere, and work unchanged across
// platforms. Used by AppConfig (monitored folders), LibraryCache (scanned
// track paths) and PlaylistManager (XSPF <location>/<volume>).
//
// Resolution comes in two flavours (see the callers for why both exist):
//   resolve()   — verifies candidates with QFileInfo::exists(), probes every
//                 mounted volume as a fallback. Use for small batches.
//   quickPath() — in-memory name/root matching only, never touches disk.
//                 Use for large batches (e.g. LibraryCache::load(), which
//                 runs synchronously on the main thread for instant startup
//                 and must not do per-entry filesystem I/O at 12K+ scale).
// Both take a pre-fetched QStorageInfo::mountedVolumes() list — callers are
// responsible for fetching that once per batch, not once per entry, since
// the enumeration itself is a real OS call.
struct VolumePath
{
    QString volumeName;    // QStorageInfo::name() captured at write time; may be
                            // empty (unlabeled volume) — relativePath still works
    QString relativePath;  // volume-root-relative, forward slashes, leading '/'
    QString rawPath;       // absolute path at write time — last-resort fallback
                            // when no containing volume could be identified at all

    static VolumePath fromAbsolutePath(const QString &absPath);

    QString resolve(const QList<QStorageInfo> &mounted) const;
    QString quickPath(const QList<QStorageInfo> &mounted) const;

    QVariantMap toVariantMap() const;
    static VolumePath fromVariantMap(const QVariantMap &m);
};
