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
// qtVersion() — the Qt version Topaz is running with (qVersion(), the
//               runtime library — normally the build version too); shown on
//               the About dialog's POWERED BY → Qt details page.
// topazLines() / thirdPartyLines() — non-blank lines of code of Topaz itself and
//               of the vendored KISS FFT + miniz sources, from codestats.h
//               (written once per release by tools/count-loc.ps1).
class BuildInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString version   READ version   CONSTANT)
    Q_PROPERTY(QString buildDate READ buildDate CONSTANT)
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)
    Q_PROPERTY(int topazLines      READ topazLines      CONSTANT)
    Q_PROPERTY(int thirdPartyLines READ thirdPartyLines CONSTANT)

public:
    explicit BuildInfo(QObject *parent = nullptr) : QObject(parent) {}

    QString version()   const;
    QString buildDate() const;
    QString qtVersion() const;
    int topazLines() const;
    int thirdPartyLines() const;
};
