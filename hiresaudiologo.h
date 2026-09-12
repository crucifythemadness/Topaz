#pragma once

#include <QObject>
#include <QQmlEngine>

// ── HiResAudioLogo ────────────────────────────────────────────────────────
// Tiny stateless singleton utility, same pattern as WindowChrome (see
// windowchrome.h). "Hi-Res_Audio.svg" is a real, trademarked logo Topaz has
// no rights to redistribute, so it is deliberately NOT bundled as a Qt
// resource / compiled into Topaz.exe (contrast with every other *.svg icon
// in CMakeLists.txt's RESOURCES list). Instead, if the user places their own
// legitimate copy of "Hi-Res_Audio.svg" directly beside the running
// Topaz.exe, this exposes a usable file:// URL for it; otherwise an empty
// string, so TopBar's Hi-Res Audio badge simply never shows -- no bundled
// asset ships with Topaz itself.
//
// Used from TopBar.qml as:  source: HiResAudioLogo.url()
class HiResAudioLogo : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit HiResAudioLogo(QObject *parent = nullptr);

    // "file:///.../Hi-Res_Audio.svg" if that file exists directly beside
    // the running executable (QCoreApplication::applicationDirPath()),
    // otherwise an empty string. Checked fresh on every call (cheap -- one
    // QFileInfo::exists()) rather than cached, so a copy dropped in while
    // Topaz is already running is picked up the next time this is read
    // (e.g. TopBar.qml's badge re-reads it on every track change, since
    // its binding also depends on PlaybackEngine::currentFormat).
    Q_INVOKABLE QString url() const;
};
