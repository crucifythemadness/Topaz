#include "systemvolumecontroller.h"

#include <QtGlobal>
#include <QDebug>
#include <QMetaObject>

#ifdef Q_OS_WIN
#include <windows.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>

// Well-known, stable Microsoft-published GUIDs, hardcoded rather than
// relying on __uuidof() (an MSVC extension with inconsistent coverage on
// MinGW) or on linking uuid.lib via -DINITGUID — keeps this dependency-free,
// matching the rest of this codebase's avoidance of extra link-time deps.
// Each one was cross-checked against Microsoft's published values and (for
// IAudioEndpointVolumeCallback) the actual mingw-w64 endpointvolume.h source.
static const CLSID kClsidMMDeviceEnumerator = {
    0xBCDE0395, 0xE52F, 0x467C, { 0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E }
};
static const IID kIidIMMDeviceEnumerator = {
    0xA95664D2, 0x9614, 0x4F35, { 0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6 }
};
static const IID kIidIAudioEndpointVolume = {
    0x5CDF2C82, 0x841E, 0x4546, { 0x97, 0x22, 0x0C, 0xF7, 0x40, 0x78, 0x22, 0x9A }
};
static const IID kIidIAudioEndpointVolumeCallback = {
    0x657804FA, 0xD6AD, 0x4496, { 0x8A, 0x60, 0x35, 0x27, 0x52, 0xAF, 0x4F, 0x89 }
};
static const IID kIidIUnknown = {
    0x00000000, 0x0000, 0x0000, { 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 }
};

// ── VolumeChangeCallback ──────────────────────────────────────────────────
// Minimal IAudioEndpointVolumeCallback implementation. OnNotify() is invoked
// by the audio engine on one of its own internal worker threads — never the
// GUI thread that owns SystemVolumeController — so it must not touch
// SystemVolumeController's state directly. It instead posts to the owner via
// QMetaObject::invokeMethod(owner, lambda, Qt::QueuedConnection): passing the
// owner as the context object makes Qt automatically marshal the call onto
// the owner's own thread, and automatically (silently) drop it if the owner
// is destroyed before the queued call runs — exactly the safety this needs,
// with no manual bookkeeping beyond that.
class VolumeChangeCallback : public IAudioEndpointVolumeCallback
{
public:
    explicit VolumeChangeCallback(SystemVolumeController *owner) : m_owner(owner) {}

    // IUnknown
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppvObject) override
    {
        if (!ppvObject) return E_POINTER;
        if (riid == kIidIUnknown || riid == kIidIAudioEndpointVolumeCallback) {
            *ppvObject = static_cast<IAudioEndpointVolumeCallback *>(this);
            AddRef();
            return S_OK;
        }
        *ppvObject = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override
    {
        return ULONG(m_refCount.fetchAndAddOrdered(1) + 1);
    }
    ULONG STDMETHODCALLTYPE Release() override
    {
        const ULONG remaining = ULONG(m_refCount.fetchAndAddOrdered(-1) - 1);
        if (remaining == 0) delete this;
        return remaining;
    }

    // IAudioEndpointVolumeCallback
    HRESULT STDMETHODCALLTYPE OnNotify(PAUDIO_VOLUME_NOTIFICATION_DATA pNotify) override
    {
        if (!pNotify) return S_OK;
        const float level = pNotify->fMasterVolume;
        const bool  muted = pNotify->bMuted != FALSE;
        QMetaObject::invokeMethod(
            m_owner, [owner = m_owner, level, muted]() {
                owner->applyLevel(level);
                owner->applyMute(muted);
            },
            Qt::QueuedConnection);
        return S_OK;
    }

private:
    SystemVolumeController *m_owner;
    QAtomicInt m_refCount{1};
};

struct SystemVolumeController::Impl
{
    bool comInitialized = false; // only true if this instance's CoInitializeEx call
                                  // actually succeeded (not RPC_E_CHANGED_MODE) — only
                                  // then does this instance own a matching CoUninitialize.
    IMMDeviceEnumerator    *enumerator     = nullptr;
    IMMDevice              *device         = nullptr;
    IAudioEndpointVolume   *endpointVolume = nullptr;
    VolumeChangeCallback   *callback       = nullptr;
};

SystemVolumeController::SystemVolumeController(QObject *parent)
    : QObject(parent), m_impl(new Impl)
{
    // RPC_E_CHANGED_MODE (COM already initialized on this thread with a
    // different concurrency model, e.g. by Qt itself) is a failure HRESULT,
    // so SUCCEEDED() already excludes it — COM is still usable in that case,
    // this instance just didn't add its own reference, so it must not call
    // CoUninitialize() later.
    const HRESULT initHr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    m_impl->comInitialized = SUCCEEDED(initHr);

    HRESULT hr = CoCreateInstance(kClsidMMDeviceEnumerator, nullptr, CLSCTX_ALL,
                                   kIidIMMDeviceEnumerator,
                                   reinterpret_cast<void **>(&m_impl->enumerator));
    if (FAILED(hr) || !m_impl->enumerator) {
        qWarning("SystemVolumeController: CoCreateInstance(MMDeviceEnumerator) failed, hr=0x%08lX", hr);
        return;
    }

    hr = m_impl->enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &m_impl->device);
    if (FAILED(hr) || !m_impl->device) {
        qWarning("SystemVolumeController: GetDefaultAudioEndpoint failed, hr=0x%08lX", hr);
        return;
    }

    hr = m_impl->device->Activate(kIidIAudioEndpointVolume, CLSCTX_ALL, nullptr,
                                   reinterpret_cast<void **>(&m_impl->endpointVolume));
    if (FAILED(hr) || !m_impl->endpointVolume) {
        qWarning("SystemVolumeController: IMMDevice::Activate(IAudioEndpointVolume) failed, hr=0x%08lX", hr);
        return;
    }

    float level = 0.0f;
    hr = m_impl->endpointVolume->GetMasterVolumeLevelScalar(&level);
    if (SUCCEEDED(hr))
        applyLevel(level);
    else
        qWarning("SystemVolumeController: GetMasterVolumeLevelScalar failed, hr=0x%08lX", hr);

    BOOL mute = FALSE;
    hr = m_impl->endpointVolume->GetMute(&mute);
    if (SUCCEEDED(hr))
        applyMute(mute != FALSE);
    else
        qWarning("SystemVolumeController: GetMute failed, hr=0x%08lX", hr);

    // Live sync: get notified of any future change to this endpoint's
    // volume, from any source (see the class doc comment in the header).
    m_impl->callback = new VolumeChangeCallback(this);
    hr = m_impl->endpointVolume->RegisterControlChangeNotify(m_impl->callback);
    if (FAILED(hr))
        qWarning("SystemVolumeController: RegisterControlChangeNotify failed, hr=0x%08lX", hr);
}

SystemVolumeController::~SystemVolumeController()
{
    if (m_impl->endpointVolume && m_impl->callback)
        m_impl->endpointVolume->UnregisterControlChangeNotify(m_impl->callback);
    if (m_impl->callback)       m_impl->callback->Release();
    if (m_impl->endpointVolume) m_impl->endpointVolume->Release();
    if (m_impl->device)         m_impl->device->Release();
    if (m_impl->enumerator)     m_impl->enumerator->Release();
    if (m_impl->comInitialized) CoUninitialize();
    delete m_impl;
}

void SystemVolumeController::applyLevel(float level)
{
    const int v = qBound(0, qRound(level * 100.0f), 100);
    if (v == m_volume) return;
    m_volume = v;
    emit volumeChanged();
}

void SystemVolumeController::refresh()
{
    if (!m_impl->endpointVolume) return;
    float level = 0.0f;
    HRESULT hr = m_impl->endpointVolume->GetMasterVolumeLevelScalar(&level);
    if (SUCCEEDED(hr))
        applyLevel(level);
    else
        qWarning("SystemVolumeController: refresh()'s GetMasterVolumeLevelScalar failed, hr=0x%08lX", hr);

    BOOL mute = FALSE;
    hr = m_impl->endpointVolume->GetMute(&mute);
    if (SUCCEEDED(hr))
        applyMute(mute != FALSE);
    else
        qWarning("SystemVolumeController: refresh()'s GetMute failed, hr=0x%08lX", hr);
}

void SystemVolumeController::applyMute(bool muted)
{
    if (muted == m_muted) return;
    m_muted = muted;
    emit mutedChanged();
}

void SystemVolumeController::setMuted(bool m)
{
    if (m == m_muted) return;
    m_muted = m;                        // optimistic, like setVolume()
    if (m_impl->endpointVolume) {
        const HRESULT hr = m_impl->endpointVolume->SetMute(m ? TRUE : FALSE, nullptr);
        if (FAILED(hr))
            qWarning("SystemVolumeController: SetMute failed, hr=0x%08lX", hr);
    } else {
        qWarning("SystemVolumeController: setMuted() called but no IAudioEndpointVolume "
                 "available (construction-time COM setup failed) — OS mute not changed");
    }
    emit mutedChanged();
}

void SystemVolumeController::setVolume(int v)
{
    v = qBound(0, v, 100);
    if (v == m_volume) return;
    m_volume = v;
    if (m_impl->endpointVolume) {
        const HRESULT hr =
            m_impl->endpointVolume->SetMasterVolumeLevelScalar(float(v) / 100.0f, nullptr);
        if (FAILED(hr))
            qWarning("SystemVolumeController: SetMasterVolumeLevelScalar failed, hr=0x%08lX", hr);
    } else {
        qWarning("SystemVolumeController: setVolume() called but no IAudioEndpointVolume "
                 "available (construction-time COM setup failed) — OS volume not changed");
    }
    emit volumeChanged();
}

#else  // Linux

#include <QByteArray>
#include <QElapsedTimer>
#include <QTimer>

#include <pulse/pulseaudio.h>

// Linux implementation -- a native libpulse client, the counterpart of the
// Windows Core Audio one above. It talks to PulseAudio, and to PipeWire
// through its pulseaudio-compatible server (pipewire-pulse), so it needs no
// external tool. (The first Linux version shelled out to `pactl`: no live
// sync, a blocking process spawn per call, and a hard dependency on that
// binary.)
//
// Threading: pa_threaded_mainloop runs libpulse on its own thread. Every
// libpulse callback executes on that thread with the mainloop lock held, so a
// callback never touches Qt state directly -- like the Windows
// IAudioEndpointVolumeCallback it posts to the owner with
// QMetaObject::invokeMethod(owner, ..., Qt::QueuedConnection), which marshals
// onto the GUI thread and drops the call if the owner is already gone. In the
// other direction, the GUI thread takes pa_threaded_mainloop_lock() before it
// touches the context or the fields marked "loop lock" below. Nothing on the
// GUI thread ever waits for a server reply: setVolume()/refresh() only send a
// request, and the answer comes back through the same callback path.
//
// Flow: connect -> on READY subscribe to SINK + SERVER events and ask for the
// server info -> its default sink name -> that sink's info (index + volume).
// A SERVER event (the default sink was switched) repeats that lookup; a SINK
// event for our sink re-reads its volume. That is the live push-sync.
struct SystemVolumeController::Impl
{
    Impl() { pa_cvolume_init(&volume); }

    SystemVolumeController *owner = nullptr;
    pa_threaded_mainloop   *loop  = nullptr;

    // ---- loop lock ----
    pa_context  *ctx       = nullptr;
    uint32_t     sinkIndex = PA_INVALID_INDEX; // the default sink we follow
    pa_cvolume   volume;                       // its last known per-channel volume
    bool         haveVolume = false;
    bool         shuttingDown = false;
    bool         warnedNoSink = false;         // one warning per outage, not per slider step
    bool         warnedLost   = false;         // same for connection failures / retries

    // ---- GUI thread only ----
    QElapsedTimer sinceLocalSet;   // echo suppression, see applyServerLevel()
    QElapsedTimer sinceLocalMute;  // same for the mute state, see applyServerMute()
    bool          reconnectPending = false;
};

// Holds the static libpulse callbacks. Named like the Windows COM callback
// class because the header already declares that name a friend (needed for the
// private applyLevel()); on Linux it simply plays the same role.
class VolumeChangeCallback
{
public:
    static constexpr int kEchoSuppressMs = 250;
    static constexpr int kReconnectDelayMs = 3000;

    // Creates and connects a fresh context. Caller holds the loop lock (or the
    // loop is not started yet). PA_CONTEXT_NOFAIL: if the server isn't up yet
    // (PipeWire session still starting, PulseAudio launched later by another
    // app) libpulse keeps waiting for it instead of failing. NOAUTOSPAWN:
    // Topaz must never start a sound server just to read a volume.
    static bool connectContext(SystemVolumeController *self)
    {
        auto *d = self->m_impl;
        pa_mainloop_api *api = pa_threaded_mainloop_get_api(d->loop);
        d->ctx = pa_context_new(api, "Topaz");
        if (!d->ctx) {
            qWarning("SystemVolumeController: pa_context_new failed -- OS volume unavailable");
            return false;
        }
        pa_context_set_state_callback(d->ctx, &onState, self);
        if (pa_context_connect(d->ctx, nullptr,
                               pa_context_flags_t(PA_CONTEXT_NOFAIL | PA_CONTEXT_NOAUTOSPAWN),
                               nullptr) < 0) {
            if (!d->warnedLost) {
                d->warnedLost = true;
                qWarning("SystemVolumeController: pa_context_connect failed (%s) -- OS volume unavailable",
                         pa_strerror(pa_context_errno(d->ctx)));
            }
            pa_context_unref(d->ctx);
            d->ctx = nullptr;
            return false;
        }
        return true;
    }

    // Detaches and releases the current context. Caller holds the loop lock.
    static void dropContext(SystemVolumeController *self)
    {
        auto *d = self->m_impl;
        if (!d->ctx) return;
        // Cleared first so the disconnect below doesn't call back into us.
        pa_context_set_state_callback(d->ctx, nullptr, nullptr);
        pa_context_set_subscribe_callback(d->ctx, nullptr, nullptr);
        pa_context_disconnect(d->ctx);
        pa_context_unref(d->ctx);
        d->ctx = nullptr;
        d->sinkIndex = PA_INVALID_INDEX;
        d->haveVolume = false;
    }

    // GUI thread. Rebuilds the connection after the server went away.
    static void reconnect(SystemVolumeController *self)
    {
        auto *d = self->m_impl;
        d->reconnectPending = false;
        pa_threaded_mainloop_lock(d->loop);
        if (!d->shuttingDown) {
            dropContext(self);
            connectContext(self);
        }
        pa_threaded_mainloop_unlock(d->loop);
    }

    // Loop thread.
    static void onState(pa_context *c, void *ud)
    {
        auto *self = static_cast<SystemVolumeController *>(ud);
        auto *d = self->m_impl;
        if (d->shuttingDown || c != d->ctx) return;

        switch (pa_context_get_state(c)) {
        case PA_CONTEXT_READY: {
            pa_context_set_subscribe_callback(c, &onSubscribe, self);
            if (pa_operation *op = pa_context_subscribe(
                    c, pa_subscription_mask_t(PA_SUBSCRIPTION_MASK_SINK | PA_SUBSCRIPTION_MASK_SERVER),
                    nullptr, nullptr))
                pa_operation_unref(op);
            requestServerInfo(self);
            break;
        }
        case PA_CONTEXT_FAILED:
        case PA_CONTEXT_TERMINATED:
            if (!d->warnedLost) {   // once per outage, not once per retry
                d->warnedLost = true;
                qWarning("SystemVolumeController: PulseAudio connection lost (%s) -- retrying every %d s",
                         pa_strerror(pa_context_errno(c)), kReconnectDelayMs / 1000);
            }
            // A delay, so a persistent failure can't turn into a tight loop.
            QMetaObject::invokeMethod(self, [self]() {
                auto *impl = self->m_impl;
                if (impl->reconnectPending) return;
                impl->reconnectPending = true;
                QTimer::singleShot(kReconnectDelayMs, self, [self]() { reconnect(self); });
            }, Qt::QueuedConnection);
            break;
        default:
            break;
        }
    }

    // Loop thread.
    static void onSubscribe(pa_context *c, pa_subscription_event_type_t t, uint32_t idx, void *ud)
    {
        auto *self = static_cast<SystemVolumeController *>(ud);
        auto *d = self->m_impl;
        if (d->shuttingDown || c != d->ctx) return;

        const unsigned facility = t & PA_SUBSCRIPTION_EVENT_FACILITY_MASK;
        const unsigned type     = t & PA_SUBSCRIPTION_EVENT_TYPE_MASK;

        if (facility == PA_SUBSCRIPTION_EVENT_SERVER) {
            requestServerInfo(self);          // default sink may have changed
        } else if (facility == PA_SUBSCRIPTION_EVENT_SINK && idx == d->sinkIndex) {
            if (type == PA_SUBSCRIPTION_EVENT_REMOVE) {
                d->sinkIndex = PA_INVALID_INDEX; // our sink is gone; find the new default
                d->haveVolume = false;
                requestServerInfo(self);
            } else if (pa_operation *op = pa_context_get_sink_info_by_index(c, idx, &onSinkInfo, self)) {
                pa_operation_unref(op);
            }
        }
    }

    // Loop thread (or any thread holding the loop lock).
    static void requestServerInfo(SystemVolumeController *self)
    {
        auto *d = self->m_impl;
        if (!d->ctx) return;
        if (pa_operation *op = pa_context_get_server_info(d->ctx, &onServerInfo, self))
            pa_operation_unref(op);
    }

    // Loop thread.
    static void onServerInfo(pa_context *c, const pa_server_info *info, void *ud)
    {
        auto *self = static_cast<SystemVolumeController *>(ud);
        auto *d = self->m_impl;
        if (d->shuttingDown || c != d->ctx || !info) return;

        if (!info->default_sink_name || !*info->default_sink_name) {
            qWarning("SystemVolumeController: the audio server reports no default sink");
            return;
        }
        if (pa_operation *op = pa_context_get_sink_info_by_name(c, info->default_sink_name,
                                                                &onSinkInfo, self))
            pa_operation_unref(op);
    }

    // Loop thread.
    static void onSinkInfo(pa_context *c, const pa_sink_info *info, int eol, void *ud)
    {
        auto *self = static_cast<SystemVolumeController *>(ud);
        auto *d = self->m_impl;
        if (d->shuttingDown || c != d->ctx) return;
        if (eol < 0) {
            qWarning("SystemVolumeController: sink query failed (%s)", pa_strerror(pa_context_errno(c)));
            return;
        }
        if (eol > 0 || !info) return;

        // The loudest channel is "the" volume (as in GNOME's mixer), matching
        // setVolume(), whose pa_cvolume_scale() also sets the loudest channel:
        // read and write agree, so an unbalanced sink doesn't make the slider
        // jump on the next refresh.
        const float level = float(double(pa_cvolume_max(&info->volume)) / double(PA_VOLUME_NORM));
        if (d->sinkIndex != info->index)
            qInfo("SystemVolumeController: following PulseAudio sink \"%s\" (%d%%)",
                  info->name, qRound(level * 100.0f));
        d->sinkIndex  = info->index;
        d->volume     = info->volume;
        d->haveVolume = true;
        d->warnedNoSink = false;
        d->warnedLost   = false;

        // Level and mute are applied independently: an echo-suppressed level
        // report must not swallow a real mute change riding along with it.
        const bool muted = info->mute != 0;
        QMetaObject::invokeMethod(self, [self, level, muted]() {
            applyServerLevel(self, level);
            applyServerMute(self, muted);
        }, Qt::QueuedConnection);
    }

    // GUI thread. A change reported by the server. Reports that arrive right
    // after our own setVolume() are the echoes of the slider drag itself
    // (38, 39, 40 ... trailing behind a slider that is already at 41) and
    // would make the slider jump back and forth, so they're ignored: the
    // value we just set is the truth. Everything later -- keyboard volume
    // keys, the panel applet, another app -- goes through applyLevel().
    static void applyServerLevel(SystemVolumeController *self, float level)
    {
        auto *d = self->m_impl;
        if (d->sinceLocalSet.isValid() && d->sinceLocalSet.elapsed() < kEchoSuppressMs)
            return;
        self->applyLevel(level);
    }

    // GUI thread. Same idea for the mute state: a report that was already
    // under way when the user clicked the mute button still carries the old
    // state and would flip the button straight back, so reports arriving
    // right after our own setMuted() are ignored.
    static void applyServerMute(SystemVolumeController *self, bool muted)
    {
        auto *d = self->m_impl;
        if (d->sinceLocalMute.isValid() && d->sinceLocalMute.elapsed() < kEchoSuppressMs)
            return;
        self->applyMute(muted);
    }
};

SystemVolumeController::SystemVolumeController(QObject *parent)
    : QObject(parent), m_impl(new Impl)
{
    m_impl->owner = this;
    m_impl->loop = pa_threaded_mainloop_new();
    if (!m_impl->loop) {
        qWarning("SystemVolumeController: pa_threaded_mainloop_new failed -- OS volume unavailable");
        return;
    }
    if (pa_threaded_mainloop_start(m_impl->loop) < 0) {
        qWarning("SystemVolumeController: pa_threaded_mainloop_start failed -- OS volume unavailable");
        pa_threaded_mainloop_free(m_impl->loop);
        m_impl->loop = nullptr;
        return;
    }
    // The answer (initial volume) arrives asynchronously via the callbacks
    // and lands in volume() a moment after construction.
    pa_threaded_mainloop_lock(m_impl->loop);
    VolumeChangeCallback::connectContext(this);
    pa_threaded_mainloop_unlock(m_impl->loop);
}

SystemVolumeController::~SystemVolumeController()
{
    if (m_impl->loop) {
        pa_threaded_mainloop_lock(m_impl->loop);
        m_impl->shuttingDown = true;
        VolumeChangeCallback::dropContext(this);
        pa_threaded_mainloop_unlock(m_impl->loop);
        pa_threaded_mainloop_stop(m_impl->loop);   // joins the loop thread: no callback can run after this
        pa_threaded_mainloop_free(m_impl->loop);
    }
    delete m_impl;
}

void SystemVolumeController::applyLevel(float level)
{
    const int v = qBound(0, qRound(level * 100.0f), 100);
    if (v == m_volume) return;
    m_volume = v;
    emit volumeChanged();
}

void SystemVolumeController::refresh()
{
    if (!m_impl->loop) return;
    // Non-blocking: only asks. The reply comes back through onSinkInfo() /
    // onServerInfo() and lands in volume() via a queued call.
    pa_threaded_mainloop_lock(m_impl->loop);
    if (m_impl->ctx && pa_context_get_state(m_impl->ctx) == PA_CONTEXT_READY) {
        if (m_impl->sinkIndex != PA_INVALID_INDEX) {
            if (pa_operation *op = pa_context_get_sink_info_by_index(
                    m_impl->ctx, m_impl->sinkIndex, &VolumeChangeCallback::onSinkInfo, this))
                pa_operation_unref(op);
        } else {
            VolumeChangeCallback::requestServerInfo(this);
        }
    }
    pa_threaded_mainloop_unlock(m_impl->loop);
}

void SystemVolumeController::setVolume(int v)
{
    v = qBound(0, v, 100);
    if (v == m_volume) return;
    m_volume = v;                      // optimistic, as on Windows
    m_impl->sinceLocalSet.restart();

    bool sent = false;
    if (m_impl->loop) {
        pa_threaded_mainloop_lock(m_impl->loop);
        if (m_impl->ctx && pa_context_get_state(m_impl->ctx) == PA_CONTEXT_READY
            && m_impl->sinkIndex != PA_INVALID_INDEX && m_impl->haveVolume
            && pa_cvolume_valid(&m_impl->volume)) {
            // Scaling (not setting every channel) keeps a left/right balance
            // the user configured elsewhere; an all-zero sink gets every
            // channel set to the new level (pa_cvolume_scale's own rule).
            pa_cvolume cv = m_impl->volume;
            pa_cvolume_scale(&cv, pa_volume_t(qRound64(double(v) / 100.0 * double(PA_VOLUME_NORM))));
            m_impl->volume = cv;
            if (pa_operation *op = pa_context_set_sink_volume_by_index(
                    m_impl->ctx, m_impl->sinkIndex, &cv, nullptr, nullptr)) {
                pa_operation_unref(op);
                sent = true;
            }
        }
        if (!sent && !m_impl->warnedNoSink) {
            m_impl->warnedNoSink = true;
            qWarning("SystemVolumeController: setVolume() found no connected PulseAudio/PipeWire "
                     "default sink -- OS volume not changed");
        }
        pa_threaded_mainloop_unlock(m_impl->loop);
    }
    emit volumeChanged();
}

void SystemVolumeController::applyMute(bool muted)
{
    if (muted == m_muted) return;
    m_muted = muted;
    emit mutedChanged();
}

void SystemVolumeController::setMuted(bool m)
{
    if (m == m_muted) return;
    m_muted = m;                       // optimistic, as on Windows
    m_impl->sinceLocalMute.restart();

    bool sent = false;
    if (m_impl->loop) {
        pa_threaded_mainloop_lock(m_impl->loop);
        if (m_impl->ctx && pa_context_get_state(m_impl->ctx) == PA_CONTEXT_READY
            && m_impl->sinkIndex != PA_INVALID_INDEX) {
            if (pa_operation *op = pa_context_set_sink_mute_by_index(
                    m_impl->ctx, m_impl->sinkIndex, m ? 1 : 0, nullptr, nullptr)) {
                pa_operation_unref(op);
                sent = true;
            }
        }
        if (!sent && !m_impl->warnedNoSink) {
            m_impl->warnedNoSink = true;
            qWarning("SystemVolumeController: setMuted() found no connected PulseAudio/PipeWire "
                     "default sink -- OS mute not changed");
        }
        pa_threaded_mainloop_unlock(m_impl->loop);
    }
    emit mutedChanged();
}

#endif
