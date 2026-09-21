#pragma once

#include <QObject>
#include <QPoint>
#include <QQmlEngine>
#include <QTimer>

// ── CursorAutoHider ───────────────────────────────────────────────────────
// Hides the mouse cursor application-wide once it has been idle for
// `idleSeconds` (default 5) while `enabled`, and shows it again the moment the
// mouse is used. Main.qml enables it exactly while Topaz is fullscreen (F11 or
// "Start Topaz in Full Screen"), so the cursor doesn't sit over the artwork on
// a kiosk/party display.
//
// Why C++: QML has no global cursor override, and a per-item `cursorShape`
// can't work for the main window -- dozens of items set their own (pointing
// hand on buttons, ...) and an overlay MouseArea would swallow clicks. Hiding
// is QGuiApplication::setOverrideCursor(Qt::BlankCursor), which covers every
// Topaz window (main window, all panes, dialogs) and overrides every item's own
// cursorShape.
//
// Idle detection is an application-wide event filter, installed only while
// enabled (no per-event cost otherwise), watching mouse move / button / wheel
// events on any Topaz window. It never consumes an event. A MouseMove only
// counts if the global position actually changed, so Qt's synthesized hover
// re-deliveries on a stationary cursor don't keep re-showing it.
//
// Independent of (and compatible with) Milkdrop's own F10 idle-hide
// (FloatingPane.cursorHidden): both blank the cursor and both undo it on mouse
// movement.
class CursorAutoHider : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // WRITE only so a QML binding can drive it (`enabled: <expression>`).
    Q_PROPERTY(bool enabled     READ enabled     WRITE setEnabled     NOTIFY enabledChanged)
    Q_PROPERTY(int  idleSeconds READ idleSeconds WRITE setIdleSeconds NOTIFY idleSecondsChanged)
    // True while the cursor is currently hidden by this object.
    Q_PROPERTY(bool hidden      READ hidden                           NOTIFY hiddenChanged)

public:
    explicit CursorAutoHider(QObject *parent = nullptr);
    ~CursorAutoHider() override;

    bool enabled()     const { return m_enabled;     }
    int  idleSeconds() const { return m_idleSeconds; }
    bool hidden()      const { return m_hidden;      }

    // Turning it off (or destroying the object) restores the cursor at once.
    void setEnabled(bool enabled);
    // Clamped to >= 1.
    void setIdleSeconds(int seconds);

signals:
    void enabledChanged();
    void idleSecondsChanged();
    void hiddenChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void onActivity();
    void onIdleTimeout();
    void hideCursor();
    void showCursor();

    bool   m_enabled     = false;
    int    m_idleSeconds = 5;
    // Whether THIS object currently has a BlankCursor override pushed. Keeps
    // the QGuiApplication override stack balanced: never pushed twice, always
    // popped on disable/destruction.
    bool   m_hidden      = false;
    QPoint m_lastPos;
    QTimer m_idleTimer;
};
