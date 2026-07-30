#include <QApplication>
#include <QQmlApplicationEngine>

// QApplication (not QGuiApplication) is required here even though Topaz is a
// QML-only UI: QSystemTrayIcon (used by AutoPlayController for AUTO PLAY
// activate/deactivate/starvation notifications) lives in QtWidgets and needs
// a QApplication instance to function.
int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

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
