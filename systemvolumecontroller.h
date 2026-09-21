#pragma once

#include <QObject>
#include <QQmlEngine>

// ── SystemVolumeController ────────────────────────────────────────────────
// Controls the OS master output volume (not Topaz's own playback level —
// that's QAudioOutput::setVolume(), used only internally for crossfade
// ramping). Qt has no cross-platform API for this, so the .cpp implements
// it per-platform behind an #ifdef Q_OS_WIN split: on Windows, the Core
// Audio IAudioEndpointVolume COM interface directly (with live push-sync
// via IAudioEndpointVolumeCallback — see below); on Linux, a native libpulse
// client (PulseAudio, and PipeWire through its pulseaudio-compatible server)
// on a pa_threaded_mainloop, with the same live push-sync via libpulse's
// sink/server subscription events, and without any external tool.
//
// All Windows/COM and libpulse headers are kept out of this header, behind a
// private PIMPL in the .cpp — <windows.h>-family headers define macros
// (interface, min, max) that can clash with Qt/STL if leaked into every file
// that includes this one. Impl's shape differs per-platform since only
// systemvolumecontroller.cpp itself ever touches it.
//
// volume() is seeded from the OS's actual current volume at construction
// time, so the first value a bound QML Slider sees already reflects "what
// the OS actually has" at startup. refresh() re-seeds it on demand (called
// right before the QML volume popup opens, in case the OS volume changed
// elsewhere while Topaz was already running). Beyond that, volume() also
// stays live-synced for the rest of the session: an IAudioEndpointVolumeCallback
// is registered with the endpoint, so any external change — another app,
// Windows' own volume UI, or hardware volume controls that route through the
// OS volume model — updates this property too, without the user needing to
// reopen the popup. (Whether a *specific* piece of external hardware routes
// through the OS volume model at all is outside Windows' or Topaz's control —
// some pro-audio interfaces do pure analog attenuation that never touches it.)
//
// The one simplification kept on Windows: the default audio endpoint is only
// resolved once, at construction; a mid-session default-device change (e.g.
// the user switches their default output device in Windows Settings) won't be
// picked up. A IMMNotificationClient/OnDefaultDeviceChanged registration would
// handle that, but that's a distinct concern from volume-level sync and
// wasn't asked for. The Linux client does follow the default sink, and
// reconnects if the sound server restarts. On Linux the initial volume arrives
// asynchronously a moment after construction (nothing blocks the GUI thread);
// mute state is not mirrored on either platform.
//
// Instantiated once in Main.qml:
//   SystemVolumeController { id: systemVolume }
class VolumeChangeCallback; // defined in the .cpp: the COM callback on Windows, the static libpulse callbacks on Linux

class SystemVolumeController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Needs to call the private applyLevel() from OnNotify() (see the .cpp) —
    // that method is intentionally not public since it's only meant to be
    // reached via the constructor, refresh(), or this callback.
    friend class VolumeChangeCallback;

    // 0-100, mirrors the OS master volume. Seeded from the OS at
    // construction. READ-only property (no WRITE clause) with a separate
    // Q_INVOKABLE setter, matching AppConfig's convention elsewhere in this
    // codebase — a property's WRITE function is only wired into the
    // obj.prop = value assignment mechanism, not exposed as a directly
    // callable obj.setVolume(x) method from QML unless it's independently
    // Q_INVOKABLE (a real bug caught here: the call silently did nothing).
    Q_PROPERTY(int volume READ volume NOTIFY volumeChanged)

public:
    explicit SystemVolumeController(QObject *parent = nullptr);
    ~SystemVolumeController() override;

    int volume() const { return m_volume; }
    Q_INVOKABLE void setVolume(int v);

    // Re-reads the OS's current volume and updates this property if it
    // changed. Called from TopBar.qml right before the volume popup opens.
    Q_INVOKABLE void refresh();

signals:
    void volumeChanged();

private:
    // Applies a 0.0-1.0 scalar level read from the OS (during construction,
    // refresh(), or asynchronously from the IAudioEndpointVolumeCallback —
    // see the .cpp) — updates m_volume and emits volumeChanged() only if the
    // rounded 0-100 value actually changed. The callback path always reaches
    // this via QMetaObject::invokeMethod(this, ..., Qt::QueuedConnection),
    // since OnNotify fires on an internal audio-engine thread, not this
    // object's own (GUI) thread, and this method is not thread-safe to call
    // directly from elsewhere.
    void applyLevel(float level);

    struct Impl;
    Impl *m_impl;

    int m_volume = 100;
};
