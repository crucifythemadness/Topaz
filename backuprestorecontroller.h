#pragma once

// Full definition required (not a forward-declare): AUTOMOC's combined
// mocs_compilation.cpp concatenates every moc_*.cpp alphabetically and
// can't be relied on to have already pulled in PlaylistManager's full
// definition otherwise -- see AutoPlayController's/MilkdropCleanupController's
// own headers for this exact note.
#include "playlistmanager.h"
#include "appconfig.h"

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QStringList>
#include <QVariantMap>

// ── BackupRestoreController ──────────────────────────────────────────────
// Backs the MISC tab's "Backup Topaz Environment"/"Restore Topaz
// Environment" feature -- see UC-27. Zips/unzips Topaz.config, playlist
// XML files, and Topaz.rating.json into/from a single *.zip, using the
// vendored miniz library (third_party/miniz/).
//
// Deliberately synchronous -- no worker QThread, unlike
// PlaylistExportController. That controller's worker thread exists because
// a single QFile::copy() of a multi-GB audio file can't be chunked with
// periodic processEvents() calls; every file this class ever touches is a
// small JSON/XML text file (a handful of KB to, worst case, a few MB for
// Topaz.rating.json on a huge library), squarely the same scale of work
// MilkdropCleanupController already does synchronously. Every Q_INVOKABLE
// here IS the entire operation -- no progress properties, no *Finished
// signals, the caller gets its answer as the return value.
//
// miniz never touches a filesystem path directly -- only its _mem APIs are
// used (mz_zip_writer_init_heap/add_mem/finalize_heap_archive for building,
// mz_zip_reader_init_mem/extract_to_mem for reading), fed buffers that
// QFile already read from/will write to disk. The _file-suffixed miniz
// functions go through plain narrow-char fopen() internally, which isn't
// guaranteed Unicode-safe on Windows the way QFile already is everywhere
// else in this codebase.
//
// Instantiated once in Main.qml (same convention as every other stateful
// QML_ELEMENT controller in this app).
class BackupRestoreController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(PlaylistManager* playlistManager READ playlistManager
               WRITE setPlaylistManager NOTIFY playlistManagerChanged)
    Q_PROPERTY(AppConfig* appConfig READ appConfig
               WRITE setAppConfig NOTIFY appConfigChanged)

public:
    explicit BackupRestoreController(QObject *parent = nullptr);

    PlaylistManager* playlistManager() const { return m_playlistManager; }
    void setPlaylistManager(PlaylistManager *pm);

    AppConfig* appConfig() const { return m_appConfig; }
    void setAppConfig(AppConfig *cfg);

    // ── BACKUP ────────────────────────────────────────────────────────────
    // categories: subset of {"config", "playlists", "ratings"}. ".zip" is
    // appended to zipFileName if not already present (case-insensitive).
    // A category with nothing on disk (e.g. "ratings" checked but no track
    // has ever been rated) is silently skipped, not an error; if that
    // leaves zero files across every checked category, this fails with a
    // "nothing to back up" error rather than writing an empty zip.
    // Returns { success: bool, error: string, zipPath: string, fileCount: int }.
    Q_INVOKABLE QVariantMap runBackup(const QStringList &categories,
                                       const QString &destFolder,
                                       const QString &zipFileName) const;

    // Lets BackupDialog.qml warn before overwriting -- normalizes
    // destFolder+zipFileName exactly like runBackup() does internally, so
    // the two never disagree about the final path.
    Q_INVOKABLE bool backupTargetExists(const QString &destFolder,
                                         const QString &zipFileName) const;

    // ── RESTORE: inspection only -- opens the zip read-only, extracts
    // nothing ────────────────────────────────────────────────────────────
    // Returns { error: "<reason>" } if the file can't be opened/isn't a
    // valid zip. Otherwise:
    //   { hasPlaylists: bool, hasRatings: bool, hasConfig: bool,
    //     playlists: [ { fileName, conflict }, ... ], ratingsConflict: bool }
    // hasConfig tells RestoreDialog.qml whether "Restore Config" has
    // anything to do -- see restoreConfig() below.
    Q_INVOKABLE QVariantMap inspectZip(const QString &zipFilePath) const;

    // ── RESTORE: one playlist entry, one decision ────────────────────────
    // entryFileName: bare file name as returned by inspectZip()'s
    // "playlists" list (e.g. "Foo.xml") -- looked up in the zip at
    // "playlists/<entryFileName>".
    // action: "overwrite" | "skip" | "rename"
    // Returns { success: bool, error: string, writtenFileName: string } --
    // writtenFileName is "" when skipped, or when a "rename" exhausted all
    // 9 " - Copy 0N" slots (treated as failed for that file).
    Q_INVOKABLE QVariantMap restorePlaylistEntry(const QString &zipFilePath,
                                                  const QString &entryFileName,
                                                  const QString &action) const;

    // ── RESTORE: ratings, one decision for the whole file ────────────────
    // mode: "overwrite" | "skip" | "mergeNew" | "mergeAll". Call with
    // "overwrite" directly (no dialog needed) when inspectZip()'s
    // ratingsConflict was false -- that's exactly "just copy it in".
    // Returns { success: bool, error: string, addedCount: int, updatedCount: int }.
    Q_INVOKABLE QVariantMap restoreRatings(const QString &zipFilePath,
                                            const QString &mode) const;

    // ── RESTORE: config, one call, no conflict dialog ────────────────────
    // Extracts config/Topaz.config from the zip and applies it live via
    // AppConfig::restoreFromJson() (which preserves the currently running
    // audioBackend and emits every other NOTIFY signal, so the rest of
    // the running app picks up the change immediately -- see UC-27).
    // Returns { success: bool, error: string }.
    Q_INVOKABLE QVariantMap restoreConfig(const QString &zipFilePath) const;

signals:
    void playlistManagerChanged();
    void appConfigChanged();

private:
    // <destFolder>/<zipFileName>, with ".zip" appended if missing --
    // shared by runBackup()/backupTargetExists() so they never disagree.
    QString finalZipPath(const QString &destFolder, const QString &zipFileName) const;

    PlaylistManager *m_playlistManager = nullptr;
    AppConfig       *m_appConfig       = nullptr;
};
