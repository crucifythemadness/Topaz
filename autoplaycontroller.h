#pragma once

#include "appconfig.h"
#include "librarymodel.h"
#include "playbackengine.h"

#include <QObject>
#include <QQmlEngine>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QTimer>

// Full headers (not forward declarations) are required here, not just for our
// own Q_PROPERTY pointer types: Qt6's Q_PROPERTY(SomeClass* ...) requires
// SomeClass to be a complete type wherever it's registered, and AUTOMOC's
// combined mocs_compilation.cpp concatenates every moc_*.cpp in alphabetical
// order — "autoplaycontroller" sorts before "librarymodel"/"playbackengine",
// so relying on their own headers being pulled in later by their own moc
// files is not safe. Including them directly here removes the ordering
// dependency entirely.

// ── AutoPlayController ────────────────────────────────────────────────────
// Owns all AUTO PLAY policy: candidate selection (genre/rating/repeat-mode
// filtering), the queue-horizon polling timer, the in-memory play-history,
// starvation detection, and the manual-queue-editing gating rules. Depends on
// PlaybackEngine + LibraryModel + AppConfig; none of those classes know this
// one exists, keeping PlaybackEngine a pure playback engine and LibraryModel
// a pure library index. See UC-16 in the architecture doc for the full
// session lifecycle and selection algorithm.
//
// Instantiated once in Main.qml:
//   AutoPlayController {
//       id: autoPlay
//       engine: engine; libraryModel: libraryModel; appConfig: appConfig
//       activeGenreNames: lib.activeGenreNames
//   }
class AutoPlayController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(PlaybackEngine* engine      READ engine      WRITE setEngine      NOTIFY engineChanged)
    Q_PROPERTY(LibraryModel*   libraryModel READ libraryModel WRITE setLibraryModel NOTIFY libraryModelChanged)
    Q_PROPERTY(AppConfig*      appConfig    READ appConfig    WRITE setAppConfig    NOTIFY appConfigChanged)
    // Bound from LibraryData.qml's `activeGenreNames` — the live source of
    // truth for which genres are toggled on in GenreBar.
    Q_PROPERTY(QStringList activeGenreNames READ activeGenreNames WRITE setActiveGenreNames NOTIFY activeGenreNamesChanged)

    // True while an AUTO PLAY session is running (the footer button is red).
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    // Whether the user may currently add/remove/reorder tracks in the queue —
    // always true outside an active session (MANUAL MODE); during a session,
    // follows AppConfig::autoPlayAllowManualModification.
    Q_PROPERTY(bool manualQueueEditingAllowed READ manualQueueEditingAllowed NOTIFY manualQueueEditingAllowedChanged)
    // Whether the queue's CLEAR button may be used — always false during an
    // active session regardless of manualQueueEditingAllowed, true otherwise.
    Q_PROPERTY(bool queueClearAllowed READ queueClearAllowed NOTIFY queueClearAllowedChanged)
    // Whether the genre criterion for starting a session is satisfied: always
    // true when Consider Genre is off; otherwise requires at least one active
    // genre. Gates BottomBar's AUTO PLAY button (grey when false) in addition
    // to the existing autoPlayReady/ratingsReady gate.
    Q_PROPERTY(bool genreRequirementMet READ genreRequirementMet NOTIFY genreRequirementMetChanged)

public:
    explicit AutoPlayController(QObject *parent = nullptr);

    PlaybackEngine *engine()      const { return m_engine; }
    LibraryModel   *libraryModel() const { return m_libraryModel; }
    AppConfig      *appConfig()    const { return m_appConfig; }
    QStringList     activeGenreNames() const { return m_activeGenreNames; }

    bool active() const { return m_active; }
    bool manualQueueEditingAllowed() const;
    bool queueClearAllowed() const { return !m_active; }
    bool genreRequirementMet() const;

    void setEngine(PlaybackEngine *engine);
    void setLibraryModel(LibraryModel *model);
    void setAppConfig(AppConfig *cfg);
    void setActiveGenreNames(const QStringList &names);

    // Toggled by BottomBar's AUTO PLAY button click. Starts a session if
    // inactive (or does nothing if the queue is empty and no track in the
    // whole library currently qualifies), stops one if active.
    Q_INVOKABLE void toggle();

    // Routes the queue's CLEAR button: clears the play-history in lockstep
    // with clearing the queue itself (only reachable when queueClearAllowed).
    Q_INVOKABLE void clearQueueAndHistory();

signals:
    void engineChanged();
    void libraryModelChanged();
    void appConfigChanged();
    void activeGenreNamesChanged();
    void activeChanged();
    void manualQueueEditingAllowedChanged();
    void queueClearAllowedChanged();
    void genreRequirementMetChanged();
    // Emitted only when a session stops because no eligible track could be
    // found (as opposed to the user clicking the button off themselves).
    void starved();

private slots:
    void onTrackPlayedToCompletion(const QString &filePath);
    void onQueueExhausted();
    void onPollTick();

private:
    void start();
    void stop(bool starved);
    void restartPollTimerFromConfig();
    // Adds exactly one track if tracks-ahead is under the configured horizon;
    // stops the session (starved) if under horizon but no candidate exists.
    // Called only from onPollTick() — additions beyond the initial
    // empty-queue kickstart always happen strictly on the polling cadence,
    // never immediately when the session starts or when the user edits the
    // queue mid-session.
    void maybeFillHorizon();
    // Genre/rating/repeat-mode/already-queued filtering; returns an empty
    // map if nothing qualifies. Random selection among whatever remains.
    QVariantMap pickNextCandidate() const;

    PlaybackEngine *m_engine       = nullptr;
    LibraryModel   *m_libraryModel = nullptr;
    AppConfig      *m_appConfig    = nullptr;
    QStringList     m_activeGenreNames;

    bool    m_active = false;
    QTimer *m_pollTimer = nullptr;

    // filePath -> number of times fully played to completion this session.
    QHash<QString, int> m_playCounts;
};
