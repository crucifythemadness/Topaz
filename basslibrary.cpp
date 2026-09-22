#include "basslibrary.h"

#include <QCoreApplication>
#include <QDebug>
#include <QFile>

#include <string>

BassLibrary &BassLibrary::instance()
{
    static BassLibrary lib;
    return lib;
}

BassLibrary::~BassLibrary()
{
    // Freeing plugins explicitly isn't required -- BASS_Free() frees every
    // loaded plugin along with the output device -- but BASS_Free() itself
    // is worth calling so a clean shutdown doesn't rely purely on process exit.
    if (m_loaded && BASS_Free)
        BASS_Free();
}

template <typename Fn>
bool BassLibrary::resolve(Fn &fn, const char *name)
{
    fn = reinterpret_cast<Fn>(m_bass.resolve(name));
    return fn != nullptr;
}

bool BassLibrary::load()
{
    if (m_loaded) return true;

    const QString dir = QCoreApplication::applicationDirPath();
#if defined(_WIN32)
    m_bass.setFileName(dir + QStringLiteral("/bass.dll"));
#else
    m_bass.setFileName(dir + QStringLiteral("/libbass.so"));
#endif
    if (!m_bass.load()) {
        qWarning() << "BassLibrary: failed to load" << m_bass.fileName()
                    << "-" << m_bass.errorString();
        return false;
    }

    bool ok = true;
    ok &= resolve(BASS_Init, "BASS_Init");
    ok &= resolve(BASS_Free, "BASS_Free");
    ok &= resolve(BASS_PluginLoad, "BASS_PluginLoad");
    ok &= resolve(BASS_PluginFree, "BASS_PluginFree");
    ok &= resolve(BASS_StreamCreateFile, "BASS_StreamCreateFile");
    ok &= resolve(BASS_StreamFree, "BASS_StreamFree");
    ok &= resolve(BASS_ChannelPlay, "BASS_ChannelPlay");
    ok &= resolve(BASS_ChannelPause, "BASS_ChannelPause");
    ok &= resolve(BASS_ChannelStop, "BASS_ChannelStop");
    ok &= resolve(BASS_ChannelGetPosition, "BASS_ChannelGetPosition");
    ok &= resolve(BASS_ChannelSetPosition, "BASS_ChannelSetPosition");
    ok &= resolve(BASS_ChannelGetLength, "BASS_ChannelGetLength");
    ok &= resolve(BASS_ChannelBytes2Seconds, "BASS_ChannelBytes2Seconds");
    ok &= resolve(BASS_ChannelSeconds2Bytes, "BASS_ChannelSeconds2Bytes");
    ok &= resolve(BASS_ChannelIsActive, "BASS_ChannelIsActive");
    ok &= resolve(BASS_ChannelSetAttribute, "BASS_ChannelSetAttribute");
    ok &= resolve(BASS_ChannelSetSync, "BASS_ChannelSetSync");
    ok &= resolve(BASS_ErrorGetCode, "BASS_ErrorGetCode");
    ok &= resolve(BASS_ChannelGetInfo, "BASS_ChannelGetInfo");
    ok &= resolve(BASS_ChannelGetData, "BASS_ChannelGetData");
    if (!ok) {
        qWarning() << "BassLibrary: bass.dll is missing one or more expected exports";
        m_bass.unload();
        return false;
    }

    if (!BASS_Init(-1, 44100, 0, nullptr, nullptr)) {
        qWarning() << "BassLibrary: BASS_Init failed, error code" << BASS_ErrorGetCode();
        m_bass.unload();
        return false;
    }

#if defined(_WIN32)
    // BASS_UNICODE tells BASS_PluginLoad() the filename is UTF-16 (WCHAR*)
    // rather than ANSI -- applicationDirPath() isn't guaranteed ASCII-safe.
    const std::wstring flacPath = (dir + QStringLiteral("/bassflac.dll")).toStdWString();
    const std::wstring opusPath = (dir + QStringLiteral("/bassopus.dll")).toStdWString();
    if (!BASS_PluginLoad(flacPath.c_str(), BASS_UNICODE))
        qWarning() << "BassLibrary: failed to load bassflac.dll plugin, error code" << BASS_ErrorGetCode();
    if (!BASS_PluginLoad(opusPath.c_str(), BASS_UNICODE))
        qWarning() << "BassLibrary: failed to load bassopus.dll plugin, error code" << BASS_ErrorGetCode();
#else
    // Non-Windows BASS takes plain UTF-8 filenames -- no BASS_UNICODE
    // equivalent exists there. QFile::encodeName matches the platform's
    // actual filesystem encoding.
    const QByteArray flacPath = QFile::encodeName(dir + QStringLiteral("/libbassflac.so"));
    const QByteArray opusPath = QFile::encodeName(dir + QStringLiteral("/libbassopus.so"));
    if (!BASS_PluginLoad(flacPath.constData(), 0))
        qWarning() << "BassLibrary: failed to load libbassflac.so plugin, error code" << BASS_ErrorGetCode();
    if (!BASS_PluginLoad(opusPath.constData(), 0))
        qWarning() << "BassLibrary: failed to load libbassopus.so plugin, error code" << BASS_ErrorGetCode();
#endif

    // Optional effect exports (see basslibrary.h) -- deliberately not part of
    // `ok` above.
    resolve(BASS_ChannelSetFX, "BASS_ChannelSetFX");
    resolve(BASS_ChannelRemoveFX, "BASS_ChannelRemoveFX");
    resolve(BASS_FXSetParameters, "BASS_FXSetParameters");
    resolve(BASS_ChannelGetAttribute, "BASS_ChannelGetAttribute");

    m_loaded = true;
    return true;
}

bool BassLibrary::loadFx()
{
    if (m_fxLoaded) return true;
    if (!m_loaded) return false;
    if (!BASS_ChannelSetFX || !BASS_ChannelRemoveFX || !BASS_FXSetParameters) {
        qWarning() << "BassLibrary: bass.dll lacks the effect exports -- compressor unavailable";
        return false;
    }

    const QString dir = QCoreApplication::applicationDirPath();
#if defined(_WIN32)
    m_bassFx.setFileName(dir + QStringLiteral("/bass_fx.dll"));
#else
    m_bassFx.setFileName(dir + QStringLiteral("/libbass_fx.so"));
#endif
    if (!m_bassFx.load()) {
        // Retried on every request (the user may drop the file in while
        // Topaz runs), but only reported once per process.
        if (!m_fxWarned) {
            m_fxWarned = true;
            qWarning() << "BassLibrary: failed to load" << m_bassFx.fileName()
                        << "-" << m_bassFx.errorString();
        }
        return false;
    }

    // bass_fx registers its BFX effect types with BASS when it is initialised;
    // calling its version export makes sure that has happened (bass_fx.h: the
    // documented way to force the library to load) and proves the library
    // really is BASS_FX before any effect is requested from it.
    using GetVersionFn = BASS_DWORD (BASSCALL *)();
    auto getVersion = reinterpret_cast<GetVersionFn>(m_bassFx.resolve("BASS_FX_GetVersion"));
    if (!getVersion) {
        qWarning() << "BassLibrary: bass_fx has no BASS_FX_GetVersion export -- ignoring it";
        m_bassFx.unload();
        return false;
    }
    qInfo("BassLibrary: BASS_FX %08lX loaded", static_cast<unsigned long>(getVersion()));
    m_fxLoaded = true;
    return true;
}
