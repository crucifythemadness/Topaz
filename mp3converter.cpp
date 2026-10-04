#include "mp3converter.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QMutex>
#include <QMutexLocker>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QStringList>

namespace Mp3Converter {

QString findFfmpeg()
{
#ifdef Q_OS_WIN
    const QString local = QCoreApplication::applicationDirPath() + QStringLiteral("/ffmpeg.exe");
#else
    const QString local = QCoreApplication::applicationDirPath() + QStringLiteral("/ffmpeg");
#endif
    if (QFileInfo(local).isFile())
        return local;
    return QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
}

bool ffmpegUsable(const QString &ffmpegPath)
{
    if (ffmpegPath.isEmpty())
        return false;

    // Keyed on size + mtime too, so replacing the file (say, an ffmpeg
    // without LAME by one with it) is noticed without restarting Topaz.
    const QFileInfo fi(ffmpegPath);
    const QString key = ffmpegPath + QLatin1Char('|') + QString::number(fi.size())
                        + QLatin1Char('|') + QString::number(fi.lastModified().toMSecsSinceEpoch());

    static QMutex mutex;
    static QHash<QString, bool> cache;
    {
        QMutexLocker lock(&mutex);
        const auto it = cache.constFind(key);
        if (it != cache.constEnd())
            return it.value();
    }

    bool usable = false;
    QProcess p;
    p.start(ffmpegPath, { QStringLiteral("-hide_banner"), QStringLiteral("-encoders") });
    if (p.waitForStarted(3000)) {
        p.closeWriteChannel();
        if (p.waitForFinished(8000)) {
            usable = p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0
                     && p.readAllStandardOutput().contains("libmp3lame");
        } else {
            p.kill();
            p.waitForFinished(1000);
        }
    }

    QMutexLocker lock(&mutex);
    cache.insert(key, usable);
    return usable;
}

namespace {

// One ffmpeg run. `withCover` adds the mapping of the first video stream
// (FLAC/Opus embedded pictures show up to ffmpeg as an "attached picture"
// video stream) and copies it into the MP3's ID3 tag as cover art.
Outcome runOnce(const QString &ffmpegPath, const QString &srcPath, const QString &destPath,
                qint64 durationMs, bool withCover, const std::atomic<bool> &cancel,
                const std::function<void(double)> &onFraction)
{
    QStringList args = {
        QStringLiteral("-nostdin"), QStringLiteral("-hide_banner"),
        QStringLiteral("-loglevel"), QStringLiteral("error"),
        QStringLiteral("-nostats"),
        QStringLiteral("-progress"), QStringLiteral("pipe:1"),
        QStringLiteral("-y"),
        QStringLiteral("-i"), srcPath,
        QStringLiteral("-map"), QStringLiteral("0:a:0"),
    };
    if (withCover)
        args << QStringLiteral("-map") << QStringLiteral("0:v:0?")
             << QStringLiteral("-c:v") << QStringLiteral("copy");
    args << QStringLiteral("-c:a") << QStringLiteral("libmp3lame")
         << QStringLiteral("-b:a")  << QStringLiteral("320k")      // CBR
         << QStringLiteral("-ar")   << QStringLiteral("44100")
         << QStringLiteral("-ac")   << QStringLiteral("2")
         // FLAC keeps its Vorbis comments as file-level metadata (the first
         // mapping); Opus keeps them on the audio stream, which that mapping
         // misses -- the second one merges them in (a no-op for FLAC).
         << QStringLiteral("-map_metadata") << QStringLiteral("0")
         << QStringLiteral("-map_metadata:g") << QStringLiteral("0:s:a:0")
         << QStringLiteral("-id3v2_version") << QStringLiteral("3")  // widest player/car-stereo support
         << QStringLiteral("-f") << QStringLiteral("mp3")
         << destPath;

    // stderr merged into stdout: one pipe to drain, so ffmpeg can never block
    // on a full stderr pipe. The "-progress" output is plain key=value lines;
    // anything else is a diagnostic.
    QProcess p;
    p.setProcessChannelMode(QProcess::MergedChannels);
    p.start(ffmpegPath, args);
    if (!p.waitForStarted(5000)) {
        Outcome o;
        o.error = QStringLiteral("Could not start ffmpeg: ") + p.errorString();
        return o;
    }
    p.closeWriteChannel();

    static const QRegularExpression progressLine(QStringLiteral("^[A-Za-z0-9_]+="));
    QByteArray pending;
    QString lastDiagnostic;
    auto consume = [&](const QByteArray &data) {
        pending += data;
        int nl;
        while ((nl = pending.indexOf('\n')) >= 0) {
            const QString line = QString::fromUtf8(pending.left(nl)).trimmed();
            pending.remove(0, nl + 1);
            if (line.isEmpty())
                continue;
            if (line.startsWith(QLatin1String("out_time_us="))) {
                bool ok = false;
                const qint64 us = line.mid(12).toLongLong(&ok);
                if (ok && us >= 0 && durationMs > 0 && onFraction)
                    onFraction(qBound(0.0, double(us) / (double(durationMs) * 1000.0), 1.0));
            } else if (!progressLine.match(line).hasMatch()) {
                lastDiagnostic = line;
            }
        }
    };

    while (p.state() != QProcess::NotRunning) {
        if (cancel.load(std::memory_order_relaxed)) {
            p.kill();
            p.waitForFinished(3000);
            QFile::remove(destPath);
            Outcome o;
            o.cancelled = true;
            return o;
        }
        p.waitForReadyRead(100);
        consume(p.readAll());
    }
    consume(p.readAll());
    if (!pending.isEmpty())
        consume("\n");

    Outcome o;
    if (p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0
        && QFileInfo(destPath).size() > 0) {
        o.ok = true;
        if (onFraction)
            onFraction(1.0);
        return o;
    }
    QFile::remove(destPath);
    o.error = !lastDiagnostic.isEmpty()
                  ? lastDiagnostic
                  : QStringLiteral("ffmpeg exited with code %1").arg(p.exitCode());
    return o;
}

} // namespace

Outcome convert(const QString &ffmpegPath, const QString &srcPath, const QString &destPath,
                qint64 durationMs, const std::atomic<bool> &cancel,
                const std::function<void(double)> &onFraction)
{
    QElapsedTimer timer;
    timer.start();
    Outcome o = runOnce(ffmpegPath, srcPath, destPath, durationMs, /*withCover=*/true,
                        cancel, onFraction);

    // A cover that ffmpeg can't map/copy fails right at initialisation. Retry
    // once without it so the track still converts (just without a cover). A
    // failure later than that is a decode/disk problem, not the cover, and a
    // second attempt would only double the wasted time.
    // If both attempts fail, the second one's message is the one reported: with
    // no cover mapping involved it names the audio problem ("Invalid data found
    // when processing input"), where the first only says "nothing was written".
    if (!o.ok && !o.cancelled && timer.elapsed() < 3000)
        o = runOnce(ffmpegPath, srcPath, destPath, durationMs, /*withCover=*/false,
                    cancel, onFraction);
    return o;
}

} // namespace Mp3Converter
