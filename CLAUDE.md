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
