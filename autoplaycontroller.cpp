#include "autoplaycontroller.h"
#include "appconfig.h"
#include "librarymodel.h"
#include "playbackengine.h"

#include <QRandomGenerator>
#include <QApplication>
#include <QStyle>

AutoPlayController::AutoPlayController(QObject *parent)
    : QObject(parent)
{
    m_pollTimer = new QTimer(this);
    connect(m_pollTimer, &QTimer::timeout, this, &AutoPlayController::onPollTick);

    // Checked once here (not re-checked per notification): tray availability
    // doesn't change during a run in any way this app needs to react to.
    m_trayAvailable = QSystemTrayIcon::isSystemTrayAvailable();
    if (m_trayAvailable) {
        // app.ico is bundled via CMakeLists.txt's qt_add_qml_module RESOURCES
        // app.ico, which places it under the module's plain URI prefix
        // (/Topaz/) — a different, simpler prefix than QML_FILES get
        // (:/qt/qml/Topaz/), confirmed from the generated
        // build/.qt/rcc/topaz_raw_res_0.qrc.
        QIcon icon(QStringLiteral(":/Topaz/app.ico"));
        if (icon.isNull()) {
            // Defensive fallback so a future resource-path mistake degrades
            // to "wrong-looking icon" rather than silently killing the tray
            // icon (and with it every notification) again.
            icon = QApplication::style()->standardIcon(QStyle::SP_MediaPlay);
        }
        m_trayIcon = new QSystemTrayIcon(icon, this);
        m_trayIcon->setToolTip(QStringLiteral("Topaz"));
        m_trayIcon->show();
    }
}

void AutoPlayController::showTrayMessage(const QString &title, const QString &message)
{
    if (!m_trayAvailable || !m_trayIcon) return;
    m_trayIcon->showMessage(title, message, QSystemTrayIcon::Information, 5000);
}

bool AutoPlayController::manualQueueEditingAllowed() const
{
    return !m_active || (m_appConfig && m_appConfig->autoPlayAllowManualModification());
}

bool AutoPlayController::genreRequirementMet() const
{
    if (!m_appConfig || !m_appConfig->autoPlayConsiderGenre()) return true;
    return !m_activeGenreNames.isEmpty();
}

bool AutoPlayController::playPauseAllowed() const
{
    if (!m_active || manualQueueEditingAllowed()) return true;
    if (!m_appConfig) return false;
    const QString mode = m_appConfig->autoPlayTransportAccess();
    return mode == QStringLiteral("playPause") || mode == QStringLiteral("playPauseAndSelect");
}

bool AutoPlayController::trackNavigationAllowed() const
{
    if (!m_active || manualQueueEditingAllowed()) return true;
    if (!m_appConfig) return false;
    return m_appConfig->autoPlayTransportAccess() == QStringLiteral("playPauseAndSelect");
}

void AutoPlayController::setEngine(PlaybackEngine *engine)
{
    if (m_engine == engine) return;
    if (m_engine) m_engine->disconnect(this);
    m_engine = engine;
    if (m_engine) {
        connect(m_engine, &PlaybackEngine::trackPlayedToCompletion,
                this, &AutoPlayController::onTrackPlayedToCompletion);
        connect(m_engine, &PlaybackEngine::queueExhausted,
                this, &AutoPlayController::onQueueExhausted);
    }
    emit engineChanged();
}

void AutoPlayController::setLibraryModel(LibraryModel *model)
{
    if (m_libraryModel == model) return;
    m_libraryModel = model;
    emit libraryModelChanged();
}

void AutoPlayController::setAppConfig(AppConfig *cfg)
{
    if (m_appConfig == cfg) return;
    if (m_appConfig) m_appConfig->disconnect(this);
    m_appConfig = cfg;
    if (m_appConfig) {
        // A live interval change must take effect immediately: restart the
        // timer (which both changes its interval and resets the countdown)
        // whenever a session is currently running.
        connect(m_appConfig, &AppConfig::autoPlayTitleAddingIntervalSecondsChanged,
                this, [this]() { if (m_active) restartPollTimerFromConfig(); });
        connect(m_appConfig, &AppConfig::autoPlayAllowManualModificationChanged,
                this, &AutoPlayController::manualQueueEditingAllowedChanged);
        connect(m_appConfig, &AppConfig::autoPlayAllowManualModificationChanged,
                this, &AutoPlayController::playPauseAllowedChanged);
        connect(m_appConfig, &AppConfig::autoPlayAllowManualModificationChanged,
                this, &AutoPlayController::trackNavigationAllowedChanged);
        connect(m_appConfig, &AppConfig::autoPlayConsiderGenreChanged,
                this, &AutoPlayController::genreRequirementMetChanged);
        connect(m_appConfig, &AppConfig::autoPlayTransportAccessChanged,
                this, &AutoPlayController::playPauseAllowedChanged);
        connect(m_appConfig, &AppConfig::autoPlayTransportAccessChanged,
                this, &AutoPlayController::trackNavigationAllowedChanged);
    }
    emit appConfigChanged();
    emit manualQueueEditingAllowedChanged();
    emit genreRequirementMetChanged();
    emit playPauseAllowedChanged();
    emit trackNavigationAllowedChanged();
}

void AutoPlayController::setActiveGenreNames(const QStringList &names)
{
    if (m_activeGenreNames == names) return;
    m_activeGenreNames = names;
    emit activeGenreNamesChanged();
    emit genreRequirementMetChanged();
}

void AutoPlayController::toggle()
{
    if (m_active) stop(false);
    else          start();
}

void AutoPlayController::clearQueueAndHistory()
{
    m_playCounts.clear();
    if (m_engine) m_engine->clearQueue();
}

void AutoPlayController::start()
{
    if (m_active || !m_engine || !m_appConfig || !m_libraryModel) return;
    if (!genreRequirementMet()) return;

    m_playCounts.clear();   // fresh history for this session

    if (m_engine->queueCount() == 0) {
        const QVariantMap candidate = pickNextCandidate();
        if (candidate.isEmpty()) return;   // nothing to play at all — stay inactive
        m_engine->addTrack(candidate);     // auto-plays since the queue was empty
    }

    m_active = true;
    emit activeChanged();
    emit manualQueueEditingAllowedChanged();
    emit queueClearAllowedChanged();
    emit playPauseAllowedChanged();
    emit trackNavigationAllowedChanged();
    showTrayMessage(QStringLiteral("AUTO PLAY"), QStringLiteral("Activated"));

    restartPollTimerFromConfig();
}

void AutoPlayController::stop(bool starved)
{
    if (!m_active) return;
    m_pollTimer->stop();
    m_active = false;
    emit activeChanged();
    emit manualQueueEditingAllowedChanged();
    emit queueClearAllowedChanged();
    emit playPauseAllowedChanged();
    emit trackNavigationAllowedChanged();
    if (starved) {
        emit this->starved();
        showTrayMessage(QStringLiteral("AUTO PLAY starvation"),
                         QStringLiteral("There are no more suitable tracks available"));
    } else {
        showTrayMessage(QStringLiteral("AUTO PLAY"), QStringLiteral("Deactivated"));
    }
}

void AutoPlayController::restartPollTimerFromConfig()
{
    if (!m_appConfig) return;
    const int secs = qMax(1, m_appConfig->autoPlayTitleAddingIntervalSeconds());
    m_pollTimer->start(secs * 1000);
}

void AutoPlayController::onPollTick()
{
    if (!m_active) return;
    maybeFillHorizon();
}

void AutoPlayController::maybeFillHorizon()
{
    if (!m_active || !m_engine || !m_appConfig) return;

    // Tracks-ahead, not raw queueCount(): the queue never shrinks on natural
    // playback (only manual removeAt/clearQueue do), so already-played rows
    // must not count against the horizon.
    const int ahead = m_engine->queueCount() - m_engine->currentIndex() - 1;
    if (ahead >= m_appConfig->autoPlayQueueHorizon()) return;

    const QVariantMap candidate = pickNextCandidate();
    if (candidate.isEmpty()) {
        stop(true);   // starving — no eligible track found
        return;
    }
    m_engine->addTrack(candidate);
}

void AutoPlayController::onTrackPlayedToCompletion(const QString &filePath)
{
    if (filePath.isEmpty()) return;
    m_playCounts[filePath] = m_playCounts.value(filePath, 0) + 1;
}

void AutoPlayController::onQueueExhausted()
{
    if (!m_active || !m_engine) return;

    const QVariantMap candidate = pickNextCandidate();
    if (candidate.isEmpty()) {
        stop(true);
        return;
    }
    m_engine->addTrack(candidate);
    m_engine->playAt(m_engine->queueCount() - 1);
}

QVariantMap AutoPlayController::pickNextCandidate() const
{
    if (!m_libraryModel || !m_appConfig || !m_engine) return {};

    const QVariantList pool = m_libraryModel->autoPlayCandidatePool(
        m_activeGenreNames,
        m_appConfig->autoPlayConsiderGenre(),
        m_appConfig->autoPlayConsiderRating(),
        m_appConfig->autoPlayMinimumRating());
    if (pool.isEmpty()) return {};

    // Each track's effective occurrence count for the repeat-mode cap is
    // completed plays (m_playCounts, updated only on natural completion) PLUS
    // every occurrence of it in the queue from the currently-playing position
    // onward (the now-playing row itself, and anything still queued ahead) —
    // each such occurrence represents a play that either is happening right
    // now or is guaranteed to happen once reached. This is what stops "once"
    // from re-selecting the track that's playing at this very moment, and
    // "twice" from queuing a third copy of something already queued twice
    // ahead, without a separate hard exclusion for either case.
    QHash<QString, int> queueOccurrences;
    const QVariantList queued = m_engine->trackList();
    const int curIdx = m_engine->currentIndex();
    for (int i = qMax(0, curIdx); i < queued.size(); ++i) {
        const QString p = queued.at(i).toMap().value(QStringLiteral("filePath")).toString();
        if (!p.isEmpty())
            queueOccurrences[p] = queueOccurrences.value(p, 0) + 1;
    }

    const QString mode = m_appConfig->autoPlaySongRepeat();

    QList<QVariantMap> eligible;
    QList<QVariantMap> fallbackEligible;   // "twiceIfNoneAvailable" only

    for (const QVariant &v : pool) {
        const QVariantMap tm = v.toMap();
        const QString path = tm.value(QStringLiteral("filePath")).toString();

        const int effectiveCount = m_playCounts.value(path, 0) + queueOccurrences.value(path, 0);

        if (mode == QStringLiteral("once")) {
            if (effectiveCount == 0) eligible.append(tm);
        } else if (mode == QStringLiteral("twice")) {
            if (effectiveCount < 2) eligible.append(tm);
        } else if (mode == QStringLiteral("twiceIfNoneAvailable")) {
            if (effectiveCount == 0) eligible.append(tm);
            else if (effectiveCount == 1) fallbackEligible.append(tm);
        } else { // "several" — no repeat-count cap at all
            eligible.append(tm);
        }
    }

    if (eligible.isEmpty() && mode == QStringLiteral("twiceIfNoneAvailable"))
        eligible = fallbackEligible;

    if (eligible.isEmpty()) return {};

    // Always random — every track-adding path funnels through this function,
    // so selection is never deterministic/library-ordered anywhere.
    const int idx = QRandomGenerator::global()->bounded(eligible.size());
    return eligible.at(idx);
}
