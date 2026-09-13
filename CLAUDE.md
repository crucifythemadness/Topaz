# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Topaz is a Windows desktop audio jukebox (Qt6 / QML) that plays FLAC and MP3 files from
a scanned music library, organized by Genre → Album Artist → Album, into a FIFO playback
queue with XSPF playlist support. Full functional spec and architecture (use cases,
data flows, component APIs) live in `architecture/AudioJukeboxTopaz.md` — read it before
making non-trivial changes; it documents *why* several non-obvious implementation choices
were made (see especially the drag & drop and queue-reorder sections).

**Keep `architecture/AudioJukeboxTopaz.md` always up to date.** Whenever a change adds,
modifies, or removes a use case, a component's public API, a data flow, or a design
decision, update the corresponding section of that document in the same change — it is
the authoritative spec, not a historical record.

## Build

Toolchain (pinned in `.vscode/settings.json`): Qt 6.10.2 mingw_64, MinGW 13.1.0, Ninja,
CMake from the Qt install. There is no separate CLI build script — the CMake configure/build
settings and environment `PATH` overrides are declared in `.vscode/settings.json` and used by
the VS Code CMake Tools extension (`cmake.configureSettings`, `cmake.configureEnvironment`).

To build from a shell, replicate those settings, e.g.:

```sh
cmake -B build -G Ninja \
  -DCMAKE_PREFIX_PATH=C:/Qt/6.10.2/mingw_64 \
  -DCMAKE_MAKE_PROGRAM=C:/Qt/Tools/Ninja/ninja.exe \
  -DCMAKE_C_COMPILER=C:/Qt/Tools/mingw1310_64/bin/gcc.exe \
  -DCMAKE_CXX_COMPILER=C:/Qt/Tools/mingw1310_64/bin/g++.exe \
  -DCMAKE_RC_COMPILER=C:/Qt/Tools/mingw1310_64/bin/windres.exe
cmake --build build
```

Run the built binary at `build/Topaz.exe` (or use the "Run topaz (Qt Quick)" launch
config in `.vscode/launch.json`, which builds first via the CMake preLaunchTask).

### Release build / deployment

`build/` is left as a Debug tree for day-to-day VS Code work (CMake Tools writes
`CMAKE_BUILD_TYPE=Debug` there by default). For a Release build, use a **separate**
build directory — same toolchain, `-DCMAKE_BUILD_TYPE=Release` added — so it doesn't
force VS Code to reconfigure/rebuild the Debug tree:

```sh
cmake -B build-release -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=C:/Qt/6.10.2/mingw_64 \
  -DCMAKE_MAKE_PROGRAM=C:/Qt/Tools/Ninja/ninja.exe \
  -DCMAKE_C_COMPILER=C:/Qt/Tools/mingw1310_64/bin/gcc.exe \
  -DCMAKE_CXX_COMPILER=C:/Qt/Tools/mingw1310_64/bin/g++.exe \
  -DCMAKE_RC_COMPILER=C:/Qt/Tools/mingw1310_64/bin/windres.exe
cmake --build build-release --target topaz
```

This produces optimized, non-`d`-suffixed `libprojectM-4.dll` / `libprojectM-4-playlist.dll`
/ `glew32.dll` alongside `Topaz.exe` in `build-release/` (same `RUNTIME_OUTPUT_DIRECTORY`
convention as the Debug tree — see `CMakeLists.txt`'s GLEW section). KissFFT needs no DLL;
it's vendored source compiled directly into `Topaz.exe` (`third_party/kissfft/`).

To assemble a minimal, self-contained deploy folder (`/deploy/`, gitignored) — just what's
needed to run `Topaz.exe` on another machine, nothing from the build tree's object files/
CMake cache:

```sh
mkdir deploy
cp build-release/Topaz.exe build-release/libprojectM-4.dll \
   build-release/libprojectM-4-playlist.dll build-release/glew32.dll deploy/
C:/Qt/6.10.2/mingw_64/bin/windeployqt6.exe --qmldir . --compiler-runtime deploy/Topaz.exe
mkdir deploy/Topaz
cp build-release/Topaz/qmldir build-release/Topaz/topaz.qmltypes deploy/Topaz/
```

`windeployqt6` pulls in every Qt DLL actually used (including the Multimedia FFmpeg
backend's `avcodec-*`/`avformat-*`/`avutil-*`/`swresample-*`/`swscale-*`), the QML
modules/plugins the app imports, the platform plugin, and (via `--compiler-runtime`)
the MinGW runtime DLLs (`libgcc_s_seh-1.dll`, `libstdc++-6.dll`, `libwinpthread-1.dll`).
It does not know about `libprojectM`/GLEW since those aren't Qt — hence the manual copy
step above.

**The last two lines are not optional — the app fails to start without them.**
`qt_add_qml_module` generates a companion `Topaz/` directory next to `Topaz.exe` in
*every* build tree (`build-release/Topaz/`), containing a `qmldir` whose `prefer
:/Topaz/` line redirects module resolution to the QML resources actually compiled
into the exe. `QQmlApplicationEngine` always searches the app's own directory for a
`<ModuleName>/qmldir` as part of resolving `engine.loadFromModule("Topaz", "Main")`
(`main.cpp`) — that's how it finds the module when running in-place from
`build/`/`build-release/`. Copy `Topaz.exe` alone into a fresh folder without this,
and that search comes up empty: the app exits immediately (`QCoreApplication::exit(-1)`
from `objectCreationFailed` in `main.cpp`) with `Module "Topaz" contains no type named
"Main"` — silently, since it's a `WIN32_EXECUTABLE` with no attached console, so nothing
appears on stderr unless you set `QT_FORCE_STDERR_LOGGING=1` first. Only `qmldir` +
`topaz.qmltypes` are actually needed at runtime (confirmed by testing) — the loose
`.qml` files `qt_add_qml_module` also copies into that folder are for IDE tooling
(Qt Creator/`qmlls`) only and can be left out of the deploy folder.

Re-run all of this after each Release rebuild; nothing here is incremental.

### Linux build / deploy (experimental, via Docker Desktop)

Topaz also builds and runs on Linux — verified end-to-end (`cmake`/`ninja` build,
`ldd`-clean link, and a runtime smoke test in a container with none of the build
environment installed) via Docker Desktop on this same Windows machine. See the
`future_linux_port` project memory for the full history; the working recipe:

```sh
# One-time: build the reusable environment image (Ubuntu 24.04 + official
# Qt 6.10.2 via aqtinstall — Ubuntu's own apt Qt6 is 6.4.2, too old:
# QQmlApplicationEngine::loadFromModule() needs 6.5+, QAudioBufferOutput needs 6.8+)
docker build -f Dockerfile.linux -t topaz-linux-build .

# One-time: a named volume for build output. Must NOT be a Windows bind
# mount — NTFS's case-insensitivity leaks through Docker Desktop's file
# sharing even inside the Linux container, which silently breaks the
# case-sensitive Topaz/topaz distinction the build relies on (see below).
docker volume create topaz-linux-build-vol

# Configure + build (source bind-mounted from the host is fine; only the
# build OUTPUT needs the real Linux-native volume)
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd):/src" -v topaz-linux-build-vol:/build -w /src \
  topaz-linux-build bash -c "cmake -B /build -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build /build"
```

`MSYS_NO_PATHCONV=1` is required when running these `docker` commands from Git Bash
on Windows, or container-side absolute paths like `-w /src` get silently mangled by
MSYS's automatic path conversion.

**Why the executable is named `topaz` (lowercase) on Linux, `Topaz.exe` on Windows**:
`qt_add_qml_module(topaz URI Topaz ...)` generates a `Topaz/` companion directory
right next to the built binary (see the deploy section above). On Windows this never
collides with `Topaz.exe` (different name, `.exe` suffix). On a case-sensitive Linux
filesystem, an executable literally named `Topaz` collides directly with that
same-named directory (`ld: cannot open output file Topaz: Is a directory`) —
`CMakeLists.txt` sets `OUTPUT_NAME Topaz` only under `if(WIN32)`; Linux keeps CMake's
default (the target's own name, `topaz`).

To assemble a self-contained `deploy-linux/` folder (gitignored, mirrors `/deploy/`
above) from an already-built volume:

```sh
docker run --rm -v topaz-linux-build-vol:/build -v "$(pwd)/deploy-linux:/out" topaz-linux-build bash -c '
QT=/opt/qt/6.10.2/gcc_64
cp /build/topaz /out/topaz-bin && chmod +x /out/topaz-bin
mkdir -p /out/Topaz && cp /build/Topaz/qmldir /build/Topaz/topaz.qmltypes /out/Topaz/
mkdir -p /out/lib
find "$QT/lib" -maxdepth 1 -name "*.so*" ! -name "*.debug" -exec cp -L {} /out/lib/ \;
cp -L /build/_deps/projectm-build/src/libprojectM/libprojectM-4.so.4 /out/lib/
cp -L /build/_deps/projectm-build/src/playlist/libprojectM-4-playlist.so.4 /out/lib/
cp -L /build/lib/libGLEW.so.2.2 /out/lib/
mkdir -p /out/plugins && cp -r "$QT/plugins/." /out/plugins/
rm -rf /out/plugins/{designer,help,printsupport,sqldrivers,qmllint,qmlls,qmltooling}
cp -r "$QT/qml" /out/qml
'
```
**Every copy into `deploy-linux/lib/` uses `-L` (dereference), never `-P`/plain `cp -r`
of a symlink** — confirmed the hard way, from an actual physical Linux machine: an
earlier version of this recipe preserved Qt's `libFoo.so -> libFoo.so.6 ->
libFoo.so.6.10.2` symlink chains, which looked fine on this Windows dev machine (Docker
Desktop's bind-mount correctly materializes them as real NTFS symlinks here) but silently
vanished when the user copied `deploy-linux/` onto a FAT32/exFAT-formatted USB drive to
move it to their Linux box — neither filesystem has any concept of a Unix symlink. Result:
`error while loading shared libraries: libQt6Multimedia.so.6: cannot open shared object
file`. Dereferencing means the bundle is made entirely of real files, so it survives any
transfer medium (USB stick of any filesystem, Explorer copy, zip, network share) — at the
cost of some duplicated bytes (~210 MB → ~470 MB), an easy trade for a trial package.

Plus, into `deploy-linux/lib/`: `libstdc++.so.6`/`libgcc_s.so.1` (cross-distro libstdc++
version safety, the Linux analogue of `windeployqt6 --compiler-runtime` above) and the
full transitive "system" library chain `ldd build/topaz` reports beyond Qt/projectM/GLEW
(OpenGL/GLX vendor-dispatch — `libOpenGL.so.0`/`libGLX.so.0`/`libGLdispatch.so.0`, easy to
miss since it's a separate package from `libgl1` — Kerberos/GSSAPI pulled in by Qt Network,
and PulseAudio's own codec dependencies) — confirmed by trial against a genuinely bare
`ubuntu:24.04` container with none of these installed, not guessed in advance.

**`ldd` on the main executable alone is not enough** — Qt's platform/plugin `.so` files
(loaded dynamically at runtime, never linked directly by `topaz-bin`) have their own further
dependencies invisible to that check. Found by `ldd`-ing `deploy-linux/plugins/platforms/*.so`
and `deploy-linux/plugins/wayland-*/*.so` directly: the **xcb** platform plugin
(`libqxcb.so` — the one actually used on a real X11 desktop) needs 14 more libraries
bundled into `lib/` — `libxcb-cursor.so.0` (named directly in Qt's own "xcb-cursor0 or
libxcb-cursor0 is needed" startup error) plus `libxcb-icccm.so.4`/`image.so.0`/
`keysyms.so.1`/`randr.so.0`/`render-util.so.0`/`render.so.0`/`shape.so.0`/`shm.so.0`/
`sync.so.1`/`util.so.1`/`xfixes.so.0`/`xkb.so.1` and `libxkbcommon-x11.so.0`. The
**wayland** plugin family similarly needs `libffi.so.8`/`libwayland-client.so.0` bundled
(`libwayland-cursor.so.0`/`libwayland-egl.so.1` are needed too for full Wayland support but
aren't installed in the build image as of this writing — a known gap, low priority since
Topaz has only actually been tested under xcb).

**Test the real platform plugin, not just `offscreen`** — every earlier verification round
forced `QT_QPA_PLATFORM=offscreen`, which never loads `libqxcb.so` at all, so this whole
class of missing-library gap went undetected until real hardware hit it. The clean-room
verification now also installs `xvfb` (`apt-get install xvfb`) and forces
`QT_QPA_PLATFORM=xcb` with `DISPLAY` pointed at a running `Xvfb :99 -screen 0 1024x768x24 &`
— this actually exercises the same platform-plugin code path a real X11 desktop does.

`deploy-linux/` also needs a small `qt.conf` (`[Paths]` / `Plugins = plugins` /
`Qml2Imports = qml`) and a `run-topaz.sh` wrapper that sets `LD_LIBRARY_PATH` to `lib/`
before `exec`-ing `topaz-bin` — the binary's own build-time RPATH points at `/opt/qt`/`/build`,
which won't exist on a real
target machine, but `LD_LIBRARY_PATH` takes precedence over it (modern CMake emits
`DT_RUNPATH`, not old-style `DT_RPATH`).

Like the Windows deploy, BASS (`libbass.so`/`libbassflac.so`/`libbassopus.so`) is never
bundled — the user supplies their own licensed copies next to `topaz-bin` if wanted.

There is no test suite in this repository.

## Architecture

### C++ / QML split

All heavy logic (file I/O, tag parsing, playback, playlist XML) lives in C++ classes
registered as `QML_ELEMENT` and exposed to QML via `qt_add_qml_module` (see
`CMakeLists.txt`). QML files are UI-only and drive behavior by calling invokable methods
and binding to properties/signals on these C++ objects. `Theme.qml` is the sole QML
singleton (declared via `QT_QML_SINGLETON_TYPE`) and holds every color/typography/spacing
token — QML files should reference `Theme.*` rather than hardcoding values.

### Core C++ classes

| Class | Files | Role |
|---|---|---|
| `TrackInfo` | `trackinfo.h` | Flat struct — the single record type for the whole library (no separate Genre/Artist/Album entity classes, by design, for 12K+ entry scale) |
| `TagReader` | `tagreader.h/cpp` | Dependency-free ID3v2 (MP3) + Vorbis Comment/FLAC tag reader; also generates cover thumbnails and reads raw full-res covers |
| `LibraryCache` | `librarycache.h/cpp` | Atomic read/write of `Topaz.library.json` |
| `LibraryScanner` | `libraryscanner.h/cpp` | Runs on a dedicated worker `QThread`: directory walk, genre filtering, `QFileSystemWatcher`-based runtime monitoring |
| `LibraryModel` | `librarymodel.h/cpp` | `QAbstractListModel` + `QML_ELEMENT`; owns the `LibraryScanner` thread; exposes query invokables to QML (`filteredAlbums`, `buildLibraryTree`, etc.) |
| `AppConfig` | `AppConfig.h/cpp` | Reads/writes `Topaz.config` JSON (genres, monitored folders, window/panel layout); auto-saves on every mutation |
| `PlaybackEngine` | `playbackengine.h/cpp` | `QAbstractListModel` + `QML_ELEMENT`; simultaneously the queue model *and* the playback controller (wraps `QMediaPlayer`/`QAudioOutput`) |
| `PlaylistManager` | `playlistmanager.h/cpp` | XSPF (`.xml`) playlist file I/O, including drive-letter-stripped portable paths |

### Threading model

`LibraryScanner` work (directory walks, tag reading, JSON serialization) always runs on
its own worker thread; results cross to the main thread only via Qt queued-connection
signals (`scanProgress`, `scanCompleted`). Startup uses a hybrid strategy: the JSON cache
is loaded synchronously on the main thread first for an instant UI, then a `statCheck`
runs on the worker thread to reconcile changes. Never do filesystem/tag-reading work
directly on the main thread when extending scanning behavior.

### QML component structure

Registered QML files (`qt_add_qml_module`, URI `Topaz`): `Main.qml` is the
`ApplicationWindow` root that owns `AppConfig`, `LibraryData` (shared UI selection
state), `LibraryModel`, `PlaybackEngine`, `PlaylistManager`, and the modal dialogs.
The four main panels (`LibraryTree`, `AlbumBrowser`, `PlaybackQueue`, `NowPlaying`) sit in
a horizontal `SplitView`; only `AlbumBrowser` has `SplitView.fillWidth: true` and absorbs
resize surplus. Panel widths and window size are persisted to `Topaz.config` via a
debounced (500 ms) `AppConfig.saveLayout()` call.

Data flow for filtering follows one repeated pattern worth knowing before touching any
of it: `GenreBar`/`LibraryTree` mutate `LibraryData` selection state → `LibraryTree`
rebuilds a flat JS row array synchronously → `AlbumBrowser` reacts via
`Qt.callLater(_scheduleRefresh)` (deliberately deferred a tick so the tree frame renders
first) → calls `LibraryModel.filteredAlbums()`. `LibraryModel.filteredAlbums()` and
`buildLibraryTree()` are each single O(N_tracks) passes over the flat track list using
`QHash` grouping — do not reintroduce per-album or per-genre rescans.

### Drag & drop — two distinct mechanisms, do not mix

- **Adding a track to the queue** (`AlbumCard` → `PlaybackQueue`): Qt's internal
  `Drag.active`/`DropArea` mechanism with `Drag.hotSpot` manually recomputed on every
  `positionChanged` (required because the source item itself never moves — see
  `architecture/AudioJukeboxTopaz.md` UC-06 for why).
- **Reordering within the queue**: pure mouse-position tracking against
  `queueList.contentItem`, no `Drag`/`DropArea` involved (see UC-11 for why the
  Drag/DropArea approach was rejected — hover-visibility deadlock and per-delegate
  DropArea fragility in a virtualized `ListView`).

### Persistence formats

- `Topaz.config` — app settings (genres, monitored folders, window/panel layout), JSON, at `QStandardPaths::AppConfigLocation`.
- `Topaz.library.json` — scanned track cache, same directory.
- `<AppConfigLocation>/playlists/<name>.xml` — XSPF v1 playlists, drive letters stripped from `<location>` for portability across drive-letter reassignment.

Config/cache directory on Windows: `%APPDATA%\Topaz\Topaz\`.

### Performance constraints to preserve

These were deliberate fixes for measured UI lag — don't undo them:
- Album cover `Image` elements must set `sourceSize` to the display size (e.g. 160×160)
  so Qt decodes at that resolution rather than keeping full-res bitmaps in memory.
- `AlbumCard` has no multi-selection state and no context menus (`Menu`/`QQuickPopup`
  instantiation per card was the primary source of lag in large genre views).
- `ListView` delegate recycling (`cacheBuffer`) is relied on in `AlbumBrowser` and
  `PlaybackQueue`; avoid patterns that force all delegates to stay instantiated.
