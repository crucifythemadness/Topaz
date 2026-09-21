#include "cursorautohider.h"

#include <QCoreApplication>
#include <QCursor>
#include <QEvent>
#include <QGuiApplication>
#include <QMouseEvent>

CursorAutoHider::CursorAutoHider(QObject *parent)
    : QObject(parent)
{
    m_idleTimer.setSingleShot(true);
    m_idleTimer.setInterval(m_idleSeconds * 1000);
    connect(&m_idleTimer, &QTimer::timeout, this, &CursorAutoHider::onIdleTimeout);
}

CursorAutoHider::~CursorAutoHider()
{
    if (m_enabled) {
        if (QCoreApplication *app = QCoreApplication::instance())
            app->removeEventFilter(this);
    }
    if (m_hidden)
        QGuiApplication::restoreOverrideCursor();
}

void CursorAutoHider::setEnabled(bool enabled)
{
    if (m_enabled == enabled) return;
    m_enabled = enabled;

    QCoreApplication *app = QCoreApplication::instance();
    if (enabled) {
        m_lastPos = QCursor::pos();
        if (app) app->installEventFilter(this);
        m_idleTimer.start();
    } else {
        if (app) app->removeEventFilter(this);
        m_idleTimer.stop();
        showCursor();
    }
    emit enabledChanged();
}

void CursorAutoHider::setIdleSeconds(int seconds)
{
    seconds = qMax(1, seconds);
    if (m_idleSeconds == seconds) return;
    m_idleSeconds = seconds;
    m_idleTimer.setInterval(m_idleSeconds * 1000);
    if (m_enabled && !m_hidden)
        m_idleTimer.start();
    emit idleSecondsChanged();
}

bool CursorAutoHider::eventFilter(QObject *, QEvent *event)
{
    switch (event->type()) {
    case QEvent::MouseMove: {
        const QPoint pos = static_cast<QMouseEvent *>(event)->globalPosition().toPoint();
        if (pos != m_lastPos) {
            m_lastPos = pos;
            onActivity();
        }
        break;
    }
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonRelease:
    case QEvent::MouseButtonDblClick:
    case QEvent::Wheel:
        onActivity();
        break;
    default:
        break;
    }
    return false;   // observe only, never consume
}

void CursorAutoHider::onActivity()
{
    showCursor();
    m_idleTimer.start();
}

void CursorAutoHider::onIdleTimeout()
{
    if (!m_enabled) return;

    // A held button (a long press or a slow drag) is mouse use, however still
    // the cursor is: keep it visible and check again later.
    if (QGuiApplication::mouseButtons() != Qt::NoButton) {
        m_idleTimer.start();
        return;
    }
    hideCursor();
}

void CursorAutoHider::hideCursor()
{
    if (m_hidden) return;
    QGuiApplication::setOverrideCursor(QCursor(Qt::BlankCursor));
    m_hidden = true;
    emit hiddenChanged();
}

void CursorAutoHider::showCursor()
{
    if (!m_hidden) return;
    QGuiApplication::restoreOverrideCursor();
    m_hidden = false;
    emit hiddenChanged();
}
