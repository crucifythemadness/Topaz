#include "windowchrome.h"

#include <QGuiApplication>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QSurfaceFormat>
#include <QDebug>

#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>

namespace {
// DWMWA_BORDER_COLOR / DWMWA_COLOR_NONE, hardcoded rather than relied upon as
// header-defined enum names — both are Windows 11 (build 22000+) additions
// that mingw-w64's bundled dwmapi.h may predate, same defensive reasoning as
// SystemVolumeController's hardcoded COM GUIDs elsewhere in this codebase.
// Values confirmed against Microsoft's published DWMWINDOWATTRIBUTE docs:
// DWMWA_BORDER_COLOR = 34; DWMWA_COLOR_NONE (0xFFFFFFFE) "suppress[es] the
// drawing of the window border."
constexpr DWORD    kDwmwaBorderColor = 34;
constexpr COLORREF kDwmwaColorNone   = 0xFFFFFFFE;
}
#endif

WindowChrome::WindowChrome(QObject *parent)
    : QObject(parent)
{
}

void WindowChrome::prepareWindow(QQuickWindow *window)
{
    if (!window) return;

    // Step 1: request an alpha-capable surface BEFORE the native window
    // exists. Must happen before anything (including step 2 below) forces
    // creation — once created, the format is locked in, and a QML `color`
    // binding with alpha from that point on only controls what's drawn, not
    // whether the window can composite as translucent at all.
    QSurfaceFormat fmt = window->format();
    fmt.setAlphaBufferSize(8);
    window->setFormat(fmt);

    // Step 2: create the native window now, with that format.
    window->create();

    // One-shot terminal diagnostics for "the pane opens but nothing is drawn"
    // reports (seen on X11/NVIDIA): what platform this is, whether the native
    // window actually got the alpha channel requested above, which graphics API
    // the scene graph ended up on, and any scene graph failure. window->format()
    // after create() is the format actually granted, not the one requested.
    qInfo() << "WindowChrome: platform" << QGuiApplication::platformName()
            << "| alpha buffer requested 8, granted" << window->format().alphaBufferSize();
    QObject::connect(window, &QQuickWindow::sceneGraphInitialized, window, [window]() {
        const QSGRendererInterface *ri = window->rendererInterface();
        const char *api = "unknown";
        if (ri) {
            switch (ri->graphicsApi()) {
            case QSGRendererInterface::Software:    api = "Software";    break;
            case QSGRendererInterface::OpenGL:      api = "OpenGL";      break;
            case QSGRendererInterface::Direct3D11:  api = "Direct3D11";  break;
            case QSGRendererInterface::Vulkan:      api = "Vulkan";      break;
            case QSGRendererInterface::Metal:       api = "Metal";       break;
            case QSGRendererInterface::Null:        api = "Null";        break;
            default: break;
            }
        }
        qInfo() << "WindowChrome: scene graph initialized, graphics API" << api;
    });
    QObject::connect(window, &QQuickWindow::sceneGraphError, window,
                     [](QQuickWindow::SceneGraphError, const QString &message) {
        qWarning() << "WindowChrome: scene graph error:" << message;
    });

#ifdef Q_OS_WIN
    // Step 3: only now does a real HWND exist to remove Windows 11's default
    // per-window DWM accent border, drawn around any top-level window since
    // build 22000 regardless of content or frameless status. No Linux
    // equivalent needed -- most Linux window managers don't add this kind
    // of per-window accent border in the first place.
    const HWND hwnd = reinterpret_cast<HWND>(window->winId());
    if (!hwnd) return;

    const HRESULT hr = DwmSetWindowAttribute(hwnd, kDwmwaBorderColor,
                                              &kDwmwaColorNone, sizeof(kDwmwaColorNone));
    if (FAILED(hr))
        qWarning() << "WindowChrome: DwmSetWindowAttribute(DWMWA_BORDER_COLOR) failed, hr =" << hr;
#endif
}
