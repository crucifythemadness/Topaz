#pragma once

// Full definition required (not a forward-declare): AUTOMOC's combined
// mocs_compilation.cpp concatenates every moc_*.cpp alphabetically and can't
// be relied on to have already pulled in AppConfig's full definition
// otherwise -- see AutoPlayController's own header for this exact note.
#include "appconfig.h"

#include <QFileInfo>
#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// ── MilkdropCleanupController ────────────────────────────────────────────
// Backs the MISC tab's "Cleanup Incompatible Milkdrop Presets" feature and
// the MilkdropCleanupDialog.qml it opens -- see UC-25. Scans configured
// Milkdrop preset folders (AppConfig.milkdropPresetFolders) with
// MilkdropPresetChecker and deletes whatever it flags as incompatible.
//
// Instantiated once in Main.qml (same convention as every other stateful
// QML_ELEMENT controller in this app), not locally inside the dialog --
// Main.qml's onClosing veto needs direct visibility into `cleaning`.
class MilkdropCleanupController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(AppConfig* appConfig READ appConfig WRITE setAppConfig NOTIFY appConfigChanged)
    Q_PROPERTY(bool    cleaning        READ cleaning        NOTIFY cleaningChanged)
    Q_PROPERTY(int     cleanupProgress READ cleanupProgress NOTIFY cleanupProgressChanged)
    Q_PROPERTY(QString currentFileName READ currentFileName NOTIFY currentFileNameChanged)

public:
    explicit MilkdropCleanupController(QObject *parent = nullptr);

    AppConfig* appConfig() const { return m_appConfig; }
    void setAppConfig(AppConfig *cfg);

    bool    cleaning()        const { return m_cleaning; }
    int     cleanupProgress() const { return m_cleanupProgress; }
    QString currentFileName() const { return m_currentFileName; }

    // Returns [{ path, presetCount, exists }, ...] -- one entry per
    // configured Milkdrop preset folder. exists=false (folder missing from
    // disk) shows presetCount=0, distinguished so the dialog can display
    // "(folder not found)" rather than a misleading empty-folder count.
    Q_INVOKABLE QVariantList presetFolders() const;

    // Scans and deletes incompatible presets in exactly the given folders
    // (paths must be a subset of presetFolders()'s own paths). No-op if a
    // cleanup is already running.
    Q_INVOKABLE void startCleanup(const QStringList &folderPaths);

signals:
    void appConfigChanged();
    void cleaningChanged();
    void cleanupProgressChanged();
    void currentFileNameChanged();

    // Emitted once startCleanup() finishes (or immediately if there was
    // nothing to scan). perFolderResults: [{ path, removed, failed, total }, ...].
    void cleanupFinished(QVariantList perFolderResults);

private:
    // Recursive preset-file walk, shared by presetFolders() (counting) and
    // startCleanup() (building the work list) -- mirrors
    // LibraryScanner::discoverAudioFiles()'s exact shape rather than
    // introducing a second recursive-scan idiom (QDirIterator) into the
    // codebase. NoSymLinks guards against a Windows junction looping back to
    // an ancestor directory in a large third-party-curated pack.
    QList<QFileInfo> discoverPresetFiles(const QString &dirPath) const;

    AppConfig *m_appConfig = nullptr;
    bool       m_cleaning        = false;
    int        m_cleanupProgress = 0;
    QString    m_currentFileName;
};
