#include "milkdropcleanupcontroller.h"
#include "milkdroppresetchecker.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QHash>

MilkdropCleanupController::MilkdropCleanupController(QObject *parent)
    : QObject(parent)
{
}

void MilkdropCleanupController::setAppConfig(AppConfig *cfg)
{
    if (m_appConfig == cfg) return;
    m_appConfig = cfg;
    emit appConfigChanged();
}

QList<QFileInfo> MilkdropCleanupController::discoverPresetFiles(const QString &dirPath) const
{
    QList<QFileInfo> result;
    const QDir::Filters dirFilter =
        QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable | QDir::NoSymLinks;

    QDir dir(dirPath);
    for (const QFileInfo &fi : dir.entryInfoList(dirFilter)) {
        if (fi.isDir()) {
            result.append(discoverPresetFiles(fi.absoluteFilePath()));
            continue;
        }
        const QString suffix = fi.suffix().toLower();
        if (suffix == QStringLiteral("milk") || suffix == QStringLiteral("milk2"))
            result.append(fi);
    }
    return result;
}

QVariantList MilkdropCleanupController::presetFolders() const
{
    QVariantList result;
    if (!m_appConfig) return result;

    for (const QVariant &v : m_appConfig->milkdropPresetFolders()) {
        const QString path = v.toMap().value(QStringLiteral("path")).toString();
        const bool exists = QDir(path).exists();
        const int count = exists ? discoverPresetFiles(path).size() : 0;

        QVariantMap entry;
        entry[QStringLiteral("path")]        = path;
        entry[QStringLiteral("presetCount")] = count;
        entry[QStringLiteral("exists")]      = exists;
        result.append(entry);
    }
    return result;
}

void MilkdropCleanupController::startCleanup(const QStringList &folderPaths)
{
    if (m_cleaning) return;

    struct WorkItem { QString folderPath; QFileInfo file; };
    QList<WorkItem> workItems;
    QHash<QString, int> totalByFolder;
    for (const QString &folder : folderPaths) {
        totalByFolder[folder] = 0;
        for (const QFileInfo &fi : discoverPresetFiles(folder))
            workItems.append({ folder, fi });
    }
    for (const auto &item : std::as_const(workItems))
        ++totalByFolder[item.folderPath];

    const int total = workItems.size();

    auto buildResults = [&](const QHash<QString, int> &removedByFolder,
                             const QHash<QString, int> &failedByFolder) {
        QVariantList results;
        for (const QString &folder : folderPaths) {
            QVariantMap r;
            r[QStringLiteral("path")]    = folder;
            r[QStringLiteral("removed")] = removedByFolder.value(folder, 0);
            r[QStringLiteral("failed")]  = failedByFolder.value(folder, 0);
            r[QStringLiteral("total")]   = totalByFolder.value(folder, 0);
            results.append(r);
        }
        return results;
    };

    if (total == 0) {
        emit cleanupFinished(buildResults({}, {}));
        return;
    }

    m_cleaning = true;
    emit cleaningChanged();
    m_cleanupProgress = 0;
    emit cleanupProgressChanged();

    // No "is MilkdropView currently rendering one of these folders" guard:
    // rebuildPresetList() only reacts to the *folder list* changing, never
    // re-validates folder contents against disk, and projectM already has a
    // preset_switch_failed callback for a playlist entry disappearing out
    // from under it (already wired up, already logged) -- a live render
    // session is already stale-tolerant by construction. See UC-25.
    QHash<QString, int> removedByFolder;
    QHash<QString, int> failedByFolder;

    QElapsedTimer pumpTimer;
    pumpTimer.start();

    for (int i = 0; i < total; ++i) {
        const WorkItem &item = workItems.at(i);
        m_currentFileName = item.file.fileName();
        emit currentFileNameChanged();

        const MilkdropCompatibilityResult check =
            MilkdropPresetChecker::checkFile(item.file.absoluteFilePath());
        if (!check.compatible) {
            if (QFile::remove(item.file.absoluteFilePath()))
                ++removedByFolder[item.folderPath];
            else
                ++failedByFolder[item.folderPath];
        }

        m_cleanupProgress = (i + 1) * 100 / total;
        emit cleanupProgressChanged();

        // Throttled to ~60fps rather than pumped every file -- avoids
        // per-call overhead at real-world scale (one configured folder in
        // testing had ~9800 preset files) while keeping the UI visibly live.
        if (pumpTimer.elapsed() >= 16) {
            QCoreApplication::processEvents();
            pumpTimer.restart();
        }
    }

    m_cleaning = false;
    emit cleaningChanged();
    m_currentFileName.clear();
    emit currentFileNameChanged();

    emit cleanupFinished(buildResults(removedByFolder, failedByFolder));
}
