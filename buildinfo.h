#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>

// ── BuildInfo ─────────────────────────────────────────────────────────────
// Exposes compile-time build metadata to QML for the About Topaz dialog.
// Not a singleton — instantiated directly where needed (AboutDialog.qml),
// matching this codebase's convention of instantiating C++ logic objects
// once at their point of use rather than introducing a QML-singleton pattern
// for a value only one dialog needs.
//
// version()   — CMake's own project version (see CMakeLists.txt's
//               project(Topaz VERSION ...) and the matching
//               target_compile_definitions(... TOPAZ_VERSION_STRING=...)).
// buildDate() — the C++ __DATE__ macro, i.e. whatever date this translation
//               unit was actually compiled — auto-updates every build with
//               no manual upkeep.
class BuildInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString version   READ version   CONSTANT)
    Q_PROPERTY(QString buildDate READ buildDate CONSTANT)

public:
    explicit BuildInfo(QObject *parent = nullptr) : QObject(parent) {}

    QString version()   const;
    QString buildDate() const;
};
