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
        QMetaObject::invokeMethod(
            m_owner, [owner = m_owner, level]() { owner->applyLevel(level); },
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
    const HRESULT hr = m_impl->endpointVolume->GetMasterVolumeLevelScalar(&level);
    if (SUCCEEDED(hr))
        applyLevel(level);
    else
        qWarning("SystemVolumeController: refresh()'s GetMasterVolumeLevelScalar failed, hr=0x%08lX", hr);
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

#include <QProcess>
#include <QRegularExpression>

// Linux implementation -- controls the OS master volume via the `pactl`
// CLI tool (ships with PulseAudio and with modern PipeWire's pulseaudio-
// compatible layer, so this covers both) rather than linking libpulse
// directly. A deliberate first-pass simplification -- see the
// future_linux_port project memory: revisit with a native libpulse client
// (real async live-sync, no text parsing, no external-binary dependency)
// after the first successful test on an actual Linux machine.
//
// No live push notifications when something OUTSIDE Topaz changes the
// volume (the Windows build's RegisterControlChangeNotify equivalent) --
// refresh() re-queries on demand instead, which TopBar.qml already calls
// right before the volume popup opens, so the displayed value is correct
// at the point the user actually looks at it.
struct SystemVolumeController::Impl {};

namespace {

QString defaultSinkName()
{
    QProcess proc;
    proc.start(QStringLiteral("pactl"), { QStringLiteral("get-default-sink") });
    if (!proc.waitForFinished(1000) || proc.exitCode() != 0)
        return QString();
    return QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
}

// Parses the first "NN%" occurrence out of `pactl get-sink-volume`'s
// output. Multi-channel volumes are reported per-channel, but Topaz's
// slider (like Windows' master volume) treats it as a single scalar, so
// the first channel's percentage stands in for all of them -- correct for
// typical symmetric stereo output.
bool queryVolumePercent(const QString &sinkName, int *outPercent)
{
    QProcess proc;
    proc.start(QStringLiteral("pactl"),
               { QStringLiteral("get-sink-volume"), sinkName });
    if (!proc.waitForFinished(1000) || proc.exitCode() != 0)
        return false;
    const QString output = QString::fromUtf8(proc.readAllStandardOutput());
    static const QRegularExpression re(QStringLiteral("(\\d+)%"));
    const QRegularExpressionMatch m = re.match(output);
    if (!m.hasMatch())
        return false;
    *outPercent = m.captured(1).toInt();
    return true;
}

} // namespace

SystemVolumeController::SystemVolumeController(QObject *parent)
    : QObject(parent), m_impl(new Impl)
{
    refresh();
}

SystemVolumeController::~SystemVolumeController()
{
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
    const QString sink = defaultSinkName();
    if (sink.isEmpty()) {
        qWarning() << "SystemVolumeController: pactl get-default-sink failed "
                       "(pactl not installed, or no default sink) -- volume unavailable";
        return;
    }
    int percent = 0;
    if (!queryVolumePercent(sink, &percent)) {
        qWarning() << "SystemVolumeController: pactl get-sink-volume failed for sink" << sink;
        return;
    }
    applyLevel(float(percent) / 100.0f);
}

void SystemVolumeController::setVolume(int v)
{
    v = qBound(0, v, 100);
    if (v == m_volume) return;
    m_volume = v;
    const QString sink = defaultSinkName();
    if (sink.isEmpty()) {
        qWarning() << "SystemVolumeController: setVolume() found no default sink -- OS volume not changed";
        emit volumeChanged();
        return;
    }
    // Fire-and-forget, matching the Windows build's own optimistic-UI
    // behavior: m_volume/volumeChanged() are already updated above
    // regardless of whether the OS call itself succeeds.
    QProcess::startDetached(QStringLiteral("pactl"),
        { QStringLiteral("set-sink-volume"), sink, QStringLiteral("%1%").arg(v) });
    emit volumeChanged();
}

#endif
