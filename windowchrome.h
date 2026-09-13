#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QQuickWindow>

// Full QQuickWindow header (not a forward declaration) required here — same
// reasoning as AutoPlayController's header comment: Qt6's automatic
// QMetaType registration for a pointer parameter type (here, the
// removeAccentBorder(QQuickWindow*) Q_INVOKABLE parameter) needs the
// pointed-to type to be complete wherever the metaobject code is compiled
// (AUTOMOC's combined mocs_compilation.cpp), not just forward-declared.

// ── WindowChrome ──────────────────────────────────────────────────────────
// Tiny singleton utility that prepares a FloatingPane's underlying native
// window (see FloatingPane.qml) for genuine per-pixel transparency and strips
// OS-drawn chrome, in the one order that actually works on Windows:
//
// 1. Request an alpha-capable surface format BEFORE the native window is
//    created. Qt6's default hardware-rendering (RHI/D3D11) backend on
//    Windows does NOT reliably negotiate window-level alpha compositing from
//    a QML `color` binding with alpha alone — confirmed both empirically
//    (AudioVisualizerWindow's audioVisualizerPaneOpacity read back as 0 but
//    the pane still rendered fully opaque) and via known reports of the same
//    issue (Qt Forum: "Qt5 -> Qt6 partial window transparency",
//    "Translucent background not rendering correctly in Qt6 with hardware
//    rendering"). Once the native window is created, its surface format is
//    fixed — setting `color` with alpha afterward has no effect on whether
//    the window *can* composite as translucent, only on what it draws once
//    it already can.
// 2. Explicitly create() the window now, with that format.
// 3. Only then call DwmSetWindowAttribute() to suppress Windows 11's default
//    per-window DWM accent border, which needs a real HWND and stays visible
//    around ANY top-level window (frameless or not) since Windows 11 build
//    22000, independent of the window's own content.
//
// QML_SINGLETON since this has no per-pane state — every FloatingPane
// instance calls the same stateless prepareWindow(this) from its own
// Component.onCompleted, applying to every pane in the family (harmless for
// BigCoverWindow/TagInfoWindow, which are always fully opaque — an unused
// alpha channel changes nothing visually for them).
//
// Steps 1-2 (alpha surface format + create()) are plain cross-platform
// QQuickWindow/QSurfaceFormat calls and run on every platform. Only step 3
// (the actual DwmSetWindowAttribute() call) is guarded behind #ifdef
// Q_OS_WIN in windowchrome.cpp -- a no-op on Linux, since most window
// managers there don't draw this kind of per-window accent border anyway.
// Same guarding approach as SystemVolumeController (see the
// future_linux_port note in project memory) -- Linux port step 1.
//
// Used from FloatingPane.qml as:
//   Component.onCompleted: WindowChrome.prepareWindow(pane)
class WindowChrome : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit WindowChrome(QObject *parent = nullptr);

    // Must be called before anything else touches the window's native state
    // (before the window is shown, and before any other code forces native
    // creation via winId()/show()) — see the class comment for why the order
    // (format -> create -> DWM border removal) is load-bearing. No-op if
    // window is null; logs via qWarning (does not throw/crash) if the DWM
    // border-removal step fails, e.g. on pre-Windows-11 systems.
    Q_INVOKABLE void prepareWindow(QQuickWindow *window);
};
