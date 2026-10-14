#include "genrescancontroller.h"

#include "libraryscanner.h"
#include "tagreader.h"

#include <QCollator>
#include <QFileInfo>
#include <QHash>
#include <QSet>
#include <QThread>
#include <QThreadPool>
#include <QVariantMap>
#include <QtConcurrent>
#include <algorithm>

// ── Worker ────────────────────────────────────────────────────────────────

namespace {

struct GenreTally
{
    QString name;   // spelling first seen
    int     count = 0;
};

QVariantList toSortedList(const QHash<QString, GenreTally> &tally)
{
    QList<GenreTally> list = tally.values();
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(list.begin(), list.end(), [&](const GenreTally &a, const GenreTally &b) {
        return collator.compare(a.name, b.name) < 0;
    });
    QVariantList out;
    out.reserve(list.size());
    for (const GenreTally &g : std::as_const(list)) {
        QVariantMap m;
        m[QStringLiteral("name")]  = g.name;
        m[QStringLiteral("count")] = g.count;
        out.append(m);
    }
    return out;
}

} // namespace

void GenreScanWorker::runScan(QVariantList folders)
{
    // 1. List the files -- the library scan's own listing, so both scans see
    //    exactly the same files. A set guards against overlapping folders
    //    (a folder configured together with one of its own subfolders).
    QStringList paths;
    QSet<QString> seen;
    for (const QVariant &v : std::as_const(folders)) {
        const QVariantMap f = v.toMap();
        const QList<QFileInfo> files = LibraryScanner::listAudioFiles(
            f.value(QStringLiteral("path")).toString(),
            f.value(QStringLiteral("includeSubfolders")).toBool(), m_cancel);
        for (const QFileInfo &fi : files) {
            const QString p = fi.absoluteFilePath();
            if (!seen.contains(p)) { seen.insert(p); paths.append(p); }
        }
        if (m_cancel.load(std::memory_order_relaxed)) break;
    }

    const int total = paths.size();
    QHash<QString, GenreTally> tally;   // key: genre lower-cased
    int withoutGenre = 0;
    int done = 0;

    if (m_cancel.load(std::memory_order_relaxed)) {
        emit finished({}, 0, total, true);
        return;
    }
    emit progress(0, total, {}, 0);

    // 2. Read the tags in parallel, in the library scan's chunk size, over a
    //    pool of the same size. TagReader::read() already reduces a multi-genre
    //    tag to its first genre -- the value the library matches against.
    QThreadPool pool;
    pool.setMaxThreadCount(LibraryScanner::tagReadThreadCount());
    for (int i = 0; i < total; i += LibraryScanner::kTagReadChunkSize) {
        if (m_cancel.load(std::memory_order_relaxed)) break;

        const QStringList chunk = paths.mid(i, LibraryScanner::kTagReadChunkSize);
        const QStringList genres = QtConcurrent::blockingMapped<QStringList>(
            &pool, chunk,
            [](const QString &path) { return TagReader::read(path, false).genre.trimmed(); });

        for (const QString &g : genres) {
            if (g.isEmpty()) { ++withoutGenre; continue; }
            GenreTally &t = tally[g.toLower()];
            if (t.name.isEmpty()) t.name = g;
            ++t.count;
        }
        done += chunk.size();
        emit progress(done, total, toSortedList(tally), withoutGenre);
    }

    emit finished(toSortedList(tally), withoutGenre, total,
                  m_cancel.load(std::memory_order_relaxed) || done < total);
}

// ── Controller ────────────────────────────────────────────────────────────

GenreScanController::GenreScanController(QObject *parent) : QObject(parent)
{
    m_worker = new GenreScanWorker();
    m_thread = new QThread(this);
    m_worker->moveToThread(m_thread);

    connect(m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(this, &GenreScanController::_requestScan,
            m_worker, &GenreScanWorker::runScan, Qt::QueuedConnection);
    connect(m_worker, &GenreScanWorker::progress,
            this, &GenreScanController::onWorkerProgress, Qt::QueuedConnection);
    connect(m_worker, &GenreScanWorker::finished,
            this, &GenreScanController::onWorkerFinished, Qt::QueuedConnection);

    m_thread->start();
}

GenreScanController::~GenreScanController()
{
    if (m_worker) m_worker->cancel();
    m_thread->quit();
    if (!m_thread->wait(3000)) {
        // A single huge tag read can outlast the wait; detach rather than let
        // ~QObject delete a still-running QThread (fatal) -- same as
        // PlaylistExportController/LibraryModel.
        m_thread->setParent(nullptr);
    }
}

QVariantList GenreScanController::scannableFolders(const QVariantList &folders)
{
    QVariantList out;
    for (const QVariant &v : folders) {
        const QVariantMap f = v.toMap();
        const QString path = f.value(QStringLiteral("path")).toString();
        if (!f.value(QStringLiteral("active"), true).toBool()) continue;
        if (!f.value(QStringLiteral("available"), true).toBool() || path.isEmpty()) continue;
        QVariantMap e;
        e[QStringLiteral("path")] = path;
        e[QStringLiteral("includeSubfolders")] =
            f.value(QStringLiteral("includeSubfolders"), true).toBool();
        out.append(e);
    }
    return out;
}

bool GenreScanController::hasScannableFolder(const QVariantList &folders) const
{
    return !scannableFolders(folders).isEmpty();
}

int GenreScanController::progress() const
{
    if (m_filesTotal <= 0) return (m_scanning || m_listing) ? 0 : 100;
    return int(qint64(m_filesDone) * 100 / m_filesTotal);
}

void GenreScanController::startScan(const QVariantList &folders)
{
    if (m_scanning) {
        // A previous scan is still winding down (e.g. the dialog was closed
        // mid-scan and reopened at once): stop it and run this one right after.
        m_pendingFolders = folders;
        m_restartPending = true;
        cancelScan();
        return;
    }
    m_scanning  = true;
    m_listing   = true;
    m_cancelled = false;
    m_filesDone = m_filesTotal = m_filesWithoutGenre = 0;
    m_genres.clear();
    emit stateChanged();
    emit genresChanged();
    m_worker->resetCancel();
    emit _requestScan(scannableFolders(folders));
}

void GenreScanController::cancelScan()
{
    if (m_worker) m_worker->cancel();
}

void GenreScanController::onWorkerProgress(int done, int total, const QVariantList &genres,
                                           int withoutGenre)
{
    if (m_restartPending) return;   // a superseded scan's last report
    m_listing = false;
    m_filesDone = done;
    m_filesTotal = total;
    m_filesWithoutGenre = withoutGenre;
    emit stateChanged();
    if (genres != m_genres) {
        m_genres = genres;
        emit genresChanged();
    }
}

void GenreScanController::onWorkerFinished(const QVariantList &genres, int withoutGenre,
                                           int total, bool cancelled)
{
    m_scanning = false;
    if (m_restartPending) {
        // Results of the superseded scan are of no interest -- start the
        // requested one (its startScan() resets every property).
        m_restartPending = false;
        startScan(m_pendingFolders);
        return;
    }
    m_listing  = false;
    m_cancelled = cancelled;
    m_filesTotal = total;
    if (!cancelled) m_filesDone = total;
    m_filesWithoutGenre = withoutGenre;
    if (genres != m_genres) {
        m_genres = genres;
        emit genresChanged();
    }
    emit stateChanged();
    emit scanFinished();
}
