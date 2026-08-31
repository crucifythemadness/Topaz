#pragma once

#include <QLibrary>
#include <QString>

// Minimal, hand-declared subset of BASS's stable public C ABI (from bass.h,
// see https://www.un4seen.com/) needed by BassAudioDeck -- an interface
// description, not a copy of BASS's source or binary. bass.dll itself is
// never bundled with Topaz (see UC-15); the user downloads and places it
// (and bassflac.dll/bassopus.dll) next to Topaz.exe themselves.
//
// All BASS entry points and callbacks use the __stdcall calling convention
// on Windows (BASSCALL below), matching bass.h.
#if defined(_WIN32)
#define BASSCALL __stdcall
#else
#define BASSCALL
#endif

using BASS_DWORD  = unsigned long;
using BASS_QWORD  = unsigned long long;
// HSTREAM/HPLUGIN/HSYNC are all just DWORD-sized opaque handles in bass.h.
using BASS_HANDLE = unsigned long;
using BASS_BOOL   = int;

typedef void (BASSCALL *BassSyncProc)(BASS_HANDLE handle, BASS_DWORD channel, BASS_DWORD data, void *user);

// Only freq/chans are actually used (by BassAudioDeck's buffer tap, see
// UC-15 "Step 3") -- stable, unchanged since BASS 2.0.
struct BASS_CHANNELINFO {
    BASS_DWORD  freq;
    BASS_DWORD  chans;
    BASS_DWORD  flags;
    BASS_DWORD  ctype;
    BASS_DWORD  origres;
    BASS_HANDLE plugin;
    BASS_HANDLE sample;
    const char *filename;
};

// ── BASS constants (bass.h) ─────────────────────────────────────────────────
inline constexpr BASS_DWORD BASS_UNICODE        = 0x80000000u;
inline constexpr BASS_DWORD BASS_POS_BYTE       = 0;
inline constexpr BASS_DWORD BASS_ACTIVE_PLAYING = 1;
inline constexpr BASS_DWORD BASS_ATTRIB_VOL     = 2;
inline constexpr BASS_DWORD BASS_SYNC_END       = 2;
// ORed into BASS_ChannelGetData()'s length parameter -- makes BASS hand back
// float samples regardless of the stream's own native format. See UC-15
// "Step 3" / BassAudioDeck's buffer tap.
inline constexpr BASS_DWORD BASS_DATA_FLOAT     = 0x40000000u;

// ── BassLibrary ───────────────────────────────────────────────────────────
// Runtime loader (QLibrary) for bass.dll, resolved next to Topaz.exe -- never
// linked at build time (see AppConfig::bassLibraryAvailable(), UC-15).
// Singleton: BASS_Init()/PluginLoad() only need to happen once per process.
// load() is idempotent -- safe to call every time createDecksIfNeeded()
// considers BASS; returns true immediately once already loaded.
class BassLibrary
{
public:
    static BassLibrary &instance();

    // Loads bass.dll, resolves every function pointer below, calls
    // BASS_Init(-1, 44100, 0, nullptr, nullptr), then BASS_PluginLoad() for
    // bassflac.dll/bassopus.dll (both next to the executable, registered as
    // BASS *plugins* -- not separate APIs to call directly -- so
    // BASS_StreamCreateFile() transparently handles FLAC/Opus afterward).
    // Returns false if bass.dll itself can't be loaded/resolved or
    // BASS_Init() fails; a plugin individually failing to load is only
    // logged, not fatal.
    bool load();
    bool isLoaded() const { return m_loaded; }

    BASS_BOOL   (BASSCALL *BASS_Init)(int device, BASS_DWORD freq, BASS_DWORD flags, void *win, const void *clsid) = nullptr;
    BASS_BOOL   (BASSCALL *BASS_Free)() = nullptr;
    BASS_HANDLE (BASSCALL *BASS_PluginLoad)(const void *file, BASS_DWORD flags) = nullptr;
    BASS_BOOL   (BASSCALL *BASS_PluginFree)(BASS_HANDLE handle) = nullptr;
    BASS_HANDLE (BASSCALL *BASS_StreamCreateFile)(BASS_BOOL mem, const void *file, BASS_QWORD offset, BASS_QWORD length, BASS_DWORD flags) = nullptr;
    BASS_BOOL   (BASSCALL *BASS_StreamFree)(BASS_HANDLE handle) = nullptr;
    BASS_BOOL   (BASSCALL *BASS_ChannelPlay)(BASS_HANDLE handle, BASS_BOOL restart) = nullptr;
    BASS_BOOL   (BASSCALL *BASS_ChannelPause)(BASS_HANDLE handle) = nullptr;
    BASS_BOOL   (BASSCALL *BASS_ChannelStop)(BASS_HANDLE handle) = nullptr;
    BASS_QWORD  (BASSCALL *BASS_ChannelGetPosition)(BASS_HANDLE handle, BASS_DWORD mode) = nullptr;
    BASS_BOOL   (BASSCALL *BASS_ChannelSetPosition)(BASS_HANDLE handle, BASS_QWORD pos, BASS_DWORD mode) = nullptr;
    BASS_QWORD  (BASSCALL *BASS_ChannelGetLength)(BASS_HANDLE handle, BASS_DWORD mode) = nullptr;
    double      (BASSCALL *BASS_ChannelBytes2Seconds)(BASS_HANDLE handle, BASS_QWORD pos) = nullptr;
    BASS_QWORD  (BASSCALL *BASS_ChannelSeconds2Bytes)(BASS_HANDLE handle, double pos) = nullptr;
    BASS_DWORD  (BASSCALL *BASS_ChannelIsActive)(BASS_HANDLE handle) = nullptr;
    BASS_BOOL   (BASSCALL *BASS_ChannelSetAttribute)(BASS_HANDLE handle, BASS_DWORD attrib, float value) = nullptr;
    BASS_HANDLE (BASSCALL *BASS_ChannelSetSync)(BASS_HANDLE handle, BASS_DWORD type, BASS_QWORD param, BassSyncProc proc, void *user) = nullptr;
    int         (BASSCALL *BASS_ErrorGetCode)() = nullptr;
    // Used by BassAudioDeck's buffer tap for the Audio Visualizer/Milkdrop
    // (UC-15 "Step 3") -- BASS_ChannelGetData returns bytes written, or
    // (BASS_DWORD)-1 on error.
    BASS_BOOL   (BASSCALL *BASS_ChannelGetInfo)(BASS_HANDLE handle, BASS_CHANNELINFO *info) = nullptr;
    BASS_DWORD  (BASSCALL *BASS_ChannelGetData)(BASS_HANDLE handle, void *buffer, BASS_DWORD length) = nullptr;

private:
    BassLibrary() = default;
    ~BassLibrary();
    Q_DISABLE_COPY(BassLibrary)

    template <typename Fn>
    bool resolve(Fn &fn, const char *name);

    QLibrary m_bass;
    bool m_loaded = false;
};
