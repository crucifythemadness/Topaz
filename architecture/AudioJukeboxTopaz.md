---
title: Audio Jukebox Topaz
abstract: this document describes the software architecture of Topaz
layout: default
area: Common
category: Software Architecture
author: 
- Michel Stauffer
---

# References  
[Qt](https://en.wikipedia.org/wiki/Qt_(software))
[flac](https://en.wikipedia.org/wiki/FLAC)  
[mp3](https://en.wikipedia.org/wiki/MP3)  
[opus](https://en.wikipedia.org/wiki/Opus_(audio_format))
[ID3-Tag](https://de.wikipedia.org/wiki/ID3-Tag)
[FIFO](https://en.wikipedia.org/wiki/FIFO_(computing_and_electronics))
[Fade - audio engineering](https://en.wikipedia.org/wiki/Fade_(audio_engineering))
[Json](https://www.json.org/json-en.html)
[GUI](https://en.wikipedia.org/wiki/Graphical_user_interface)
[QML](https://en.wikipedia.org/wiki/QML)

# Abbreviations and definitions of terms  
- flac (Free Lossless Audio Codec)  
- mp3 (formally MPEG-1 Audio Layer III or MPEG-2 Audio Layer III)
- opus (a lossy audio codec, delivered in an Ogg container)
- Topaz (Project name and also the Application name)

# Introduction and overview
Topaz is an audio jukebox which is a desktop app that can play audio files (*.flac, *.mp3, and *.opus) from a queue. The queue plays the audio files according to the FIFO principle. Optionally, the user can set whether the audio files should be played with fade-in and fade-out (Fade - audio engineering) or whether the audio files should be played to the end before the next audio file is played. The user can move audio files within the queue up and down, except the audio file that is currently playing. The audio files are stored within a main folder that Topaz can scan. Topaz has an application Json Config-File were the user can set the proper main folder path via GUI. Audio files are then organized under three levels. Genre, Album Artist and Album. At the Top are 30 toggle buttons (3 rows with 10 buttons over the whole application with) that are representing the genres. A genre is active when the button is pressed and all album artists, albums and audio files under this genre are now visible and selectable. Available Genres can be configured within the application config file. The application config file will be read at startup and each available genre will be connected with one toggle button. On the left side under the genre toggle buttons is a tree control that contains all available genres. The tree control has three levels (genre, album artist, album). Right from that is a section that can contain all albums, each with the cover and all the audio files, from a selected Genre or a selected Album artist. Alternatively the user can also just select one Album. Right from that is antother section with the audio file queue. The queue should display the Number when the Audio file will be played, the Album name, the Artist, the Name of the Audio file and the Audio file bitrate. Right from that is antother section that contains the cover and detail information of the audio file that is currently playing. All together we have 4 sections that are under the big genre toggle buttons. Each Audio file that Topaz played will be stored and saved automatically in a Json playlist file. The possibility to manage playlist files is in the section on the right side were the details of the currently playing Audio file are. The User can start a new playlist with a given name or the User can load an already existing playlist. That means that at the application startup the user has to decide to create a new playlist or load an exisisting playlist. If the User loads an existing playlist, Topaz will automatically start playing the first audio file from that playlist. Albums or Audio Files can be add to the queue via context menu (mouse right click) or via drag and drop. Topaz should be an application that has a moderate memory consumption. That means that unnecessary Album covers and Audio Files (ID3-Tag Informations) in Memory has to be unloaded.

# Essential requirements  
- Topaz will be a Qt application (GUI with QML or partially with QML)

## Supported application resolutions  
- 1920x1080  (auto-fullscreen when monitor is exactly this resolution)
- 1920x1200  (auto-fullscreen when monitor is exactly this resolution)
- 2560x1440  (auto-fullscreen when monitor is exactly this resolution)
- 3840x2160  (auto-fullscreen when monitor is exactly this resolution)
- 4096x2160
- Windowed fully resizable (minimum 1280 × 720)

# Use Cases

## UC-01 Browse by Genre

| Field | Detail |
|-------|--------|
| **Goal** | User filters the library tree and album browser by activating one or more genre toggle buttons. |
| **Actor** | User |
| **Precondition** | At least one genre is configured and the library has been scanned. |
| **Trigger** | User clicks a genre toggle button in the `GenreBar`. |

### Normal Flow

1. User clicks a genre button (e.g. "Techno").
2. `GenreBar` calls `lib.toggleGenre(index)`.
3. `LibraryData.toggleGenre()` flips the `active` flag in `genreModel` and rebuilds `activeGenreNames`. If the genre was just **activated**, it becomes the sole `selectedGenre` (replacing any prior selection). If it was just **deactivated**, the nearest remaining active genre is auto-selected instead — the one positionally after it, or if it was the last active genre, the one before it; if no active genres remain, `selectedGenre` is cleared. `selectedArtist`/`selectedAlbum` are cleared in both cases. When a genre is auto-selected this way, `LibraryData` emits `genreAutoSelected(genre)`, and `LibraryTree` scrolls that genre's header row into view via `positionViewAtIndex(..., ListView.Contain)`. This scroll-into-view only happens for auto-selection — manually clicking a genre, artist, or album row in the tree does not trigger it. **All of this auto-selection is suppressed while SEARCH is active** (`LibraryData.activeTab !== "library"`, one-way bound from `Main.qml`'s own `activeTab` — see UC-21): `activeGenreNames` still updates normally (so "Consider Genre" search stays correct), but the *entire* existing selection — `selectedGenre` **and** `selectedArtist`/`selectedAlbum` — is left completely untouched, since `LibraryTree`/`AlbumBrowser` aren't even loaded on that tab and disturbing any part of a stale selection would otherwise surprise the user the next time they switch back to LIBRARY (e.g. a previously drilled-down artist reverting to just its genre). Note `selectedArtist`/`selectedAlbum` are cleared by `_rebuildActiveNames()` itself (`LibraryData.qml`), not by `toggleGenre()` directly — both are gated on the same `activeTab === "library"` check.
4. `LibraryTree.onLibraryChanged` fires → tree renders only active-genre sections.
5. `AlbumBrowser` receives `onActiveGenreNamesChanged` → schedules `_scheduleRefresh()` via `Qt.callLater` (deferred to the next event-loop tick so LibraryTree renders its frame first) → `currentAlbums = lib.filteredAlbums()` → `ListView` updates.
6. `AlbumBrowser` subtitle updates to reflect the new filter path (e.g. `TECHNO`).

### Alternate: Genre drill-down (tree click)

User clicks a genre header row in `LibraryTree`:
- `LibraryTree` calls `lib.selectGenre(name)`. Clicking the same genre again deselects it.
- `LibraryData.selectGenre()` sets `selectedGenre`, clears `selectedArtist` / `selectedAlbum`.
- `AlbumBrowser` receives `onSelectedGenreChanged` → `filteredAlbums()` narrows to that single genre only.
- Genre header highlights in `secondary` (teal) colour; all expanded artist nodes collapse.

### Alternate: Artist drill-down

After activating genres, the user clicks an artist row in `LibraryTree`:
- `LibraryTree` calls `lib.selectArtist(name, genre)` (passing the genre section the row belongs to) and toggles local expand state.
- `LibraryData.selectArtist()` pre-selects that `genre` if it differs from the current `selectedGenre` (an artist can appear under more than one genre section when their tracks carry different genre tags) — otherwise `AlbumBrowser` would narrow to the wrong genre and show no albums for that artist. Clicking the same artist row again (same name *and* same genre) deselects it.
- `AlbumBrowser` receives `onSelectedArtistChanged` (and `onSelectedGenreChanged` if the genre changed) → `currentAlbums` narrows to that artist's albums only.

### Alternate: Album drill-down

User clicks an album row in `LibraryTree`:
- `LibraryTree` calls `lib.selectAlbum(title)`.
- `AlbumBrowser` receives `onSelectedAlbumChanged` → `currentAlbums` narrows to that single album.

### Empty-State Rules

- If no genres are active: `LibraryTree` shows "No genres active" hint; `AlbumBrowser` shows "No albums to show" hint.
- If a genre is active but has no artists yet: `LibraryTree` shows "No artists scanned yet" under that genre node.

---

## UC-02 Open Setup Dialog

| Field | Detail |
|-------|--------|
| **Goal** | User opens the setup dialog to configure genres and monitored folders. |
| **Actor** | User |
| **Precondition** | Application is running. |
| **Trigger** | User clicks the gear icon (⚙) in the `TopBar`. |

### Normal Flow

1. User clicks the ⚙ icon in the top-right toolbar.
2. `TopBar` emits `settingsRequested()`.
3. `Main.qml` handles `onSettingsRequested` → calls `setupDialog.open()`.
4. `SetupDialog` opens as a modal popup centered on the application window with a dark scrim behind it.
5. Dialog opens on the **GENRES** tab by default. The dialog can be dragged
   to another position by pressing and dragging its header (the "SETUP"
   title bar) — a `MouseArea` there (`SetupDialog.qml`, declared before the
   header's close-✕ button so it doesn't intercept that click) tracks the
   press-to-move delta and writes it directly to the `Popup`'s `x`/`y`.
   Centering deliberately uses plain `x`/`y` bindings against
   `Overlay.overlay`'s size (`x: Overlay.overlay ? (Overlay.overlay.width -
   width) / 2 : 0`, and similarly for `y`) rather than `anchors.centerIn:
   Overlay.overlay` (still used by `MessageBox.qml`/`NewPlaylistDialog.qml`,
   which aren't draggable): `Popup.anchors.centerIn` is backed by
   `QQuickPopupAnchors`, which keeps reasserting `x`/`y` from C++ rather
   than through a plain overridable QML binding, so it fights any manual
   drag and the popup never visibly moves — ordinary `x`/`y` bindings behave
   like normal `Item` bindings and get cleanly broken by the drag's direct
   assignment. This position is intentionally **not** persisted anywhere in
   `AppConfig` — `onAboutToShow` recomputes `x`/`y` from `Overlay.overlay`'s
   current size every time the dialog opens, so it always comes back
   centered regardless of where it was left (and picks up a window resize
   that happened while it was closed). Contrast with the `FloatingPane`-
   based panes (`MilkdropWindow`, etc.), which persist dragged geometry via
   `geometrySettled()`/`AppConfig.saveLayout()` (see UC-17/UC-19/UC-20) —
   `SetupDialog` deliberately does not, and being a `Popup` rather than a
   separate `Window`, it can't use `FloatingPane`'s `Window.startSystemMove()`
   mechanism anyway.
6. User switches tabs or closes the dialog with the ✕ button.

---

## UC-03 Configure Genres

| Field | Detail |
|-------|--------|
| **Goal** | User defines the list of genre names that appear as toggle buttons in `GenreBar`. |
| **Actor** | User |
| **Precondition** | Setup dialog is open on the GENRES tab. |
| **Trigger** | User interacts with genre management controls. |

### Normal Flow — Add genre

1. User types a genre name into the text input (e.g. "Techno").
2. User presses **Enter** or clicks **ADD**.
3. `SetupDialog.doAddGenre()` calls `appConfig.addGenre(name)`.
4. `AppConfig` performs a case-insensitive duplicate check, appends the name to `m_genres`, emits `genresChanged`, and auto-saves to `Topaz.config`.
5. `LibraryData` receives `genresChanged` → `rebuildGenreModel()` clears and repopulates `genreModel` from `appConfig.genres`.
6. `GenreBar` `Repeater` re-evaluates → the new genre button appears immediately.

### Normal Flow — Delete selected genre

1. User clicks a genre cell in the grid to select it (highlighted in `secondaryContainer` colour).
2. User clicks **DELETE SELECTED**.
3. `appConfig.removeGenreAt(index)` removes the entry, emits `genresChanged`, auto-saves.
4. `LibraryData.rebuildGenreModel()` fires; the chip disappears from `GenreBar`.

### Normal Flow — Delete all genres

1. User clicks **DELETE ALL**.
2. `appConfig.clearGenres()` empties the list, emits `genresChanged`, auto-saves.
3. `GenreBar` shows empty state; `LibraryTree` and `AlbumBrowser` show their no-genres hints.

### Rules

- Duplicate names (case-insensitive) are silently ignored.
- Genre names are stored in their original casing and displayed upper-cased in `GenreBar`.
- Maximum 30 genres are displayed in `GenreBar` (3 rows × 10 columns); additional genres are
  still stored but may not be visible until the layout is extended.
- The GENRES tab in `SetupDialog` lays out configured genres in a fixed 6-column grid
  (up to 5 rows = 30 cells) sized to always fit without a scrollbar, mirroring
  `GenreBar`'s own fixed-grid pattern; genres beyond 30 remain stored but may not all
  be visible, the same accepted ceiling as `GenreBar`.

---

## UC-04 Configure File Monitoring Folders

| Field | Detail |
|-------|--------|
| **Goal** | User specifies which directories Topaz should scan for audio files (FLAC / MP3 / Opus). |
| **Actor** | User |
| **Precondition** | Setup dialog is open on the FILE MONITORING tab. |
| **Trigger** | User interacts with folder management controls. |

### Normal Flow — Add folder

1. User clicks **ADD FOLDER**.
2. A native OS folder-picker dialog (`QtQuick.Dialogs.FolderDialog`) opens.
3. User selects a directory and confirms.
4. `FolderDialog.onAccepted` calls `appConfig.addFolder(selectedFolder, true)`.
5. `AppConfig` converts the `file://` URL to a local path via `QUrl::toLocalFile()`,
   converts it to a volume-anchored `VolumePath` (`volumepath.h`), performs a
   duplicate check by `(volume, relPath)`, appends the entry with
   `includeSubfolders: true`, emits `foldersChanged`, and auto-saves.
6. The new row appears in the folder list with the **SUBFOLDERS** checkbox ticked.
   If the folder's volume is later unmounted (disk unplugged, moved elsewhere),
   the row dims and shows a "not connected" indicator instead of removing itself
   from the list — `AppConfig::folders()` still returns the entry, just with an
   empty resolved `path` and `available: false` (see "Config file format" below).

### Normal Flow — Toggle subfolders

1. User clicks the checkbox in the **SUBFOLDERS** column of any folder row.
2. `appConfig.setFolderSubfolders(index, !current)` flips the flag, emits `foldersChanged`,
   auto-saves.
3. The checkbox visual updates immediately.

### Normal Flow — Delete selected folder

1. User clicks a row to select it (row highlighted with `p10` tint).
2. User clicks **DELETE SELECTED**.
3. `appConfig.removeFolderAt(index)` removes the entry, emits `foldersChanged`, auto-saves.

### Normal Flow — Delete all folders

1. User clicks **DELETE ALL**.
2. `appConfig.clearFolders()` empties the list, emits `foldersChanged`, auto-saves.

### Rules

- Duplicate paths (exact string match) are silently ignored.
- The `includeSubfolders` flag defaults to `true` when a folder is first added.

---

## UC-05 Scan Audio Directories

| Field | Detail |
|-------|--------|
| **Goal** | Topaz scans all configured folders for audio files whose genre matches a configured genre and populates the library. |
| **Actor** | User / System |
| **Precondition** | At least one genre and one folder are configured in `AppConfig`. |
| **Trigger** | User clicks **SCAN DIRECTORIES** in `BottomBar`, OR startup stat-check finds new/changed files. |

### Normal Flow — Full scan

1. `BottomBar` emits `scanRequested()`.
2. `Main.qml` calls `libraryModel.startFullScan()`.
3. `LibraryModel` copies genres + folders from `AppConfig`, emits `_requestFullScan` to worker thread.
4. `LibraryScanner.fullScan()` delegates to the shared `performScan()` pipeline on
   the worker thread (`statCheck()` delegates to the same pipeline — see the
   Startup stat-check flow below; the two have always had near-identical
   semantics, so both are now thin wrappers around one implementation):
   a. **Discover** — recursively walks each configured folder (respecting
      `includeSubfolders`), listing every `*.mp3`/`*.flac`/`*.opus` file
      currently on disk. Pure filesystem listing, no tag reads. Each
      folder's configured path is first canonicalized via
      `VolumePath::fromAbsolutePath(path).resolve(mountedVolumes)`
      (`libraryscanner.cpp`, `volumepath.h/cpp`) — once per folder, not per
      file — so every discovered `TrackInfo::filePath` is byte-identical to
      however `VolumePath::resolve()`/`quickPath()` reconstruct the same
      file's path elsewhere (cache reload, playlist load). Without this, a
      folder configured with a non-canonical drive-letter case (e.g.
      `d:/Music` — still resolves fine, since NTFS is case-insensitive)
      would produce `TrackInfo::filePath`s that silently fail every
      exact-string comparison against the canonical form: this folder's
      files would never match the existing cache in step 4b below (forcing
      a full tag re-read on every scan) and would never match a playlist
      track's resolved path in `LibraryModel::buildStandaloneTrackCards()`'s
      cover lookup (see UC-22), showing no cover despite being in the
      library. Falls back to the raw configured path unchanged if the
      volume can't currently be resolved (e.g. unmounted) — same as before
      this fix.
   b. **Classify** — for each discovered file, compares its `lastModified`
      against the existing cache: unchanged files reuse their cached
      `TrackInfo` verbatim (no tag read at all); new/changed files are queued.
      A cached entry whose file didn't show up in the discovery walk (deleted,
      or its folder removed from configuration) is simply never re-added —
      this is also how deletions are detected (see the stat-check flow below).
   c. **Parallel tag-read** — the queued set is read via `TagReader::read()`
      in parallel over a small `QThreadPool` (capped at `min(4, core count)` —
      this is disk-I/O-bound work, not CPU-bound, so more threads isn't
      always better, especially on external/spinning drives), in chunks of
      ~200 files so cancellation and `scanProgress(done, total)` stay
      responsive between chunks. Each file's genre tag (case-insensitive
      trim) is compared against configured genres; unmatched files are
      dropped. Freshly-read entries get a stable UUID (reused from cache if
      the path is already known).
   d. **Resolve cover art** — one pass, after reused-cache and freshly-read
      entries are merged: for every `(genre, albumArtist, album)` triple —
      genre is part of the key so two same-named albums filed under
      different genres (e.g. a duplicate rip classified both "Alt. Rock" and
      "Punk Rock") resolve their own covers independently rather than
      colliding into one — with no cover anywhere in the merged set yet,
      deterministically picks the
      entry with the lexicographically smallest file path as representative
      (order-independent — unlike walking file-by-file, which only worked
      because it was strictly sequential) and re-reads just those
      representatives in parallel with cover extraction enabled.
5. Scanner saves the result to `Topaz.library.json` via `LibraryCache::save()`.
6. Scanner emits `scanCompleted(tracks)`.
7. `LibraryModel.onScanCompleted()` calls `beginResetModel/endResetModel`, replaces `m_tracks`, emits `libraryRefreshed()`.
8. `LibraryData._rebuildTree()` fires → `LibraryTree` and `AlbumBrowser` update.

### Normal Flow — Startup stat-check (hybrid strategy step 2)

1. `Main.qml Component.onCompleted` → `libraryModel.loadCacheAndStartStatCheck()`.
2. Cache is read synchronously from `Topaz.library.json` → displayed immediately (step 1 of hybrid strategy).
3. `statCheck` is dispatched to worker thread, delegating to the same
   `performScan()` pipeline described above.
4. The discover → classify step (4a/4b above) is what validates each cached
   entry: still-present, unchanged files are reused as-is (no tag read);
   files no longer found on disk are dropped (deleted); new/changed files are
   queued for the parallel tag-read (4c). Only genuinely new or changed files
   are ever re-read — a prior version of this method accidentally re-read
   every file on every stat-check due to a wiring bug; fixed by unifying on
   this single classify-against-the-real-cache step.
5. Cover art is resolved (4d), the updated cache is saved, and `scanCompleted`
   is emitted.

### Empty-State Rules

- If no genres are configured: scan returns 0 tracks; user must configure genres first.
- If no folders are configured: scan returns 0 tracks; user must configure folders first.
- `BottomBar` SCAN DIRECTORIES button is visually disabled (label changes to "SCANNING…") while a scan is in progress.

### Genre Matching Rule (Version 1)

The genre tag value read from the audio file (TCON for MP3, GENRE for FLAC/Opus) is
compared **case-insensitively** against the configured genre names in `AppConfig`.

```
File tag:    "techno"        → normalised: "techno"
Configured:  ["Techno", …]  → normalised: ["techno", …]
Result:      match → include
```

Each audio file must have **exactly one genre** that matches a configured genre.
Multi-genre tags (delimited strings) are not parsed in version 1; the entire tag
value is compared as-is (after normalisation).

---

## UC-06 Startup Library Load

| Field | Detail |
|-------|--------|
| **Goal** | Topaz displays the library instantly from cache while a background check runs. |
| **Actor** | System |
| **Precondition** | `Topaz.library.json` exists and is valid. |
| **Trigger** | Application startup. |

### Normal Flow

1. `Main.qml Component.onCompleted` fires after QML engine is ready.
2. `libraryModel.loadCacheAndStartStatCheck()` reads `Topaz.library.json` synchronously on the main thread (< 100 ms for 12K entries).
3. `applyTracks()` populates `m_tracks` and emits `libraryRefreshed()` → UI is visible immediately.
4. In parallel (worker thread): stat-check begins silently.
5. If stat-check finds changes: `scanCompleted` is received on main thread → model is refreshed.

---

## UC-07 Runtime Directory Monitoring

| Field | Detail |
|-------|--------|
| **Goal** | Topaz automatically detects when audio files are added or removed while the application is running. |
| **Actor** | System |
| **Precondition** | At least one folder is configured; a scan has completed. |
| **Trigger** | `QFileSystemWatcher::directoryChanged` fires. |

### Normal Flow

1. `QFileSystemWatcher` (owned by `LibraryScanner` on the worker thread) watches all root configured folders.
2. OS signals a directory change.
3. A 2-second debounce timer (re)starts; rapid successive changes are coalesced.
4. Timer fires → `statCheck` is triggered automatically.
5. Updated library is emitted via `scanCompleted` → UI refreshes.

---

# GUI Architecture

## Design System

The visual language is the **"Technical Monolith"** dark theme defined in
`design/google-stitch/notes.md`. Key rules:

- **No-border rule** — major section boundaries are expressed through background colour
  shifts (surface hierarchy), never 1 px lines.
- **Surface hierarchy**: `surfaceContainerLowest` → `surface` → `surfaceContainerLow` →
  `surfaceContainerHigh` → `surfaceBright` from darkest to brightest.
- **Typography**: Manrope (headlines), Inter (body/labels), JetBrains Mono (technical
  data). These three fonts must be embedded as Qt resources — add them to
  `qt_add_qml_module(… RESOURCES fonts/…)` once the `.ttf` / `.otf` files are available.
  Qt falls back to system fonts (Segoe UI, Consolas) until then.

Reference files:

| File | Purpose |
|------|---------|
| `design/google-stitch/mockup.png` | Full-resolution visual mockup |
| `design/google-stitch/layout.html` | HTML prototype with Tailwind token mapping |
| `design/google-stitch/notes.md` | Design-system rules, colour tokens, component logic |

## QML Module Structure

All components are registered in the `Topaz` QML module
(`qt_add_qml_module`, URI `Topaz`, version `1.0`).

```
Topaz module
├── Theme.qml           singleton — all colour, typography, spacing, and radius tokens
├── WindowChrome         C++ QML_ELEMENT + QML_SINGLETON — stateless native helper: requests an alpha-capable surface before native window creation (real translucency) and strips the Windows 11 DWM accent border off FloatingPane windows; see UC-17
├── AppConfig           C++ QML_ELEMENT — reads/writes Topaz.config JSON; exposes genres & folders
├── LibraryModel        C++ QML_ELEMENT — QAbstractListModel + scanner orchestration
│                         property AppConfig appConfig
│                         Q_INVOKABLE: loadCacheAndStartStatCheck(), startFullScan()
│                         Q_INVOKABLE queries: genres(), artistsForGenre(), albumsForArtist(), filteredAlbums(), buildLibraryTree(), searchLibrary()  — see UC-21; buildStandaloneTrackCards()  — see UC-22
├── LibraryData.qml     shared state model — genre toggle, selection, tree builder
│                         property AppConfig appConfig
│                         property LibraryModel libraryModel
│                         property string activeTab  (one-way bound from Main.qml's own activeTab; suppresses genre auto-selection in toggleGenre() while SEARCH is active, see UC-01/UC-21)
│                         property real albumScrollY  (AlbumBrowser's ListView.contentY, persisted here so it survives the Loader swap, see UC-21)
├── SearchData.qml      independent search state model — see UC-21 (deliberately not coupled to LibraryData beyond one read-only property)
│                         property LibraryModel libraryModel
│                         property var activeGenreNames  (one-way bound from LibraryData.activeGenreNames by Main.qml)
│                         property string query, mode ("all"/"artists"/"albums"/"tracks"), property bool considerGenre, property bool matchWholeWord, property var results
│                         property real resultScrollY  (SearchResultBrowser's ListView.contentY, persisted here so it survives the Loader swap, see UC-21)
├── PlaylistsData.qml   independent playlists-tab state model — see UC-22 (deliberately not coupled to LibraryData/SearchData beyond one read-only property)
│                         property PlaylistManager playlistManager, property LibraryModel libraryModel
│                         property var engine  (one-way ref to PlaybackEngine, read-only — used only to recognize the playlist currently active in the queue)
│                         property var playlists, property string selectedFileName/selectedDisplayName, property var albums, property var selectedRawTracks
│                         property real resultScrollY  (PlaylistViewer's ListView.contentY, persisted here so it survives the Loader swap, see UC-22)
├── Main.qml            ApplicationWindow root; owns AppConfig, LibraryData, SearchData, PlaylistsData, LibraryModel, PlaybackEngine, PlaylistManager, SystemVolumeController, AudioVisualizerController, SetupDialog, NewPlaylistDialog
│                         property string activeTab ("library"/"playlists"/"search")  — drives TopBar's tab highlighting and which components the SplitView's first two Loaders load, see UC-21/UC-22
│                         property bool bigCoverPaneOpen  (toggled by NowPlaying.onBigCoverRequested / BigCoverWindow.onCloseRequested)
│                         Loader { active: bigCoverPaneOpen; sourceComponent: BigCoverWindow {...} }  — see "Detachable panes" below
│                         property bool tagInfoPaneOpen  (toggled by BottomBar.onTagInfoToggleRequested / TagInfoWindow.onCloseRequested)
│                         Loader { active: tagInfoPaneOpen; sourceComponent: TagInfoWindow {...} }  — see UC-18
│                         property bool audioVisualizerPaneOpen  (toggled by BottomBar.onAudioVisualizerToggleRequested / AudioVisualizerWindow.onCloseRequested)
│                         Loader { active: audioVisualizerPaneOpen; sourceComponent: AudioVisualizerWindow {...} }  — see UC-19
│                         property bool milkdropPaneOpen  (toggled by BottomBar.onMilkdropToggleRequested / MilkdropWindow.onCloseRequested)
│                         Loader { active: milkdropPaneOpen; sourceComponent: MilkdropWindow {...} }  — see UC-20
│                         SplitView slot 1: Loader { sourceComponent: activeTab === "search" ? SearchPanel : activeTab === "playlists" ? PlaylistsPanel : LibraryTree }  — see UC-21/UC-22
│                         SplitView slot 2: Loader { sourceComponent: activeTab === "search" ? SearchResultBrowser : activeTab === "playlists" ? PlaylistViewer : AlbumBrowser }  — see UC-21/UC-22
├── SetupDialog.qml     Modal setup popup (tabs: GENRES | FILE MONITORING | CROSSFADE | AUTO PLAY | AUDIO VISUALIZER | MILKDROP, see UC-15 / UC-14 / UC-19 / UC-20)
├── NewPlaylistDialog.qml Modal popup — user enters a name; calls PlaylistManager.createPlaylist(); shows MessageBox on name collision
│                         signal playlistCreated()  ← emitted on success; Main.qml calls playlistsData.refreshPlaylists() so the PLAYLISTS tab stays live even while already active, see UC-22
├── MessageBox.qml      Themed single-message popup with OK button; reusable across the application
├── FloatingPane.qml    Reusable base Window for detachable panes (frameless, movable, resizable, right-click-to-close) — see "Detachable panes" below
├── BigCoverWindow.qml  FloatingPane specialization: shows only the current track's cover art
├── TagInfoWindow.qml   FloatingPane specialization: shows the current track's tag metadata, content scales with pane size — see UC-18
├── AudioVisualizerWindow.qml FloatingPane specialization: renders bumping bars from AudioVisualizerController's barLevels/peakLevels — see UC-19
├── MilkdropWindow.qml  FloatingPane specialization: hosts a MilkdropView (C++ QQuickItem, owns the projectM render pipeline directly) — see UC-20
├── TopBar.qml          Header (logo | navigation tabs | loudspeaker icon + gear icon + avatar)  height 64 px
│                         property var systemVolume  (bound to SystemVolumeController; drives the OS-Volume flyout, see below)
│                         property string activeTab ("library"/"playlists"/"search", bound from Main.qml)  — drives which of the 3 tabs is highlighted; a Repeater-driven Row (same array-model convention as BottomBar), see UC-21/UC-22
│                         signal librarySelected() / playlistsSelected() / searchSelected()  ← tab click; "dumb component, owner decides" — Main.qml sets activeTab in response
│                         signal settingsRequested()  ← gear icon click
│                         Loudspeaker icon (🔊, leftmost of the three): click opens a non-modal Popup (~8cm/300px-wide
│                         Slider, 0-100, labeled "OS Volume") anchored under the button via parent: <button item>.
│                         Closes when neither the button nor the popup itself has been hovered for ~150ms (combined
│                         hover state + debounce Timer, to avoid flicker-closing in transit from button to popup) —
│                         deliberately not Popup.CloseOnPressOutside, since the close trigger is hover-exit, not click.
│                         Slider.onMoved calls systemVolume.setVolume(Math.round(value)) directly (Q_INVOKABLE, see
│                         SystemVolumeController below — its Q_PROPERTY volume is intentionally READ-only, matching
│                         AppConfig's convention of always using a separate Q_INVOKABLE setter rather than a
│                         Q_PROPERTY WRITE clause, since a WRITE function is not itself callable as obj.setX() from
│                         QML unless also marked Q_INVOKABLE — an early version of this feature used WRITE and the
│                         slider silently did nothing to the real OS volume). onClicked also calls
│                         systemVolume.refresh() right before opening the popup, so the slider reflects the OS
│                         volume even if it changed elsewhere while Topaz was already running; beyond that,
│                         Slider.value stays live-synced for the whole session via SystemVolumeController's
│                         IAudioEndpointVolumeCallback registration — no further QML-side action needed, since
│                         volumeChanged() re-firing is enough for the existing value: binding to pick it up,
│                         popup open or not (see SystemVolumeController below).
├── GenreBar.qml        3 × 10 genre toggle grid  (reads lib.genreModel, calls lib.toggleGenre)
├── LibraryTree.qml     Left sidebar  default width 286 px, user-resizable  (flat virtualised ListView; flatRows JS array; no nested Repeaters)
├── SearchPanel.qml     Replaces LibraryTree in the same SplitView slot when SEARCH is active — see UC-21 (independent of LibraryData; property SearchData searchData)
├── PlaylistsPanel.qml  Replaces LibraryTree/SearchPanel in the same SplitView slot when PLAYLISTS is active — see UC-22 (independent of LibraryData/SearchData; property PlaylistsData playlistsData; playlist row disabled when active in queue)
├── AlbumBrowser.qml    Center album list  flex-grow (absorbs all surplus width from window resize or panel drag)  (calls lib.filteredAlbums() via Qt.callLater; property autoPlay forwarded to each AlbumCard, see UC-16)
├── SearchResultBrowser.qml  Replaces AlbumBrowser in the same SplitView slot when SEARCH is active — see UC-21 (property SearchData searchData, property var engine/autoPlay forwarded to AlbumCard, same as AlbumBrowser)
├── PlaylistViewer.qml  Replaces AlbumBrowser/SearchResultBrowser in the same SplitView slot when PLAYLISTS is active — see UC-22 (property PlaylistsData playlistsData, property var engine/autoPlay forwarded to AlbumCard; header shows a compact LOAD button instead of a title label)
├── AlbumCard.qml       Single album card delegate (cover + year label + track listing; single-track drag & drop to queue; no selection; no context menus)
│                         property var engine  (optional; used for double-click add-to-queue and drag cursor override)
│                         property var autoPlay  (optional; gates double-click add via autoPlay.manualQueueEditingAllowed, see UC-16)
│                         property int albumYear  (0 = unknown, hides the label; left-aligned under the cover, Theme.labelMd, literal white)
│                         property string albumGenre  (empty = hidden; renders as "Genre | Year" when both set — SearchResultBrowser-only, see UC-21; AlbumBrowser leaves it unset so Library-tab cards are unchanged)
├── PlaybackQueue.qml   Queue panel  default width 374 px, user-resizable  (bound to PlaybackEngine model; DropArea; move/remove; shows activePlaylistName in header when set; shows LOCK PLAYLIST toggle when a playlist is active)
│                         Auto-scrolls to keep the current track topmost (and upcoming tracks visible below it) on every add/remove, whenever the queue overflows the panel — independent of AUTO PLAY/MANUAL MODE, see UC-11
│                         property var autoPlay  (gates clear/remove/move/reorder/drop via autoPlay.manualQueueEditingAllowed + autoPlay.queueClearAllowed; row click (select another track) via autoPlay.trackNavigationAllowed; clear button routes through autoPlay.clearQueueAndHistory(), see UC-16)
├── NowPlaying.qml      Right panel  default width 359 px, user-resizable  (bound to PlaybackEngine + PlaylistManager: art + transport + progress + playlists + 10-star rating row, see UC-14)
|                         property playlistManager PlaylistManager
|                         property var autoPlay  (gates playlist-load add; LOAD and REMOVE buttons are both fully disabled during an active AUTO PLAY session via autoPlay.queueClearAllowed; Play/Pause via autoPlay.playPauseAllowed; Previous/Next via autoPlay.trackNavigationAllowed, see UC-16)
|                         signal newPlaylistRequested()  <- "+ NEW" button click
|                         signal bigCoverRequested()  <- left-click on the album cover (pointing-hand cursor, same as Play/Pause); opens the detachable BigCoverWindow pane, see below
|                         FileDialog loadPlaylistDialog <- opens on LOAD; default folder = playlistDirectory(); filter *.xml
|                         Playlist row 1: NEW | LOAD (disabled whenever an AUTO PLAY session is active; when enabled, clears active playlist first if one is loaded, then opens file dialog)
|                         Playlist row 2: EXPORT (permanently disabled — not yet implemented) | REMOVE (active only when playlist loaded AND queue-clear is allowed; routes through autoPlay.clearQueueAndHistory())
│                         signal newPlaylistRequested()  ← “+ NEW” button click
└── BottomBar.qml       Footer toolbar  height 56 px  (signal scanRequested; scanning property; autoPlayReady property — bound to libraryModel.ratingsReady, gates whether AUTO PLAY is clickable at all; autoPlay property — bound to the AutoPlayController instance; button color reads autoPlay.active (green/red traffic light), click calls autoPlay.toggle(), see UC-16)
                          signal tagInfoToggleRequested()  ← TAG INFORMATION button click; property tagInfoPaneOpen (bound from Main.qml) drives its on/off color — same "dumb button, owner decides" split as scanRequested()/scanning, see UC-18
                          signal audioVisualizerToggleRequested()  ← AUDIO VISUALIZER button click; property audioVisualizerPaneOpen (bound from Main.qml) drives its on/off color — same split, see UC-19
                          signal milkdropToggleRequested()  ← MILKDROP button click; property milkdropPaneOpen (bound from Main.qml) drives its on/off color — same split, see UC-20
```

## LibraryModel Component

`LibraryModel` is a C++ `QAbstractListModel` subclass marked `QML_ELEMENT`.
It owns a `LibraryScanner` worker that lives on a dedicated `QThread`.  All
heavy I/O (tag reading, directory walking, JSON serialisation) runs off the
main thread; the main thread only receives light result copies via Qt's
queued-connection mechanism. Tag reading itself is further fanned out across
a small `QThreadPool` (via `QtConcurrent`) spawned from the worker thread —
see `LibraryScanner::readTagsParallel()`/`resolveCoverArt()` — so scan time
scales with available cores (bounded conservatively; this is disk-I/O-bound
work), not just with track count.

### C++ class overview

| Class | File | Role |
|-------|------|------|
| `TrackInfo` | `trackinfo.h` | Flat data struct; the single record type in the library |
| `TagReader` | `tagreader.h/cpp` | Zero-dependency ID3v2 + FLAC + Opus tag reader; cover thumbnail generator |
| `LibraryCache` | `librarycache.h/cpp` | Atomic read/write of `Topaz.library.json` |
| `LibraryScanner` | `libraryscanner.h/cpp` | Worker: directory walk, parallel tag-reading (`QtConcurrent`/`QThreadPool`), genre filter, QFileSystemWatcher |
| `LibraryModel` | `librarymodel.h/cpp` | QAbstractListModel + Q_INVOKABLE query helpers exposed to QML |
| `PlaylistManager` | `playlistmanager.h/cpp` | XSPF playlist file creation; path-portability helpers; `listPlaylists()` for the PLAYLISTS tab (see UC-22) |
| `SystemVolumeController` | `systemvolumecontroller.h/cpp` | Windows OS master-volume control via Core Audio COM |

### SystemVolumeController — Windows OS master volume

Controls the Windows **system** output volume (not Topaz's own playback level —
`QAudioOutput::setVolume()` is separate, used only internally for crossfade ramping).
Qt has no cross-platform API for this, so `SystemVolumeController` wraps the Windows
Core Audio `IAudioEndpointVolume` COM interface directly — the same kind of
native-Windows-API work as `AutoPlayController`'s `QSystemTrayIcon` notifications.

`Q_PROPERTY(int volume READ volume NOTIFY volumeChanged)` — deliberately **no WRITE
clause**; mutation goes through a separate `Q_INVOKABLE void setVolume(int)`, matching
`AppConfig`'s convention everywhere else in this codebase. This matters: a function
referenced only via a `Q_PROPERTY`'s `WRITE` clause is wired into the `obj.prop = x`
assignment mechanism but is **not** itself exposed as a callable `obj.setX(x)` method
from QML unless it's independently `Q_INVOKABLE`. An early version of this class used
`WRITE setVolume` and called it from QML as `systemVolume.setVolume(...)` — the call
silently did nothing (no error, no crash), because `setVolume` wasn't actually
reachable that way; the bound `Slider` still looked fully functional since its
displayed value came from the `Slider`'s own local `value`, not from `volume`. Any
future `Q_PROPERTY` on a new class in this codebase should follow the same
READ/NOTIFY-only + separate-`Q_INVOKABLE`-setter pattern to avoid repeating this.

Construction sequence: `CoInitializeEx` (apartment-threaded; `RPC_E_CHANGED_MODE` —
COM already initialized on this thread by something else, e.g. Qt itself — is treated
as "still usable, just don't call `CoUninitialize()` for it later") → `CoCreateInstance`
an `IMMDeviceEnumerator` → `GetDefaultAudioEndpoint(eRender, eConsole, ...)` (the same
role Windows' own volume flyout/taskbar targets) → `Activate` an `IAudioEndpointVolume`
on it → `GetMasterVolumeLevelScalar()` once to seed `volume` (0-100, rounded) from
whatever the OS actually has at startup → `RegisterControlChangeNotify()` a callback
for live sync (below). All the well-known CLSID/IID GUIDs are hardcoded (verified
against Microsoft's published values, and for `IAudioEndpointVolumeCallback`'s IID
specifically, against the actual mingw-w64 `endpointvolume.h` source) rather than
relying on `__uuidof()` (an MSVC extension with inconsistent MinGW coverage) or
linking `uuid.lib` via `-DINITGUID` — kept dependency-free, consistent with the rest
of this codebase. Any COM step failing logs a `qWarning()` (this class's own boundary
with unpredictable external/OS state is judged to warrant it, even though no other
class in this codebase logs anything) and leaves the endpoint pointer null;
`setVolume()` becomes a no-op (with its own `qWarning()`) rather than crashing.

**Staying in sync with volume changes made outside Topaz** — two layers:
- `Q_INVOKABLE void refresh()`: re-runs just the `GetMasterVolumeLevelScalar()` +
  seed step. Called from `TopBar.qml`'s loudspeaker `onClicked`, right before the
  popup opens — covers "the OS volume changed while Topaz was already running, before
  the pane was ever opened."
- Live sync for the rest of the session: a private nested `VolumeChangeCallback`
  class (in the `.cpp`, not the header) implements `IAudioEndpointVolumeCallback`,
  registered via `RegisterControlChangeNotify()` after `Activate()` succeeds and
  unregistered in the destructor before releasing `endpointVolume`. Its `OnNotify()`
  fires whenever the endpoint's volume changes **from any source** — other apps,
  Windows' own volume UI, or hardware volume controls (keys, external soundcard
  knobs, etc.) that route through the OS volume model. Whether a *specific* piece of
  external hardware routes through that model at all is outside Windows' or Topaz's
  control — most consumer USB audio interfaces do (they act like standard multimedia
  volume keys), but some pro-audio interfaces do pure analog attenuation on the
  device itself, entirely bypassing it; in that case no Windows API could ever
  observe the change, since it isn't an OS-level concept at all.
  - **Threading**: `OnNotify` runs on an internal audio-engine worker thread, never
    the GUI thread that owns `SystemVolumeController`. It cannot safely touch
    `m_volume`/emit `volumeChanged()` directly. It instead calls
    `QMetaObject::invokeMethod(this, lambda, Qt::QueuedConnection)` passing the
    controller itself as the context object — Qt automatically marshals the call
    onto the controller's own thread, and automatically (silently) drops it if the
    controller is destroyed before the queued call runs, with no extra manual
    guarding needed. The shared `applyLevel(float)` helper (used by the constructor,
    `refresh()`, and this callback alike) does the actual scalar→0-100 conversion and
    the emit, guarded to no-op if the value didn't actually change.
  - **Self-notification loopback**: the audio engine notifies *all* registered
    listeners for *any* change, including ones this class itself caused via
    `setVolume()` — so every `setVolume()` call also triggers its own `OnNotify`
    round-trip back to this same object. This is harmless, not a bug: `applyLevel`'s
    unchanged-value guard makes it a no-op re-affirmation of the value already set.
  - `VolumeChangeCallback` needs to call the private `applyLevel()`, so
    `SystemVolumeController` forward-declares it and declares it a `friend class` —
    the only such relationship in this codebase, needed because the callback class
    must live in the `.cpp` (same PIMPL/no-Windows-headers-in-the-header rationale
    below) rather than as a member of `SystemVolumeController` itself.

All Windows/COM headers (`mmdeviceapi.h`, `endpointvolume.h`) are confined to the
`.cpp` behind a private `struct Impl` (PIMPL) — `<windows.h>`-family headers define
macros (`interface`, `min`, `max`) that can clash with Qt/STL if leaked into every
file that includes `systemvolumecontroller.h`.

**Known simplification** (not fixed, not requested): no default-audio-device-change
tracking — the endpoint is resolved once at construction; if the user switches their
default output device in Windows Settings mid-session, `SystemVolumeController` keeps
targeting the old one. An `IMMNotificationClient`/`OnDefaultDeviceChanged`
registration would handle that, but it's a distinct concern (device swap, not volume
level) from what was asked for here.

### TagReader — supported formats

| Format | Tag standard | Fields read |
|--------|-------------|-------------|
| MP3 | ID3v2.2, ID3v2.3, ID3v2.4 | TIT2, TPE1, TPE2, TALB, TRCK, TCON, TLEN, TYER/TDRC, APIC |
| FLAC | Vorbis Comment + STREAMINFO + PICTURE | TITLE, ARTIST, ALBUMARTIST, ALBUM, TRACKNUMBER, GENRE, DATE |
| Opus | Ogg container; `OpusTags` packet (Vorbis-comment layout) | TITLE, ARTIST, ALBUMARTIST, ALBUM, TRACKNUMBER, GENRE, DATE |

**Bitrate and duration for MP3**: the first MPEG frame header (past the ID3v2 tag) is
always scanned to determine bitrate, since ID3v2 has no dedicated bitrate frame. Duration
is taken from the `TLEN` frame when present; otherwise it is estimated from the same
frame header scan:
1. Scan past ID3v2 tag to first MPEG sync word; read bitrate/sample-rate from the frame header.
2. Check for Xing/Info VBR header → use `frame_count × samples_per_frame / sample_rate`.
3. CBR fallback → `audio_bytes × 8 / bitrate`.

**Duration and bitrate for Opus**: Opus has no total-sample-count field like FLAC's
`STREAMINFO`. `readOpus()` walks Ogg page framing (`TagReader::readOggPageHeader()`,
shared with `readRawCover()`'s Opus branch) past every page, tracking the granule
position of the *last* page in the stream; duration is
`(lastGranule - preSkip) × 1000 / 48000` ms, where `preSkip` comes from the `OpusHead`
packet on the first page (bytes 10-11, little-endian — RFC 7845 §5.1). Opus has no
nominal-bitrate header field either, so bitrate falls back to the same
filesize-over-duration approximation FLAC uses when not explicitly known.

An Ogg page's payload is capped at ~64KB (255 segments × 255 bytes), but the
`OpusTags` packet routinely exceeds that once it embeds cover art, and per RFC 7845 §3
is allowed to span multiple pages. `TagReader::readOggPacket()` handles this
transparently — it concatenates page payloads for as long as
`readOggPageHeader()`'s `continuesPacket` out-parameter (true when a page's last
lacing value is 255) says the packet isn't finished — and is used to read both
`OpusHead` and `OpusTags` in `readOpus()` and `readRawCover()`'s Opus branch. Reading
`OpusTags` as a single page (the original implementation) silently truncated or missed
`METADATA_BLOCK_PICTURE` for any file where cover art pushed the comment header past
one page, while earlier, smaller comments (TITLE/ARTIST/...) still parsed fine — this
was the cause of a "tags work, cover doesn't" bug fixed shortly after Opus support
first shipped.

**Cover thumbnails**: extracted from APIC (MP3), PICTURE (FLAC), or the
`METADATA_BLOCK_PICTURE` comment (Opus — a base64-encoded block using the identical
binary layout as FLAC's PICTURE block, decoded and parsed via the shared
`TagReader::parsePictureBlock()` helper), scaled to 160×160 JPEG via `QImage`, encoded
as Base64. Only one thumbnail is generated per `(genre, albumArtist, album)`
triple; all other tracks in the same album (and same genre) store an empty
`coverThumb`. Passed to `AlbumCard` as a
`data:image/jpeg;base64,…` URL.

`parsePictureBlock()` and the `VORBIS_COMMENT` vendor-string skip in `readFlac()` both
skip a length-prefixed field with two explicit statements (`const len = beU32(); pos
+= len;`) rather than a single combined expression like `pos += 4 + int(beU32())`.
That combined form looks equivalent but isn't: since C++17, a compound assignment's
right operand — including `beU32()`'s own `pos`-mutating side effect — is sequenced
before the left operand's value read, so it silently double-skips the length field
itself. This was verified empirically against this project's exact compiler/standard,
not just reasoned about. It was the actual cause of Opus (and, latent/unconfirmed
until fixed alongside it, FLAC) cover art never showing up, and of FLAC's tag fields
being at risk of the same corruption — fixed together since `parsePictureBlock()` is
shared by both formats. Watch for this exact pattern (a lambda that mutates a captured
index as a side effect, combined into one assignment expression with its own return
value) if extending `TagReader` further.

**Full-resolution cover** (`readRawCover`): a separate static method added for
the `NowPlaying` panel. It re-opens the file, locates the APIC (MP3), PICTURE (FLAC),
or `METADATA_BLOCK_PICTURE` comment (Opus) and returns the raw embedded image bytes —
no scaling. Called off-thread by `PlaybackEngine` via `QtConcurrent::run` when the
current track changes (see `PlaybackEngine::currentLargeCoverSource`).

### LibraryModel public API

| Method / Property | Description |
|-------------------|-------------|
| `appConfig` | Bound AppConfig instance (set from Main.qml) |
| `scanning` | `true` while a scan is running |
| `scanProgress` | 0–100 completion percentage |
| `trackCount` | Number of tracks currently in the model |
| `albumCount` | Number of distinct albums currently in the model (canonicalized by trimmed+lowercased `albumArtist\|album`, same normalization as `buildLibraryTree()`). Recomputed in one O(N_tracks) pass whenever `applyTracks()` replaces `m_tracks` (cache load / scan complete) — not recomputed per read. Shown on the About dialog's TOPAZ tab. |
| `ratingsReady` | `true` once a scan (full or stat-check) has completed at least once in this session with rating enrichment applied (see UC-14). Gates the AUTO PLAY button in `BottomBar`; never reset back to `false`. |
| `loadCacheAndStartStatCheck()` | Load cache instantly, then dispatch stat-check |
| `startFullScan()` | Trigger a full rescan on the worker thread |
| `genres()` | Distinct genre strings present in the library |
| `artistsForGenre(genre)` | Album artists for a genre, sorted |
| `albumsForArtist(artist, genre)` | Album titles for an artist, sorted |
| `filteredAlbums(activeGenres, selectedArtist, selectedAlbum)` | Album display objects for AlbumBrowser. **Single O(N_tracks) pass** using `QHash` to group tracks by `(albumArtist\|album)` key; cover thumb and year (first non-zero seen per album, same defensive pattern as the cover thumb) collected in the same pass; no per-album full rescan. Replaces the former O(N_tracks × N_albums) three-pass algorithm. Result sorted by albumArtist ascending, then year descending, then albumTitle ascending (case-insensitive); unknown-year albums (`year == 0`) sort last within their artist group. |
| `buildLibraryTree(activeGenres)` | **Single-pass** tree builder: returns `[ { genre, artists: [ { name, albums: [{title}] } ] } ]` for `LibraryData._rebuildTree()`. One O(N_tracks) scan replaces the former N_genres + N_artists separate full-list scans. |
| `coverThumbForAlbum(album, albumArtist)` | Base64 thumbnail for an album |
| `searchLibrary(query, mode, activeGenres, considerGenre, matchWholeWord)` | Substring search across `albumArtist`/`album`/`title` — see UC-21. `matchWholeWord=true` requires the match to be bounded by non-alphanumeric characters (or field start/end) via a plain-`QString` `matchesWholeWord()` helper, not `QRegularExpression`; `false` (default) uses ordinary substring `contains()`, chosen once per call via a small lambda rather than branching per field. `mode` is `"all"` \| `"artists"` \| `"albums"` \| `"tracks"` (unrecognized values behave as `"all"`). **Single O(N_tracks) pass, all modes** — `albumArtist`/`album` are constant across every track in their group (the same invariant `filteredAlbums()`'s grouping key relies on), so a match on either field for one track is guaranteed to match every sibling track in that album too; no second "find matches, then rescan for siblings" pass is needed. A title-only match is inherently per-track already, which is exactly the "just this track, not its album siblings" behavior `"tracks"` mode needs. `considerGenre=false` ignores `activeGenres` entirely; `considerGenre=true` with an empty `activeGenres` returns no results (mirrors `filteredAlbums()`'s equivalent short-circuit). Empty/whitespace-only `query` returns no results. Shares its post-filter grouping/sort/serialize tail with `filteredAlbums()` via a private `serializeAlbumAccum()` helper (an anonymous-namespace `AlbumAccum` struct, extracted from the two functions' ~60 lines of previously-duplicated logic) — same `QVariantList` shape as `filteredAlbums()`, except `isActive` is always `false` (no search-result card is naturally "selected"). **Cover fix-up**: since `"tracks"`-mode (and `"all"`-mode title-only) matches only include the matching track(s), not the rest of the album, a second pass over `m_tracks` fills in any still-missing album cover from any track carrying one (skipped entirely if every matched album already has a cover) — otherwise a track whose own tag lacks embedded art would show no cover even though a sibling track has one. `filteredAlbums()`/`buildLibraryTree()` never need this since they always include an album's full track list already. |
| `buildStandaloneTrackCards(tracks)` | Converts an arbitrary raw track list (the shape `PlaylistManager::loadPlaylist()` returns) into one standalone, `AlbumCard`-shaped entry **per track** — no grouping by album, unlike `filteredAlbums()`/`searchLibrary()` — see UC-22. Builds a `filePath → TrackInfo*` lookup over `m_tracks` once (O(N_tracks)) so any track still present in the scanned library reuses its own tag data at no extra I/O cost; a track no longer in the scan is still rendered, synthesized from the input map's own fields. Cover art is resolved per track via `coverThumbForAlbum(album, albumArtist)` whenever the matched/synthesized track's own `coverThumb` is empty — the common case, since `coverThumb` is only populated on one representative track per album in the whole scanned library (see UC-05) — so every track of an album shows a cover regardless of which one happens to be that representative; only an album with no cover anywhere in the library renders without one. `isActive` is always `false`. Calls `serializeAlbumAccum(albumAccum, false, /*preserveOrder=*/true)` — cards are emitted in the playlist's own track order rather than alphabetically re-sorted. |
| `libraryRefreshed()` signal | Emitted after cache load or scan complete |

### Library cache format — `Topaz.library.json`

Stored alongside `Topaz.config` in `QStandardPaths::AppConfigLocation`.

```json
{
  "version": 1,
  "tracks": [
    {
      "id":           "550e8400-e29b-41d4-a716-446655440000",
      "volume":       "MusicDrive",
      "relPath":      "/Electronic/Techno/Artist/Album/01_Track.flac",
      "rawPath":      "D:/Music/Electronic/Techno/Artist/Album/01_Track.flac",
      "fileName":     "01_Track.flac",
      "title":        "Track Title",
      "artist":       "Artist Name",
      "albumArtist":  "Album Artist",
      "album":        "Album Name",
      "genre":        "Techno",
      "track":        1,
      "year":         2018,
      "duration":     234000,
      "bitrate":      1024,
      "fileSize":     54321678,
      "lastModified": 1718400000000,
      "coverThumb":   "",
      "rating":       0,
      "ratingId":     "6f9619ff-8b86-d011-b42d-00c04fc964ff"
    }
  ]
}
```

**Path storage**: `volume`/`relPath` replace what used to be a single absolute
`filePath`, anchored on the track's volume label via `VolumePath`
(`volumepath.h`) — the same scheme `AppConfig` uses for monitored folders and
`PlaylistManager` for XSPF `<location>`/`<volume>`. `rawPath` is kept only as a
last-resort fallback for unlabeled volumes. `LibraryCache::save()` captures this
from the just-scanned `TrackInfo.filePath` (always a live absolute path at that
point); `LibraryCache::load()` resolves it back via `VolumePath::quickPath()` — an
in-memory match against currently mounted volumes with **no filesystem access**,
since `load()` runs synchronously on the main thread for the instant-startup
cache display (see below) at up to 12K+ tracks, and a `QFileInfo::exists()` stat
call per track there would stall it. A track whose volume isn't currently
mounted is skipped from the loaded set (the async `statCheck` that always
follows immediately after would prune it a moment later anyway).

**Cover storage**: `coverThumb` is populated for one representative track of
each `(genre, albumArtist, album)` triple (genre included so a same-named
album filed under two different genres gets its own cover instead of the two
colliding); all other tracks have an empty string.
An average JPEG thumbnail (160×160, quality 80) is ≈ 10 KB; Base64-encoded ≈ 14 KB.
For 500 albums: ≈ 7 MB total cache size — well within acceptable range.

### Rating cache format — `Topaz.rating.json`

Stored alongside `Topaz.config`/`Topaz.library.json` in `QStandardPaths::AppConfigLocation`.
Written and read by `RatingCache` (`ratingcache.h/cpp`), mirroring `LibraryCache`'s
atomic tmp-then-rename save pattern. This file — not `Topaz.library.json` — is the
authoritative store for user ratings, so ratings survive a full library rebuild
(rescan). See UC-14 for the full read/write flow.

```json
{
  "version": 1,
  "ratings": [
    {
      "genre":    "Techno",
      "ratingId": "6f9619ff-8b86-d011-b42d-00c04fc964ff",
      "rating":   8
    }
  ]
}
```

Only rated tracks (`rating` 1–10) are ever written; unrated tracks (`rating` 0) never
appear here. `ratingId` is the join key back to `TrackInfo.ratingId` (see
`TrackInfo::computeRatingId()` in the class diagram below and UC-14).

### Data Flow: Library Scan

```
BottomBar.scanRequested()
   │
   ▼
Main.qml → libraryModel.startFullScan()
   │  copies appConfig.genres + folders
   │  emit _requestFullScan (queued → worker thread)
   ▼
LibraryScanner.fullScan() [worker thread]
   └── performScan()  (shared by fullScan() and statCheck())
        ├── discoverAudioFiles() per folder (recursive per config) — plain
        │     directory listing, no tag reads
        ├── classify each discovered file against the cache:
        │     unchanged → reuse cached TrackInfo verbatim
        │     new/changed → queue for parallel read
        │     (cached entries not rediscovered = deleted, simply dropped)
        ├── readTagsParallel() — TagReader::read(path, false) over a bounded
        │     QThreadPool, chunked (~200 files/chunk)
        │     genre filter (case-insensitive match) applied per result
        │     assign stable UUID from cache or new QUuid
        │     emit scanProgress(done, total) between chunks
        ├── resolveCoverArt() — one deterministic representative track per
        │     (genre, albumArtist, album) re-read in parallel with cover extraction
        ├── LibraryCache::save(result) → Topaz.library.json
        └── emit scanCompleted(tracks)
          │ (queued → main thread)
          ▼
LibraryModel.onScanCompleted()
   ├── beginResetModel / endResetModel → updates QML ListView delegates
   ├── emit trackCountChanged()
   └── emit libraryRefreshed()
          │
          └──► LibraryData._rebuildTree()
                   └── LibraryTree.activeGenres refreshes
                       AlbumBrowser.currentAlbums refreshes
```

### Data Flow: Startup (Hybrid Strategy)

```
Main.qml Component.onCompleted
   │
   ▼
libraryModel.loadCacheAndStartStatCheck()
   │
   ├── Step 1: LibraryCache::load() ← synchronous, main thread
   │     < 100ms for 12K entries
   │     applyTracks() → libraryRefreshed() → UI displays cached data
   │
   └── Step 2: emit _requestStatCheck (queued → worker thread)
               LibraryScanner.statCheck() → performScan(), same pipeline as
               fullScan() above — the discover/classify step is what
               validates cached entries (unchanged → reused as-is, missing →
               dropped) and finds new/changed files, all in one pass
               └── emit scanCompleted → model refresh (only if changes found)
```

```
[Runtime] QFileSystemWatcher.directoryChanged
   │  (debounced 2 s)
   ▼
LibraryScanner.statCheck() → same flow as startup step 2
```

`AppConfig` is a C++ `QObject` subclass marked with `QML_ELEMENT`.  It is
instantiated once in `Main.qml` (`AppConfig { id: appConfig }`) and passed by
reference to `LibraryData`, `SetupDialog`, and `PlaybackEngine` (the latter reads
`crossfadeEnabled`/`crossfadeSeconds` live — never cached — on every crossfade
eligibility check; see UC-15).

### Responsibilities

- Load `Topaz.config` from disk at construction time.
- Expose `genres` (`QStringList`) and `folders` (`QVariantList`) as QML-readable
  properties with change notifications.
- Provide `Q_INVOKABLE` mutators that update in-memory state, emit the appropriate
  change signal, and call `save()` atomically.
- Convert `file://` URLs (returned by `FolderDialog`) to local paths via
  `QUrl::toLocalFile()`.

### Config file location

```
Windows:  %APPDATA%\Topaz\Topaz\Topaz.config
Linux:    ~/.config/Topaz/Topaz.config
macOS:    ~/Library/Preferences/Topaz/Topaz.config
```

(Determined at runtime by `QStandardPaths::AppConfigLocation`.)

### Config file format — `Topaz.config`

```json
{
    "genres": [
        "Techno",
        "IDM",
        "Drone"
    ],
    "folders": [
        { "volume": "MusicDrive", "relPath": "/Electronic", "rawPath": "D:/Music/Electronic",
          "includeSubfolders": true  },
        { "volume": "MusicDrive", "relPath": "/Jazz",       "rawPath": "D:/Music/Jazz",
          "includeSubfolders": false }
    ],
    "windowWidth":        1920,
    "windowHeight":       1080,
    "libraryTreeWidth":   286,
    "playbackQueueWidth": 374,
    "nowPlayingWidth":    359,
    "crossfade": {
        "enabled": false,
        "seconds": 5.0
    },
    "autoPlay": {
        "queueHorizon": 5,
        "titleAddingIntervalSeconds": 30,
        "considerGenre": false,
        "considerRating": false,
        "minimumRating": 5,
        "allowManualModification": false,
        "songRepeat": "once",
        "transportAccess": "nothing",
        "flickerNewTracks": false
    },
    "bigCoverPane": {
        "x": 100, "y": 100, "width": 400, "height": 400, "screenName": "DISPLAY1"
    },
    "tagInfoPane": {
        "x": 100, "y": 100, "width": 500, "height": 230, "screenName": "DISPLAY1"
    },
    "audioVisualizer": {
        "barCount": 24, "color": "#00DAF3", "decaySpeed": 0.5, "sensitivity": 0.5,
        "peakHoldEnabled": true, "paneOpacity": 1.0
    },
    "audioVisualizerPane": {
        "x": 100, "y": 100, "width": 500, "height": 260, "screenName": "DISPLAY1"
    }
}
```

Each folder is anchored on its volume's **label** rather than a Windows drive
letter (`VolumePath`, `volumepath.h`) — `volume`/`relPath` are what's actually
resolved at runtime; `rawPath` is kept only as a last-resort fallback for
unlabeled volumes. This means a monitored folder keeps working after its drive
is reassigned a different letter or remounted elsewhere (including under a
future Linux build's mount points). `AppConfig::folders()` computes two
non-persisted fields fresh on every call — `path` (the currently resolved
absolute path, or `""` if the volume isn't mounted right now) and `available`
(`bool`) — which `SetupDialog`'s FILE MONITORING tab uses to dim a folder row
and show a "not connected" indicator instead of a broken path (see UC-04).
`LibraryScanner` simply skips folders with an empty `path`, same as it always
has for any other unreachable folder.

Settings are grouped into a nested object per `SetupDialog` tab (`crossfade`,
`autoPlay`, `audioVisualizer`); genres/folders/window-layout stay flat at the top
level. The `AppConfig` property/method names (`crossfadeEnabled`, `crossfadeSeconds`,
`autoPlayQueueHorizon`, and their setters) are unchanged by this grouping — only the
on-disk JSON shape differs. `bigCoverPane`/`tagInfoPane`/`audioVisualizerPane` are
also nested; unlike the others, their *presence* in the file (not a stored bool) is
what "configured" means — absent means that pane has never been positioned yet, so
`Main.qml` uses a centered default instead of its saved `X`/`Y` (see UC-17/UC-18/UC-19).

### AppConfig public API

| Method | Description |
|--------|-------------|
| `addGenre(name)` | Append genre (deduplicates case-insensitively); auto-saves. |
| `removeGenreAt(index)` | Remove genre by index; auto-saves. |
| `clearGenres()` | Remove all genres; auto-saves. |
| `addFolder(rawPath, includeSubfolders)` | Converts `rawPath` to a volume-anchored `VolumePath` (`volumepath.h`) and appends it (deduplicates by `(volume, relPath)`); auto-saves. |
| `removeFolderAt(index)` | Remove folder by index; auto-saves. |
| `clearFolders()` | Remove all folders; auto-saves. |
| `setFolderSubfolders(index, flag)` | Toggle the includeSubfolders flag; auto-saves. |
| `saveLayout(windowWidth, windowHeight, libraryTreeWidth, playbackQueueWidth, nowPlayingWidth)` | Persist the current window size and resizable panel widths in a single atomic JSON write. Called from QML via a 500 ms debounce timer on every resize event. Window dimensions are not overwritten while in fullscreen. |
| `crossfadeEnabled` / `setCrossfadeEnabled(enabled)` | Whether crossfade is active between tracks (default `false`); auto-saves. Set from `SetupDialog`'s CROSSFADE tab toggle (see UC-15). |
| `crossfadeSeconds` / `setCrossfadeSeconds(seconds)` | Crossfade length in seconds (default `5.0`); clamped to `[2.0, 10.0]` and snapped to the nearest `0.5` s; auto-saves. Set from `SetupDialog`'s CROSSFADE tab slider. |
| `autoPlayQueueHorizon` / `setAutoPlayQueueHorizon(tracks)` | How many tracks the (still-unimplemented) AUTO PLAY feature should keep filled into `PlaybackQueue` as a lookahead (default `5`); clamped to `[1, 15]`; auto-saves. Set from `SetupDialog`'s AUTO PLAY tab slider ("Queue Horizon"); not yet consumed by any queue-filling logic (see UC-14). |
| `autoPlayTitleAddingIntervalSeconds` / `setAutoPlayTitleAddingIntervalSeconds(seconds)` | Polling interval, in seconds, the (still-unimplemented) AUTO PLAY feature should use to add one new track at a time to the queue (default `30`); clamped to `[5, 90]`; auto-saves. Set from `SetupDialog`'s AUTO PLAY tab slider ("Title Adding"); not yet consumed by any poller (see UC-14). |
| `autoPlayConsiderGenre` / `setAutoPlayConsiderGenre(enabled)` | Whether the (still-unimplemented) AUTO PLAY feature should factor genre into track selection (default `false`); auto-saves. Set from `SetupDialog`'s AUTO PLAY tab toggle ("Consider Genre"); not yet consumed by any selection logic (see UC-14). |
| `autoPlayConsiderRating` / `setAutoPlayConsiderRating(enabled)` | Whether the (still-unimplemented) AUTO PLAY feature should factor title rating into track selection (default `false`); auto-saves. Set from `SetupDialog`'s AUTO PLAY tab toggle ("Consider Rating"); not yet consumed by any selection logic (see UC-14). |
| `autoPlayMinimumRating` / `setAutoPlayMinimumRating(rating)` | Minimum title rating (1-10) the (still-unimplemented) AUTO PLAY feature should consider when `autoPlayConsiderRating` is on (default `5`); clamped to `[1, 10]`; auto-saves. Set from `SetupDialog`'s AUTO PLAY tab star row ("Minimum Rating"), reusing the same star glyph/palette as `NowPlaying`'s rating row; not yet consumed by any selection logic (see UC-14). |
| `autoPlayAllowManualModification` / `setAutoPlayAllowManualModification(enabled)` | Whether the (still-unimplemented) AUTO PLAY feature should allow the user to manually modify its auto-filled queue entries (default `false`); auto-saves. Set from `SetupDialog`'s AUTO PLAY tab toggle ("Allow Manual Modification"); not yet consumed by any queue-filling or editing logic (see UC-14). |
| `autoPlaySongRepeat` / `setAutoPlaySongRepeat(mode)` | How many times AUTO PLAY should play a selected track before moving on (default `"once"`); one of `"once"`, `"twice"`, `"twiceIfNoneAvailable"`, `"several"` — invalid values are silently ignored (no-op); auto-saves. Set from `SetupDialog`'s AUTO PLAY tab radio group ("Play a Title") — the app's first radio-button control; not yet consumed by any selection logic (see UC-14). |
| `autoPlayTransportAccess` / `setAutoPlayTransportAccess(mode)` | How much manual transport control remains available during an active AUTO PLAY session while `autoPlayAllowManualModification` is off (default `"nothing"`); one of `"nothing"`, `"playPause"`, `"playPauseAndSelect"` — invalid values are silently ignored (no-op); auto-saves. Set from `SetupDialog`'s AUTO PLAY tab "Exceptions" radio group, indented under and only interactive while Allow Manual Modification is off. Consumed by `AutoPlayController::playPauseAllowed()`/`trackNavigationAllowed()` (see UC-16). |
| `autoPlayFlickerNewTracks` / `setAutoPlayFlickerNewTracks(enabled)` | Whether a track `AutoPlayController` just added briefly flickers its `PlaybackQueue` row (default `false`); auto-saves. Set from `SetupDialog`'s AUTO PLAY tab toggle ("New Tracks are Flickering"). Consumed by `PlaybackQueue.qml`'s row delegate via the new `PlaybackEngine` `autoPlayAdded` queue role (see UC-16). |
| `bigCoverPaneConfigured` / `bigCoverPaneX` / `Y` / `Width` / `Height` | Read-only; the detachable BigCoverWindow pane's last-saved geometry (defaults `400`×`400`, `configured` starts `false`). See UC-17. |
| `saveBigCoverPaneGeometry(x, y, width, height, screenName)` | Persists the pane's geometry after a move/resize settles; `screenName` is stored for completeness/debugging but not re-exposed as its own property. Auto-saves. Called from `Main.qml`'s `Loader` on `FloatingPane.geometrySettled()`. |
| `tagInfoPaneConfigured` / `tagInfoPaneX` / `Y` / `Width` / `Height` | Read-only; the detachable TagInfoWindow pane's last-saved geometry (defaults `500`×`230`, `configured` starts `false`). Same convention as `bigCoverPane*` above. See UC-18. |
| `saveTagInfoPaneGeometry(x, y, width, height, screenName)` | Persists the pane's geometry after a move/resize settles. Same calling convention as `saveBigCoverPaneGeometry`. |
| `audioVisualizerBarCount` / `setAudioVisualizerBarCount(count)` | Number of bars the Audio Visualizer pane renders (default `24`); clamped to `[8, 64]`; auto-saves. Set from `SetupDialog`'s AUDIO VISUALIZER tab slider. Read live by `AudioVisualizerController` on every processed audio block — never cached, same convention `PlaybackEngine` uses for crossfade settings. See UC-19. |
| `audioVisualizerColor` / `setAudioVisualizerColor(color)` | Hex color string for the bars (default `"#00DAF3"`); no validation beyond non-empty. Set from 32 preset swatches (16-column `Grid`, two full rows) on the AUDIO VISUALIZER tab (not a full color picker — see UC-19). |
| `audioVisualizerDecaySpeed` / `setAudioVisualizerDecaySpeed(speed)` | How quickly bars fall after a peak (default `0.5`); clamped to `[0.0, 1.0]`; auto-saves. Set from `SetupDialog`'s AUDIO VISUALIZER tab slider ("SLOW"…"FAST"). |
| `audioVisualizerSensitivity` / `setAudioVisualizerSensitivity(sensitivity)` | Gain offset applied before dB normalization in `AudioVisualizerController::processBlock` (default `0.5` = no change from the original fixed mapping); clamped to `[0.0, 1.0]`; auto-saves. Mapped to ±18dB (`(sensitivity - 0.5) * 2 * 18`) — `1.0` boosts bars closer to full height on loud passages, `0.0` cuts them noticeably lower. Set from `SetupDialog`'s AUDIO VISUALIZER tab slider ("LOW"…"HIGH", displayed 0–100%). See UC-19. |
| `audioVisualizerPeakHoldEnabled` / `setAudioVisualizerPeakHoldEnabled(enabled)` | Whether a slowly-decaying peak marker is drawn above each bar (default `true`); auto-saves. Set from `SetupDialog`'s AUDIO VISUALIZER tab toggle. |
| `audioVisualizerPaneOpacity` / `setAudioVisualizerPaneOpacity(opacity)` | Background-only opacity for the Audio Visualizer pane (default `1.0`, fully opaque); clamped to `[0.0, 1.0]`; auto-saves. Applied to `AudioVisualizerWindow`'s `Window.color` alpha channel only — never to the bars/peak ticks, which stay fully opaque regardless. Set from `SetupDialog`'s AUDIO VISUALIZER tab slider (0–100%). |
| `audioVisualizerBarOpacity` / `setAudioVisualizerBarOpacity(opacity)` | Foreground-only opacity for the Audio Visualizer's bars and peak-hold ticks (default `1.0`, fully opaque); clamped to `[0.0, 1.0]`; auto-saves. Independent of `audioVisualizerPaneOpacity` — applied as an ordinary `opacity:` binding on `AudioVisualizerWindow`'s `barsRow` (level bars + peak ticks together), not `Window.color`, so no premultiply treatment is needed (unlike the pane background, this isn't a native window clear color — Qt Quick's scenegraph alpha blending already composites it correctly). Set from `SetupDialog`'s AUDIO VISUALIZER tab slider (0–100%). |
| `audioVisualizerPaneConfigured` / `audioVisualizerPaneX` / `Y` / `Width` / `Height` | Read-only; the detachable AudioVisualizerWindow pane's last-saved geometry (defaults `500`×`260`, `configured` starts `false`). Same convention as `bigCoverPane*`/`tagInfoPane*` above. See UC-19. |
| `saveAudioVisualizerPaneGeometry(x, y, width, height, screenName)` | Persists the pane's geometry after a move/resize settles. Same calling convention as `saveBigCoverPaneGeometry`. |
| `save()` | Persist current state to `Topaz.config` (called automatically by all mutators). |

## Data Flow: Genre Filter (GenreBar toggle)

```
User click
   │
   ▼
GenreBar.onClicked
   │  lib.toggleGenre(index)
   ▼
LibraryData
   ├── genreModel.setProperty(index, "active", ...)
   ├── activeGenreNames = [rebuilt array]
   ├── selectedGenre  = ""    ← property-change notification fires
   ├── selectedArtist = ""
   └── selectedAlbum  = ""
   └── _rebuildTree()  → library = [active genres with artists/albums]
          │
          ├──► LibraryTree.onLibraryChanged
          │        → activeGenres = lib.library
          │        → _rebuildFlatList() rebuilds flat JS array (pure JS, no C++ calls)
          │        → ListView renders only visible rows (virtualised, ~10-15 delegates)
          │        Note: onActiveGenreNamesChanged NOT wired to LibraryTree — avoids a
          │        second rebuild with stale lib.library before _rebuildTree() completes.
          │
          └──► AlbumBrowser.Connections.onActiveGenreNamesChanged
                   └── Qt.callLater(_scheduleRefresh)
                           (deferred: frame renders first, then filteredAlbums() runs)
                           └── ListView.model = currentAlbums  →  UI updates
```

## Data Flow: Genre Drill-down (LibraryTree click)

```
User clicks genre header row in LibraryTree
   │
   ▼
LibraryTree._selectGenre(genre)
   ├── expandedArtists = {}   (collapse all)
   │      → onExpandedArtistsChanged → _rebuildFlatList()
   │          (rebuilds flatRows JS array, ListView updates instantly)
   └── lib.selectGenre(genre)
          │
          ▼
      LibraryData.selectGenre()
          ├── selectedGenre  = genre  (toggle: clears if already selected)
          ├── selectedArtist = ""
          └── selectedAlbum  = ""
                 │  (no lib.library change → no _rebuildFlatList() triggered)
                 │  (LibraryTree delegate bindings on lib.selectedGenre update reactively)
                 │
                 └──► AlbumBrowser.Connections.onSelectedGenreChanged
                          └── Qt.callLater → currentAlbums = lib.filteredAlbums()
```

## Data Flow: Genre Configuration

```
TopBar gear click
   │  settingsRequested()
   ▼
Main.qml
   │  setupDialog.open()
   ▼
SetupDialog (GENRES tab)
   │  appConfig.addGenre(name)  /  removeGenreAt(i)  /  clearGenres()
   ▼
AppConfig (C++)
   ├── mutates m_genres
   ├── save()  →  Topaz.config written to disk
   └── emit genresChanged()
          │
          └──► LibraryData.rebuildGenreModel()
                   ├── _genreModel.clear()
                   ├── _genreModel.append({name, active:false}) for each genre
                   ├── activeGenreNames = []
                   └── selectedArtist / selectedAlbum = ""
                            │
                            └──► GenreBar Repeater re-evaluates
                                 LibraryTree / AlbumBrowser update via existing bindings
```

## Data Flow: Folder Configuration

```
SetupDialog (FILE MONITORING tab)
   │  ADD FOLDER  →  FolderDialog (native OS picker)
   │  onAccepted: appConfig.addFolder(selectedFolder, true)
   ▼
AppConfig (C++)
   ├── QUrl::toLocalFile() converts file:// URL to local path
   ├── mutates m_folders
   ├── save()  →  Topaz.config written to disk
   └── emit foldersChanged()
          │
          └──► SetupDialog folderList.model (bound to appConfig.folders)
                   └── ListView updates immediately

Next scan will pick up the new folder automatically.
```

## Data Flow: Search (SearchPanel typing)

```
User types in SearchPanel's query TextInput
   │  onTextEdited: searchData.query = text
   ▼
SearchData (independent of LibraryData)
   ├── onQueryChanged → _scheduleSearch()
   │       ├── query.trim() === "" → results = []; mode = "all"  (synchronous, no debounce)
   │       └── otherwise → restart 250ms debounce Timer
   ▼ (Timer fires)
libraryModel.searchLibrary(query, mode, activeGenreNames, considerGenre, matchWholeWord)
   │  single O(N_tracks) pass — see "LibraryModel public API" / UC-21
   ▼
SearchData.results = [...]
   │
   └──► SearchResultBrowser ListView.model  (bound directly — no Qt.callLater
            needed here; SearchData's debounce already centralizes the async
            update)
                └── AlbumCard delegates render (same object shape as
                    filteredAlbums(); albumGenre prop fed from the result's
                    genre field renders "Genre | Year" under the cover)

Mode-button click (ALL/ARTISTS/ALBUMS/TRACKS) → searchData.mode = "..." →
same debounce → re-search. "Match whole word" / "Consider Genre" checkbox
toggles → same debounce → re-search; Consider Genre is additionally gated
on lib.activeGenreNames (one-way bound into SearchData by Main.qml).
```

## Supported Resolutions → Adaptive Layout Strategy

| Resolution | Startup behaviour | ColumnLayout behaviour |
|-----------|-------------------|------------------------|
| 1280 × 720 (minimum) | Windowed | All four panels visible; minimum enforced |
| 1920 × 1080 | **Auto-fullscreen** (`Window.FullScreen`) | Design baseline — all four panels fully visible |
| 1920 × 1200 | **Auto-fullscreen** (`Window.FullScreen`) | Extra vertical space absorbed by AlbumBrowser |
| 2560 × 1440 | **Auto-fullscreen** (`Window.FullScreen`) | Font scale and spacing scale up proportionally (future) |
| 3840 × 2160 | **Auto-fullscreen** (`Window.FullScreen`) | Font scale and spacing scale up proportionally (future) |
| 4096 × 2160 | Windowed 1920 × 1080 | AlbumBrowser gains a 2-column card grid (future) |

**Startup logic** (`Main.qml`):
```qml
visibility: ((Screen.width === 1920 && Screen.height === 1080) ||
             (Screen.width === 1920 && Screen.height === 1200) ||
             (Screen.width === 2560 && Screen.height === 1440) ||
             (Screen.width === 3840 && Screen.height === 2160))
            ? Window.FullScreen : Window.Windowed
width:  1920
height: 1080
minimumWidth:  1280
minimumHeight:  720
```

> Topaz starts fullscreen when the monitor is exactly 1920×1080, 1920×1200, 2560×1440, or 3840×2160.
> On all other resolutions (including 4096×2160) it starts windowed at 1920×1080.
> AlbumBrowser absorbs surplus width as the user resizes.

### Panel layout — `SplitView`

The four main panels (LibraryTree, AlbumBrowser, PlaybackQueue, NowPlaying) are
arranged in a horizontal `SplitView` (Qt Quick Controls 2).  A 5 px drag handle
sits between each pair of adjacent panels; its colour follows the surface
hierarchy tokens (`surfaceContainerLow` at rest → `surfaceContainerHigh` on
hover → `secondary` teal when actively dragged).

| Panel | Default width | Minimum width | Size behaviour |
|-------|--------------|---------------|----------------|
| LibraryTree | 286 px | 160 px | user-resizable |
| AlbumBrowser | — | 400 px | `SplitView.fillWidth: true` — absorbs all surplus |
| PlaybackQueue | 374 px | 240 px | user-resizable |
| NowPlaying | 359 px | 280 px | user-resizable |

When the application window is widened or narrowed, only AlbumBrowser grows or
shrinks.  Resizing a panel handle narrows AlbumBrowser accordingly, down to its
400 px minimum.

When TopBar's SEARCH tab is active, the LibraryTree and AlbumBrowser slots
are occupied by `SearchPanel.qml`/`SearchResultBrowser.qml` instead (via a
`Loader` in each slot — see UC-21), but the slots' widths, minimums, and
resize/persistence behavior are unchanged, since those live on the `Loader`
itself rather than on whichever component it currently loads.

### Layout persistence

The window size and the three resizable panel widths are persisted in
`Topaz.config` so that the layout is restored exactly on the next startup.

**Save mechanism** — `Main.qml` watches `onWidthChanged` on the
`ApplicationWindow` (for window resizing) and on each resizable panel (for
handle dragging). All of these restart a single 500 ms debounce `Timer`.
When the timer fires it calls `appConfig.saveLayout(...)` which writes all five
values (`windowWidth`, `windowHeight`, `libraryTreeWidth`, `playbackQueueWidth`,
`nowPlayingWidth`) in one atomic JSON write. While in fullscreen mode the stored
window dimensions are not overwritten.

**Restore mechanism** — On startup, `AppConfig::load()` reads the five values
from JSON (falling back to the design-baseline defaults when absent). `Main.qml`
binds `width: appConfig.windowWidth` and `height: appConfig.windowHeight`, and
each resizable panel binds `SplitView.preferredWidth` to the corresponding
appConfig property. `SplitView` breaks those QML bindings the first time the
user drags a handle, taking over management of `preferredWidth` from that point
onward.

## Performance Design

### Album cover memory

Every `Image` element that displays an album cover sets `sourceSize` to the
**display size** (e.g., `sourceSize.width: 160; sourceSize.height: 160`).
Qt decodes the PNG at that resolution instead of keeping the full-resolution
bitmap in memory.  A 1400 × 1400 px cover therefore occupies ≈ 100 KB instead
of ≈ 7.8 MB.

```qml
// AlbumCard.qml — canonical pattern
Image {
    sourceSize.width:  160
    sourceSize.height: 160
    asynchronous: true
    fillMode: Image.PreserveAspectCrop
}
```

### Delegate recycling

`AlbumBrowser` and `PlaybackQueue` use `ListView` with `cacheBuffer` set
conservatively (200 px and 120 px respectively). Off-screen delegates are
released automatically; only visible items remain instantiated.

### Lazy cover loading

When the file-system backend is connected, the `ID3Info.Cover` (`QPixmap`)
will be loaded on demand and cleared when the containing album scrolls
permanently out of the `cacheBuffer` zone.  An LRU cover cache (capacity
configurable via the app JSON config) will be introduced at that point.

# Data model

## Class diagram

> The architecture has been refactored from separate entity classes (Genre,
> AlbumArtist, Album, ID3Info) to a flat `TrackInfo` struct for version 1.
> This avoids object-graph overhead for 12K+ entries while retaining all
> required data.  The logical entities (Genre, AlbumArtist, Album) exist as
> distinct string values within each `TrackInfo` and can be re-introduced as
> proper entity classes in a future version if needed (e.g., for user-editable
> metadata or playlist enrichment).

```mermaid
  classDiagram
    direction LR

    class TrackInfo {
      +QUuid id
      +QString filePath
      +QString fileName
      +QString title
      +QString artist
      +QString albumArtist
      +QString album
      +QString genre
      +int track
      +int year
      +qint64 duration
      +int bitrate
      +qint64 fileSize
      +qint64 lastModified
      +QString coverThumb
      +int rating
      +QUuid ratingId
      +computeRatingId(albumArtist, artist, album, title)$ QUuid
    }

    class TagReader {
      +read(filePath, generateCoverThumb) TrackInfo$
      +readRawCover(filePath) QByteArray$
    }

    class LibraryCache {
      +load() QList~TrackInfo~$
      +save(tracks) bool$
      +cacheFilePath() QString$
    }

    class RatingCache {
      +load() QHash~QUuid,int~$
      +save(tracks) bool$
      +setRating(genre, ratingId, rating) bool$
      +cacheFilePath() QString$
    }

    class LibraryScanner {
      +onThreadStarted()
      +fullScan(genres, folders, cache)
      +statCheck(genres, folders, cache)
      ~scanProgress(done, total)
      ~scanCompleted(tracks)
    }

    class LibraryModel {
      +appConfig AppConfig
      +scanning bool
      +scanProgress int
      +trackCount int
      +albumCount int
      +ratingsReady bool
      +loadCacheAndStartStatCheck()
      +startFullScan()
      +genres() QStringList
      +artistsForGenre(genre) QStringList
      +albumsForArtist(artist, genre) QStringList
      +filteredAlbums(activeGenres, artist, album) QVariantList
      +buildLibraryTree(activeGenres) QVariantList
      +searchLibrary(query, mode, activeGenres, considerGenre, matchWholeWord) QVariantList
      +autoPlayCandidatePool(activeGenres, considerGenre, considerRating, minimumRating) QVariantList
      +buildStandaloneTrackCards(tracks) QVariantList
      ~libraryRefreshed()
    }

    class SearchData {
      +libraryModel LibraryModel
      +activeGenreNames QStringList
      +query string
      +mode string
      +considerGenre bool
      +matchWholeWord bool
      +results QVariantList
    }

    class PlaylistsData {
      +playlistManager PlaylistManager
      +libraryModel LibraryModel
      +engine PlaybackEngine
      +playlists QVariantList
      +selectedFileName string
      +selectedDisplayName string
      +albums QVariantList
      +selectedRawTracks QVariantList
      +resultScrollY real
      +refreshPlaylists()
      +selectPlaylist(fileName)
      +clearSelection()
    }

    class AppConfig {
      +genres QStringList
      +folders QVariantList
      +crossfadeEnabled bool
      +crossfadeSeconds double
      +autoPlayQueueHorizon int
      +autoPlayTitleAddingIntervalSeconds int
      +autoPlayConsiderGenre bool
      +autoPlayConsiderRating bool
      +autoPlayMinimumRating int
      +autoPlayAllowManualModification bool
      +autoPlaySongRepeat string
      +autoPlayTransportAccess string
      +addGenre(name)
      +removeGenreAt(index)
      +addFolder(path, subfolders)
      +removeFolderAt(index)
      +setCrossfadeEnabled(enabled)
      +setCrossfadeSeconds(seconds)
      +setAutoPlayQueueHorizon(tracks)
      +setAutoPlayTitleAddingIntervalSeconds(seconds)
      +setAutoPlayConsiderGenre(enabled)
      +setAutoPlayConsiderRating(enabled)
      +setAutoPlayMinimumRating(rating)
      +setAutoPlayAllowManualModification(enabled)
      +setAutoPlaySongRepeat(mode)
      +setAutoPlayTransportAccess(mode)
      +save()
      ~genresChanged()
      ~foldersChanged()
      ~crossfadeChanged()
      ~autoPlayQueueHorizonChanged()
      ~autoPlayTitleAddingIntervalSecondsChanged()
      ~autoPlayConsiderGenreChanged()
      ~autoPlayConsiderRatingChanged()
      ~autoPlayMinimumRatingChanged()
      ~autoPlayAllowManualModificationChanged()
      ~autoPlaySongRepeatChanged()
      ~autoPlayTransportAccessChanged()
    }

    class AutoPlayController {
      +engine PlaybackEngine
      +libraryModel LibraryModel
      +appConfig AppConfig
      +activeGenreNames QStringList
      +active bool
      +manualQueueEditingAllowed bool
      +queueClearAllowed bool
      +genreRequirementMet bool
      +playPauseAllowed bool
      +trackNavigationAllowed bool
      +toggle()
      +clearQueueAndHistory()
      +clearHistory()
      ~activeChanged()
      ~manualQueueEditingAllowedChanged()
      ~queueClearAllowedChanged()
      ~genreRequirementMetChanged()
      ~playPauseAllowedChanged()
      ~trackNavigationAllowedChanged()
      ~starved()
    }

    LibraryModel --> LibraryScanner : owns (worker thread)
    LibraryModel --> LibraryCache   : calls load/save
    LibraryModel --> AppConfig      : reads genres+folders
    LibraryScanner --> TagReader    : calls read()
    LibraryScanner --> LibraryCache : calls save()
    LibraryScanner --> RatingCache  : calls load() to enrich tracks
    TagReader ..> TrackInfo         : produces
    LibraryModel "1" *-- "0..*" TrackInfo : m_tracks
    PlaybackEngine "1" *-- "0..*" TrackInfo : m_queue
    PlaybackEngine --> QMediaPlayer  : wraps ×2 (dual-deck, see UC-15)
    PlaybackEngine --> QAudioOutput  : wraps ×2 (dual-deck, see UC-15)
    PlaybackEngine --> AppConfig     : reads crossfadeEnabled/crossfadeSeconds live
    AutoPlayController --> PlaybackEngine : addTrack/playAt/trackList/clearQueue; listens trackPlayedToCompletion + queueExhausted (see UC-16)
    AutoPlayController --> LibraryModel   : calls autoPlayCandidatePool() (see UC-16)
    AutoPlayController --> AppConfig      : reads all autoPlay* settings live (see UC-16)
    SearchData --> LibraryModel : calls searchLibrary() (see UC-21)
    PlaylistsData --> LibraryModel : calls buildStandaloneTrackCards() (see UC-22)
    PlaylistsData --> PlaybackEngine : reads activePlaylistName (read-only, see UC-22)
```

---

## UC-06 Add a Track to the Playback Queue

| Field | Detail |
|-------|--------|
| **Goal** | User adds a single track to the playback queue via drag & drop. |
| **Actor** | User |
| **Precondition** | At least one album is visible in `AlbumBrowser`. |
| **Trigger** | User drags a track row from `AlbumCard` to `PlaybackQueue`. |

### Normal Flow — Drag from track row to queue

1. User presses and holds the left button on a track row and moves the mouse more than 8 px.
2. `trackMA.onPositionChanged` sets `trackRow.Drag.active = true`, calls `engine.beginDragCursor()` to push a system-wide `Qt::ForbiddenCursor` override (🚫 — "not over a valid drop target," the default state until proven otherwise), and on every subsequent `positionChanged`, updates `Drag.hotSpot` to the cursor's current position in `trackRow`-local coordinates:
   ```
   scenePt = mapToItem(null, mouse.x, mouse.y)   // cursor in scene space
   rowPt   = trackRow.mapToItem(null, 0, 0)       // trackRow origin in scene space
   Drag.hotSpot = scenePt - rowPt                 // hotspot follows cursor
   ```
   `trackRow` itself never moves from its layout position. The hotspot tracking is what causes Qt's drop system to report the drag to DropAreas under the actual cursor.
3. As the cursor enters `PlaybackQueue`, its `DropArea.containsDrag` becomes `true` — the panel highlights in secondary colour, and `onEntered` calls `engine.setDragCursorAllowed(true)`, switching the cursor to `Qt::DragCopyCursor` (➕ with arrow) via `QGuiApplication::changeOverrideCursor()` — changing the shape of the already-pushed override rather than pushing a second one. Leaving the panel (`onExited`) calls `setDragCursorAllowed(false)`, switching back to `Qt::ForbiddenCursor`. This means the cursor only ever shows "+" while actually over the one valid drop target, and "not allowed" everywhere else for the whole gesture.
4. User releases. `DropArea.onDropped` reads `drop.source.trackData`, calls `engine.addTracks([trackData])`, accepts `Qt.CopyAction`.
5. `trackMA.onReleased` calls `engine.restoreOverrideCursor()` to revert the cursor. `PlaybackEngine` appends the track; `PlaybackQueue` ListView updates.

### Normal Flow — Double-click track to add to queue

1. User double-clicks a track row.
2. `trackMA.onDoubleClicked` calls `root.engine.addTracks([modelData])` directly.
3. Same result as a successful drag-drop, without leaving the album browser.

### Why dynamic `Drag.hotSpot` is required

Qt's DropArea fires when the drag source item's hotspot (`item.mapToScene(Drag.hotSpot)`) is inside the DropArea's scene bounds. If `trackRow` never moves (it stays in the AlbumBrowser layout), the hotspot stays in the AlbumBrowser area and never reaches the PlaybackQueue DropArea — so the drop never triggers. Updating `Drag.hotSpot` every `positionChanged` to equal `cursorScenePos - trackRowScenePos` ensures the absolute hotspot position always matches the mouse cursor, regardless of where `trackRow` sits in the scene.

### Why internal drag (not `Drag.Automatic`)

`Drag.Automatic` uses the OS drag-and-drop mechanism and requires `Drag.mimeData`. It is designed for dragging between different windows or applications. Our source and target are both inside the same `ApplicationWindow`, so **internal drag** (`Drag.active` / `drop.source`) is the correct pattern.

### Drag key separation

The application has two distinct drag flows. Only the AlbumCard → queue flow uses Qt's
`Drag`/`DropArea` mechanism. The queue-internal reorder uses pure mouse tracking (see UC-11)
and does **not** involve `Drag.active` or `DropArea`.

| Flow | Mechanism | `Drag.keys` / DropArea |
|------|-----------|------------------------|
| Add to queue (AlbumCard → PlaybackQueue) | Qt internal drag (`Drag.active` + `DropArea`) | `Drag.keys: ["externalDrop"]`; DropArea in `PlaybackQueue`: `keys: ["externalDrop"]` |
| Queue reorder (within PlaybackQueue) | Pure mouse tracking in `dragHandleMA` | No `Drag.active`, no `DropArea` — `queueArea.reorderFrom/To` properties + single `insertBar` |

### Why `HoverHandler` instead of `MouseArea` for card hover

`AlbumCard` originally used a full-card `MouseArea` (`cardHover`) for the background-colour hover effect. Because it was declared **last** in the component (therefore topmost in z-order), it intercepted every `onPressed` before the per-track `trackMA` could see it. Even with `propagateComposedEvents: true`, non-composed events (`pressed`, `positionChanged`, `released`) are **not** propagated, so drag could never start.

The fix: replace `cardHover` MouseArea with `HoverHandler`. `HoverHandler` is a pointer-handler (not a MouseArea) — it observes hover without consuming any press or move events, letting `trackMA` receive them unobstructed.

### Why `preventStealing: true` on `trackMA`

The `albumList` ListView is interactive (flick-scrollable). Without `preventStealing: true`, once the user moves the mouse a few pixels after pressing, the ListView's flick handler can steal the gesture from `trackMA`, preventing `onPositionChanged` from firing and the drag from starting. `preventStealing: true` tells the parent Flickable/ListView to not take the event once `trackMA` has accepted the press.

### Design constraints (performance)

- **No multi-selection**: `AlbumCard` carries no selection state — no `selectedIndices` JS object, no Ctrl+click logic.
- **No context menus**: `QtQuick.Controls.Menu` removed from `AlbumCard`. Each `Menu` is backed by a `QQuickPopup` overlay; instantiating dozens of them per genre change was the primary source of UI lag.
- **No album drag**: the cover area is not a drag source; only individual track rows are draggable.
- **Minimal engine reference in `AlbumCard`**: `engine` is an optional `property var` on `AlbumCard`, used only for double-click add-to-queue and the drag cursor override via `beginDragCursor` / `setDragCursorAllowed` / `restoreOverrideCursor`. `AlbumBrowser` itself has no engine reference. Setting the cursor via a C++ invokable (`QGuiApplication`'s override-cursor stack) is necessary because a QML `cursorShape` binding on `trackMA` is ineffective once the mouse leaves the `MouseArea`'s bounds during a drag — the global override persists regardless of which item is under the cursor. `setDragCursorAllowed()` deliberately uses `QGuiApplication::changeOverrideCursor()` (changes the shape of the currently-active override) rather than another `setOverrideCursor()` call while switching between "+"/"not allowed" mid-drag — stacking a second override there would require a second `restoreOverrideCursor()` to unwind it, which nothing in the drag flow calls.

---

## UC-11 Reorder Tracks in the Playback Queue

| Field | Detail |
|-------|--------|
| **Goal** | User reorders a non-playing track in the queue by dragging it to a new position. |
| **Actor** | User |
| **Precondition** | At least two tracks are in the queue; the track to move is not currently playing. |
| **Trigger** | User presses and drags the drag-handle (\u283f) of a queue row. |

### Normal Flow

1. User hovers over a non-playing queue row — the drag handle (\u283f, braille six-dot glyph) is always present at z:2 in the position-number column (visible for all non-playing rows).
2. User presses the handle. `dragHandleMA.onPressed` sets `queueArea.reorderFrom = index` and `queueArea.reorderTo = index`.
3. User moves the mouse. `dragHandleMA.onPositionChanged` fires continuously (`preventStealing: true` prevents the ListView from stealing the gesture):
   - Maps the cursor to `queueList.contentItem` coordinate space, which automatically accounts for scroll offset.
   - Computes `newTo = Math.floor(pt.y / 68)`, clamped to `[0, queueCount-1]`.
   - Sets `queueArea.reorderTo = newTo`.
4. The source row dims to 45 % opacity (`opacity: queueArea.reorderFrom === index ? 0.45 : 1.0`).
5. A single 2 px `insertBar` Rectangle (z:10, outside delegates, inside `queueArea`) shows the insert position:
   - Moving down (from < to): bar at `(to + 1) * 68 - queueList.contentY` (below target row).
   - Moving up   (from > to): bar at `to * 68 - queueList.contentY` (above target row).
6. User releases. `dragHandleMA.onReleased` resets `reorderFrom`/`reorderTo` to `−1` (bar disappears), then calls `engine.moveTrack(from, to)`.
7. `PlaybackEngine.moveTrack()` calls `beginMoveRows` / `endMoveRows`; the `ListView` animates the row to its new position.

### Alternate: Released on same row or cancelled

If `from === to`, `moveTrack` is not called. If released outside the queue area, the drag terminates the same way.

### Why pure mouse tracking instead of `Drag`/`DropArea`

Using `Drag.active` on a ListView delegate and per-delegate `DropArea` targets is unreliable because:
- The drag handle's `visible` gate (`rowHover.containsMouse`) causes the handle to hide itself at z:2, since `dragHandleMA` above it consumes hover events, setting `rowHover.containsMouse = false` at the moment the user hovers over the handle — a visibility deadlock.
- DropAreas inside delegate items are sibling items of the drag source. Qt's per-delegate DropArea approach works for simple cases but is fragile in a scrollable ListView with dynamic model indices.

Pure mouse tracking avoids both issues: `onPositionChanged` fires reliably as long as the button is pressed, regardless of what is under the cursor. `mapToItem(queueList.contentItem, ...)` gives the exact content-space Y coordinate from which the target index is computed directly.

### Design decisions

- **Drag handle always visible** (`visible: !model.playing`): no hover dependency; this avoids the z-order hover-stealing deadlock described above. The glyph colour changes on hover/drag for visual feedback without affecting interactivity.
- **`preventStealing: true`**: prevents the `ListView`'s flick handler from stealing the press from `dragHandleMA`.
- **Playing row excluded**: `dragHandle.visible: !model.playing`, mirroring the constraint on `moveUp`/`moveDown`.
- **Single insert bar**: one shared `Rectangle` (z:10) in `queueArea` replaces per-delegate DropArea highlighting. Positioning is computed from `reorderTo * 68 - queueList.contentY`, which is always in the correct view-space coordinate.

### Position numbers stay consistent across every queue mutation

`PosRole` (the "#" column, `model.pos`) is derived purely from each row's index
(`index.row() + 1` in `PlaybackEngine::data()`) — there is no stored track number.
Because it's index-derived, `beginRemoveRows`/`endRemoveRows`/`beginMoveRows`/
`endMoveRows` alone are **not** sufficient to make it re-render correctly: those calls
only tell the view a row was removed/moved, not that role data changed for the rows
that shifted into new positions as a result, so every queue-mutating method must
explicitly `emit dataChanged(..., { PosRole })` for the affected range.
`moveUp`/`moveDown`/`moveTrack` already do this for the rows between the old and new
position. `removeAt()` does it unconditionally for every row from the removal point
to the end of the queue, regardless of whether the removed track was before, at
(currently playing), or after `m_currentIndex` — all three cases previously needed
this, but only the "before" case had it, leaving stale numbers after removing the
current track or a track further ahead in the queue.

### Auto-scroll to keep the current + upcoming tracks visible

`queueArea.autoScrollToCurrent()` (`PlaybackQueue.qml`) runs on every
`PlaybackEngine::queueCountChanged` (via a `Connections` block, deferred one tick with
`Qt.callLater` so `queueList.contentHeight` already reflects the new row count) —
i.e. on every add (`addTrack`/`addTracks`) and every remove (`removeAt`/`clearQueue`),
from any source. It sets `queueList.contentY = currentIndex * 68` (clamped to the
content's end), pinning the currently-playing row to the top of the visible viewport —
already-played rows scroll out of view above it, and as many upcoming/queued tracks as
the panel's height can hold become visible below. It's a no-op whenever the queue
doesn't overflow the panel (`contentHeight <= height`, no scrollbar showing), so a
short queue is never force-scrolled. This behavior is **independent of AUTO PLAY vs.
MANUAL MODE** — it reacts purely to queue-length changes, regardless of what triggered
them. It does *not* re-trigger on ordinary playback advancing to the next track alone
(no count change) — only on an actual add/remove.

---

## UC-07 Playback Controls

| Field | Detail |
|-------|--------|
| **Goal** | User controls audio playback (play, pause, previous, next, seek). |
| **Actor** | User |
| **Precondition** | At least one track is in the queue. |
| **Trigger** | User interacts with transport controls in `NowPlaying.qml`. |

### Normal Flow — Play / Pause

1. User clicks the ▶ / ⏸ button.
2. `NowPlaying` calls `engine.togglePlay()`.
3. `PlaybackEngine` toggles `QMediaPlayer` between playing and paused states.
4. `engine.isPlaying` property changes → button icon updates immediately.

### Design note — blinking the Play/Pause button while manually paused

`engine.userPaused` (`bool`) drives a looping blink animation on the
Play/Pause button (`NowPlaying.qml`, the same `SequentialAnimation on
opacity` idiom used for the AUTO PLAY button's active-state blink and
`PlaybackQueue`'s new-track flicker). It is deliberately **not** derived
from `!isPlaying` — several other states (most notably the queue having
finished naturally, see UC-16, and the brief instant during any track
transition) also produce `isPlaying() == false` without the user having
paused anything, and would blink incorrectly if used directly.
`m_userPaused` is instead set explicitly, only by `togglePlay()`'s pause
branch, and cleared at exactly three points: `togglePlay()`'s resume
branch (same track resumed), `switchCurrentIndexTo()` (the single choke
point shared by every "a new track becomes current" path — both hard cuts
via `loadTrack()` and the crossfade midpoint in `onFadeTick()` — so a
crossfade transition also correctly ends a stale pause state), and
`clearQueue()` (no current track left to be "paused"). Deliberately
*not* cleared by `previous()`'s "restart current track" branch (`position
> 3s` or already the first track) — that branch only seeks to position 0
without calling `play()`, so a paused track stays paused (and keeps
blinking) at the reset position, matching "blinks until the user resumes
playback or a different track plays" literally: rewinding the same track
is neither of those.

### Normal Flow — Next / Previous

- **Next** (⏭): `engine.next()` → loads `m_currentIndex + 1`, calls `play()`.
- **Previous** (⏮): `engine.previous()`:
  - If `position > 3 s` → seeks to `0` (restart current track).
  - Otherwise → loads `m_currentIndex - 1`, calls `play()`.

### Normal Flow — Seek

1. User clicks or drags the progress bar thumb in `NowPlaying`.
2. `NowPlaying` calls `engine.seek(fraction * engine.duration)`.
3. `QMediaPlayer.setPosition()` updates playback position.
4. `engine.position` notifies → `positionString` and `progressBar.progress` update.

### Normal Flow — Track ends automatically

1. `QMediaPlayer` emits `mediaStatusChanged(EndOfMedia)`.
2. `PlaybackEngine.advanceToNext()` increments `m_currentIndex`, loads the next track, calls `play()`.
3. If the queue is exhausted, playback stops; `isPlaying` → `false`.

### Displayed information

| NowPlaying element | Source |
|-------------------|--------|
| Album art | `engine.currentLargeCoverSource` (full-res, loaded async); falls back to `engine.currentCoverSource` (160 px thumb) until ready |
| Track title | `engine.currentTitle` |
| Artist | `engine.currentArtist` (artist with fallback to albumArtist) |
| Format badge | `engine.currentFormat` + `engine.currentBitrate` KBPS |
| Rating (stars) | `engine.currentRating` (0-10); set by clicking a star, calls `engine.setCurrentRating(n)`. Same row as the format badge — stars right-aligned, format badge left-aligned (see UC-14). Hidden entirely when no track is loaded (`NO TRACK` state). Filled stars use a hardcoded blue (`#00A6ED`) — a deliberate, one-off exception to the theme palette, not a `Theme.*` token. |
| Elapsed time | `engine.positionString` ("M:SS") |
| Total time | `engine.durationString` ("M:SS") |
| Progress ratio | `engine.position / engine.duration` |

---

## PlaybackEngine Component

`PlaybackEngine` is a C++ `QAbstractListModel` subclass marked `QML_ELEMENT`.
It serves as **both the queue model** (rows = `TrackInfo` records) and the **playback controller**.  The queue is the single source of truth; `PlaybackQueue.qml` binds its `ListView.model` directly to the engine instance.

**Dual-deck playback (crossfade)**: rather than a single `QMediaPlayer`/`QAudioOutput`
pair, `PlaybackEngine` owns two independent pairs (`m_players[2]`/`m_audioOutputs[2]`,
"decks") because Qt Multimedia cannot play two sources from one player — a real
crossfade needs the outgoing and incoming track playing simultaneously on separate
players while their volumes ramp in opposite directions. `m_player`/`m_audioOutput`
remain as member names but are now **alias pointers**, always equal to
`m_players[m_activeDeck]`/`m_audioOutputs[m_activeDeck]`; every pre-existing
single-deck code path (`position()`, `duration()`, `seek()`, etc.) is unchanged and
simply operates on "whichever deck is active." Only the crossfade-specific code
(`startCrossfade()`, `onFadeTick()`, `cancelCrossfade()`) reasons about both decks
explicitly. See UC-15 for the full crossfade flow.

### Public API

| Method / Property | Type | Description |
|-------------------|------|-------------|
| `currentIndex` | `int` | Index of the currently loaded track (−1 = nothing) |
| `isPlaying` | `bool` | `true` when `QMediaPlayer` is in `PlayingState` |
| `userPaused` | `bool` | `true` only while the current track is paused via `togglePlay()`'s explicit pause branch — never for any other "not playing" state (see UC-07's design note). Drives `NowPlaying`'s Play/Pause button blink. |
| `position` | `qint64` | Playback position in milliseconds |
| `duration` | `qint64` | Duration of current track in milliseconds |
| `positionString` | `QString` | `position` formatted as "M:SS" |
| `durationString` | `QString` | `duration` formatted as "M:SS" |
| `currentTitle` | `QString` | Title of the current track |
| `currentArtist` | `QString` | artist (falls back to albumArtist) of the current track |
| `currentAlbum` | `QString` | Album name of the current track |
| `currentAlbumArtist` | `QString` | Album artist of the current track (added for `TagInfoWindow`, UC-18) |
| `currentGenre` | `QString` | Genre tag of the current track (added for `TagInfoWindow`, UC-18) |
| `currentYear` | `int` | Release year of the current track, `0` if unknown (added for `TagInfoWindow`, UC-18) |
| `currentTrackNumber` | `int` | Track number of the current track, `0` if unknown (added for `TagInfoWindow`, UC-18) |
| `currentFormat` | `QString` | "FLAC", "MP3", or "OPUS" derived from file extension |
| `currentBitrate` | `int` | kbps bitrate of the current track |
| `currentRating` | `int` | Rating (0-10; 0 = unrated) of the current track. Resolved in `loadTrack()` via `TrackInfo::computeRatingId()` + `RatingCache::load()` — the single canonical point regardless of how the track reached the queue (see UC-14). |
| `currentCoverSource` | `QString` | `data:image/jpeg;base64,…` cover thumbnail URL — 160×160 px, available immediately |  
| `currentLargeCoverSource` | `QString` | Full-resolution cover as a `data:` URL, loaded asynchronously via `QtConcurrent::run` + `QFutureWatcher`. Unlike `currentCoverSource` (always re-encoded to JPEG by `TagReader::makeCoverThumb()`), this is `TagReader::readRawCover()`'s untouched embedded bytes — JPEG *or* PNG — so the MIME type is sniffed from the magic bytes (`\x89PNG` → `image/png`, else `image/jpeg`) rather than hardcoded. Empty until the background task completes; `NowPlaying.qml` falls back to `currentCoverSource` in the interim. |
| `queueCount` | `int` | Number of tracks in the queue |
| `activePlaylistName` | `QString` | File name (with `.xml` extension) of the playlist currently associated with the queue; empty when no playlist is active. Displayed in the `PlaybackQueue` header. Cleared automatically when the queue is cleared. |
| `playlistLocked` | `bool` | When `true`, queue mutations (add, remove, move) do **not** update the XSPF file on disk. Default: `false`. Reset to `false` automatically when `activePlaylistName` changes or `clearQueue()` is called. When set from `true` → `false`, the XSPF is immediately rewritten with the current queue contents. |
| `playlistManager` | `PlaylistManager*` | Reference to the `PlaylistManager` instance set from `Main.qml`. Used internally to sync the XSPF file when tracks are added, removed, or reordered. |
| `appConfig` | `AppConfig*` | Reference to the `AppConfig` instance set from `Main.qml`. `crossfadeEnabled`/`crossfadeSeconds` are read live from it on every crossfade eligibility check (see UC-15) — never cached. |
| `addTrack(map, autoPlayAdded=false)` | invokable | Append a single track map to the queue. If `activePlaylistName` is set **and** `playlistLocked` is `false`, calls `playlistManager.appendTrack()` to persist the change. `autoPlayAdded` is set only by `AutoPlayController`'s 3 add call sites (see UC-16); when `true`, marks the new row's `autoPlayAdded` queue role `true` and clears it again after ~2s. Auto-plays the new track when the queue was empty **or** `m_queueFinished` (every queued track already played through to its natural end) — never while merely paused (see UC-16). |
| `addTracks(list)` | invokable | Batch-append a QVariantList of track maps. Calls `appendTrack` for each new entry when a playlist is active and not locked. Same widened auto-play condition as `addTrack()` above — also used for manual single-track adds (`AlbumCard` double-click, drag-and-drop into `PlaybackQueue`), not just playlist loading. |
| `removeAt(index)` | invokable | Remove track at given queue index. Captures `filePath` before removal; calls `playlistManager.removeTrackByPath()` when a playlist is active and not locked. |
| `moveUp(index)` | invokable | Swap track with predecessor (not allowed on playing track). Calls `playlistManager.rewritePlaylist()` when a playlist is active and not locked. |
| `moveDown(index)` | invokable | Swap track with successor (not allowed on playing track). Calls `playlistManager.rewritePlaylist()` when a playlist is active and not locked. |
| `moveTrack(from, to)` | invokable | Move any non-playing track from one queue index to another in a single step. Updates `m_currentIndex` if the currently playing track falls in the shifted range. Uses `QAbstractItemModel::beginMoveRows` / `endMoveRows` so the bound `ListView` animates the reorder automatically. Calls `playlistManager.rewritePlaylist()` when a playlist is active and not locked. |
| `clearQueue()` | invokable | Stop playback, empty the queue, clear `activePlaylistName`, and reset `playlistLocked` to `false`. |
| `loadPlaylistTracks(tracks)` | invokable | Replaces the entire queue with `tracks` — used exclusively by the "load a playlist" flows (`NowPlaying`/`PlaylistViewer` LOAD buttons). Behaves exactly like `clearQueue()`+`addTracks(tracks)` unless `crossfadeEnabled` is on and a track is currently playing (and both it and the new first track exceed `crossfadeSeconds`), in which case it crossfades directly into the new playlist's first track instead of a hard stop-then-restart — see UC-23. |
| `setActivePlaylistName(name)` | invokable | Set the active playlist file name (e.g. `"GothicRock01.xml"`). Resets `playlistLocked` to `false`. Called from `NewPlaylistDialog` after successful creation, and from the load-playlist flow. |
| `setPlaylistLocked(locked)` | invokable | Set the lock state. When unlocked (`false`), immediately calls `playlistManager.rewritePlaylist()` so the file reflects any changes made while locked. |
| `setCurrentRating(rating)` | invokable | Set the current track's rating (1-10; no-op otherwise or if no track is loaded). Updates the queue entry and calls `RatingCache::setRating(genre, ratingId, rating)` to persist immediately. |
| `trackList()` | invokable | Return all queued tracks as `QVariantList` of maps (`filePath`, `title`, `artist`, `albumArtist`, `album`, `trackNumber`, `durationMs`) — used by `PlaylistManager.createPlaylist()` |
| `beginDragCursor()` | invokable | Pushes a system-wide `Qt::ForbiddenCursor` override via `QGuiApplication::setOverrideCursor()` — the default "not over a valid drop target" cursor for a drag gesture. Called by `AlbumCard` the moment a drag starts (> 8 px threshold). |
| `setDragCursorAllowed(allowed)` | invokable | Changes the *shape* of the already-pushed override cursor between `Qt::DragCopyCursor` (`allowed=true`) and `Qt::ForbiddenCursor` (`allowed=false`) via `QGuiApplication::changeOverrideCursor()` — not a second push, so one `restoreOverrideCursor()` at drag end still correctly pops it. Called by `PlaybackQueue`'s `DropArea.onEntered`/`onExited`. |
| `restoreOverrideCursor()` | invokable | Calls `QGuiApplication::restoreOverrideCursor()` — restores the cursor to its previous state. Called by `AlbumCard` on `onReleased` when a drag ends. |
| `playAt(index)` | invokable | Load and play the track at given index |
| `togglePlay()` | invokable | Toggle between play and pause |
| `next()` | invokable | Advance to the next track |
| `previous()` | invokable | Restart or go to previous track |
| `seek(ms)` | invokable | Seek to a position in milliseconds |

**`year` field threading (added for `TagInfoWindow`, UC-18)**: `TrackInfo::year` was
always populated by the scanner, but the `QVariantMap`s built to queue a track never
carried a `"year"` key — `trackFromMap()` (used by `addTrack`/`addTracks`) simply had
nothing to read. Fixed by threading `"year"` through the three call sites that build
these maps: `LibraryModel::filteredAlbums()`'s per-track map (used when queueing from
`AlbumCard`), `LibraryModel::autoPlayCandidatePool()` (used by AUTO PLAY), and
`PlaylistManager::loadPlaylist()`'s per-entry map (re-read live from the file via
`TagReader::read()`). No scanner or cache-schema change — the data already existed in
`TrackInfo`, it just wasn't being copied into the maps that cross into the queue.

**`audioBufferAvailable(const QAudioBuffer &buffer)` signal (added for the audio
visualizer, UC-19)**: not a `Q_PROPERTY`/QML-facing signal — only
`AudioVisualizerController` (plain C++) connects to it. Emitted from a per-deck
`QAudioBufferOutput::audioBufferReceived` handler, filtered to `m_activeDeck` only
(a deliberate simplification during crossfades — see UC-19's "Known limitations").
`QAudioBufferOutput` requires Qt Multimedia's FFmpeg backend; see UC-19 for how that
was confirmed present on the reference toolchain.

### Queue model roles (used by PlaybackQueue.qml delegate)

| Role name | Type | Content |
|-----------|------|---------|
| `pos` | `QString` | Zero-padded queue position ("01", "02", …) |
| `trackName` | `QString` | Track title (or file name if no title tag) |
| `subLabel` | `QString` | "ARTIST • ALBUM" (uppercase) |
| `kbps` | `int` | Bitrate in kbps |
| `playing` | `bool` | `true` for the currently playing row |
| `durationStr` | `QString` | "M:SS" track duration |
| `coverSource` | `QString` | `data:image/jpeg;base64,…` or empty |
| `autoPlayAdded` | `bool` | `true` for ~2s after `AutoPlayController` added this row (see UC-16); drives the new-track flicker |

### Track map format (input to addTrack / addTracks)

Each track map produced by `LibraryModel.filteredAlbums()` now contains:

```json
{
  "number":      "01",
  "title":       "Track Title",
  "duration":    "3:52",
  "durationMs":  232000,
  "bitrate":     1411,
  "filePath":    "C:/Music/Artist/Album/01_Track.flac",
  "artist":      "Artist Name",
  "albumArtist": "Album Artist",
  "album":       "Album Name",
  "genre":       "Techno",
  "coverSource": "data:image/jpeg;base64,..."
}
```

`PlaylistManager.loadPlaylist()`'s track maps include the same `genre` field (read via
`TagReader::read()`). `rating`/`ratingId` are deliberately **not** part of this map —
`PlaybackEngine::loadTrack()` always (re-)resolves them from `Topaz.rating.json` via
`TrackInfo::computeRatingId()`, the single canonical point regardless of how a track
reached the queue (see UC-14).

---

## PlaylistManager Component

`PlaylistManager` is a C++ `QObject` subclass marked `QML_ELEMENT`.
It encapsulates all XSPF playlist file I/O and is instantiated once in `Main.qml`.

### Playlist file location

```
<AppConfigLocation>/playlists/<name>.xml
```

On Windows: `%APPDATA%\Topaz\Topaz\playlists\<name>.xml`

The directory is created automatically on first use.

### XSPF format (version 1)

Topaz uses [XSPF version 1](http://xspf.org/ns/0/) with the following element
mapping:

| XSPF element | Source field | Notes |
|---|---|---|
| `<playlist version="1" xmlns="http://xspf.org/ns/0/">` | — | Root element |
| `<title>` | Playlist name | Entered by user |
| `<track>/<location>` | `TrackInfo.filePath` | Volume-relative: `D:/Music/x.flac` → `/Music/x.flac`, root stripped via `VolumePath` (`volumepath.h`) |
| `<track>/<volume>` | `TrackInfo.filePath` | The containing volume's label (`QStorageInfo::name()`); omitted when the volume is unlabeled |
| `<track>/<title>` | `TrackInfo.title` | Falls back to file name if empty |
| `<track>/<creator>` | `TrackInfo.albumArtist` or `TrackInfo.artist` | XSPF maps `creator` to track artist |
| `<track>/<album>` | `TrackInfo.album` | |
| `<track>/<trackNum>` | `TrackInfo.track` | Omitted when 0 |
| `<track>/<duration>` | `TrackInfo.duration` | Milliseconds, as required by XSPF |

**Location portability**: paths are anchored to the volume's **label**, not a
Windows drive letter, via the shared `VolumePath` helper (`volumepath.h`) also
used by `AppConfig` (monitored folders) and `LibraryCache` (scanned tracks). This
means playlists survive a drive-letter reassignment (e.g. external drive moved
from `E:` to `F:`) *and* work unchanged on a future Linux build, where volumes
have no drive letter at all — `QStorageInfo::name()`/`rootPath()` behave the same
way there (label via udev/blkid, a `/media/<user>/<label>`-style mount point).
`<volume>` is an optional hint only: `loadPlaylist()` always falls back to probing
every mounted volume for the stored relative path if the named volume isn't found
(renamed, unlabeled, or a different machine), so old playlists written before the
`<volume>` element existed still load correctly.

### Public API

| Method | Description |
|---|---|
| `playlistDirectory()` | Returns (and creates) the absolute playlist folder path. |
| `playlistExists(name)` | `true` when `<name>.xml` already exists in the playlist folder. |
| `createPlaylist(name, tracks)` | Write a new XSPF file. Returns empty string on success or a human-readable error string (name empty, already exists, write failure). Receives the track list from `PlaybackEngine.trackList()`. |
| `appendTrack(nameWithExt, map)` | Parse the existing XSPF file, append one `<track>` entry, and rewrite. `nameWithExt` includes the `.xml` extension. Accepts both `"number"` and `"trackNumber"` map keys for the track number. Returns `true` on success. |
| `removeTrackByPath(nameWithExt, filePath)` | Parse the existing XSPF file, remove the first `<track>` whose `<location>` matches the volume-relative form of `filePath`, and rewrite. Returns `true` when a track was removed. |
| `rewritePlaylist(nameWithExt, tracks)` | Overwrite the entire XSPF file with the given ordered track list. Used after any reorder operation (`moveUp`, `moveDown`, `moveTrack`) and when the playlist lock is turned off. The playlist `<title>` is derived from the file's base name. Returns `true` on success. |
| `loadPlaylist(filePath)` | Accepts a local path or a `file://` URL. Parses the XSPF, resolves each `<volume>`/`<location>` pair back to an absolute path via `VolumePath::resolve()` (tries the named volume first, then probes every volume mounted via `QStorageInfo::mountedVolumes()`, fetched once for the whole playlist). Tracks whose file cannot be found on any volume are silently skipped. Returns a `QVariantMap` with `"fileName"` (base name + `.xml`) and `"tracks"` (QVariantList of resolved track maps ready for `PlaybackEngine.addTracks()`). |

### Example output

```xml
<?xml version="1.0" encoding="UTF-8"?>
<playlist version="1" xmlns="http://xspf.org/ns/0/">
  <title>My Playlist</title>
  <trackList>
    <track>
      <location>/Music/Techno/Artist/Album/01_Track.flac</location>
      <volume>MusicDrive</volume>
      <title>Track Title</title>
      <creator>Album Artist</creator>
      <album>Album Name</album>
      <trackNum>1</trackNum>
      <duration>232000</duration>
    </track>
  </trackList>
</playlist>
```

---

## UC-08 Create New Playlist

| Field | Detail |
|-------|--------|
| **Goal** | User creates a new XSPF playlist, optionally pre-populated with the current queue. |
| **Actor** | User |
| **Precondition** | Application is running. |
| **Trigger** | User clicks **+ NEW** in the `NowPlaying` panel. |

### Normal Flow

1. User clicks **+ NEW**.
2. `NowPlaying` emits `newPlaylistRequested()`.
3. `Main.qml` handles `onNewPlaylistRequested` → calls `newPlaylistDialog.open()`.
4. `NewPlaylistDialog` opens centred on the application window.
5. User types a playlist name (no extension required) and clicks **OK** (or presses Enter).
6. `NewPlaylistDialog.tryCreate()`:
   a. Trims whitespace from the name; ignores click if name is empty.
   b. Calls `engine.trackList()` to obtain the current queue (empty list when queue is empty).
   c. Calls `playlistManager.createPlaylist(name, tracks)`.
7. `PlaylistManager` writes the XSPF file to `<AppConfigLocation>/playlists/<name>.xml`.
8. `NewPlaylistDialog` emits `playlistCreated()`; `Main.qml` handles it with
   `playlistsData.refreshPlaylists()` so the PLAYLISTS tab's list reflects
   the new playlist immediately, even if it's already the active tab (see
   UC-22).
9. Dialog closes automatically.

### Alternate: Name already exists

At step 6c, `PlaylistManager.createPlaylist()` returns a non-empty error string.
`NewPlaylistDialog` sets `errorBox.message` and calls `errorBox.open()`.
The themed `MessageBox` overlay appears with the error text.
User dismisses it with **OK** and can correct the name or cancel.

### Alternate: Queue is empty

At step 6b, `engine.trackList()` returns an empty list.
The playlist file is created with an empty `<trackList/>`.
This is valid XSPF and no special handling is required.

### Design decisions

- **No system dialog**: errors are reported via a themed in-app `MessageBox`
  popup, consistent with the rest of the UI.
- **Relative location**: every `<location>` is written relative to its volume's
  root (via `VolumePath`), with an optional `<volume>` label hint, so playlists
  stay portable when the music drive letter changes — or across platforms
  entirely, since the same scheme has no drive-letter dependency at all.
- **Automatic sync on every queue mutation**: tracks added to the queue **are** appended to the XSPF automatically (`PlaybackEngine` → `PlaylistManager.appendTrack`). Tracks removed are removed (`PlaylistManager.removeTrackByPath`). Tracks reordered trigger a full rewrite (`PlaylistManager.rewritePlaylist`). All sync calls are guarded by `playlistLocked`.
- **Playlist lock**: the `PlaybackQueue` header shows a **LOCK PLAYLIST** toggle (animated thumb switch) whenever a playlist is active. When locked (toggled right), all sync calls are suppressed. When unlocked, the XSPF is immediately rewritten to match the current queue. The lock is reset automatically on `clearQueue()` or when a new playlist becomes active. This allows the user to load a playlist as a starting point, rearrange tracks freely for one-time listening, then decide whether to keep the changes by unlocking.

---

## UC-09 Unload Active Playlist

| Field | Detail |
|-------|--------|
| **Goal** | User unloads the active playlist and clears the queue without deleting the file from disk. |
| **Actor** | User |
| **Precondition** | A playlist is active (`engine.activePlaylistName` is non-empty). |
| **Trigger** | User clicks **REMOVE** in the `NowPlaying` panel. |

### Normal Flow

1. User clicks **REMOVE** (button is enabled only when `activePlaylistName ≠ ""`; otherwise rendered at 35 % opacity with `ArrowCursor`).
2. `NowPlaying` calls `engine.clearQueue()`.
3. `PlaybackEngine.clearQueue()` stops playback, empties `m_queue`, clears `m_activePlaylistName`, and emits `activePlaylistNameChanged` + `queueCountChanged`.
4. `PlaybackQueue` header loses the playlist name display; queue `ListView` becomes empty.
5. The REMOVE button returns to its inactive (dimmed) state.
6. The playlist `.xml` file on disk is **not** modified or deleted and can be loaded again via LOAD.

### Design decisions

- **Non-destructive**: REMOVE only unloads the in-memory state; the file is preserved.
- **Single action**: reuses `clearQueue()` which already handles the playlist name reset, keeping the engine's invariant that an empty queue has no associated playlist.

---

## UC-10 Load Existing Playlist

| Field | Detail |
|-------|--------|
| **Goal** | User loads an existing XSPF playlist from disk into the queue. |
| **Actor** | User |
| **Precondition** | Application is running. |
| **Trigger** | User clicks **LOAD** in the `NowPlaying` panel. |

### Normal Flow

1. User clicks **LOAD**. `loadPlaylistDialog.currentFolder` is set to
   `playlistManager.playlistDirectory()` (the folder where new playlists
   are saved) and the dialog opens — nothing about the current queue is
   touched yet (see Design decisions: this used to clear the queue right
   here, before the file was even picked).
2. The native file-open dialog opens with title **"Select a XSPF
   Playlist"** and filter `*.xml`.
3. User selects an `.xml` file and confirms.
4. `loadPlaylistDialog.onAccepted` calls `playlistManager.loadPlaylist(selectedFile)`.
5. `PlaylistManager.loadPlaylist()` parses the XSPF, then for each `<track>`:
   a. Builds a `VolumePath` from the entry's `<volume>`/`<location>` and calls `.resolve(mounted)` (`mounted` fetched once for the whole playlist) — tries the named volume's root first, then falls back to prepending every mounted volume's root to the relative path.
   b. If the resulting absolute path exists → included in the result.
   c. If not found on any volume → silently skipped.
6. `autoPlay.clearHistory()` resets AUTO PLAY's play-count history (if
   bound), then `engine.loadPlaylistTracks(result.tracks)` **always**
   replaces the queue — crossfading into it if eligible, or an instant
   replace otherwise (see UC-23 for the full decision) — regardless of
   whether a playlist was already active. (An earlier version of this step
   only replaced when `engine.activePlaylistName ≠ ""`, falling back to a
   silent `addTracks()` append otherwise — appending behind whatever was
   already playing, with no effect on playback at all. Fixed: LOAD should
   always mean "load this playlist now.")
7. `engine.setActivePlaylistName(result.fileName)` sets the display name in the `PlaybackQueue` header.

### Alternate: All tracks missing

If no tracks resolve successfully, `result.tracks` is empty.  `addTracks` is not called; queue stays empty and nothing plays.  No error dialog is shown (silent skip by design).

### Alternate: Partial tracks missing

Only the found tracks are added; the missing ones are silently omitted.  The loaded playlist file on disk is unchanged.

### Alternate: Load from PlaylistViewer (PLAYLISTS tab)

`PlaylistViewer`'s own **LOAD** button (see UC-22) triggers the identical
effect — same step-6/7 branch (`loadPlaylistTracks()` if a playlist was
already active, else `addTracks()`), `setActivePlaylistName()` — but skips
steps 1-5 entirely: the file was already selected via `PlaylistsPanel`, and
`PlaylistManager.loadPlaylist()` was already called once (to build the
preview) by `PlaylistsData.selectPlaylist()`. The already-parsed track list
is reused from `PlaylistsData.selectedRawTracks` rather than re-reading and
re-parsing the XSPF file and re-running `TagReader::read()` on every track
a second time.

### Alternate: Crossfade into the new playlist

See UC-23 for the full mechanism. In short: if `AppConfig.crossfadeEnabled`
is on and a track is currently playing when step 6 runs,
`engine.loadPlaylistTracks()` fades the currently-playing track directly
into the new playlist's first track instead of stopping and restarting —
otherwise (setting off, nothing playing, or either track too short for the
configured crossfade length) it behaves exactly like the original
`clearQueue()`+`addTracks()` sequence.

### Design decisions

- **Path resolution via `QStorageInfo`**: probing only real mounted volumes (not all 26 drive letters) is both faster and more reliable, and is the same cross-platform API on Linux. `VolumePath::resolve()` first tries the volume named in `<volume>` (fast path), then falls back to prepending every mounted volume's root to the relative path format (e.g. `/Music/foo.flac`) in turn — the same fallback the code always used, now shared with `AppConfig` and `LibraryCache` via `volumepath.h` rather than being playlist-specific.
- **TagReader call on load**: XSPF does not store bitrate or exact duration. During `loadPlaylist()`, `TagReader::read(path, false)` is called for each resolved file to retrieve the actual bitrate, duration, and any tag fields that were absent or empty in the XSPF. Cover thumbnail generation is skipped (`generateCoverThumb = false`) to keep loading fast; the `NowPlaying` panel loads the cover asynchronously from the audio file via `TagReader::readRawCover` when the track starts playing.
- **Clearing/crossfading moved from the LOAD button's click to the file dialog's accept**: originally, clicking LOAD cleared the queue immediately (if a playlist was active), *before* the file dialog even opened — so canceling the dialog left the queue emptied for nothing. Introducing UC-23's crossfade required knowing the target tracks before deciding whether/how to replace the queue, which only made this pre-existing quirk impossible to keep — the decision now happens in `onAccepted`, once `result.tracks` is known, fixing the cancel case as a side effect rather than a deliberate behavior change.

---

## UC-12 Drag Scrollbar Thumb to Scroll a Panel

| Field | Detail |
|-------|--------|
| **Goal** | User scrolls a panel's list by pressing and dragging its scrollbar thumb. |
| **Actor** | User |
| **Precondition** | The panel's content is taller than its viewport (thumb visible). |
| **Trigger** | User presses the left mouse button on the thumb in `LibraryTree`, `AlbumBrowser`, or `PlaybackQueue` and drags vertically. |

### Normal Flow

1. User presses the thumb. The `MouseArea` on the thumb records the press position (mapped into the track's coordinate space via `mapToItem`) and the list's current `contentY`.
2. User drags up or down. Each move event re-maps the cursor into track space, scales the pixel delta by the ratio of scrollable content range to available track range (`(contentHeight - height) / (trackHeight - thumbHeight)`), and assigns the result to the list's `contentY` (clamped to `[0, contentHeight - height]`).
3. The thumb's existing position/size bindings (`y`/`height` driven by `ListView.visibleArea.yPosition`/`heightRatio`) follow automatically as `contentY` changes — no separate redraw logic is needed.
4. The thumb shifts to `Theme.secondary` while the drag is active, and to `Theme.fgSurfaceVariant` on hover when idle, mirroring the color language already used for the `SplitView` panel-resize handles (rest → hover → active-drag).
5. User releases the mouse button; the thumb returns to its rest color (`Theme.outlineVariant`).

### Design notes

- Implemented identically (aside from the bound `ListView` id: `treeList`, `albumList`, `queueList`) in `LibraryTree.qml`, `AlbumBrowser.qml`, and `PlaybackQueue.qml`, each of which already has its own local "Custom scrollbar" block rather than a shared component.
- Reuses the `mapToItem`-based drag-tracking approach already used for `AlbumCard`'s track drag and `PlaybackQueue`'s queue-reorder drag handle (see UC-06 and UC-11) rather than introducing a new interaction technique.
- `preventStealing: true` on the thumb's `MouseArea` keeps the `ListView`'s own flick gesture from stealing the drag, the same technique already used for the queue-reorder drag handle.
- Mouse-wheel scrolling and click-drag on the list content itself are unaffected — this only adds a second way to scroll, via the thumb.
- Row/track delegates in `LibraryTree`, `AlbumCard` (used by `AlbumBrowser`), and `PlaybackQueue` all reserve the rightmost 8 px for the scrollbar thumb's column — either by making the delegate itself narrower (`LibraryTree`, `width: treeList.width - 8`) or by trimming the row's click-catching `MouseArea` with `anchors.rightMargin: 8` (`AlbumCard`'s `trackMA`, `PlaybackQueue`'s `rowHover`) — so row interaction never competes with the scrollbar thumb for the same mouse press. Without this, a row's own `MouseArea` can win the press instead of the thumb (identical idle cursor on both makes this invisible until the user drags), reinterpreting the gesture as that row's own drag instead of a scroll. The scrollbar track `Rectangle` in each panel also sets `z: 2` as a defensive guarantee that it hit-tests above delegate content.

---

## UC-13 Cancel Ongoing Scan on Application Close

| Field | Detail |
|-------|--------|
| **Goal** | Topaz cancels an in-progress library scan instead of crashing or hanging when the user closes the application while a scan is running. |
| **Actor** | System |
| **Precondition** | A `fullScan()` or `statCheck()` is actively running on the `LibraryScanner` worker thread. |
| **Trigger** | User closes the application window (or the app otherwise quits) while `LibraryModel.scanning` is `true`. |

### Normal Flow

1. The application's normal shutdown path destroys the QML object tree, including `LibraryModel`.
2. `LibraryModel::~LibraryModel()` detects the worker thread is still running and calls `LibraryScanner::cancelScan()` — a thread-safe, non-queued call that sets an atomic flag directly, without waiting for the worker's event loop.
3. `LibraryScanner::performScan()` (the shared pipeline behind both `fullScan()`
   and `statCheck()`) checks this flag between each stage — during the
   directory-discovery walk, between each `readTagsParallel()` chunk (≈ 200
   files), and before `resolveCoverArt()`'s cover-reread batch — and returns
   as soon as it's set, unwinding without writing a partial result to
   `Topaz.library.json` and without emitting `scanCompleted()`.
4. `LibraryModel` then calls `QThread::quit()` and waits (up to 3 s) for the now-unwound worker thread to exit its event loop.
5. Once the thread has stopped, `LibraryModel`'s destructor completes and the application closes normally.

### Alternate: worker doesn't stop within the wait timeout

If the wait still times out (e.g. a single slow file read on unresponsive I/O), the destructor detaches the `QThread` (`setParent(nullptr)`) instead of allowing `~QObject` to delete a still-running thread, which Qt treats as a fatal error. The detached thread is reclaimed by the OS when the process exits.

### Design notes

- Cancellation uses a plain `std::atomic<bool>` (`LibraryScanner::m_cancelRequested`) polled by the worker loop, not a queued signal/slot — a queued call would never be processed while the worker thread is busy inside a long-running `fullScan()`/`statCheck()` call, since queued slots only run when that thread's event loop is free.
- The flag is reset to `false` at the start of `performScan()` (shared by both `fullScan()` and `statCheck()`), so a cancellation triggered by one shutdown attempt doesn't permanently block a future scan.
- This only guards application shutdown; it does not add a user-facing "cancel scan" control to the UI.

---

## UC-14 Persist and Restore Title Ratings

| Field | Detail |
|-------|--------|
| **Goal** | User ratings for individual tracks (1–10) persist independently of the scanned library, so a full library rebuild (rescan) never loses them. |
| **Actor** | System |
| **Precondition** | A scan (full or stat-check) is running or has just completed. |
| **Trigger** | `LibraryScanner::fullScan()`/`statCheck()` completing, or the user clicking a star in `NowPlaying`. |

### Normal Flow — Enrich ratings during a scan

1. `LibraryScanner` builds the final scanned track list as before (unchanged scanning
   logic).
2. `RatingCache::load()` reads `Topaz.rating.json` once into a `QHash<QUuid, int>`
   (`ratingId` → `rating`).
3. A single pass over the final track list:
   a. If a track's `ratingId` is null (a brand-new/changed track just read by
      `TagReader`, or a `Topaz.library.json` entry predating this feature), it is
      computed via `TrackInfo::computeRatingId(albumArtist, artist, album, title)` — a
      deterministic `QUuid::createUuidV5()` over a fixed, hardcoded namespace UUID and
      the literal concatenation `albumArtist;artist;album;title`. The same tag values
      always produce the same `ratingId`, so it survives a full library rebuild.
   b. `track.rating` is (re-)set from the loaded ratings hash (`0` if not present) —
      `Topaz.rating.json` is always authoritative, so this also picks up ratings edited
      outside the running scan (e.g. a future maintenance task reconciling lost
      ratings after a tag edit).
4. `LibraryCache::save()` persists the enriched tracks (including `rating`/`ratingId`)
   to `Topaz.library.json` as usual, so the next app startup's instant cache-display
   step shows correct ratings immediately, without waiting for the background
   stat-check to finish.
5. `scanCompleted(tracks)` is emitted as usual.
6. `LibraryModel::onScanCompleted()` sets `ratingsReady = true` (only the first time,
   this session) after applying the enriched tracks.
7. `Main.qml` binds `BottomBar.autoPlayReady: libraryModel.ratingsReady` — the AUTO PLAY
   entry in `BottomBar` switches from its not-ready (grey, unclickable) to ready
   (green) traffic-light state, and becomes clickable.

### Normal Flow — Set a rating from NowPlaying

1. `NowPlaying` shows a row of 10 star glyphs on the same line as the format/bitrate
   badge (stars left-aligned, badge right-aligned), bound to `engine.currentRating`:
   stars `0..currentRating-1` render filled (`Theme.secondary`), the rest unfilled
   (`Theme.outlineVariant`, `Theme.fgSurfaceVariant` on hover).
2. User clicks the *n*-th star (1-10). Its `MouseArea.onClicked` calls
   `engine.setCurrentRating(n)`.
3. `PlaybackEngine::setCurrentRating()` validates `n` is in `[1,10]` and a track is
   loaded, computes `ratingId` if still null, sets `m_queue[m_currentIndex].rating = n`,
   and calls `RatingCache::setRating(genre, ratingId, n)` — an **upsert** (update the
   matching `ratingId` entry if present, else append) that reads, modifies, and
   atomically rewrites `Topaz.rating.json`, leaving every other track's rating
   untouched. This is distinct from `RatingCache::save()` (a full-list overwrite used
   only by the scan-time bulk enrichment pass above).
4. `currentRatingChanged()` fires; the star row updates immediately to show exactly `n`
   filled stars.
5. When `NowPlaying` starts a different track (`PlaybackEngine::loadTrack()`, triggered
   by `playAt()`/`togglePlay()`/`next()`/`previous()`/`advanceToNext()` — every playback
   path funnels through it), `ratingId` is computed if still null and `rating` is always
   refreshed from `RatingCache::load()`, then `currentRatingChanged()` fires so the star
   row reflects the new track's own rating. `clearQueue()` and `removeAt()`'s
   empty-queue branch also emit `currentRatingChanged()`, resetting the row to unfilled
   when nothing is loaded.

### Design notes

- **`Topaz.rating.json` is the sole authoritative source for `rating`** — not
  `Topaz.library.json`. A full rebuild (deleting/regenerating `Topaz.library.json`) does
  not lose ratings, because step 3 above re-applies them from `Topaz.rating.json` on
  every scan, including the one immediately following a rebuild.
- **`ratingId` stability depends on exact tag stability**: if `albumArtist`, `artist`,
  `album`, or `title` change later (re-tagging), `computeRatingId()` produces a
  different UUID and the link to any existing rating is lost — the same tradeoff every
  other derived `TrackInfo` property already has with respect to file changes. A future
  maintenance task is expected to reconcile orphaned ratings in `Topaz.rating.json`.
- **Content-based identity caveat**: two distinct tracks with identical
  albumArtist/artist/album/title (e.g. duplicate pressings) collide onto the same
  `ratingId` and share a rating — an accepted trade-off of metadata-based identity.
- **AUTO PLAY button is a traffic-light toggle, now fully wired**: `BottomBar`'s AUTO
  PLAY entry has three color states — grey (`Theme.fgSurfaceVariant`) while
  `autoPlayReady` is `false` (before the first scan completes) and unclickable; green
  (`#00C853`) once ready and `autoPlay.active` is `false`; red (`#FF1744`) while
  `autoPlay.active` is `true`. Clicking calls `AutoPlayController::toggle()` — a real
  session start/stop, not just a color flip. Neither color is a `Theme.*` token; like
  the rating stars' `#00A6ED`, they are deliberate hardcoded one-offs chosen for a
  literal traffic-light metaphor. See UC-16 for the full session lifecycle, candidate
  selection algorithm, and manual-editing gating rules.
- **AUTO PLAY configuration is fully consumed by `AutoPlayController`** (see UC-16):
  `autoPlayQueueHorizon` (`AppConfig`, default `5`, range `[1, 15]`) is the tracks-ahead
  target the polling timer fills toward; `autoPlayTitleAddingIntervalSeconds`
  (`AppConfig`, default `30`, range `[5, 90]`) is that timer's interval, restarted live
  on change; `autoPlayConsiderGenre`/`autoPlayConsiderRating`/`autoPlayMinimumRating`
  filter `LibraryModel::autoPlayCandidatePool()`'s results; `autoPlaySongRepeat` governs
  the in-memory play-history filter; `autoPlayAllowManualModification` drives
  `AutoPlayController::manualQueueEditingAllowed`. All read live on every candidate
  pick / gating check — no caching, so a mid-session change always takes effect on the
  very next evaluation.
- **Two distinct persistence paths, one file**: `RatingCache::save()` (full-list
  overwrite, scan-time bulk enrichment) and `RatingCache::setRating()` (single upsert,
  interactive star click) both write `Topaz.rating.json` via the same private
  `loadEntries()`/`saveEntries()` atomic tmp-then-rename helpers, but are not
  mutex-protected against each other — a star click landing in the exact window of a
  background scan's save is a theoretical, low-probability race (each individual write
  is still atomic/non-corrupting; one write could just be overwritten by the other).
  Consistent with the rest of this codebase, which doesn't lock file I/O across threads
  elsewhere either (e.g. `LibraryCache::save()`); not engineered around here.
- **Cancellation-safe**: if a scan is canceled mid-flight (see UC-13), the enrichment
  pass — like `LibraryCache::save()` and `scanCompleted` — is skipped entirely, so
  `ratingsReady` only ever becomes `true` after a scan that actually completed.
- **Crossfade interaction**: the "current track" bookkeeping described in step 5 above
  (`ratingId`/`rating` resolution, `currentRatingChanged()`) lives in a shared method,
  `PlaybackEngine::switchCurrentIndexTo()`. A hard-cut transition calls it from
  `loadTrack()`; a crossfade transition calls it at the fade's midpoint instead, while
  `loadTrack()` itself is not invoked — see UC-15.

---

## UC-15 Crossfade Between Tracks

| Field | Detail |
|-------|--------|
| **Goal** | The next track fades in while the current track fades out, instead of a hard cut — optional, configured in Setup. |
| **Actor** | User (configuration), System (playback) |
| **Precondition** | `AppConfig.crossfadeEnabled` is `true`; at least one more track follows the current one in the queue. |
| **Trigger** | The active deck's playback position reaches `(duration − crossfadeSeconds)`. |

### Normal Flow — Configure crossfade

1. User opens **Setup → CROSSFADE**.
2. User toggles the **Crossfade** switch (same visual pattern as `PlaybackQueue`'s LOCK
   PLAYLIST toggle) → `appConfig.setCrossfadeEnabled(...)` → auto-saves to
   `Topaz.config`. The **Length** row (label, value, slider, min/max) dims to 35%
   opacity and the slider is disabled while crossfade is off.
3. User drags the **Length** slider (`QtQuick.Controls.Slider`, `2.0`–`10.0` s,
   `stepSize: 0.5`, restyled to match the theme). The live value is shown above the
   slider (bound to the slider's own `value`, so it updates smoothly while dragging);
   `"2.0 s"`/`"10.0 s"` labels flank the track as the min/max. `onMoved` (fires only on
   user interaction, not programmatic changes) calls `appConfig.setCrossfadeSeconds(...)`,
   which clamps to `[2.0, 10.0]`, snaps to the nearest `0.5`, and auto-saves.
4. `PlaybackEngine` reads both settings live from `appConfig` on every eligibility
   check (never cached), so a change takes effect starting with the very next
   transition — no restart needed.

### Normal Flow — Crossfade a transition

1. On every `positionChanged` tick of the **active** deck, `PlaybackEngine` checks: is
   crossfade enabled, is a next track queued, and — **the eligibility rule** — do
   *both* the active track's live `QMediaPlayer::duration()` and the next track's tag
   `TrackInfo.duration` exceed the configured crossfade length? If not, nothing
   happens and the transition falls through to the existing hard-cut path
   (`EndOfMedia` → `advanceToNext()` → `loadTrack()`).
2. Once `position >= duration − crossfadeMs`, `startCrossfade()` captures
   `m_fadeOutDeck = m_activeDeck` and `m_fadeInDeck = 1 - m_activeDeck` — fixed for
   this fade's whole lifetime, independent of when the UI-facing `m_activeDeck` alias
   itself later swaps (see step 4) — loads the next track into `m_fadeInDeck` at
   volume `0`, starts it playing, and starts `m_fadeTimer` (~40 ms tick).
3. Each tick (`onFadeTick()`) advances a simple elapsed-ms counter (not wall-clock —
   stopping the `QTimer` freezes the fade exactly in place, which is what makes pause
   trivial) and linearly sets `m_fadeOutDeck.volume = 1 − frac`,
   `m_fadeInDeck.volume = frac`.
4. At the **midpoint** (`frac >= 0.5`, fired once): `m_activeDeck` (and the `m_player`/
   `m_audioOutput` alias pointers) swap to `m_fadeInDeck` **here**, not at
   fade-completion — immediately followed by `switchCurrentIndexTo(nextIdx)`
   (`m_currentIndex` advances, `rating`/`ratingId` resolve for the incoming track, the
   cover fetch kicks off, `currentIndexChanged`/`currentTrackChanged`/
   `currentRatingChanged` fire) and explicit `durationChanged()`/`positionChanged()`/
   `isPlayingChanged()` emissions. This is the single point that satisfies "update
   *everything* in `NowPlaying` — including the length label and play/pause icon, which
   read through the now-swapped `m_player` alias — and `PlaybackQueue`'s highlighted
   row in the middle of the crossfade." `PlaybackQueue`'s highlight comes from
   `IsPlayingRole`, refreshed by the same `dataChanged` call inside
   `switchCurrentIndexTo()`. Swapping the alias at the midpoint rather than
   fade-completion also avoids a signal-ordering bug where stopping the outgoing deck
   at fade-completion would otherwise fire a stale `isPlayingChanged()` from the
   about-to-be-reassigned alias.
5. At `frac >= 1.0`: the timer stops, `m_fadeOutDeck` (no longer `m_activeDeck` since
   the swap already happened at the midpoint, so its `playbackStateChanged` is
   correctly suppressed by the per-deck signal guards) is stopped and its volume reset
   to `1.0` for reuse.

### Alternate: track too short to crossfade

The eligibility rule in step 1 above is the single mechanism behind all three cases the
feature was specified with, with no extra state needed:
- A track shorter than the crossfade length can never supply a valid fade-out **or**
  fade-in window (the ramp would have to start before the track even began), so it's
  excluded from either side of a transition automatically.
- The very **first** track played in a session (`playAt()`/`togglePlay()` from an idle
  queue/`addTrack()` auto-play) always goes through `loadTrack()` directly — the
  crossfade machinery is never engaged for it, so it never fades in.
- If the **next** track is too short, the current transition falls through to a hard
  cut; since a hard-cut-into track was never crossfaded, the same rule means it also
  can't crossfade *out* into whatever follows it — so the track *after* a short one
  also starts with a hard cut, regardless of its own length.

### Alternate: interrupted mid-crossfade

`cancelCrossfade()` — stop the fade timer, stop the standby deck, reset both decks'
volumes to `1.0` — runs before `loadTrack()`, `seek()`, and every queue-mutating method
(`removeAt`, `clearQueue`, `moveUp`, `moveDown`, `moveTrack`). Any of these occurring
mid-crossfade abandons the fade and snaps to a clean single-deck state rather than
attempting to reconcile the interruption with an in-progress fade — a deliberate
simplification, since this is a narrow, few-second window. `togglePlay()` pauses/resumes
both decks together when `m_crossfading` is true — and, critically, also stops/restarts
`m_fadeTimer` itself in lockstep. `m_fadeElapsedMs` advances purely on the timer's
wall-clock ticks, independent of the decks' actual playback state, so pausing only the
decks without also stopping the timer would let the fade keep advancing in the
background — including past the midpoint (`switchCurrentIndexTo()`, which also clears
`userPaused`, see UC-07) or to completion — while the user sits paused, silently
swapping the current track out from under them and ending the Play/Pause blink early.
Stopping `m_fadeTimer` is what actually makes "stopping the `QTimer` freezes the fade
exactly in place" (above) true for a user-initiated pause, not just for
`cancelCrossfade()`; resuming restarts the timer, which continues the ramp from the
exact `frac` it was frozen at, since `m_fadeElapsedMs` was never touched.

### Design notes

- **Why dual-deck**: `QMediaPlayer` cannot play two sources at once, so a real
  crossfade requires two independent `QMediaPlayer`/`QAudioOutput` pairs. `m_player`/
  `m_audioOutput` are kept as alias pointers to `m_players[m_activeDeck]`/
  `m_audioOutputs[m_activeDeck]` specifically so every pre-existing single-deck code
  path continues to work unchanged.
- **Linear fade**: volumes are set directly from the elapsed fraction with no easing
  curve, per the requirement.
- **AUTO PLAY feature is unrelated**: this use case is purely a playback-transition
  effect; it does not use track ratings and is independent of the AUTO PLAY button
  discussed in UC-14/UC-16.

---

## UC-16 AUTO PLAY Session

| Field | Detail |
|-------|--------|
| **Goal** | While active, AUTO PLAY keeps the queue filled to `Queue Horizon` by polling every `Title Adding` seconds and adding one library track at a time, chosen by the Consider Genre / Consider Rating / Play a Title filters. |
| **Actor** | User (start/stop, config changes), System (candidate selection, polling, gating) |
| **Precondition** | `libraryModel.ratingsReady` is `true` (a scan has completed at least once). |
| **Trigger** | User clicks the AUTO PLAY footer button. |

`AutoPlayController` (`autoplaycontroller.h/.cpp`, `QML_ELEMENT`) owns this entire use
case. It depends on `PlaybackEngine`, `LibraryModel`, and `AppConfig` — none of those
three classes have any knowledge of `AutoPlayController`, keeping `PlaybackEngine` a
pure playback engine and `LibraryModel` a pure library index. Instantiated once in
`Main.qml`, bound to `activeGenreNames: lib.activeGenreNames` (the same source GenreBar
itself reads) and forwarded as `autoPlay` to `BottomBar`, `AlbumBrowser`→`AlbumCard`,
`PlaybackQueue`, and `NowPlaying`.

### Normal Flow — Start a session

1. User clicks AUTO PLAY. The button is only clickable/green once **both**
   `autoPlayReady` (`libraryModel.ratingsReady`) is `true` **and**
   `autoPlay.genreRequirementMet` is `true` — the latter is always `true` when
   `autoPlayConsiderGenre` is off, otherwise it requires
   `activeGenreNames` (bound from `lib.activeGenreNames`) to be non-empty, since with
   Consider Genre on and zero active genres AUTO PLAY could never find a single
   eligible candidate. `BottomBar` combines both into a local `autoPlayGated`
   property for its color and click-handler. `start()` re-checks
   `genreRequirementMet()` itself (defense in depth) before doing anything else, so
   it refuses to start regardless of how `toggle()` was invoked.
2. `BottomBar` calls `autoPlay.toggle()` → `start()`.
3. `start()` clears the in-memory play-history (`QHash<QString /*filePath*/, int>
   m_playCounts`) — a fresh history every session.
4. If the queue is empty **or** `engine.queueFinished()` is `true` (every queued
   track has already played through to its natural end — see "Auto-play a
   newly-added track" below), `pickNextCandidate()` (below) selects one track and
   `PlaybackEngine::addTrack(candidate, true)` adds it — `addTrack`'s auto-play
   condition (queue empty or finished) starts it playing immediately, satisfying
   "add the first track immediately and play it" whether the queue was genuinely
   empty or just has nothing left to play. A track that's merely *paused* leaves
   `queueFinished()` `false`, so starting AUTO PLAY in that state does **not**
   force a new track over it — falls through to case 5 instead. If no candidate
   exists at all (the library has nothing matching the current filters), `start()`
   returns without activating — the button stays green.
5. Otherwise (something is actually playing or paused), `m_active` becomes `true`
   and the poll timer starts at the configured interval — no immediate top-up; the
   next addition happens on the first tick (see below).
6. `activeChanged()`/`manualQueueEditingAllowedChanged()`/`queueClearAllowedChanged()`
   fire — `BottomBar` turns red; the queue's clear button and (unless Allow Manual
   Modification is on) add/remove/reorder controls become disabled.

**No separate mid-session force-stop is needed if genres are cleared while a session
is running**: `autoPlayCandidatePool()` with `considerGenre=true` and an empty
`activeGenres` list matches nothing (every track's genre-membership test against an
empty set is false), so `pickNextCandidate()` already returns no candidate and the
existing starvation path (`stop(true)`, below) fires the next time the controller
needs to add a track — the genre-requirement gate only needs to guard *starting* a
session, not react to it changing mid-session.

### Normal Flow — Polling top-up

1. Every `autoPlayTitleAddingIntervalSeconds` seconds, `onPollTick()` calls
   `maybeFillHorizon()`.
2. `maybeFillHorizon()` computes **tracks-ahead** as `queueCount() - currentIndex() -
   1` — not raw `queueCount()`, since the queue never shrinks on natural playback
   (only manual `removeAt`/`clearQueue` do; already-played rows stay in `m_queue`
   forever). If tracks-ahead `>= autoPlayQueueHorizon`, nothing happens this tick —
   "wait for the next possible Title Adding."
3. Otherwise `pickNextCandidate()` selects one track and `addTrack()`s it — never more
   than one per tick, by construction (every top-up beyond the initial kickstart is
   gated behind this single per-tick call, not a loop).
4. If no candidate exists, the session **starves**: `stop(true)` — see below.
5. A mid-session change to `autoPlayTitleAddingIntervalSeconds` restarts the timer
   immediately (`QTimer::start(ms)` both changes the interval and resets the
   countdown) via a direct connection to `AppConfig::autoPlayTitleAddingIntervalSecondsChanged`,
   so a slider drag takes effect on the very next wait, not the current one.

### Normal Flow — Candidate selection (`pickNextCandidate()`)

1. `LibraryModel::autoPlayCandidatePool(activeGenreNames, considerGenre,
   considerRating, minimumRating)` returns every library track passing the genre
   filter (skipped entirely if Consider Genre is off) and the rating filter (skipped
   if Consider Rating is off; unrated tracks, `rating == 0`, are naturally excluded
   whenever it's on, since `minimumRating` is clamped to `[1, 10]`).
2. Each candidate's **effective occurrence count** is computed as completed plays
   (`m_playCounts`, updated only via `trackPlayedToCompletion` — see below) **plus**
   however many times its `filePath` appears in `engine.trackList()` from
   `currentIndex()` onward (the currently-playing row itself, and everything still
   queued ahead of it — each such occurrence represents a play that either is
   happening right now or is guaranteed to happen once reached). This single unified
   count is what stops `"once"` from re-selecting the track that's playing at this
   very moment (it has 0 completed plays but 1 queue occurrence) as well as anything
   already sitting unplayed further ahead — there is no separate hard "already
   queued" exclusion; both cases fall out of the same formula.
3. The pool is filtered by `autoPlaySongRepeat` against each candidate's effective
   count: `"once"` keeps count `== 0`; `"twice"` keeps count `< 2` (so a track playing
   once right now, effective count `1`, can still be queued for its second and final
   play); `"twiceIfNoneAvailable"` prefers count `== 0`, falling back to count `== 1`
   only when zero count-`0` tracks remain (never count `>= 2`); `"several"` applies no
   cap at all — unaffected by queue occurrences, a track can be queued repeatedly
   regardless of how many copies are already playing/queued/completed.
4. If nothing remains, no candidate (starvation or a quiet no-op, depending on caller).
5. Otherwise one track is chosen uniformly at random
   (`QRandomGenerator::global()->bounded(n)`). **Every** track-adding path — the
   initial empty-queue kickstart, each poll-tick top-up, and stall recovery (below) —
   calls this same function, so selection is always random, never deterministic or
   library-ordered, and no two sessions play back the same running order.

### Normal Flow — Recording play-history

`PlaybackEngine::trackPlayedToCompletion(filePath)` is a new signal, emitted **only**
on natural completion — never on manual `next()`/`previous()`, which are a separate
code path that never touches it:
- In `advanceToNext()` (reached only via `onDeckMediaStatusChanged()`'s
  `QMediaPlayer::EndOfMedia` branch), emitted for the track at `currentIndex` just
  before advancing.
- In `onFadeTick()`'s fade-completion branch (`frac >= 1.0`), emitted for the
  **outgoing** track — captured as `m_fadeOutIndex` in `startCrossfade()`, since
  `currentIndex` has already swapped to the incoming track by the midpoint.

`AutoPlayController::onTrackPlayedToCompletion()` increments `m_playCounts[filePath]`
unconditionally (whether or not a session is currently active — harmless, since
`start()` always resets the map anyway).

### Normal Flow — Visual feedback for auto-added tracks

Optional, off by default (`AppConfig.autoPlayFlickerNewTracks`, Setup →
AUTO PLAY → "New Tracks are Flickering"). All 3 track-adding paths above —
the initial empty-queue kickstart in `start()`, each poll-tick top-up in
`maybeFillHorizon()`, and stall recovery in `onQueueExhausted()` — call
`m_engine->addTrack(candidate, true)` instead of the 1-argument form,
marking the newly appended row so `PlaybackQueue` can flicker it and draw
the user's attention. No other path (manual drag/double-click add, batch
`addTracks()` used by playlist loading — see UC-10/UC-22/UC-23) ever passes
`true`, so this is scoped to AUTO PLAY additions only.

- `PlaybackEngine::addTrack(map, autoPlayAdded = false)` sets a new,
  purely transient `TrackInfo::autoPlayAdded` field on the appended row
  (never persisted — `LibraryCache` and `PlaylistManager::appendTrack()`
  both serialize field-by-field / from the original `QVariantMap`, never
  touching this field) and exposes it as a new `QueueRole`
  (`IsAutoPlayAddedRole` → `"autoPlayAdded"` in QML), following the exact
  same shape as the existing `IsPlayingRole`/`"playing"`.
- When `autoPlayAdded` is `true`, `addTrack()` schedules a
  `QTimer::singleShot(2000, …)` that clears the flag and emits
  `dataChanged` for that role — turning the flicker into a brief ~2s
  attention cue rather than a permanent marker. The row index is captured
  by value at schedule time; if an earlier row is removed/reordered in
  that exact ~2s window the timer could clear the wrong row's flag (or
  rarely leave one flickering a touch past 2s) — an accepted,
  self-correcting tradeoff for a purely cosmetic feature, not worth a
  heavier stable-identity mechanism.
- `PlaybackQueue.qml`'s row delegate reacts to `model.autoPlayAdded` with a
  `SequentialAnimation on opacity` (looping while
  `model.autoPlayAdded && appConfig.autoPlayFlickerNewTracks` both hold)
  on a new `Rectangle` layered just behind the existing "Playing-now
  highlight" — so a track that's both just-added *and* immediately playing
  (the stall-recovery and empty-queue-kickstart cases) shows both effects
  together without conflict. Driving the animation purely off the data
  role (not a one-shot `Component.onCompleted` trick) means it behaves
  correctly under `ListView` virtualization: a row added off-screen and
  scrolled into view later won't spuriously re-flicker, since the
  animation only ever runs for as long as the role is actually `true`.

### Alternate: playback stalls at end of queue

`advanceToNext()`'s existing "no next track" branch (queue exhausted) sets
`m_queueFinished = true` (see "Auto-play a newly-added track" below) and emits a
`PlaybackEngine::queueExhausted()` signal — needed because neither
`queueCountChanged` nor `currentIndexChanged` fires in that branch, so nothing would
otherwise notice playback has silently stopped. `AutoPlayController::onQueueExhausted()`
reacts immediately (not on the next poll tick, since music has already stopped):
`pickNextCandidate()`, and if found, `addTrack(candidate, true)` — which now auto-plays
the new track on its own, since `m_queueFinished` is still `true` at this point; no
separate `playAt()` call is needed (an earlier version called both, redundantly
reloading the same track twice). If no candidate is found, `stop(true)`.

### Auto-play a newly-added track (queue empty or finished)

`PlaybackEngine::addTrack()`/`addTracks()` auto-play the newly-added track
when `m_currentIndex < 0` (queue was completely empty — the original
rule) **or** `m_queueFinished` is `true` (every queued track has already
played through to its natural end). The two states otherwise look
identical from `m_currentIndex`/`isPlaying()` alone — both leave
`m_currentIndex` pointing at the last track and `isPlaying() == false` —
so a dedicated flag is needed to tell "queue naturally finished" apart
from "current track is merely paused," which must **never** auto-start a
newly-added track. `m_queueFinished` is set only by `advanceToNext()`'s
no-next-track branch, and cleared by `loadTrack()` — the single choke
point every track-loading path (`playAt`, `next`, `previous`,
`togglePlay`'s from-empty branch, `advanceToNext`'s has-next-track branch,
and `addTrack`/`addTracks`' own auto-play branches) already funnels
through — so it's always accurate regardless of *how* a track next gets
loaded. This applies uniformly to AUTO PLAY additions and manual ones
(`AlbumCard`'s double-click, drag-and-drop into `PlaybackQueue`) alike,
since both call through `addTrack()`/`addTracks()`. `PlaybackEngine` also
exposes a plain public `queueFinished()` getter (not `Q_PROPERTY`/
`Q_INVOKABLE` — C++-only) so `AutoPlayController::start()` can apply the
exact same "empty or finished" test when deciding whether *starting* a
session should also play immediately (Normal Flow step 4 above), not just
`addTrack()`/`addTracks()` themselves.

### Alternate: starvation

Whenever `pickNextCandidate()` returns nothing during an active session (a poll tick's
top-up, or stall recovery), `stop(true)` runs: the poll timer stops, `m_active` becomes
`false`, and the three gating/active signals fire. `BottomBar` turns green again purely
as a consequence of `activeChanged()` — no separate "reset" step needed. A `starved()`
signal fires alongside, and a system-tray notification is shown (see "Desktop
notifications" below). Per the current design, nothing more sophisticated happens on
starvation: AUTO PLAY simply stops and MANUAL MODE resumes.

### Desktop notifications

`AutoPlayController` shows a Windows system-tray notification
(`QSystemTrayIcon::showMessage()`) at its three lifecycle moments — each already has an
exact, unambiguous call site, so no extra signals/state were needed beyond what
starvation detection already tracks:
- **Activated** — in `start()`, right after `m_active = true`. Title `"AUTO PLAY"`,
  message `"Activated"`.
- **Manually deactivated** — in `stop(bool starved)`'s `starved == false` branch (the
  user clicked the button off). Title `"AUTO PLAY"`, message `"Deactivated"`.
- **Starvation** — in `stop(bool starved)`'s `starved == true` branch, alongside the
  existing `starved()` signal. Title `"AUTO PLAY starvation"`, message `"There are no
  more suitable tracks available"`.

`QSystemTrayIcon::isSystemTrayAvailable()` is checked once at construction
(`m_trayAvailable`) — every `showTrayMessage()` call is a no-op when it's `false` or the
platform's tray icon couldn't be created. The tray icon itself is created (using
`app.ico`, bundled into the QML module's resources via `qt_add_qml_module`'s
`RESOURCES app.ico`) and shown for the app's entire lifetime — required because Windows
balloon/toast notifications anchor to a visible tray icon; there's no way to pop one
without a persistent icon present.

**Resource path gotcha**: files listed under `qt_add_qml_module`'s `RESOURCES` keyword
(plain, non-QML files) land under the module's bare URI prefix, `:/Topaz/app.ico` —
**not** `:/qt/qml/Topaz/app.ico`, which is only the prefix for `QML_FILES` entries (per
the QTP0001 default-prefix CMake warning, easy to mistakenly assume applies to
`RESOURCES` too). Confirmed by inspecting the generated
`build/.qt/rcc/topaz_raw_res_0.qrc`. Getting this wrong silently yields a null `QIcon`,
which is exactly what happened the first time this was implemented: the tray icon
never actually registered with the Windows shell, so no notification ever appeared. A
defensive fallback (`QApplication::style()->standardIcon(QStyle::SP_MediaPlay)` if the
loaded icon is null) now guards against the same class of mistake recurring silently.

**Known limitation — no notifications while fullscreen**: `showTrayMessage()`
notifications don't appear while Topaz is in `Window.FullScreen` mode (auto-triggered
for exact-match screen resolutions, or via F11 — see `Main.qml`). This is Windows'
Focus Assist automatic rule "When using an app in full screen mode," which suppresses
toast/balloon notifications for any true fullscreen window at the OS level, by design
(so games/movies aren't interrupted) — not a defect in Topaz's `QSystemTrayIcon` usage,
which behaves identically in fullscreen and windowed mode. A code-side workaround
(replacing true OS fullscreen with a borderless-maximized window, hoping Windows no
longer classifies it as "fullscreen" for this purpose) was considered and explicitly
declined: its effectiveness is unverified, and it would touch the existing tuned
auto-fullscreen/F11 behavior for uncertain benefit. Anyone who wants notifications
while Topaz is fullscreen can disable this via Windows Settings → Focus assist →
Automatic rules → turn off (or exempt Topaz from) "When using an app in full screen
mode."

`QSystemTrayIcon` lives in the **QtWidgets** module and requires a `QApplication`, not
the `QGuiApplication` a QML-only app normally constructs — `main.cpp` now constructs
`QApplication` instead (a drop-in superset; no QML/Quick behavior changes), and
`CMakeLists.txt` links `Qt6::Widgets`.

The tray icon is owned directly by `AutoPlayController` (`m_trayIcon`) rather than a
separate notifier class — a pragmatic choice given there are only 3 short, tightly
bound notifications; a dedicated class would be a premature abstraction for this scope.

### Alternate: manual queue editing during a session

Four independent gating properties on `AutoPlayController`, read by every relevant QML
control:
```cpp
bool manualQueueEditingAllowed() const {
    return !m_active || (m_appConfig && m_appConfig->autoPlayAllowManualModification());
}
bool queueClearAllowed() const { return !m_active; }
bool playPauseAllowed() const {
    if (!m_active || manualQueueEditingAllowed()) return true;
    if (!m_appConfig) return false;
    const QString mode = m_appConfig->autoPlayTransportAccess();
    return mode == "playPause" || mode == "playPauseAndSelect";
}
bool trackNavigationAllowed() const {
    if (!m_active || manualQueueEditingAllowed()) return true;
    if (!m_appConfig) return false;
    return m_appConfig->autoPlayTransportAccess() == "playPauseAndSelect";
}
```
`manualQueueEditingAllowed` governs add/remove/reorder (`PlaybackQueue`'s move-up/down,
remove, drag-reorder, and album-drop `DropArea`; `AlbumCard`'s double-click add;
`NowPlaying`'s playlist-load add) — always `true` outside a session (MANUAL MODE),
otherwise following `autoPlayAllowManualModification`. `queueClearAllowed` governs the
queue's CLEAR button and `NowPlaying`'s LOAD/REMOVE buttons — all three are fully
disabled (dimmed, non-interactive), not just gated on click — **always** `false`
during an active session regardless of `autoPlayAllowManualModification`,
matching "it is forbidden for the user to clear the whole queue during a session; this
is just allowed in MANUAL MODE." Every clear site routes through
`AutoPlayController::clearQueueAndHistory()` instead of calling
`engine.clearQueue()` directly, so `m_playCounts` always resets in lockstep with the
queue — including "restarting the next AUTO PLAY session does the same [reset]," since
`start()` also unconditionally clears it.

`playPauseAllowed` (gates `NowPlaying`'s Play/Pause button) and `trackNavigationAllowed`
(gates `NowPlaying`'s Previous/Next buttons and clicking a `PlaybackQueue` row to select
a different track) are both unconditionally `true` outside a session or whenever
`autoPlayAllowManualModification` is on — full transport control always accompanies
full queue control. While a session is active *and* Allow Manual Modification is off,
both instead follow `AppConfig.autoPlayTransportAccess` (`SetupDialog`'s AUTO PLAY tab
"Exceptions" radio group, indented under Allow Manual Modification and only
interactive/undimmed while it's off — the inverse dependency direction from Minimum
Rating's indent under Consider Rating): `"nothing"` (default) — both `false`, full AUTO
PLAY with zero manual interaction; `"playPause"` — only `playPauseAllowed` is `true`;
`"playPauseAndSelect"` — both `true`, since that tier is a strict superset including
play/pause. This is a pure start-time-style gate re-evaluated on every click, not a
one-shot check — toggling `autoPlayTransportAccess` or `autoPlayAllowManualModification`
mid-session takes effect on the very next click of any of these controls.

Deliberately, these gates are QML-layer only — not additionally re-checked inside
`PlaybackEngine`'s own invokables. The controller itself must call `addTrack`/etc.
unconditionally while `m_active` is `true` (that's the whole polling mechanism), so a
blanket engine-side guard would also block the controller's own legitimate calls
without a bypass parameter threaded through every call site. A single correctly-derived
gate applied consistently at every QML entry point is simpler and sufficient.

### Design notes

- **Strict one-track-per-tick, no catch-up bursts**: after the initial empty-queue
  kickstart, every further addition — whether topping up toward the horizon or
  reacting to the user having manually removed several tracks mid-session — happens
  only on the poll timer's own cadence. There is no reactive "top up immediately when
  the queue shrinks" path; a session that's well under horizon simply climbs back up
  one track per tick, matching the spec's literal "add ONE track after this certain
  amount of time" framing rather than trying to catch up faster.
- **Why a new class instead of extending `PlaybackEngine`**: `PlaybackEngine` is
  already large (dual-deck crossfade, queue model, transport). AUTO PLAY's policy
  (filtering, history, starvation, gating) has nothing to do with `QMediaPlayer`, so it
  lives in its own class that calls `PlaybackEngine`'s existing invokables rather than
  growing inside it.

---

## UC-17 Detachable Panes (Big Cover)

| Field | Detail |
|-------|--------|
| **Goal** | User detaches the current track's cover art into its own frameless, movable, resizable window — usable as a "now playing" signage view on the main display or a second monitor — independent of the main `ApplicationWindow`. |
| **Actor** | User |
| **Precondition** | Topaz is running; `NowPlaying`'s album cover is visible. |
| **Trigger** | User left-clicks the album cover in `NowPlaying` (pointing-hand cursor, same as Play/Pause). |

This is the first of a planned family of detachable panes (tag information with
larger fonts, audio visualizations are planned next) — the window chrome (move,
resize, right-click-to-close, geometry persistence) is factored into a reusable
`FloatingPane.qml` base for that reason, not speculatively.

### Why not a `Popup`

`SetupDialog`/`NewPlaylistDialog`/the OS-Volume flyout (`TopBar.qml`) all use
QtQuick Controls' `Popup`, but a `Popup` is clipped to and cannot leave its owning
`ApplicationWindow`'s surface — incompatible with "drag onto a second monitor." This
pane is instead a genuine second top-level QML `Window`, loaded on demand via a
`Loader` in `Main.qml` so each open starts from freshly-restored/validated geometry
rather than carrying stale state between opens.

### `FloatingPane.qml` — reusable chrome

A frameless (`flags: Qt.Window | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint`)
`Window` base:
- `default property alias contentData: contentItem.data` — subclasses just nest
  their content directly inside `FloatingPane { ... }` (see `BigCoverWindow.qml`).
- **Move**: a whole-pane `MouseArea` calls `Window.startSystemMove()` — an OS-native
  interactive move (Qt 6.8+; confirmed supported on Windows), not manual x/y math,
  so it's correct across monitors with different DPI/scaling without any extra code.
  `cursorShape: Qt.PointingHandCursor` + `hoverEnabled: true` on the same
  `MouseArea`, matching `NowPlaying`'s Play/Pause cursor exactly. Triggered from
  `onPositionChanged` (guarded to fire only once per gesture via a `_moveStarted`
  flag reset in `onPressed`) once actual movement is seen while the left button is
  held — **not** unconditionally on the raw press. An earlier version called
  `startSystemMove()` directly from `onPressed`; that starts the OS's native
  interactive-move loop immediately on every press, which bypasses Qt's normal
  input pipeline for that gesture and — confirmed by testing, not just theorized —
  swallows the second press of a double-click before `MouseArea`'s own
  `onDoubleClicked` synthesis ever sees it. Since a stationary click (both halves of
  a double-click) never reaches the movement branch, the native loop is never
  entered for it, leaving Qt's normal click/double-click detection intact; a real
  drag still starts moving on its very first pixel of motion, so single-click-drag
  keeps feeling instant.
- **Double-click detection (`doubleClicked()` signal)**: the same whole-pane
  `MouseArea`'s own (now-reliable, per above) `onDoubleClicked` re-emits a generic
  `doubleClicked()` signal on the pane for left-button double-clicks — what it
  *means* is entirely up to the subclass (e.g. `TagInfoWindow`'s maximize/restore
  toggle, see UC-18); `FloatingPane` itself has no maximize logic, same
  "detect/emit, owner decides" split as `closeRequested()`/`geometrySettled()`. A
  pane that never adds an `onDoubleClicked` handler (e.g. `BigCoverWindow`) is
  completely unaffected — the signal just goes unheard.
- **`cursorHidden` property**: `false` by default; when `true`, every
  interactive `MouseArea` above (the move area and all eight resize grips)
  shows `Qt.BlankCursor` instead of its own native shape. Same "generic base,
  subclass decides meaning" split as `doubleClicked()` — `FloatingPane` has
  no opinion on *when* to hide the cursor. First (and so far only) consumer:
  `MilkdropWindow.qml`'s auto-hide-during-fullscreen-idle behavior (UC-20).
  Needed because the move `MouseArea` alone already covers the whole pane, so
  a pane's own content (added into `contentItem`, which is declared *before*
  these `MouseArea`s and therefore stacks below them) has no way to override
  their cursor from outside `FloatingPane.qml` itself.
- **`mouseMoved()` signal**: emitted from the move `MouseArea`'s own
  `onPositionChanged` (fires on pure hover too, not just drags —
  `hoverEnabled: true`) on every movement over the pane's interior. Same
  generic "detect/emit, subclass decides" split as `doubleClicked()`. First
  consumer: `MilkdropWindow.qml`'s cursor-idle-reset logic (UC-20) — added
  specifically because that logic's first attempt used a separately-declared
  `HoverHandler`, which didn't reliably receive hover while stacked below
  this same `MouseArea`; reusing the `MouseArea`'s own already-proven
  movement detection (the same handler that reliably drives window dragging)
  sidesteps that reliability question entirely. Only covers the move area's
  extent, not the 8 resize grips at the pane's edges.
- **Resize**: eight thin (8px) edge/corner `MouseArea`s with the matching cursor
  shape (`SizeHorCursor`/`SizeVerCursor`/`SizeFDiagCursor`/`SizeBDiagCursor`). When
  `fixedAspectRatio` (see below) is `0` (the default), pressing one calls
  `Window.startSystemResize(Qt.<Edge>)` — OS-native, no visible grip graphics needed
  beyond the cursor change.
- **Close**: the same whole-pane `MouseArea`'s right-click emits `closeRequested()`.
  The pane does not close itself — the owner (the `Loader` in `Main.qml`) decides
  what "closed" means, currently just `bigCoverPaneOpen = false`.
- **Persistence hook**: `onXChanged`/`onYChanged`/`onWidthChanged`/`onHeightChanged`
  restart a 500ms debounce `Timer` (same pattern as `Main.qml`'s `saveLayoutTimer`)
  that emits `geometrySettled(x, y, width, height, screenName)`. `FloatingPane.qml`
  itself has no `AppConfig` dependency — generic on purpose, for the panes planned
  later — the owner wires this signal to actual persistence.
- Starts `visible: false` explicitly (not relying on `Window`'s own default) so it
  never flashes at a default position before the owner repositions it.

### `WindowChrome` singleton — genuine translucency + removing OS-drawn chrome

Added when `AudioVisualizerWindow`'s configurable background opacity (see UC-19)
exposed two separate, unrelated gaps in "frameless," found and fixed across two
rounds:

**Round 1 (insufficient on its own): Windows 11's default DWM accent border** —
drawn around *every* top-level window since Windows 11 build 22000, independent of
frameless status or content. No QML property covers this; requires a native
`DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, &DWMWA_COLOR_NONE, ...)` call. This
alone was shipped first and turned out not to be the (whole) problem — the user
reported the pane still looked like "a solid/opaque box," not just a bordered one.

**Round 2 (the actual fix): the window wasn't translucent at all.** Qt6's default
hardware-rendering (RHI/D3D11) backend on Windows does not reliably negotiate
window-level alpha compositing from a QML `color` binding with alpha alone — a real,
somewhat known Qt6-on-Windows limitation (Qt Forum: "Qt5 -> Qt6 partial window
transparency"; "Translucent background not rendering correctly in Qt6 with hardware
rendering but works with Software rendering"), confirmed here empirically (pane
opacity read back correctly but rendered fully opaque regardless). The fix: request
an alpha-capable `QSurfaceFormat` (`setAlphaBufferSize(8)`) **before** the native
window is created — once created, the surface format is locked in, and a `color`
binding with alpha from that point only controls what's drawn, not whether the
window *can* composite as translucent at all.

Both concerns live in one class, `windowchrome.h`/`.cpp` — a small `QObject` with
`QML_ELEMENT` + `QML_SINGLETON` (stateless, one shared instance), exposing a single
`Q_INVOKABLE void prepareWindow(QQuickWindow *window)` that does, strictly in this
order:
1. `window->setFormat()` with `setAlphaBufferSize(8)` requested — **must** happen
   before anything forces native creation.
2. `window->create()` — explicit, with that format now locked in.
3. `DwmSetWindowAttribute(..., DWMWA_BORDER_COLOR, DWMWA_COLOR_NONE, ...)` — only
   possible once a real `HWND` exists, which step 2 guarantees.

`FloatingPane.qml` calls it from its own
`Component.onCompleted: WindowChrome.prepareWindow(pane)` — nested
`Component.onCompleted` handlers fire innermost-first, so this runs before any
subclass's outer `Component.onCompleted` (in `Main.qml`'s `Loader.sourceComponent`
blocks, which set `visible = true`), guaranteeing the correct step order relative to
the window actually being shown.

`DWMWA_BORDER_COLOR`/`DWMWA_COLOR_NONE` are **hardcoded as raw constants** (`34` /
`0xFFFFFFFE`) rather than relied upon as names from mingw-w64's bundled `dwmapi.h` —
both are Windows 11 additions that header may predate, the same defensive reasoning
already applied to `SystemVolumeController`'s hardcoded COM GUIDs. Values
cross-checked against Microsoft's published `DWMWINDOWATTRIBUTE` documentation
before writing any code. The DWM call logs via `qWarning()` and no-ops on failure
(e.g. pre-Windows-11, where it simply fails harmlessly) rather than crashing — same
convention `SystemVolumeController` uses for COM failures. Requires linking
`dwmapi` (parallel to `ole32` for `SystemVolumeController`).

Applies to every pane in the family (`BigCoverWindow`/`TagInfoWindow`/
`AudioVisualizerWindow`), not just the visualizer — harmless for the two always-opaque
panes (an unused alpha channel changes nothing visually for them).

Windows-only, no `#ifdef` guard — same as `SystemVolumeController`; both are tracked
together as needing a platform switch for a future Linux port.

### Aspect-locked resize (`fixedAspectRatio`)

`property real fixedAspectRatio: 0` — `0` (default) means free resize via
`startSystemResize()` as above; a positive value is the `width/height` ratio to
maintain (`1.0` for a square pane like `BigCoverWindow`). Generic on purpose — any
future `FloatingPane` subclass can opt in, not just square ones.

`startSystemResize()` hands the *entire* interactive resize gesture to the OS window
manager — Qt/QML gets no opportunity to constrain intermediate frames of it, so it's
fundamentally incompatible with enforcing a ratio. When `fixedAspectRatio > 0`, the
8 resize `MouseArea`s switch to a manually-tracked resize instead, computed via
`Item.mapToGlobal()` — the same "pure mouse-position tracking" idiom `PlaybackQueue`
already uses for queue-reordering, applied here to window geometry:
- `onPressed` (`beginAspectResize`) captures the press-time *global* cursor position
  (`item.mapToGlobal(mouse.x, mouse.y)`) plus the pane's starting `x`/`y`/`width`.
- `onPositionChanged` (`updateAspectResize`) recomputes geometry from the delta
  between the *current* global cursor position and that fixed press-time snapshot —
  deliberately not accumulated per-frame local deltas, which would drift, since the
  grip itself moves every frame as the window resizes (its anchors are relative to
  the window's own edges).
- Each grip is parameterized by which corner of the pane stays fixed
  (`xAnchorRight`/`yAnchorBottom`) and which mouse-delta axis drives its growth
  (`useX`/`useY`) — corners use both axes via `Math.max()` (whichever axis moved the
  cursor further drives the resize); edges use only their own axis but still resize
  *both* dimensions together (unavoidable once locked to a ratio) — right/bottom
  edges anchor at top-left, left/top edges anchor at bottom-right, a consistent,
  predictable convention rather than an arbitrary one.
- Resulting size is clamped to `minPaneWidth`.

### `BigCoverWindow.qml`

A `FloatingPane` specialization (`fixedAspectRatio: 1.0` — covers are always square)
containing one `Image`, reusing `PlaybackEngine.currentLargeCoverSource`/
`currentCoverSource` — the exact same fallback expression `NowPlaying.qml`'s own
embedded cover `Image` already binds. Both properties already have `NOTIFY` signals
that fire on every track change, so this pane's cover "updates too" automatically —
no new C++ code needed for that. Uses `Image.PreserveAspectFit` (letterboxed, never
cropped) and `sourceSize.width/height` bound to the pane's own (reactive-to-resize)
size, matching `NowPlaying`'s decode-size-constraining pattern.

**Cover-never-appears bug, root cause and fix**: covers stayed stuck on the
placeholder through two rounds of guessing (an async-decode-vs-fresh-window race, and
a suspected `data:image/jpeg` vs. actual-PNG MIME mismatch — see `PlaybackEngine`
below) before a temporary on-screen diagnostic (`engine` null/ok,
`currentLargeCoverSource`/`currentCoverSource` string lengths, `Image.status`,
`Image.errorString`, shown directly in the pane) proved the real cause on the first
try: `bigCover.engine` was `NULL`. The wiring bug — see `Main.qml wiring` below for
the fix — was a genuine QML scoping gotcha, not a data or decode problem; `Image`'s
`sourceSize`/`asynchronous: true` settled back to matching `NowPlaying`'s pattern
once the actual cause was found.

**Double-click to cycle horizontal position**: reuses `FloatingPane`'s generic
`doubleClicked()` signal (see above) for a **4-state cycle**, a different shape of
state machine than `TagInfoWindow`'s 2-state maximize/restore toggle (UC-18) — each
double-click advances one step and wraps around: original position (captured lazily
on the *first* double-click of this open, via an uncaptured/captured flag — not a
separately persisted value, since a fresh `BigCoverWindow` instance is created by
`Main.qml`'s `Loader` every time the pane opens, so "original" naturally means
wherever *this* open started) → horizontally centered → flush right edge → flush
left edge → back to original → repeats. Only `x` changes; `y`/`width`/`height` are
never touched, since the pane is always square (`fixedAspectRatio: 1.0`) and the
user resizes it manually — double-click repositioning and manual resizing don't
interact. As with `TagInfoWindow`'s maximize, no special persistence handling is
needed: `FloatingPane`'s existing debounced `geometrySettled` fires on these
programmatic `x` changes exactly like a manual drag, so whichever state the pane is
left in when closed is what's restored next time it opens.

### `Main.qml` wiring and geometry restore

```qml
property bool bigCoverPaneOpen: false
function rectIntersectsAnyScreen(x, y, w, h) { ... }  // checked against Qt.application.screens

Loader {
    id: bigCoverLoader
    active: bigCoverPaneOpen
    // engine is set here, NOT as a declarative "engine: engine" binding
    // inside the BigCoverWindow {} block below — see the Q_PROPERTY-WRITE-
    // style gotcha note just below for why that specific form silently binds
    // to null instead of this file's PlaybackEngine.
    onLoaded: { if (item) item.engine = engine }

    sourceComponent: BigCoverWindow {
        Component.onCompleted: {
            if (appConfig.bigCoverPaneConfigured && root.rectIntersectsAnyScreen(...)) {
                x = appConfig.bigCoverPaneX; y = appConfig.bigCoverPaneY
                width = appConfig.bigCoverPaneWidth; height = appConfig.bigCoverPaneHeight
            } else {
                width = 400; height = 400   // centered-on-primary-screen default
                x = Screen.virtualX + (Screen.width - width) / 2
                y = Screen.virtualY + (Screen.height - height) / 2
            }
            visible = true
            raise(); requestActivate()
        }
        onGeometrySettled: (x, y, w, h, screenName) => appConfig.saveBigCoverPaneGeometry(x, y, w, h, screenName)
        onCloseRequested: root.bigCoverPaneOpen = false
    }
}
```

- **The `engine: NULL` gotcha (found and fixed via the on-screen diagnostic described
  above)**: `BigCoverWindow { engine: engine }` was originally written as a normal
  declarative binding, the same way `NowPlaying { engine: engine }` etc. already work
  elsewhere in this file. It silently resolved to `null`. The mechanism: `BigCoverWindow`
  is the **root object of the `Loader`'s inline `Component`** (the value of
  `sourceComponent`), and it declares its own `property var engine: null`
  (`BigCoverWindow.qml`). For a property assignment in that specific position — on a
  Component-root object, where the property name collides with an outer id of the same
  name — QML resolves the unqualified `engine` against the object's own just-declared
  property instead of walking out to `Main.qml`'s `engine` id. This is *not* general
  breakage of outer-scope lookups inside the Component: `appConfig`/`root`/`Screen`,
  referenced in the very same `Component.onCompleted` above, all resolved correctly,
  because none of them collide with a property `BigCoverWindow`/`FloatingPane`
  declares. The fix moves the assignment to `Loader.onLoaded` — a plain signal handler
  on the `Loader` itself (not inside the Component), where `engine` unambiguously
  resolves via this file's normal scope, then writes it onto `item` (`item.engine =
  engine`) explicitly. `onGeometrySettled`/`onCloseRequested` didn't need the same
  fix — `appConfig`/`root`, which they reference, aren't shadowed by anything
  `BigCoverWindow` declares. **Lesson for any future `FloatingPane` subclass**: don't
  set a property via a declarative binding at the point a `Component`'s root object is
  declared if that property's name is also an outer id — set it imperatively via
  `Loader.onLoaded`/`item.<prop> = <value>` instead.
- **Screen validation on restore**: `rectIntersectsAnyScreen()` checks the saved rect
  against every connected screen's geometry (`Qt.application.screens[i].virtualX/Y` +
  `width`/`height`, the same virtual-desktop coordinate space `Window.x/y` use) —
  guards against a monitor having been unplugged or rearranged since the pane was
  last positioned. If it doesn't intersect anything currently connected, the pane
  falls back to a centered default on the primary screen instead of restoring to a
  now-inaccessible position.
- **`raise()`/`requestActivate()` after `visible = true`**: without this, a newly
  created sibling window can render *behind* the main window when it's in exclusive
  fullscreen (`Window.FullScreen`, auto-triggered for exact-match screen
  resolutions — see UC "no notifications while fullscreen" above for the same
  underlying OS behavior affecting a different feature) — found during this
  feature's own verification, not a hypothetical.
- Clicking the cover while the pane is already open is a no-op (the `Loader` is
  already `active`), matching "always visible until right-click closes it."

### `AppConfig` — `bigCoverPane` persistence

Nested JSON object (matching the `crossfade`/`autoPlay` nested-object convention),
not the flat `windowWidth`-style keys — see the Config file format section above.
Key **presence**, not a separate stored flag, means "has been positioned before";
absence means first-ever open. `Q_PROPERTY`s are `READ`-only with a single
`NOTIFY bigCoverPaneChanged`, mutated only via the `Q_INVOKABLE
saveBigCoverPaneGeometry(...)` setter — never `Q_PROPERTY WRITE` (see UC-16's
`SystemVolumeController`-adjacent note on why: a `WRITE`-only function isn't itself
callable as `obj.setX()` from QML unless also `Q_INVOKABLE`, a mistake already made
and fixed once this session).

### Known limitations (not fixed, not requested)

- No default-audio-device-style "what if the window's screen configuration changes
  *while the pane is open*" handling beyond the OS's own window-manager behavior —
  only the *restore-at-open* path is explicitly validated against connected screens.
- Whether the pane reopens automatically on the next app launch was deliberately
  left as "no" — only geometry is persisted, not open/closed state; every launch
  starts with the pane closed until the user clicks the cover again.

## UC-18 Detachable Panes (Tag Information)

| Field | Detail |
|-------|--------|
| **Goal** | User detaches the current track's tag metadata (title, artist, album, genre, year, track, duration, format, bitrate) into its own frameless, movable, freely-resizable window, whose content (fonts/spacing) scales smoothly with the pane's size. |
| **Actor** | User |
| **Precondition** | Topaz is running. |
| **Trigger** | User clicks the "TAG INFORMATION" button in `BottomBar`. |

Second pane built on the `FloatingPane.qml` base introduced for UC-17 — see that
section for the shared chrome (move via `startSystemMove()`, right-click-to-close,
geometry-persistence debounce, `Popup`-vs-`Window` rationale) and the QML
Component-root scoping gotcha, which applies identically here. This section only
covers what's specific to `TagInfoWindow.qml`.

### `PlaybackEngine` — new metadata getters

Four new one-line getters were added, mirroring the existing `currentAlbum()`/
`currentFormat()` pattern exactly (`currentAlbumArtist`, `currentGenre`,
`currentYear`, `currentTrackNumber`; see the `PlaybackEngine` Public API table
above) — all reusing the existing `currentTrackChanged` signal, no new signal
needed. Scope was deliberately kept to metadata Topaz already scans: the mockup
this pane was built from also showed total-track-count ("01 / 22") and sample
rate/bit depth ("24-bit/96kHz"), both skipped since neither exists anywhere in
`TrackInfo` today — adding them would mean scanner/`TagReader`/cache-schema changes,
a separate, larger piece of work than this pane itself.

While wiring `currentYear`, a real (if minor) gap was found and fixed: `TrackInfo::year`
was always populated by the scanner but never threaded through the `QVariantMap`s used
to queue a track — see the `year` field threading note in the `PlaybackEngine` Public
API section above.

### `TagInfoWindow.qml`

A `FloatingPane` specialization with **no `fixedAspectRatio`** (unlike the square
`BigCoverWindow`) — free resize via `startSystemResize()`, default size 500×230, and
a floor of `minPaneWidth: 500` / `minPaneHeight: 200` (set directly on the
`FloatingPane` instance — its `minPaneWidth`/`minPaneHeight` properties already
existed generically, wired to the underlying `Window.minimumWidth`/`minimumHeight`,
so Qt enforces the floor natively during interactive resize; `TagInfoWindow.qml`
just hadn't overridden them from `FloatingPane`'s own `120`×`120` default until now).
Went through several rounds of shrinking the default and tightening internal
padding/spacing/the specs-box height: 460×420 (original) → 460×280 → 460×230 →
500×230 (current; width bumped to 500 to stay above the new minimum), since content
sitting in a top-anchored `Column` with no explicit height never grows to fill the
pane — any extra height just shows through as empty themed background. **The pane's
*saved* geometry (`Topaz.config`'s `tagInfoPane` entry) always wins over this default
once the user has resized the pane even once** — confirmed directly from a real
user's config (a genuine 1658×592 saved size on real hardware) — so shrinking the
default only affects a pane that's never been touched; an already-resized pane needs
a manual resize-down to benefit from a tighter default.

The technical-specs box (Track/Duration/Bitrate) is anchored directly to the pane's
own `left`/`right`/`bottom` edges (all with the same margin `body`'s own padding
uses) rather than being the last child of `body`'s `Column`. It used to flow inside
that `Column`, whose height is purely intrinsic — so whenever the pane was taller
than the content needed, all the leftover space collected asymmetrically below the
specs box while the side margins stayed fixed. Anchoring it independently guarantees
its bottom margin always equals the side margins exactly, at any pane size; leftover
vertical space now becomes a harmless gap between the metadata grid and the specs
box instead.

**Content scales with pane size**: a single computed property,
```qml
readonly property real scaleFactor:
    Math.max(0.55, Math.min(width / 500, height / 230))
```
multiplies every `font.pixelSize` and layout padding/spacing value in the pane. It's
derived from *both* width and height (via `Math.min`) so a pane resized narrow-but-tall
or short-but-wide doesn't overflow in the constrained dimension; floored at `0.55` so
text never becomes unreadably tiny when shrunk down. Deliberately has **no upper
cap** — an earlier `2.2` ceiling was removed at the user's request, since the pane is
meant to work as a large, readable "signage" display too (same rationale
`BigCoverWindow`/UC-17 already has for a second-monitor "now playing" display) and a
fixed ceiling just reproduces the "content stops growing, empty space grows around
it" problem the pane's default-size tuning already fixed once, from the opposite
direction.

Layout, adapted from a user-supplied mockup (`code.html`/`DESIGN.md`) but built with
this codebase's own `Theme.*` tokens rather than the mockup's hardcoded hex/Tailwind
values: a thin header strip ("ⓘ TAG INFORMATION"), a title row (large uppercase title
+ a format-badge pill reusing `NowPlaying`'s visual, `engine.currentFormat`), an
artist subtitle (same expression `NowPlaying.qml` uses), a divider, a 2-column
metadata grid (Album / Album Artist / Genre / Year — each field elides long values
with a `ToolTip` showing the full string on hover), and a bordered technical-specs
box (Track / Duration / Bitrate, 3 columns with 1px vertical dividers). Two small
inline QML `component`s (`MetadataField`, `SpecField`, Qt 6.4+ syntax) factor out the
repeated label-over-value markup without needing separate files/module registration.
Placeholder state (no track loaded) reuses the same gradient+glyph idiom as
`BigCoverWindow.qml`'s placeholder.

### Double-click to maximize width / restore

Double-clicking anywhere on the pane horizontally centers it and widens it to fill
the current screen; a second double-click restores the exact size/position from
before. Implemented via `FloatingPane`'s generic `doubleClicked()` signal (see
UC-17) — `TagInfoWindow.qml` itself does no input handling, just an
`onDoubleClicked` handler:
```qml
property bool _maximized: false
property real _restoreX: 0
property real _restoreY: 0
property real _restoreWidth: 0
property real _restoreHeight: 0

onDoubleClicked: {
    if (!_maximized) {
        _restoreX = x; _restoreY = y; _restoreWidth = width; _restoreHeight = height
        width = Screen.width
        x = Screen.virtualX
        _maximized = true
    } else {
        x = _restoreX; y = _restoreY; width = _restoreWidth; height = _restoreHeight
        _maximized = false
    }
}
```
Only `x`/`width` change on maximize — `y`/`height` are deliberately left alone,
matching the request (horizontally center + widen to fit the screen; nothing said
about vertical size/position). Restoring sets all four back regardless, which is a
no-op for `y`/`height` since maximize never touched them. Uses the bare `Screen`
attached property (`import QtQuick.Window`, added to this file for exactly this) —
the same `Screen.virtualX + (Screen.width - width) / 2`-style idiom `Main.qml`
already uses to center this pane on first-ever-open, here resolving to whichever
screen the pane is currently on. No special-casing needed for persistence: the
existing debounced `geometrySettled` in `FloatingPane.qml` fires on these
programmatic changes exactly like a manual drag/resize, so a pane closed while
maximized reopens maximized next time — consistent with saved geometry always
winning over the default (see "saved geometry always wins" note above).

### `BottomBar.qml` — TAG INFORMATION toggle wiring

The "TAG INFORMATION" button already existed in `BottomBar`'s button model (icon `ⓘ`)
but was previously a no-op. Two toggle-button idioms already existed in this file
before this change — AUTO PLAY (Main.qml owns a full controller object with gating
logic; the button reads `autoPlay.active` and calls `autoPlay.toggle()`) and SCAN
DIRECTORIES (Main.qml owns a plain bool; the button just emits `scanRequested()` and
reflects the externally-bound `scanning` property back). TAG INFORMATION follows the
**SCAN DIRECTORIES** idiom — there's no gating logic here, just open/closed — via a
new `signal tagInfoToggleRequested()` and `property bool tagInfoPaneOpen` (bound from
`Main.qml`), with the button's color reading `tagInfoPaneOpen` the same way the
generic `modelData.active` path already did.

### `Main.qml` wiring

Exact structural mirror of the `bigCoverLoader` block from UC-17 (`tagInfoLoader` /
`tagInfoPaneOpen` / `TagInfoWindow` in place of `bigCoverLoader` / `bigCoverPaneOpen`
/ `BigCoverWindow`), including the same `Loader.onLoaded: { item.engine = engine }`
pattern (required for the same Component-root scoping reason as UC-17), the same
`rectIntersectsAnyScreen()` reuse for geometry restore/validation, and the same
`raise()`/`requestActivate()` after `visible = true`. Default size on first-ever-open
(no saved geometry yet) is 500×230, centered on the primary screen.

### `AppConfig` — `tagInfoPane` persistence

Exact mirror of the `bigCoverPane` persistence block from UC-17 — nested JSON object,
key *presence* (not a stored bool) means "configured," `Q_PROPERTY`s are `READ`-only
with a single `NOTIFY tagInfoPaneChanged`, mutated only via `Q_INVOKABLE
saveTagInfoPaneGeometry(...)`. See the `AppConfig` public API table and Config file
format section above.

### Known limitations (not fixed, not requested)

Same as UC-17's: no live handling of screen-configuration changes while the pane is
open (only restore-at-open is validated against connected screens), and open/closed
state is not persisted across app restarts — every launch starts with the pane
closed.

## UC-19 Audio Visualizer (Bars)

| Field | Detail |
|-------|--------|
| **Goal** | User opens a detachable pane showing real-time bumping bars driven by the currently playing track's audio spectrum. |
| **Actor** | User |
| **Precondition** | Topaz is running. |
| **Trigger** | User clicks the "AUDIO VISUALIZER" button in `BottomBar`. |

Third pane built on the `FloatingPane.qml` base introduced for UC-17 — see that
section for the shared chrome and UC-18 for the toggle-button wiring pattern this
one mirrors exactly. This section covers what's specific to the visualizer: the
first third-party dependency this codebase has taken on, the audio-tap mechanism,
and the FFT/rendering pipeline.

### KissFFT — first third-party dependency

Everything in Topaz before this was hand-rolled specifically to stay
dependency-free (`TagReader`'s "dependency-free ID3v2/FLAC/Vorbis reader" being the
clearest example). A bar visualizer needs a real FFT, and hand-rolling one wasn't
worth it against a tiny, permissively-licensed, purpose-fit library — so this is a
deliberate, scoped exception, not a change in philosophy.

Two candidates were evaluated: **FFTW** (the speed benchmark for scientific/HPC FFT
workloads) is GPL-licensed — using the open-source build would require Topaz itself
to be GPL, or a paid commercial license from MIT; also far more machinery than a
16-64-bar visualizer's FFT workload needs. **KissFFT** (BSD-3-Clause, ~500 lines of
C for the core transform, real-FFT variant built in, runtime-configurable size) has
no such licensing entanglement and is trivially small — chosen for both reasons.

Vendored under `third_party/kissfft/` (first use of a `third_party/` layout in this
repo — everything else sits flat at the root; vendored foreign code is kept visibly
separate from Topaz's own sources): `kiss_fft.h/.c`, `kiss_fft_log.h`,
`_kiss_fft_guts.h`, `kiss_fftr.h/.c` (the real-FFT wrapper, the actual entry point
used — audio samples are real-valued, not complex; `kiss_fft.c` is its dependency).
Unmodified upstream sources, compiled as plain C (`project(... LANGUAGES CXX C RC)`
in `CMakeLists.txt` — the rest of the codebase is C++, so C had to be explicitly
enabled as a project language for these files to compile at all).

### `PlaybackEngine` — audio tap

Getting live PCM samples out of `QMediaPlayer` requires Qt 6.8+'s
`QAudioBufferOutput` API, which **only works with Qt Multimedia's FFmpeg backend**.
Confirmed present and default on the reference Qt 6.10.2 mingw_64 toolchain before
writing any code (`plugins/multimedia/ffmpegmediaplugin.dll` and `bin/avcodec-61.dll`
both exist; nothing in the codebase overrides `QT_MEDIA_BACKEND`) — this was the one
real feasibility risk in the whole feature, checked and cleared up front rather than
discovered mid-implementation.

`PlaybackEngine` runs two independent `QMediaPlayer`/`QAudioOutput` decks for
crossfading (see UC-15). A parallel `QAudioBufferOutput m_audioBufferOutputs[2]`
array is constructed inside the same per-deck loop that builds `m_players`/
`m_audioOutputs`, via `m_players[d]->setAudioBufferOutput(m_audioBufferOutputs[d])`
— independent of `setAudioOutput()`, doesn't touch normal playback in any way. Each
deck's `audioBufferReceived` signal is connected to a `[this, d]` lambda that emits
a new signal, `void audioBufferAvailable(const QAudioBuffer &buffer)`, **only when
`d == m_activeDeck`** (see the `PlaybackEngine` Public API section above for the
signal's own doc comment).

**Known limitation — crossfade simplification**: outside a crossfade, `m_activeDeck`
always matches the one deck that's actually audible, so this is exact. *During* a
crossfade, both decks are genuinely audible simultaneously for the whole fade
duration (complementary volumes, linearly ramped every 40ms tick — see
`onFadeTick()` in UC-15), and `m_activeDeck` doesn't flip to the incoming deck until
the fade's *midpoint*. The visualizer therefore silently ignores the fading-out
deck's contribution for the back half of every crossfade (and the fading-in deck for
the front half) — a real but minor, purely cosmetic gap. Accurate crossfade mixing
would mean weighting both decks' buffers by the fade fraction (not currently stored
as a member, only local to `onFadeTick()`) — a reasonable future enhancement, not
part of this first version, which was scoped to "a simple audio visualizer to see
how this works out."

### `AudioVisualizerController` — FFT pipeline

`QObject` + `QML_ELEMENT`, modeled on `AutoPlayController`'s shape: depends on
`PlaybackEngine` + `AppConfig`, neither of which knows this class exists (same
"controller subscribes to the engine's signals" split). `setEngine()` connects to
`audioBufferAvailable`; bar/decay/color settings are read live from `AppConfig` on
every processed block, never cached — same convention `PlaybackEngine` already uses
for crossfade settings.

Per-buffer pipeline (`onAudioBufferAvailable` → `appendSamples` → `processBlock`):
1. **Extract mono samples**: averages channels from the buffer's interleaved PCM.
   Only `QAudioFormat::Float` and `QAudioFormat::Int16` are handled (the two formats
   actually produced by the FFmpeg backend in practice) — anything else is silently
   skipped. A deliberate simplification, not a generic-format converter.
2. **Accumulate** into a rolling sample buffer; once `kFftSize` (1024) samples are
   available, consume exactly that many and repeat for any remainder — a plain
   non-overlapping block FFT, no overlap-add window sliding (unnecessary precision
   for a bar visualizer).
3. **Hann window** the block (reduces spectral leakage from analyzing a finite,
   non-periodic slice of audio) — standard practice for spectrum analysis.
4. **`kiss_fftr`** (real FFT) → `kFftSize/2+1` complex frequency bins.
5. **Log-spaced band grouping**: bins are averaged into `barCount` bands spaced
   logarithmically from 40Hz to `min(nyquist, 16kHz)` — matches how the spectrum is
   perceived (a linear bin→bar mapping would crush the entire low end into a
   handful of bars while treble smears across dozens).
6. **dB-scale + clamp** each band into `[0,1]` (empirically-chosen -60dB/0dB
   floor/ceiling, not exposed directly), after first adding a gain offset
   (`gainDb`) derived from `appConfig.audioVisualizerSensitivity` — `0.5`
   (default) contributes `0dB` (no change from the original mapping); the
   ±18dB range (`kMaxSensitivityBoostDb`) shifts where a given signal lands
   within the fixed floor/ceiling rather than moving the floor/ceiling
   themselves, since how much headroom typical music leaves below 0dBFS
   varies a lot by mastering.
7. **Decay**: `displayed = max(newLevel, previous - decayRate)`, where `decayRate`
   derives from `appConfig.audioVisualizerDecaySpeed` — bars fall smoothly instead
   of jittering every block. The single biggest factor in how "alive" the
   visualizer feels.
8. **Peak-hold**: a second, much-more-slowly-decaying value per bar, snapping up
   instantly to new highs.

Buffer arrival happens on the FFmpeg decode thread; the `connect()` between
`PlaybackEngine` (that thread) and `AudioVisualizerController` (main thread) uses
ordinary `Qt::AutoConnection`, which already queues delivery onto the receiver's
thread automatically — no manual `QMetaObject::invokeMethod` marshaling needed here,
unlike `SystemVolumeController`'s COM-callback case (UC-16), because this is a
regular Qt signal/slot connection, not a foreign (non-Qt) callback.

`barLevels`/`peakLevels` (`Q_PROPERTY QVariantList`, shared `NOTIFY
barLevelsChanged`) are **not** updated on every processed block — an internal
`QTimer` at ~30fps (33ms) publishes whatever's accumulated since the last tick,
decoupled from the raw block-processing rate (which can be considerably higher-
frequency than useful for a UI update).

### `AudioVisualizerWindow.qml`

A `FloatingPane` specialization with **no `fixedAspectRatio`** (freely resizable,
like `TagInfoWindow`) and a `minPaneWidth: 400` / `minPaneHeight: 200` floor. Purely
a renderer — all analysis lives in the C++ controller. A `Row` of bar `Item`s, one
per entry in `barModel` (`visualizer.barLevels`); each bar is a bottom-anchored
`Rectangle` whose height is `parent.height * level`, plus a thin peak-hold
`Rectangle` positioned via `anchors.bottomMargin: parent.height * peak` when
`visualizerConfig.audioVisualizerPeakHoldEnabled`. Color comes from
`visualizerConfig.audioVisualizerColor` (falls back to `Theme.primary` if unset).

**Repeater model is a plain integer (bar count), not the level array itself** — a
deliberate performance choice. The level array is reassigned wholesale ~30 times a
second; if that array were bound directly as `Repeater.model`, Qt Quick would treat
every reassignment as an entirely new list and recreate every delegate each tick.
Binding `model: barsRow.barCount` (a stable integer that only changes when the user
changes the bar-count setting) means delegates are created once; only their
`height`/`anchors.bottomMargin` bindings — which read `barModel[index]` reactively —
recompute each tick, which is far cheaper.

Same placeholder idiom as `BigCoverWindow`/`TagInfoWindow` (gradient + "♫ NO TRACK")
when `!engine.currentTitle`. `property var visualizer`/`engine`/`visualizerConfig`
are all set via `Main.qml`'s `Loader.onLoaded` — the same Component-root
scoping-gotcha fix applied to every pane in this family (see UC-17's `Main.qml
wiring` section). This is the first pane to also need `AppConfig` directly (for
visual settings, not playback data) — `BigCoverWindow`/`TagInfoWindow` never needed it.

**Background-only pane opacity** (`visualizerConfig.audioVisualizerPaneOpacity`,
0.0–1.0): applied to the pane's own `color` (a `Window.color` with an alpha channel
below full makes only that window's clear/background translucent — see
`WindowChrome` in UC-17 for the native prerequisite this actually needs on Windows)
**and** to the no-track placeholder's gradient — both count as "the pane's
background" for this setting. Deliberately **not** `Window.opacity` — that fades
the entire window including its content, which would make the bars translucent
too. Every bar/peak-tick `Rectangle` keeps its own fully-opaque `color` binding
untouched, so they stay crisp at any background opacity, letting the user drop the
pane anywhere (over the desktop, another window, etc.) with just the bars visible
and no panel behind them.

Two rounds were needed to get this fully invisible at 0%:
```qml
color: Qt.rgba(Theme.surfaceContainerLowest.r * paneOpacity,
               Theme.surfaceContainerLowest.g * paneOpacity,
               Theme.surfaceContainerLowest.b * paneOpacity,
               paneOpacity)
```
- **The window's own clear color premultiplies RGB by `paneOpacity`, not just the
  alpha channel.** DWM/Direct3D composition on Windows expects a
  premultiplied-alpha convention for a composited window's clear color — at true
  zero opacity the RGB channels must also be zero, or a compositor assuming
  premultiplied input can render a faint residual tint instead of true
  invisibility. This treatment is specific to the *window's own* clear color;
  ordinary in-scene `Rectangle`s (including the placeholder below) are handled by
  Qt Quick's own scenegraph alpha blending and don't need it — a plain
  `Qt.rgba(r, g, b, paneOpacity)` (alpha only) is correct for those.
- **The no-track placeholder's gradient was initially left hardcoded fully
  opaque** (a deliberate scope decision when the setting was first built) — wrong
  in practice, since the pane is easily open with nothing playing (right after
  launch, between tracks), and in that state the opacity slider had *no visible
  effect at all*. Fixed by scaling both `GradientStop` colors' alpha by
  `paneOpacity` the same way the bars background is.

**Foreground-only bar opacity** (`visualizerConfig.audioVisualizerBarOpacity`,
0.0–1.0, independent of the background setting above): a plain `opacity:`
binding on `barsRow` — the `Row` containing every level-bar and peak-tick
`Rectangle` — so the whole foreground fades or stays crisp as one unit,
mirroring how the background setting treats the pane's `color` and placeholder
gradient as one unit. Unlike the pane background, this needs **no** premultiply
treatment: `barsRow` is an ordinary in-scene `Item`, not a `Window`'s own clear
color, so Qt Quick's scenegraph alpha blending already composites it correctly
at any opacity, including 0%.

**A stricter variant of the scoping gotcha, found and fixed after the pane shipped
not opening at all**: this pane's own config property is named `visualizerConfig`,
*not* `appConfig`, deliberately. It was originally named `appConfig` (matching the
outer `id: appConfig` in `Main.qml`, the obvious name) — but `Main.qml`'s
`Component.onCompleted` for this pane (the geometry-restore block, same shape as
`BigCoverWindow`/`TagInfoWindow`'s) reads the bare identifier `appConfig` too, to
check `appConfig.audioVisualizerPaneConfigured` and restore saved geometry. Both
that `Component.onCompleted` code and the pane's own property live in the *same
object's scope* — so once the pane declared a same-named property, ordinary QML
scoping made every unqualified `appConfig` reference anywhere in that object
(not just one declarative-binding position, unlike the original `BigCoverWindow`
`engine` bug) resolve to the pane's *own*, not-yet-set `null` property instead of
the outer `AppConfig` instance. `Component.onCompleted` runs before
`Loader.onLoaded` gets a chance to assign the property, so `appConfig` read `null`
there, `appConfig.audioVisualizerPaneConfigured` threw, and the handler silently
aborted **before ever reaching `visible = true`** — the pane object was created but
never shown, moved, or raised. Symptom: clicking the button did nothing visible.
Unlike the `engine`-collision case (still present here too, but dormant — this
pane's own `Component.onCompleted` never reads `engine`), this collision was live
because the geometry-restore logic genuinely needs to read the shadowed name. Fix:
rename the pane's own property so it can never collide with any `Main.qml` outer id,
rather than trying to special-case the read (there's no way to make
`Component.onCompleted` run after `onLoaded`). **Lesson for any future
`FloatingPane` subclass**: never name a pane-local property identically to a
`Main.qml` outer id if any code inside that pane's own scope — including
`Component.onCompleted` — needs to read the *outer* value; rename the local
property instead of trying to work around the shadowing.

### `BottomBar.qml` / `Main.qml` wiring

Identical pattern to UC-18's TAG INFORMATION wiring — the "AUDIO VISUALIZER" button
already existed in `BottomBar`'s model array (confirmed still a pure placeholder,
same starting state TAG INFORMATION was in) but had no `isXBtn` flag, signal, or
`onClicked` branch until now. `signal audioVisualizerToggleRequested()` +
`property bool audioVisualizerPaneOpen` (bound from `Main.qml`), `Main.qml`'s
`audioVisualizerLoader` is a structural mirror of `tagInfoLoader` (default
size 500×260 on first-ever-open), and `AudioVisualizerController` is instantiated
once in `Main.qml` alongside `AutoPlayController`/`SystemVolumeController`.

### `AppConfig` — settings + pane geometry persistence

Two separate nested JSON objects, matching how pane geometry is already kept
separate from feature settings elsewhere (`bigCoverPane` vs. nothing analogous,
`tagInfoPane` vs. nothing analogous — this is the first pane with *both* kinds):
- `"audioVisualizer"`: `barCount`/`color`/`decaySpeed`/`peakHoldEnabled`, each a
  normal scalar `Q_PROPERTY` + dedicated `Q_INVOKABLE` setter — the
  `autoPlayQueueHorizon`/`setAutoPlayQueueHorizon` convention, not the
  single-geometry-setter one.
- `"audioVisualizerPane"`: exact mirror of `tagInfoPane`'s geometry block.

See the `AppConfig` public API table and Config file format section above for the
full property list and JSON shape.

### `SetupDialog.qml` — "AUDIO VISUALIZER" tab

Fifth tab, appended to the existing tab-strip `Repeater`'s model array. Styled
identically to the CROSSFADE/AUTO PLAY tabs it was built from: custom-styled
`Slider`s (4px track / 16px handle, `Theme.secondary` accent) for bar count
(8-64), decay speed (0.0-1.0), sensitivity (0-100%, displayed as a percentage,
divided by 100 when calling `setAudioVisualizerSensitivity`; 50% is "no
change" from the original fixed dB mapping — see the `AudioVisualizerController`
pipeline above), pane opacity (0-100%, displayed as a percentage,
divided by 100 when calling `setAudioVisualizerPaneOpacity`), and bar opacity
(0-100%, same percentage convention, calling `setAudioVisualizerBarOpacity` —
an identical slider block placed directly below pane opacity, independent
setting for the bars/peak ticks themselves), the same hand-rolled
48×24 toggle track for peak-hold, and — for color — a fixed 16-column `Grid`
(not `Row`; 32 swatches at 32px + 16px spacing no longer fit on one line at the
dialog's content width, so `columns: 16` lays them out as two full rows of 16
regardless of available width) of 32 preset swatch `Rectangle`s using the same
"`Repeater` over an options array compared against one `AppConfig` value" idiom
already used for `autoPlaySongRepeat`/`autoPlayTransportAccess`'s radio groups,
just rendered as color chips instead of labeled circles. The 32 presets are the
original 8 (4 of which already match Theme tokens — `Theme.secondary`,
`Theme.primary`, `Theme.tertiary`, `Theme.fgSurface`) plus 24 additional
saturated colors spread across the hue wheel, appended in a fixed order so
existing selections stay stable. A full HSV/RGB color picker was deliberately
not built for this first version — presets are simpler and consistent with
starting small; a real picker is a reasonable later enhancement.

### Known limitations (not fixed, not requested)

- Crossfade audio mixing simplification — see the `PlaybackEngine` section above.
- Only `Float`/`Int16` sample formats are handled; other formats are silently
  skipped (no visible error, bars just stay flat).
- dB floor/ceiling for level normalization (-60dB/0dB) are hardcoded constants,
  not exposed as settings — only a ±18dB gain offset around them is, via the
  Sensitivity setting.
- Same as UC-17/UC-18: no live handling of screen-configuration changes while the
  pane is open, and open/closed state is not persisted across app restarts.

## UC-20 Milkdrop Audio Visualizer

| Field | Detail |
|-------|--------|
| **Goal** | User opens a detachable pane showing a real-time Milkdrop-compatible preset visualization, driven by the currently playing track's audio. |
| **Actor** | User |
| **Precondition** | Topaz is running. |
| **Trigger** | User clicks the "MILKDROP" button in `BottomBar`. |

Fourth pane built on the `FloatingPane.qml` base introduced for UC-17 — see that
section for the shared chrome and UC-18/UC-19 for the toggle-button wiring pattern
this one mirrors. No double-click behavior yet (deliberately deferred, same as
UC-19's first round) — this section covers what's specific to Milkdrop: the second
third-party dependency this codebase has taken on, why it can't render directly
into Quick's own scenegraph, and the offscreen-render architecture that works
around that.

### `projectM` — second third-party dependency

[projectM](https://github.com/projectM-visualizer/projectm) is the standard
open-source, cross-platform re-implementation of Winamp's Milkdrop visualizer —
LGPL-2.1+, actively maintained, pinned to release tag `v4.1.7`. Unlike KissFFT
(UC-19, ~500 lines vendored directly into the repo), projectM is a full C++
library pulled in via CMake `FetchContent` (`FetchContent_Declare(projectm
GIT_REPOSITORY ... GIT_TAG v4.1.7)` in `CMakeLists.txt`) and built alongside
Topaz rather than vendored — first use of `FetchContent` in this codebase.
Built as a **shared library** (`BUILD_SHARED_LIBS` defaults `ON` in projectM's
own CMakeLists, matching the LGPL requirement to keep it swappable/relinkable
rather than statically baked into `Topaz.exe`). Produces
`libprojectM-4d.dll`/`libprojectM-4-playlistd.dll` (its separate playlist-
management library, `ENABLE_PLAYLIST` default `ON`), which land next to
`Topaz.exe` because `CMAKE_RUNTIME_OUTPUT_DIRECTORY` is inherited from Topaz's
own `qt_standard_project_setup()` — no manual deploy step needed.

**Windows-only build wrinkle — GLEW**: projectM's Windows "OpenGL Core Profile"
path (OpenGL ES is Linux/Android-only in their CMakeLists) requires
`find_package(GLEW REQUIRED)`, which isn't part of the Qt/MinGW toolchain.
GLEW's own git repository doesn't check in its generated `src/glew.c`/
`include/GL/glew.h` (release-archive-only), so `CMakeLists.txt` fetches the
official `glew-2.2.0.zip` release archive instead of the git repo, pointing
`FetchContent_Declare`'s `SOURCE_SUBDIR` at GLEW's bundled `build/cmake`
support directory, with `OVERRIDE_FIND_PACKAGE` so projectM's `find_package(GLEW)`
transparently resolves to this fetched copy. Three follow-up fixes were needed
because GLEW's raw CMakeLists.txt predates modern target-based CMake
conventions: (1) it only defines plain `glew`/`glew_s` targets, not the
namespaced `GLEW::glew` target projectM's CMakeLists checks for — added via
`add_library(GLEW::glew ALIAS glew)`; (2) it sets its include directory via
the old directory-scoped `include_directories()`, which doesn't propagate to
targets linking against it from other directories (like projectM's
`MilkdropPreset`) — fixed with an explicit
`target_include_directories(glew INTERFACE $<BUILD_INTERFACE:...>)`; (3) it
unconditionally redirects its own DLL output to `<build>/bin`, separate from
where `Topaz.exe` and the projectM DLLs land — fixed by overriding
`RUNTIME_OUTPUT_DIRECTORY` back to the build root after the target is created.

**A fourth, unrelated build fix was needed**: projectM's generated
`version.h` reads `CMAKE_PROJECT_VERSION_PATCH` (the *top-level* project's
version — Topaz, once projectM is `FetchContent`'d as a subdirectory), and
Topaz's own `project(Topaz VERSION 0.1 ...)` only declared a major.minor
version, leaving the patch component unset/empty and breaking that
substitution (`*patch = ;` — a compile error, not a configure-time one).
Fixed by giving Topaz's own project version a full `0.1.0`.

### The core architecture problem — why not render directly into Quick's scenegraph

Qt6 Quick's graphics backend (`QQuickWindow::setGraphicsApi()`) is a
**process-global** choice made once before any window is created — Topaz's
existing `FloatingPane` windows rely on the default Direct3D11 RHI backend on
Windows (established during UC-17/UC-18's `WindowChrome` translucency work).
projectM's renderer issues **raw OpenGL calls** and needs its own current
OpenGL context to render — it cannot be mixed directly into a D3D11-backed
`QQuickWindow`'s scenegraph the way pre-Qt6 apps used to embed raw GL via
`beforeRendering()` hooks.

Two options were considered: force the *entire app* onto the OpenGL RHI
backend (faster, direct scenegraph integration, but re-opens the exact
translucency/DWM-border problem that took three debugging rounds to fix under
D3D11 for the `AudioVisualizerWindow` opacity feature, for every existing
pane, with no guarantee OpenGL behaves the same way); or give projectM a
fully independent, invisible OpenGL context and bring its output into Quick as
an ordinary texture. The second was chosen — zero risk to the D3D11
translucency work already shipped, at the cost of a GPU→CPU→GPU round-trip
per frame (kept cheap via a modest resolution/fps, see below).

### `MilkdropView` — combined controller + render surface

Unlike `AudioVisualizerController` (a non-visual `QObject` controller feeding
small numeric arrays to separate QML-drawn bars, instantiated once in
`Main.qml` and kept alive for the whole app), `MilkdropView` is a `QQuickItem`
subclass that *is* the render surface, instantiated directly inside
`MilkdropWindow.qml` — its render window must match its own pixel size, so
controller and view are combined here, and its lifetime is deliberately tied
to the pane's own `Loader` (created on open, destroyed on close), not kept
alive for the whole app, since it owns real GPU/native resources (a
never-shown `QWindow` + `QOpenGLContext`, the projectM instance).

**Why a real (if never-shown) `QWindow`, not `QOffscreenSurface`**: the
first working version used `QOffscreenSurface` with a custom
`QOpenGLFramebufferObject` as the render target — the intuitive choice for
"invisible offscreen rendering." It silently produced nothing but
transparent-black frames. Reading projectM's actual `ProjectM.cpp` source
(v4.1.7, the pinned tag) explained why:
```cpp
m_activePreset->RenderFrame(audioData, renderContext);

// ToDo: Allow external apps to provide a custom target framebuffer.
glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
glViewport(0, 0, renderContext.viewportSizeX, renderContext.viewportSizeY);
```
`projectm_opengl_render_frame()` (the only render entry point available in
v4.1.7 — the FBO-targeted variant was added in 4.2.0, unreleased at the time
of writing) **unconditionally rebinds framebuffer 0** at the end of its own
render pass, regardless of what was bound beforehand — a custom FBO bound
before calling it never receives the real output, which is exactly what the
`toImage()` readback kept confirming (always the FBO's untouched cleared
state). Switching to rendering straight into framebuffer 0 fixes this, but
`QOffscreenSurface` isn't a valid target for that either — Qt's own docs
state its framebuffer's pixels are "not accessible," it's documented for
resource creation only (textures, FBOs), not direct readback. A real
`QWindow` (`setSurfaceType(QWindow::OpenGLSurface)`, `create()`'d but never
`show()`n) has a genuine, readable default framebuffer, exactly like
projectM's own SDL2 reference frontend (which renders into a real, if
possibly minimized, window) — visibility and "has a real renderable native
surface" are independent properties in Qt.

Pipeline:
1. **Lazy init** (`ensureInitialized()`, called from both `itemChange` on
   first attach to a window and `geometryChange`, idempotent): creates the
   never-shown `QWindow` + an independent `QOpenGLContext` (OpenGL 3.3 core
   profile), makes it current, then calls **`glewInit()`** before touching
   projectM at all. This step is easy to miss and caused a real crash the
   first time this pane shipped: libprojectM's renderer resolves every
   extended OpenGL call (FBOs, shaders, textures — see `projectM-opengl.h`,
   which `#include <GL/glew.h>` on Windows) through GLEW's global
   function-pointer table, but never calls `glewInit()` itself — confirmed by
   checking projectM's own reference frontends: the Qt one
   (`frontend-qt`, itself only partly maintained upstream) doesn't call it
   either, but the actively-maintained, Windows-CI-tested SDL2 frontend
   (`frontend-sdl-cpp/src/SDLRenderingWindow.cpp`) does, explicitly, right
   after creating its GL context — confirming it's the embedding
   application's responsibility. Skipping it means the very first extended GL
   call inside projectM's renderer jumps through an uninitialized null
   pointer — an unconditional crash on first render, regardless of presets
   (`glewExperimental = GL_TRUE` is also set first, a known GLEW
   requirement for reliable core-profile detection). Only once `glewInit()`
   succeeds does this step call `projectm_create()` (requires an
   already-current GL context) and `projectm_playlist_create()`.
2. **Surface sizing** (`resizeSurface()`): resizes the render `QWindow`
   itself to the item's pixel size × `devicePixelRatio` (no custom FBO to
   recreate); `projectm_set_window_size()` kept in sync — projectM's own
   `RenderFrame()` sets `glViewport` from that value itself (see the source
   excerpt above), so nothing else needs to touch the viewport manually.
3. **Audio feed** (`onAudioBufferAvailable`): subscribes to the *same*
   `PlaybackEngine::audioBufferAvailable` signal `AudioVisualizerController`
   already uses (UC-19) — `PlaybackEngine` doesn't know or care how many
   listeners it has. Sample extraction (mono downmix, `Float`/`Int16` only)
   directly reuses `AudioVisualizerController::appendSamples`'s pattern, but
   feeds `projectm_pcm_add_float()` instead of running an FFT — projectM does
   its own internal spectral/beat analysis.
4. **Render tick** (`onRenderTick`, ~30fps `QTimer` — half the bars
   visualizer's implicit ~60fps ceiling, since this path costs a full
   readback+upload rather than a plain `QVariantList` publish): makes the
   render context current, applies live `AppConfig` settings (read every
   tick, never cached — same convention `PlaybackEngine`/
   `AudioVisualizerController` already use), rescans the preset playlist only
   if the configured folder list actually changed (real filesystem I/O,
   unlike the cheap parameter setters). **Populating the playlist alone
   doesn't display anything** — `projectm_playlist_add_path()` only makes
   presets available, it doesn't load or activate one. Confirmed by checking
   projectM's own SDL2 reference frontend (`ProjectMWrapper.cpp`), which has
   a dedicated `DisplayInitialPreset()` step for exactly this; `rebuildPresetList()`
   mirrors it — once the (non-empty) playlist is rebuilt, it calls
   `projectm_playlist_play_next()` (shuffle on) or `projectm_playlist_set_position(0, ...)`
   (shuffle off) to actually kick off display. Worth remembering if
   preset-navigation controls (skip forward/back) are added later — they'd
   reuse these same `play_next`/`play_previous` calls. Every tick then calls
   `projectm_opengl_render_frame()` directly (no FBO to bind — it renders
   straight into the render `QWindow`'s own framebuffer 0, per the finding
   above) and reads the result back manually: `glReadPixels()` into a
   `QImage(Format_RGBA8888)` sized to `m_renderSize`, then
   `QImage::flipped(Qt::Vertical)` (OpenGL's origin is bottom-left, QImage's
   is top-left — `QOpenGLFramebufferObject::toImage()` used to handle this
   automatically when a custom FBO was still in the picture; done manually
   now) becomes the latest frame; `update()` schedules a scenegraph repaint.
5. **`updatePaintNode()`**: uploads the latest `QImage` as a
   `QSGTexture` (`window()->createTextureFromImage()`) into a
   `QSGSimpleTextureNode` — Quick's own D3D11 backend only ever sees an
   ordinary texture upload, never a raw GL call.

No presets are bundled with Topaz — the de facto standard pack
(`presets-cream-of-the-crop`, ~10K community-authored `.milk` files) is a
separate, large, mixed-per-author-licensed repository, not appropriate to
vendor. Instead, the "Preset Folders" list in the Setup dialog (see below)
lets the user point at a preset pack they've downloaded themselves —
documented behavior, not a gap: the pane will render nothing until at least
one folder with `.milk` files is configured. Since `projectm_playlist_add_path()`
scans recursively, it doesn't matter whether the configured folder is the
pack's root or its `Presets` subfolder directly — both find the same `.milk`
files. `rebuildPresetList()` additionally probes for a sibling `Textures` (or
`textures`) folder next to each configured folder and, if found, registers it
via `projectm_set_texture_search_paths()` — the common pack layout is
`Presets/` + `Textures/` side by side, and presets referencing custom
textures render broken without this.

### `MilkdropWindow.qml`

Structurally mirrors `AudioVisualizerWindow.qml` minus the opacity feature
(not requested for this pane). Explicitly sets `color: Theme.surfaceContainerLowest` on the root
`FloatingPane` — `Window.color` defaults to **white** in Qt Quick when never
set, and `FloatingPane.qml` itself doesn't set a default either; every
sibling pane sets this explicitly (`BigCoverWindow.qml`/`TagInfoWindow.qml`),
and this one shipped without it for a round, which was invisible while the
opaque "NO TRACK" placeholder covered the window but showed as a solid white
pane the moment a track played and only `MilkdropView`'s (non-fully-opaque)
render output remained. `property var milkdropConfig: null` — deliberately
not named `appConfig`, same `Component.onCompleted`-runs-before-`Loader.onLoaded`
scoping gotcha documented on `AudioVisualizerWindow.qml`'s `visualizerConfig`
property (see UC-19). A `MilkdropView { anchors.fill: parent; ... }` fills the
pane, hidden (and therefore not rendering — `onRenderTick` checks
`isVisible()`, so hiding the item fully stops the animation, not just the
display of it) behind one of two placeholders depending on why nothing is
showing. Three mutually-exclusive states, driven by two properties:
`hasTrack` (`engine.currentTitle.length > 0` — a track is *loaded*) and
`isPlaying` (`engine.isPlaying` — it's *actively playing*, backed by
`PlaybackEngine`'s `QMediaPlayer::PlayingState` check). `currentTitle` stays
set to the last track after it pauses or the queue ends (so `NowPlaying` can
keep showing it), so `hasTrack` alone doesn't mean "playing" — an earlier
version gated the visualizer on `hasTrack` alone and kept animating
indefinitely after the last track ended or the user paused, which was a real
bug, not intended behavior:
- `!hasTrack` → "♫ NO TRACK" (nothing ever loaded).
- `hasTrack && !isPlaying` → "⏸ PAUSED" (loaded, but paused or the queue
  ended — same placeholder for both, since both are simply "not currently
  playing").
- `hasTrack && isPlaying` → `MilkdropView` itself, actually rendering.

**Double-click position cycle**: exact behavioral mirror of
`BigCoverWindow.qml`'s toggle (UC-17) — original position (captured on first
double-click) → centered → right edge → left edge → back to original →
repeat, driven by `FloatingPane`'s generic `doubleClicked()` signal. Only `x`
changes; `y`/width/height are untouched, resizing stays manual. No
`fixedAspectRatio` here (unlike `BigCoverWindow`'s square-cover constraint —
Milkdrop has no aspect requirement).

**F10 fullscreen toggle**: a `Shortcut { sequence: "F10" }` (default
`Qt.WindowShortcut` context, so it fires while this pane is the active
window) — first press saves the pane's current `x`/`y`/`width`/`height` and
sets geometry to fill the screen (`Screen.virtualX/virtualY` +
`Screen.width/height` — manual geometry, not Qt's native
`Window.FullScreen` visibility mode, for consistency with how every other
multi-screen geometry calculation in this codebase already works); a second
press restores exactly what was saved. Independent of the double-click cycle
above — no shared state — so it restores whatever geometry was active right
before F10 was pressed, whether that came from manual dragging or from the
double-click cycle. First use of `Shortcut`/keyboard-triggered behavior on
any detachable pane in this codebase; a reasonable pattern to reuse if a
future pane wants the same treatment.

**Auto-hide cursor during fullscreen idle**: a 2-second, non-repeating
`Timer` sets `FloatingPane`'s generic `cursorHidden` property (see UC-17)
`true` once it fires; `FloatingPane`'s `mouseMoved()` signal (see UC-17)
resets the timer and un-hides the cursor on any movement while
`_isFullscreen` is `true`. The first version of this used a separately
declared `HoverHandler` instead — it didn't reliably receive hover events
while nested below `FloatingPane`'s own full-pane move `MouseArea` in the
item stack (a `PointerHandler`-under-`MouseArea` reliability question this
codebase can't fully resolve without live testing), so the cursor never came
back once hidden. Switching to `mouseMoved()` — emitted directly from that
same move `MouseArea`'s `onPositionChanged`, the exact handler that already
reliably drives window dragging — sidesteps the question by reusing
already-proven event delivery instead of a second, independent path. Known
minor gap: `mouseMoved()` only covers the move area's extent, not the 8
resize-grip strips at the pane's very edges, so movement confined entirely
within an 8px edge strip won't reset the idle timer — accepted as
not worth solving further (resize grips are barely relevant on a fullscreen
pane). The F10 handler starts the timer fresh on entering fullscreen and
stops it (forcing `cursorHidden` back to `false`) on exiting — the cursor is
never hidden outside fullscreen.

### `BottomBar.qml` / `Main.qml` wiring

Exact mirror of UC-19's `audioVisualizerPaneOpen`/`audioVisualizerLoader`
pattern: `milkdropToggleRequested()` signal + `milkdropPaneOpen` property in
`BottomBar.qml` (fifth toolbar button, row now divided five ways instead of
four), `root.milkdropPaneOpen` + `milkdropLoader` in `Main.qml` with the same
geometry-restore-or-center-default `Component.onCompleted` block (default
560×360). The one structural difference from the audio-visualizer Loader:
there's no separate controller instantiated in `Main.qml` to pass in (no
`MilkdropController` — see above), so `onLoaded` only sets `item.engine` and
`item.milkdropConfig`.

### `AppConfig` — `milkdrop`/`milkdropPane` persistence

Same READ-only-`Q_PROPERTY` + dedicated `Q_INVOKABLE`-setter convention as
every other settings group in this file:

| Property / method | Detail |
|---|---|
| `milkdropPresetFolders` / `addMilkdropPresetFolder(path)` / `removeMilkdropPresetFolderAt(index)` / `clearMilkdropPresetFolders()` | Flat list of plain path strings (no per-folder subfolder toggle, unlike the music `folders` list — always scanned recursively). Accepts plain paths or `file://` URLs, same as `addFolder`. |
| `milkdropShuffleEnabled` / `setMilkdropShuffleEnabled(enabled)` | Default `true`; forwarded to `projectm_playlist_set_shuffle`. |
| `milkdropPresetDuration` / `setMilkdropPresetDuration(seconds)` | Default `20.0`; clamped `[5, 120]`; forwarded to `projectm_set_preset_duration`. |
| `milkdropBeatSensitivity` / `setMilkdropBeatSensitivity(sensitivity)` | Default `1.0`; clamped `[0.0, 4.0]` (projectM's own scale); forwarded to `projectm_set_beat_sensitivity`. |
| `milkdropHardCutsEnabled` / `setMilkdropHardCutsEnabled(enabled)` | Default `false`; forwarded to `projectm_set_hard_cut_enabled`. |
| `milkdropHardCutSensitivity` / `setMilkdropHardCutSensitivity(sensitivity)` | Default `0.6`; clamped `[0.0, 1.0]`; forwarded to `projectm_set_hard_cut_sensitivity`. |
| `milkdropPresetLocked` / `setMilkdropPresetLocked(locked)` | Default `false`; forwarded to `projectm_set_preset_locked` — disables all automatic preset transitions. |
| `milkdropShowPresetName` / `setMilkdropShowPresetName(enabled)` | Default `true`; toggles `MilkdropWindow.qml`'s fading current-preset-name toast (see below) — purely a display setting, doesn't touch projectM itself. |
| `milkdropPaneConfigured` / `milkdropPaneX/Y/Width/Height` / `saveMilkdropPaneGeometry(...)` | Read-only geometry, same convention as `audioVisualizerPane*` (defaults `560`×`360`, `configured` starts `false`). |

JSON shape (nested, matching the `audioVisualizer`/`audioVisualizerPane` split):

```json
"milkdrop": { "presetFolders": ["C:/Presets"], "shuffleEnabled": true,
              "presetDuration": 20.0, "beatSensitivity": 1.0,
              "hardCutsEnabled": false, "hardCutSensitivity": 0.6,
              "presetLocked": false, "showPresetName": true },
"milkdropPane": { "x": 100, "y": 100, "width": 560, "height": 360,
                   "screenName": "DISPLAY1" }
```

### `SetupDialog.qml` — "MILKDROP" tab

Sixth tab. A preset-folder add/remove list (same delegate/button pattern as
FILE MONITORING's folder list, minus the subfolders-toggle column), a
Shuffle toggle, Preset Duration slider (5–120s), Beat Sensitivity slider
(0.0–4.0), Hard Cuts toggle + Hard Cut Sensitivity slider (0–100%), a
Lock Preset toggle, and a Show Preset Name toggle — all built from the same
`Slider`/toggle-track components already established in the AUDIO VISUALIZER
tab, so no new QML idioms.

### Current preset name toast

`MilkdropView` already registers `projectm_playlist_set_preset_switched_event_callback`
for diagnostic logging (see below); that same callback now also derives a
display name — `projectm_playlist_item(m_playlist, index)` returns the
switched-to preset's file path (freed via `projectm_playlist_free_string()`,
same call projectM's own SDL2 reference frontend uses), wrapped in
`QFileInfo(...).completeBaseName()` to strip the directory and `.milk`
extension (deliberately no further parsing of community preset-pack naming
conventions, e.g. embedded "(by Author)" credits — kept simple on purpose).
Exposed as `Q_PROPERTY(QString currentPresetName ...)`. Runs on the GUI
thread already (same thread `onRenderTick`/`rebuildPresetList` run on, no
cross-thread marshaling needed). `MilkdropWindow.qml` shows it as a
bottom-center toast — `Text.style: Text.Outline` for legibility over
arbitrary preset visuals rather than a background `Rectangle` — that snaps
to full opacity on every `currentPresetNameChanged` (gated on
`AppConfig.milkdropShowPresetName`) and fades out (`Behavior on opacity`,
1000ms) after a 5000ms hold `Timer`, mirroring projectM's own reference
frontends' toast timing convention. Also gated on `mdWindow.isPlaying` so a
toast mid-fade doesn't linger visibly over the "PAUSED" placeholder if
playback pauses mid-fade.

### Known limitations (not fixed, not requested)

- No bundled presets — see above; the pane renders nothing until the user
  configures at least one preset folder.
- Offscreen readback costs a GPU→CPU→GPU round-trip every render tick; kept
  to ~30fps to stay cheap, but this is a real, unmeasured performance cost
  worth revisiting if it turns out to matter on lower-end hardware.
- Same audio-tap crossfade simplification as UC-19 (only the active deck's
  buffer is fed in — see `PlaybackEngine` section under UC-19).
- Only `Float`/`Int16` sample formats are handled, same as UC-19.
- No mesh size / target FPS / aspect-correction settings exposed yet — left
  at projectM's own defaults for this first version. Texture search paths
  are handled automatically (sibling `Textures`/`textures` folder
  convention, see above) rather than as a separate user-facing setting.
- `projectm_opengl_render_frame_fbo()` (the more explicit FBO-targeted render
  call) isn't used because it requires projectM ≥4.2.0, unreleased at the
  time of writing — the current never-shown-`QWindow`-plus-`glReadPixels`
  approach works around this on v4.1.7, but the `_fbo` variant would be a
  cleaner, likely more efficient replacement once a newer stable tag exists;
  revisit then.
- `MilkdropView::logDiagnostic()` writes to both `qWarning()` and a
  `milkdrop_debug.log` file next to `Topaz.exe` — added because Topaz is a
  `WIN32_EXECUTABLE` with no console, so `qWarning()` alone is invisible
  however the app is normally launched. Along with the playlist
  preset-switched/failed callbacks and a periodic pixel-sample log in
  `onRenderTick()`, this was what actually made diagnosing the
  wrong-framebuffer bug above possible — worth keeping for any future
  "renders nothing" reports rather than removing it once things work.
- Same as UC-17/UC-18/UC-19: no live handling of screen-configuration changes
  while the pane is open, and open/closed state is not persisted across app
  restarts.

---

## UC-21 Search Library

| Field | Detail |
|-------|--------|
| **Goal** | User searches the whole library by artist, album, or track title without navigating the genre tree. |
| **Actor** | User |
| **Precondition** | The library has been scanned. |
| **Trigger** | User clicks the "SEARCH" tab in `TopBar`. |

### Normal Flow

1. User clicks "SEARCH". `TopBar` emits `searchSelected()` → `Main.qml` sets
   `activeTab = "search"`. The two `Loader`s in the `SplitView`'s first two
   slots swap `LibraryTree`/`AlbumBrowser` for `SearchPanel.qml`/
   `SearchResultBrowser.qml`; `PlaybackQueue` and `NowPlaying` are untouched,
   and `GenreBar` (outside the `SplitView`) stays visible and usable.
2. User types into `SearchPanel`'s query field (a `TextInput`, same
   `Rectangle`+`TextInput` convention as `SetupDialog`'s "add genre" input).
   `onTextEdited` writes directly to `SearchData.query`.
3. `SearchData` restarts a 250ms debounce `Timer` on every `query`/`mode`/
   `considerGenre`/`matchWholeWord`/`activeGenreNames` change. When it
   fires, it calls `LibraryModel.searchLibrary(query.trim(), mode,
   activeGenreNames, considerGenre, matchWholeWord)` and assigns the result
   to `SearchData.results`.
4. `SearchResultBrowser`'s `ListView` is bound directly to
   `searchData.results` — no additional refresh plumbing needed, since
   `SearchData` already centralizes the debounce. Each result renders as an
   `AlbumCard` (`searchLibrary()` returns the same per-album/per-track
   object shape `filteredAlbums()` does, so no card-rendering logic needed
   duplicating — the only addition is feeding `AlbumCard`'s `albumGenre`
   prop from the result's `genre` field, rendering "Genre | Year" under the
   cover; `AlbumBrowser` leaves `albumGenre` unset so Library-tab cards are
   unchanged), including drag-to-queue.
5. Once the trimmed query is non-empty, `SearchPanel` reveals four
   mode-toggle buttons — `ALL` (default), `ARTISTS`, `ALBUMS`, `TRACKS` —
   styled like `TopBar`'s own tabs at a smaller size. Clicking one sets
   `SearchData.mode` and triggers a fresh (debounced) search.

### Alternate: mode switch

- **ARTISTS**: matches `albumArtist` substrings; every track under a
  matching artist is returned (with all their albums/tracks), not just the
  matching one — see `LibraryModel::searchLibrary()`.
- **ALBUMS**: matches `album` substrings; every track under a matching
  album is returned.
- **TRACKS**: matches `title` substrings only; only the matching track(s)
  within an album are returned (sibling tracks are excluded), still with
  the album's cover.
- **ALL** (default): the union of all three — matching a track's
  `albumArtist`/`album`/`title` independently pulls it into the results.
  All four modes are a single O(N_tracks) pass; see the "LibraryModel
  public API" section below for why no second "pull in siblings" pass is
  needed for the artist/album cases.

### Alternate: Match whole word

- `SearchPanel`'s "Match whole word" checkbox (unchecked by default,
  positioned above "Consider Genre") is bound to `SearchData
  .matchWholeWord`. When checked, a field only counts as matched if the
  query substring is bounded by non-alphanumeric characters (or field
  start/end) on both sides — e.g. "Love" then matches "Love" but not
  "Lovely"/"Loveless" — via a plain-`QString` boundary check
  (`matchesWholeWord()` in `librarymodel.cpp`), not `QRegularExpression`,
  to match the rest of `searchLibrary()`'s style. Still a single
  O(N_tracks) pass; the boundary check only runs per field actually being
  compared, same as the substring check it replaces.

### Alternate: Consider Genre

- `SearchPanel`'s "Consider Genre" checkbox (unchecked by default) is bound
  to `SearchData.considerGenre`. When checked, search additionally requires
  `t.genre` to be one of `LibraryData.activeGenreNames` (the genres
  currently toggled on in `GenreBar`) — this is the one deliberate,
  read-only dependency `SearchData` has on `LibraryData`; nothing else
  couples the two. When unchecked, genre is ignored entirely.

### Empty-State Rules

- Query empty: `SearchResultBrowser` shows "Type a query to search your
  library." and the mode-toggle row is hidden.
- Query non-empty, zero matches: `SearchResultBrowser` shows "No matches
  for the current search."
- Clearing the query (back to empty) synchronously clears `SearchData
  .results` and resets `SearchData.mode` back to `"all"`, so the next
  search starts from a clean slate.

### Design notes

- **Independence from LIBRARY**: `SearchData`/`SearchPanel`/
  `SearchResultBrowser` never read or write `LibraryData`'s selection state
  (`selectedGenre`/`selectedArtist`/`selectedAlbum`) and never call
  `LibraryData`'s tree-building functions. Switching tabs cannot leave one
  side's state corrupted by the other.
- **PLAYLISTS tab**: has its own dedicated panel content — see UC-22.
- **Loader-based panel swap, not `visible` toggling**: a `Loader` destroys/
  recreates its content on swap, so `LibraryTree`'s local transient UI state
  (expanded-artist set, its own scroll position) resets when the user
  leaves and returns to LIBRARY — `LibraryData`'s actual selection state is
  unaffected since it lives in `lib`, not the view. `SearchData` lives
  outside both `Loader`s, so leaving and returning to SEARCH preserves the
  last query/mode/results exactly. `Loader` was chosen over keeping both
  trees permanently instantiated with `visible` toggling because it avoids
  two heavy virtualized `ListView`s coexisting and is unambiguously correct
  (rather than relying on `SplitView`'s undocumented behavior for
  runtime-toggled child visibility).
- **`AlbumBrowser`/`SearchResultBrowser` scroll position IS preserved**
  across the swap, unlike `LibraryTree`'s: each `ListView`'s `contentY` is
  mirrored into `LibraryData.albumScrollY`/`SearchData.resultScrollY`
  (`onContentYChanged`) — since those data objects, unlike the views
  themselves, survive the `Loader` swap — and restored via `Qt.callLater`
  the next time that view is (re)created (`onLibChanged`/
  `onSearchDataChanged`, both of which fire exactly once per (re)creation,
  not on every ordinary model refresh while the view stays loaded). The
  `Qt.callLater` defer is required, not optional: setting `contentY` in the
  same tick as the model change gets clamped back to 0 before
  `contentHeight` catches up — the same technique `LibraryTree.qml`
  already uses to preserve its own scroll position across a flat-list
  rebuild (`onExpandedArtistsChanged`). `LibraryTree`'s own scroll offset
  and expand-state remain unpreserved (see previous point) since those stay
  genuinely tied to the destroyed/recreated view instance itself, with no
  natural home on `LibraryData` the way a single scroll float has.

---

## UC-22 Browse Playlists (PLAYLISTS Tab)

| Field | Detail |
|-------|--------|
| **Goal** | User browses saved XSPF playlists and previews or loads one into the queue, independently of LIBRARY/SEARCH. |
| **Actor** | User |
| **Precondition** | Application is running (playlists don't require a library scan). |
| **Trigger** | User clicks the "PLAYLISTS" tab in `TopBar`. |

### Normal Flow

1. User clicks "PLAYLISTS". `TopBar` emits `playlistsSelected()` →
   `Main.qml` sets `activeTab = "playlists"`. The two `Loader`s in the
   `SplitView`'s first two slots swap `LibraryTree`/`AlbumBrowser` (or
   `SearchPanel`/`SearchResultBrowser`) for `PlaylistsPanel.qml`/
   `PlaylistViewer.qml`; `PlaybackQueue` and `NowPlaying` are untouched.
2. `PlaylistsPanel`'s `onPlaylistsDataChanged` (fired once by `Main.qml`'s
   `Loader.onLoaded` right after creation — not `Component.onCompleted`,
   see Design notes) calls `PlaylistsData.refreshPlaylists()`, which calls
   `PlaylistManager.listPlaylists()` — a `QDir` listing of `*.xml` files in
   `playlistDirectory()`, sorted by display name ascending
   (case-insensitive).
3. `PlaylistsPanel` renders one row per playlist (styled like
   `LibraryTree`'s genre row: bullet + name, `Theme.fontFamilyBody`/
   `labelLg`/`Font.Bold`, `Theme.s10` background when selected).
4. User clicks a playlist row. `PlaylistsData.selectPlaylist(fileName)`
   calls `PlaylistManager.loadPlaylist(path)` (parses the XSPF, resolves
   each track's absolute path via `VolumePath`, reads bitrate/duration/tag
   fallbacks — same as UC-10 step 5) then
   `LibraryModel.buildStandaloneTrackCards(result.tracks)` to convert the
   raw track list into one standalone, `AlbumCard`-shaped entry **per
   track** — deliberately **not** grouped by album, unlike
   `filteredAlbums()`/`searchLibrary()`, so the playlist's actual
   track-by-track composition stays visible even when several tracks from
   the same album are adjacent. Both the raw tracks
   (`PlaylistsData.selectedRawTracks`) and the per-track cards
   (`PlaylistsData.albums`) are cached.
5. `PlaylistViewer`'s `ListView` is bound to `playlistsData.albums`,
   rendering each entry as its own `AlbumCard` (each with its own cover,
   album title, artist, and single track row) — identical rendering path
   to `SearchResultBrowser` (including the `albumGenre` → "Genre | Year"
   prop), so drag-to-queue and double-click-to-queue work unmodified (see
   UC-06). The header shows the track count and playlist name on the
   right; the left side (where `AlbumBrowser`/`SearchResultBrowser` show
   "ALBUM BROWSER"/"SEARCH RESULT") instead shows a compact **LOAD**
   button (see step 6).
6. User clicks **LOAD**. Identical effect to UC-10's LOAD button, except
   no `FileDialog` is shown (the file was already picked in step 4) and no
   `PlaylistManager.loadPlaylist()` re-parse happens — the already-cached
   `PlaylistsData.selectedRawTracks` is handed straight to
   `PlaybackEngine.loadPlaylistTracks()`, which **always** replaces the
   queue, crossfading into it if eligible (see UC-23), followed by
   `engine.setActivePlaylistName(selectedFileName)` — exactly the same
   step-6 flow UC-10 uses. `PlaylistsData.clearSelection()` is then called,
   returning `PlaylistViewer` to its empty state.

### Alternate: Playlist already active in the queue

A playlist row whose `fileName` matches `engine.activePlaylistName` (the
playlist currently loaded into the queue) is rendered dimmed with an
"(IN QUEUE)" label, and its `MouseArea` is `enabled: false` — it cannot be
selected for preview. Reselecting it would only clear and reload the exact
same queue, so the row is excluded entirely rather than allowing a no-op
LOAD. This is a plain reactive binding on `engine.activePlaylistName`
(`NOTIFY`-backed `Q_PROPERTY`), so the row's state updates immediately if
the active playlist changes elsewhere (e.g. REMOVE/LOAD in `NowPlaying`)
while PLAYLISTS is the active tab.

### Alternate: Track missing a cover in the scanned library

If a playlist track's file is no longer part of the current library scan
(e.g. its folder was unmonitored since the playlist was created),
`buildStandaloneTrackCards()` still renders it correctly — just without a
cover — by synthesizing a `TrackInfo` from the XSPF-derived fields (see
Design notes).

### Design notes

- **Independence from LIBRARY/SEARCH**: `PlaylistsData`/`PlaylistsPanel`/
  `PlaylistViewer` never read or write `LibraryData`/`SearchData` state.
  The one deliberate exception is a read-only reference to `PlaybackEngine`
  (`PlaylistsData.engine`), needed solely to recognize the active-in-queue
  playlist (previous section) — the same "one intentional read-only
  cross-reference" pattern `SearchData.activeGenreNames` already
  established for LIBRARY/SEARCH.
- **No album grouping — each track is its own card**: unlike
  `filteredAlbums()`/`searchLibrary()`, `buildStandaloneTrackCards()` never
  merges tracks sharing `(genre|albumArtist|album)` into one accumulator —
  every input track becomes its own one-track `AlbumAccum`. This is
  deliberate: a playlist's whole point is showing exactly how the user
  composed it, so three tracks off the same album appearing back-to-back
  (or scattered through the playlist) each render as their own card with
  their own cover, rather than collapsing into a single browsing-style
  album rollup.
- **Playlist's own order is preserved, not alphabetically re-sorted**:
  `buildStandaloneTrackCards()` calls `serializeAlbumAccum(albumAccum,
  false, /*preserveOrder=*/true)`, a parameter that skips both of
  `serializeAlbumAccum()`'s internal sorts. Cards are emitted in the exact
  order their tracks appear in the playlist — matching the user's
  expectation that a playlist plays back in the sequence they built it in,
  not alphabetical browsing order. (The per-card track sort the flag also
  skips is moot here since every card holds exactly one track.)
- **Per-track cover fallback via `coverThumbForAlbum()`**:
  `PlaylistManager.loadPlaylist()` deliberately skips cover thumbnail
  generation for load speed (see UC-10), and `TrackInfo::coverThumb`
  itself is only populated on one representative track per `(genre,
  albumArtist, album)` triple in the whole scanned library (see UC-05 step
  4d) — every other track of that album stores an empty string. A naive
  `filePath` match alone would therefore only show a cover on whichever
  literal track happens to be that representative, leaving every other
  track of the same album blank even when the playlist has several of
  them. `buildStandaloneTrackCards()` falls back to
  `coverThumbForAlbum(album, albumArtist)` (`librarymodel.cpp:606-616`)
  whenever a track's own `coverThumb` is empty, so every track of an album
  shows its cover regardless of which literal file the scanner chose as
  representative. `coverThumbForAlbum()` is an O(N_tracks) linear scan —
  too slow to call once per track across the whole library in general, but
  negligible for a playlist, which is capped in practice at a few hundred
  tracks (200 tracks is already 12+ hours of continuous playback) — so a
  dedicated per-call hash (the pattern `searchLibrary()`'s track-cover
  fix-up pass uses at whole-library scale) isn't warranted here.
- **`onPlaylistsDataChanged`, not `Component.onCompleted`**: `Main.qml`'s
  `Loader.onLoaded` assigns `item.playlistsData` imperatively *after* the
  loaded item (and its own `Component.onCompleted`) has already run, so a
  `Component.onCompleted` handler in `PlaylistsPanel.qml` would see
  `playlistsData` still `null`. Using `onPlaylistsDataChanged` instead
  (the same fix `AlbumBrowser.onLibChanged`/
  `SearchResultBrowser.onSearchDataChanged` already apply) ensures
  `refreshPlaylists()` runs once the property is actually set, so the
  playlist listing is always fresh whenever the user switches *into*
  PLAYLISTS from another tab.
- **Live refresh while already on PLAYLISTS**: the above alone doesn't
  cover creating a playlist via `NowPlaying`'s **+ NEW** button while
  PLAYLISTS is already the active tab, since that doesn't destroy/recreate
  `PlaylistsPanel`. `NewPlaylistDialog` (see UC-08) emits
  `playlistCreated()` on success; `Main.qml` handles it with
  `onPlaylistCreated: playlistsData.refreshPlaylists()`. `PlaylistsData` is
  a plain always-alive `Item`, not `Loader`-managed, so this is safe to
  call regardless of the active tab, and `PlaylistsPanel`'s `ListView`
  (bound directly to `playlistsData.playlists`) updates immediately if it
  happens to be visible.
- **Scroll position preserved across the `Loader` swap**: identical
  mechanism to `AlbumBrowser`/`SearchResultBrowser` (previous section) —
  `PlaylistViewer`'s `ListView.contentY` mirrors into
  `PlaylistsData.resultScrollY` and is restored via `Qt.callLater` on
  `onPlaylistsDataChanged`.

---

## UC-23 Crossfade Into a Loaded Playlist

| Field | Detail |
|-------|--------|
| **Goal** | Loading a different playlist while a track is already playing fades out the current track and fades in the new playlist's first track, instead of a hard stop-then-restart. |
| **Actor** | System (playback), gated by a setting the user controls |
| **Precondition** | `AppConfig.crossfadeEnabled` is `true`; a track is currently playing; both the outgoing (live) and incoming (tag) track durations exceed `crossfadeSeconds`. |
| **Trigger** | User clicks **LOAD** in `NowPlaying` or `PlaylistViewer` (UC-10/UC-22) while a track is playing. |

### Normal Flow

1. UC-10 step 6 / UC-22 step 6 always call `PlaybackEngine
   .loadPlaylistTracks(tracks)` — never `clearQueue()`+`addTracks()`
   directly from QML — regardless of whether a playlist was already
   active. (An earlier version of this step only called
   `loadPlaylistTracks()` when `activePlaylistName ≠ ""`, silently
   appending via `addTracks()` otherwise — the bug that motivated this
   fix, see UC-10's Normal Flow step 6 note.)
2. `loadPlaylistTracks()` checks eligibility: `AppConfig.crossfadeEnabled()`
   is on, `isPlaying()` is true, a track is current
   (`m_currentIndex >= 0`), and — the same rule `onDeckPositionChanged()`
   applies to the natural crossfade (UC-15) — both the active deck's live
   `duration()` and the new first track's tag `durationMs` exceed
   `crossfadeSeconds() * 1000`. If any of that fails, it falls straight
   through to `clearQueue()`+`addTracks(tracks)` — today's original,
   unmodified behavior.
3. When eligible: captures `m_fadeOutDeck`/`m_fadeInDeck` (mirroring
   `startCrossfade()`) and the outgoing track's file path
   (`m_fadeOutFilePath`, since that track won't have a slot in the queue
   once it's replaced), builds the *entire new queue* into
   `m_pendingQueue` (not `m_queue` yet), loads the new first track onto the
   standby deck at volume `0` and starts it playing, then starts the same
   `m_fadeTimer`/`onFadeTick()` ramp the natural crossfade uses — with a
   new `m_crossfadeReplacesQueue = true` flag and `m_fadeTargetIndex = 0`.
4. At the fade's midpoint (`onFadeTick()`, `frac >= 0.5`, unchanged
   trigger): the UI-facing deck alias swaps as usual, and — only because
   `m_crossfadeReplacesQueue` is `true` — `m_queue` is replaced wholesale
   with `m_pendingQueue` (`beginResetModel`/`endResetModel`,
   `queueCountChanged()`) *before* the existing, unmodified
   `switchCurrentIndexTo(m_fadeTargetIndex)` call, which now correctly
   resolves index `0` in the *new* queue. `NowPlaying`/`PlaybackQueue`
   update together at this instant, exactly like a natural crossfade's
   midpoint.
5. At fade completion (`frac >= 1.0`): the outgoing deck stops and its
   volume resets, same as always; `trackPlayedToCompletion` fires for the
   captured `m_fadeOutFilePath` (not a `m_queue` index lookup, since that
   track is no longer in the queue) and the three new members reset so
   they can never leak into a later, unrelated natural crossfade.

### Alternate: Crossfade disabled or ineligible

Falls back to `clearQueue()`+`addTracks(tracks)` — byte-identical to the
original UC-10/UC-22 behavior. This covers: `crossfadeEnabled` off, nothing
currently playing (paused or idle queue), or either the outgoing or
incoming track being shorter than the configured crossfade length.

### Alternate: Interrupted mid-fade

Any queue-mutating method (`removeAt`, `moveUp`, `moveDown`, `moveTrack`,
`clearQueue`) or `loadTrack()`/`seek()` calls `cancelCrossfade()` first, same
as for a natural crossfade (UC-15) — now additionally resetting
`m_crossfadeReplacesQueue`/`m_pendingQueue`/`m_fadeOutFilePath`. If canceled
before the midpoint, the old queue and track are untouched and simply
resume at full volume; if canceled after the midpoint, the new queue is
already in place (the swap is synchronous, not gradual) and only the
now-irrelevant outgoing deck gets stopped.

### Design notes

- **Why not extend `startCrossfade()` directly**: that function's whole
  design assumes the outgoing and incoming tracks are adjacent indices in
  one unchanged `m_queue` — true for a natural crossfade, false here (the
  incoming track belongs to a queue that's about to replace the old one
  entirely). Reusing the same timer/ramp/midpoint machinery via one
  additive `if (m_crossfadeReplacesQueue)` branch in `onFadeTick()` (default
  `false`, set only by `loadPlaylistTracks()`) avoids duplicating that
  machinery while guaranteeing zero behavior change for the 100% of
  crossfades that don't set the flag.
- **AUTO PLAY is orthogonal**: the LOAD button is already fully disabled
  during an AUTO PLAY session (`autoPlay.queueClearAllowed` is `!active`),
  so this path only ever engages in MANUAL MODE. The one AUTO PLAY side
  effect worth preserving — `clearQueueAndHistory()`'s
  `m_playCounts.clear()` — can't reuse that method directly, since it also
  unconditionally calls `engine.clearQueue()`, which would kill the very
  playback being crossfaded. A new `AutoPlayController.clearHistory()`
  provides just the history-clear half.
- **Why the LOAD button's queue-clear moved from click to accept**: see
  UC-10's Design decisions — crossfading needs the target tracks before it
  can decide anything, which the old eager-clear-on-click structure made
  impossible.

