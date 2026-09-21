#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>

// QApplication (not QGuiApplication) is required here even though Topaz is a
// QML-only UI: QSystemTrayIcon (used by AutoPlayController for AUTO PLAY
// activate/deactivate/starvation notifications) lives in QtWidgets and needs
// a QApplication instance to function.
int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    // Pins the config/cache directory (QStandardPaths::AppConfigLocation) and
    // the X11 WM_CLASS to "Topaz" regardless of the executable's filename.
    // Without this Qt derives the name from the binary: "Topaz" on Windows
    // (Topaz.exe -- so setting it here changes nothing there), but "topaz-bin"
    // on Linux, where the deployed binary is renamed to avoid colliding with
    // the Topaz/ QML-module directory on case-insensitive filesystems.
    app.setApplicationName(QStringLiteral("Topaz"));

#ifndef Q_OS_WIN
    // Windows takes its icon from the app.rc-embedded resource; Linux has no
    // equivalent, so set it at runtime (window icon on X11; needs the
    // matching topaz.desktop, see packaging/linux/, for the Wayland app_id).
    app.setWindowIcon(QIcon(QStringLiteral(":/Topaz/app.ico")));
    app.setDesktopFileName(QStringLiteral("topaz"));
#endif

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("Topaz", "Main");

    return app.exec();
    
}
