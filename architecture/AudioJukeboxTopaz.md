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
3. `LibraryData.toggleGenre()` flips the `active` flag in `genreModel` and rebuilds `activeGenreNames`. If the genre was just **activated**, it becomes the sole `selectedGenre` (replacing any prior selection). If it was just **deactivated**, the nearest remaining active genre is auto-selected instead — the one positionally after it, or if it was the last active genre, the one before it; if no active genres remain, `selectedGenre` is cleared. `selectedArtist`/`selectedAlbum` are cleared in both cases. When a genre is auto-selected this way, `LibraryData` emits `genreAutoSelected(genre)`, and `LibraryTree` scrolls that genre's header row into view via `positionViewAtIndex(..., ListView.Contain)`. This scroll-into-view only happens for auto-selection — manually clicking a genre, artist, or album row in the tree does not trigger it.
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
5. Dialog opens on the **GENRES** tab by default.
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
   performs a duplicate check, appends `{ "path": ..., "includeSubfolders": true }`, emits
   `foldersChanged`, and auto-saves.
6. The new row appears in the folder list with the **SUBFOLDERS** checkbox ticked.

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
4. `LibraryScanner.fullScan()` runs on the worker thread:
   a. Recursively walks each configured folder (respecting `includeSubfolders`).
   b. For each `*.mp3` / `*.flac` / `*.opus` file: calls `TagReader::read()`.
   c. Compares the file's genre tag (case-insensitive trim) against configured genres. Skips unmatched files.
   d. Assigns a stable UUID (reused from cache if path is known).
   e. For the first track of each (albumArtist, album) pair: extracts and scales a 160×160 JPEG thumbnail.
   f. Emits `scanProgress(done, total)` periodically.
5. Scanner saves result to `Topaz.library.json` via `LibraryCache::save()`.
6. Scanner emits `scanCompleted(tracks)`.
7. `LibraryModel.onScanCompleted()` calls `beginResetModel/endResetModel`, replaces `m_tracks`, emits `libraryRefreshed()`.
8. `LibraryData._rebuildTree()` fires → `LibraryTree` and `AlbumBrowser` update.

### Normal Flow — Startup stat-check (hybrid strategy step 2)

1. `Main.qml Component.onCompleted` → `libraryModel.loadCacheAndStartStatCheck()`.
2. Cache is read synchronously from `Topaz.library.json` → displayed immediately (step 1 of hybrid strategy).
3. `statCheck` is dispatched to worker thread.
4. Worker validates each cached entry (file still exists, `lastModified` unchanged).
5. New files found in configured folders are scanned and added.
6. Deleted files are removed from the result.
7. Updated cache is saved and `scanCompleted` emitted.

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
├── AppConfig           C++ QML_ELEMENT — reads/writes Topaz.config JSON; exposes genres & folders
├── LibraryModel        C++ QML_ELEMENT — QAbstractListModel + scanner orchestration
│                         property AppConfig appConfig
│                         Q_INVOKABLE: loadCacheAndStartStatCheck(), startFullScan()
│                         Q_INVOKABLE queries: genres(), artistsForGenre(), albumsForArtist(), filteredAlbums(), buildLibraryTree()
├── LibraryData.qml     shared state model — genre toggle, selection, tree builder
│                         property AppConfig appConfig
│                         property LibraryModel libraryModel
├── Main.qml            ApplicationWindow root; owns AppConfig, LibraryData, LibraryModel, PlaybackEngine, PlaylistManager, SystemVolumeController, SetupDialog, NewPlaylistDialog
│                         property bool bigCoverPaneOpen  (toggled by NowPlaying.onBigCoverRequested / BigCoverWindow.onCloseRequested)
│                         Loader { active: bigCoverPaneOpen; sourceComponent: BigCoverWindow {...} }  — see "Detachable panes" below
│                         property bool tagInfoPaneOpen  (toggled by BottomBar.onTagInfoToggleRequested / TagInfoWindow.onCloseRequested)
│                         Loader { active: tagInfoPaneOpen; sourceComponent: TagInfoWindow {...} }  — see UC-18
├── SetupDialog.qml     Modal setup popup (tabs: GENRES | FILE MONITORING | CROSSFADE | AUTO PLAY, see UC-15 / UC-14)
├── NewPlaylistDialog.qml Modal popup — user enters a name; calls PlaylistManager.createPlaylist(); shows MessageBox on name collision
├── MessageBox.qml      Themed single-message popup with OK button; reusable across the application
├── FloatingPane.qml    Reusable base Window for detachable panes (frameless, movable, resizable, right-click-to-close) — see "Detachable panes" below
├── BigCoverWindow.qml  FloatingPane specialization: shows only the current track's cover art
├── TagInfoWindow.qml   FloatingPane specialization: shows the current track's tag metadata, content scales with pane size — see UC-18
├── TopBar.qml          Header (logo | navigation tabs | loudspeaker icon + gear icon + avatar)  height 64 px
│                         property var systemVolume  (bound to SystemVolumeController; drives the OS-Volume flyout, see below)
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
├── AlbumBrowser.qml    Center album list  flex-grow (absorbs all surplus width from window resize or panel drag)  (calls lib.filteredAlbums() via Qt.callLater; property autoPlay forwarded to each AlbumCard, see UC-16)
├── AlbumCard.qml       Single album card delegate (cover + year label + track listing; single-track drag & drop to queue; no selection; no context menus)
│                         property var engine  (optional; used for double-click add-to-queue and drag cursor override)
│                         property var autoPlay  (optional; gates double-click add via autoPlay.manualQueueEditingAllowed, see UC-16)
│                         property int albumYear  (0 = unknown, hides the label; left-aligned under the cover, Theme.labelMd, literal white)
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
```

## LibraryModel Component

`LibraryModel` is a C++ `QAbstractListModel` subclass marked `QML_ELEMENT`.
It owns a `LibraryScanner` worker that lives on a dedicated `QThread`.  All
heavy I/O (tag reading, directory walking, JSON serialisation) runs on the
worker thread; the main thread only receives light result copies via Qt's
queued-connection mechanism.

### C++ class overview

| Class | File | Role |
|-------|------|------|
| `TrackInfo` | `trackinfo.h` | Flat data struct; the single record type in the library |
| `TagReader` | `tagreader.h/cpp` | Zero-dependency ID3v2 + FLAC + Opus tag reader; cover thumbnail generator |
| `LibraryCache` | `librarycache.h/cpp` | Atomic read/write of `Topaz.library.json` |
| `LibraryScanner` | `libraryscanner.h/cpp` | Worker: directory walk, genre filter, QFileSystemWatcher |
| `LibraryModel` | `librarymodel.h/cpp` | QAbstractListModel + Q_INVOKABLE query helpers exposed to QML |
| `PlaylistManager` | `playlistmanager.h/cpp` | XSPF playlist file creation; path-portability helpers |
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
as Base64. Only one thumbnail is generated per `(albumArtist, album)` pair; all other
tracks in the same album store an empty `coverThumb`. Passed to `AlbumCard` as a
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
| `ratingsReady` | `true` once a scan (full or stat-check) has completed at least once in this session with rating enrichment applied (see UC-14). Gates the AUTO PLAY button in `BottomBar`; never reset back to `false`. |
| `loadCacheAndStartStatCheck()` | Load cache instantly, then dispatch stat-check |
| `startFullScan()` | Trigger a full rescan on the worker thread |
| `genres()` | Distinct genre strings present in the library |
| `artistsForGenre(genre)` | Album artists for a genre, sorted |
| `albumsForArtist(artist, genre)` | Album titles for an artist, sorted |
| `filteredAlbums(activeGenres, selectedArtist, selectedAlbum)` | Album display objects for AlbumBrowser. **Single O(N_tracks) pass** using `QHash` to group tracks by `(albumArtist\|album)` key; cover thumb and year (first non-zero seen per album, same defensive pattern as the cover thumb) collected in the same pass; no per-album full rescan. Replaces the former O(N_tracks × N_albums) three-pass algorithm. Result sorted by albumArtist ascending, then year descending, then albumTitle ascending (case-insensitive); unknown-year albums (`year == 0`) sort last within their artist group. |
| `buildLibraryTree(activeGenres)` | **Single-pass** tree builder: returns `[ { genre, artists: [ { name, albums: [{title}] } ] } ]` for `LibraryData._rebuildTree()`. One O(N_tracks) scan replaces the former N_genres + N_artists separate full-list scans. |
| `coverThumbForAlbum(album, albumArtist)` | Base64 thumbnail for an album |
| `libraryRefreshed()` signal | Emitted after cache load or scan complete |

### Library cache format — `Topaz.library.json`

Stored alongside `Topaz.config` in `QStandardPaths::AppConfigLocation`.

```json
{
  "version": 1,
  "tracks": [
    {
      "id":           "550e8400-e29b-41d4-a716-446655440000",
      "filePath":     "C:/Music/Electronic/Techno/Artist/Album/01_Track.flac",
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

**Cover storage**: `coverThumb` is populated for the first track of each
`(albumArtist, album)` pair; all other tracks have an empty string.
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
   ├── walk folders (recursive per config)
   ├── for each *.mp3 / *.flac / *.opus:
   │     TagReader::read(path, needCover)
   │     genre filter (case-insensitive match)
   │     assign stable UUID from cache or new QUuid
   │     deduplicate covers: one thumb per (albumArtist, album)
   │     emit scanProgress(done, total)
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
               LibraryScanner.statCheck()
               │  validate each cached entry (file exists, lastModified unchanged)
               │  find new files in configured folders
               │  remove deleted entries
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
        { "path": "C:/Music/Electronic", "includeSubfolders": true  },
        { "path": "C:/Music/Jazz",       "includeSubfolders": false }
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
        "transportAccess": "nothing"
    },
    "bigCoverPane": {
        "x": 100, "y": 100, "width": 400, "height": 400, "screenName": "DISPLAY1"
    },
    "tagInfoPane": {
        "x": 100, "y": 100, "width": 460, "height": 230, "screenName": "DISPLAY1"
    }
}
```

Settings are grouped into a nested object per `SetupDialog` tab (`crossfade`,
`autoPlay`); genres/folders/window-layout stay flat at the top level. The
`AppConfig` property/method names (`crossfadeEnabled`, `crossfadeSeconds`,
`autoPlayQueueHorizon`, and their setters) are unchanged by this grouping — only the
on-disk JSON shape differs. `bigCoverPane`/`tagInfoPane` are also nested; unlike the
others, their *presence* in the file (not a stored bool) is what "configured" means —
absent means that pane has never been positioned yet, so `Main.qml` uses a centered
default instead of its saved `X`/`Y` (see UC-17/UC-18).

### AppConfig public API

| Method | Description |
|--------|-------------|
| `addGenre(name)` | Append genre (deduplicates case-insensitively); auto-saves. |
| `removeGenreAt(index)` | Remove genre by index; auto-saves. |
| `clearGenres()` | Remove all genres; auto-saves. |
| `addFolder(rawPath, includeSubfolders)` | Append folder (deduplicates by path); auto-saves. |
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
| `bigCoverPaneConfigured` / `bigCoverPaneX` / `Y` / `Width` / `Height` | Read-only; the detachable BigCoverWindow pane's last-saved geometry (defaults `400`×`400`, `configured` starts `false`). See UC-17. |
| `saveBigCoverPaneGeometry(x, y, width, height, screenName)` | Persists the pane's geometry after a move/resize settles; `screenName` is stored for completeness/debugging but not re-exposed as its own property. Auto-saves. Called from `Main.qml`'s `Loader` on `FloatingPane.geometrySettled()`. |
| `tagInfoPaneConfigured` / `tagInfoPaneX` / `Y` / `Width` / `Height` | Read-only; the detachable TagInfoWindow pane's last-saved geometry (defaults `460`×`230`, `configured` starts `false`). Same convention as `bigCoverPane*` above. See UC-18. |
| `saveTagInfoPaneGeometry(x, y, width, height, screenName)` | Persists the pane's geometry after a move/resize settles. Same calling convention as `saveBigCoverPaneGeometry`. |
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
      +ratingsReady bool
      +loadCacheAndStartStatCheck()
      +startFullScan()
      +genres() QStringList
      +artistsForGenre(genre) QStringList
      +albumsForArtist(artist, genre) QStringList
      +filteredAlbums(activeGenres, artist, album) QVariantList
      +buildLibraryTree(activeGenres) QVariantList
      +autoPlayCandidatePool(activeGenres, considerGenre, considerRating, minimumRating) QVariantList
      ~libraryRefreshed()
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
2. `trackMA.onPositionChanged` sets `trackRow.Drag.active = true`, calls `engine.setDragCopyCursor()` to display a system-wide `DragCopyCursor` (➕ with arrow), and on every subsequent `positionChanged`, updates `Drag.hotSpot` to the cursor's current position in `trackRow`-local coordinates:
   ```
   scenePt = mapToItem(null, mouse.x, mouse.y)   // cursor in scene space
   rowPt   = trackRow.mapToItem(null, 0, 0)       // trackRow origin in scene space
   Drag.hotSpot = scenePt - rowPt                 // hotspot follows cursor
   ```
   `trackRow` itself never moves from its layout position. The hotspot tracking is what causes Qt's drop system to report the drag to DropAreas under the actual cursor.
3. As the cursor enters `PlaybackQueue`, its `DropArea.containsDrag` becomes `true` — the panel highlights in secondary colour.
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
- **Minimal engine reference in `AlbumCard`**: `engine` is an optional `property var` on `AlbumCard`, used only for double-click add-to-queue and the drag cursor override via `setDragCopyCursor` / `restoreOverrideCursor`. `AlbumBrowser` itself has no engine reference. Setting the cursor via a C++ invokable (`QGuiApplication::setOverrideCursor`) is necessary because a QML `cursorShape` binding on `trackMA` is ineffective once the mouse leaves the `MouseArea`'s bounds during a drag — the global override persists regardless of which item is under the cursor.

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
| `addTrack(map)` | invokable | Append a single track map to the queue. If `activePlaylistName` is set **and** `playlistLocked` is `false`, calls `playlistManager.appendTrack()` to persist the change. |
| `addTracks(list)` | invokable | Batch-append a QVariantList of track maps. Calls `appendTrack` for each new entry when a playlist is active and not locked. |
| `removeAt(index)` | invokable | Remove track at given queue index. Captures `filePath` before removal; calls `playlistManager.removeTrackByPath()` when a playlist is active and not locked. |
| `moveUp(index)` | invokable | Swap track with predecessor (not allowed on playing track). Calls `playlistManager.rewritePlaylist()` when a playlist is active and not locked. |
| `moveDown(index)` | invokable | Swap track with successor (not allowed on playing track). Calls `playlistManager.rewritePlaylist()` when a playlist is active and not locked. |
| `moveTrack(from, to)` | invokable | Move any non-playing track from one queue index to another in a single step. Updates `m_currentIndex` if the currently playing track falls in the shifted range. Uses `QAbstractItemModel::beginMoveRows` / `endMoveRows` so the bound `ListView` animates the reorder automatically. Calls `playlistManager.rewritePlaylist()` when a playlist is active and not locked. |
| `clearQueue()` | invokable | Stop playback, empty the queue, clear `activePlaylistName`, and reset `playlistLocked` to `false`. |
| `setActivePlaylistName(name)` | invokable | Set the active playlist file name (e.g. `"GothicRock01.xml"`). Resets `playlistLocked` to `false`. Called from `NewPlaylistDialog` after successful creation, and from the load-playlist flow. |
| `setPlaylistLocked(locked)` | invokable | Set the lock state. When unlocked (`false`), immediately calls `playlistManager.rewritePlaylist()` so the file reflects any changes made while locked. |
| `setCurrentRating(rating)` | invokable | Set the current track's rating (1-10; no-op otherwise or if no track is loaded). Updates the queue entry and calls `RatingCache::setRating(genre, ratingId, rating)` to persist immediately. |
| `trackList()` | invokable | Return all queued tracks as `QVariantList` of maps (`filePath`, `title`, `artist`, `albumArtist`, `album`, `trackNumber`, `durationMs`) — used by `PlaylistManager.createPlaylist()` |
| `setDragCopyCursor()` | invokable | Calls `QGuiApplication::setOverrideCursor(Qt::DragCopyCursor)` — sets the system-wide drag cursor so no child `MouseArea` can override it. Called by `AlbumCard` the moment a drag gesture starts (> 8 px threshold). |
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
| `<track>/<location>` | `TrackInfo.filePath` | Drive letter stripped: `C:/Music/x.flac` → `/Music/x.flac` |
| `<track>/<title>` | `TrackInfo.title` | Falls back to file name if empty |
| `<track>/<creator>` | `TrackInfo.albumArtist` or `TrackInfo.artist` | XSPF maps `creator` to track artist |
| `<track>/<album>` | `TrackInfo.album` | |
| `<track>/<trackNum>` | `TrackInfo.track` | Omitted when 0 |
| `<track>/<duration>` | `TrackInfo.duration` | Milliseconds, as required by XSPF |

**Location portability**: the Windows drive letter is stripped so that playlists
can be loaded even if the drive letter changes (e.g. external drive reassigned
from `E:` to `F:`).  When loading a playlist (future), Topaz will search
configured folders for the relative path.

### Public API

| Method | Description |
|---|---|
| `playlistDirectory()` | Returns (and creates) the absolute playlist folder path. |
| `playlistExists(name)` | `true` when `<name>.xml` already exists in the playlist folder. |
| `createPlaylist(name, tracks)` | Write a new XSPF file. Returns empty string on success or a human-readable error string (name empty, already exists, write failure). Receives the track list from `PlaybackEngine.trackList()`. |
| `appendTrack(nameWithExt, map)` | Parse the existing XSPF file, append one `<track>` entry, and rewrite. `nameWithExt` includes the `.xml` extension. Accepts both `"number"` and `"trackNumber"` map keys for the track number. Returns `true` on success. |
| `removeTrackByPath(nameWithExt, filePath)` | Parse the existing XSPF file, remove the first `<track>` whose `<location>` matches the stripped `filePath`, and rewrite. Returns `true` when a track was removed. |
| `rewritePlaylist(nameWithExt, tracks)` | Overwrite the entire XSPF file with the given ordered track list. Used after any reorder operation (`moveUp`, `moveDown`, `moveTrack`) and when the playlist lock is turned off. The playlist `<title>` is derived from the file's base name. Returns `true` on success. |
| `loadPlaylist(filePath)` | Accepts a local path or a `file://` URL. Parses the XSPF, resolves every relative `<location>` (no drive letter) by checking all mounted volumes via `QStorageInfo::mountedVolumes()`. Tracks whose file cannot be found on any volume are silently skipped. Returns a `QVariantMap` with `"fileName"` (base name + `.xml`) and `"tracks"` (QVariantList of resolved track maps ready for `PlaybackEngine.addTracks()`). |

### Example output

```xml
<?xml version="1.0" encoding="UTF-8"?>
<playlist version="1" xmlns="http://xspf.org/ns/0/">
  <title>My Playlist</title>
  <trackList>
    <track>
      <location>/Music/Techno/Artist/Album/01_Track.flac</location>
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
8. Dialog closes automatically.

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
- **Relative location**: the drive letter is stripped from all `<location>`
  entries so playlists are portable when the music drive letter changes.
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

1. User clicks **LOAD**.
2. If `engine.activePlaylistName ≠ ""` (a playlist is currently active): `engine.clearQueue()` is called first — identical to the REMOVE use case.
3. `loadPlaylistDialog.currentFolder` is set to `playlistManager.playlistDirectory()` (the folder where new playlists are saved).
4. The native file-open dialog opens with title **"Select a XSPF Playlist"** and filter `*.xml`.
5. User selects an `.xml` file and confirms.
6. `loadPlaylistDialog.onAccepted` calls `playlistManager.loadPlaylist(selectedFile)`.
7. `PlaylistManager.loadPlaylist()` parses the XSPF, then for each `<track>`:
   a. Calls `resolveLocation(location)` which iterates `QStorageInfo::mountedVolumes()` and prepends each volume root to the relative path.
   b. If the resulting absolute path exists → included in the result.
   c. If not found on any volume → silently skipped.
8. `engine.addTracks(result.tracks)` adds the found tracks to the queue.  Because the queue was empty, `PlaybackEngine` auto-plays the first track.
9. `engine.setActivePlaylistName(result.fileName)` sets the display name in the `PlaybackQueue` header.

### Alternate: All tracks missing

If no tracks resolve successfully, `result.tracks` is empty.  `addTracks` is not called; queue stays empty and nothing plays.  No error dialog is shown (silent skip by design).

### Alternate: Partial tracks missing

Only the found tracks are added; the missing ones are silently omitted.  The loaded playlist file on disk is unchanged.

### Design decisions

- **Path resolution via `QStorageInfo`**: probing only real mounted volumes (not all 26 drive letters) is both faster and more reliable.  The relative path format `/Music/foo.flac` is prepended with each volume root in turn.
- **TagReader call on load**: XSPF does not store bitrate or exact duration. During `loadPlaylist()`, `TagReader::read(path, false)` is called for each resolved file to retrieve the actual bitrate, duration, and any tag fields that were absent or empty in the XSPF. Cover thumbnail generation is skipped (`generateCoverThumb = false`) to keep loading fast; the `NowPlaying` panel loads the cover asynchronously from the audio file via `TagReader::readRawCover` when the track starts playing.

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
3. The scan loop inside `LibraryScanner::scanDirectory()` (and the cache-validation loop at the top of `statCheck()`) checks this flag once per file and returns as soon as it's set (checkpoint latency ≈ one file's tag-read), unwinding out of `fullScan()`/`statCheck()` without writing a partial result to `Topaz.library.json` and without emitting `scanCompleted()`.
4. `LibraryModel` then calls `QThread::quit()` and waits (up to 3 s) for the now-unwound worker thread to exit its event loop.
5. Once the thread has stopped, `LibraryModel`'s destructor completes and the application closes normally.

### Alternate: worker doesn't stop within the wait timeout

If the wait still times out (e.g. a single slow file read on unresponsive I/O), the destructor detaches the `QThread` (`setParent(nullptr)`) instead of allowing `~QObject` to delete a still-running thread, which Qt treats as a fatal error. The detached thread is reclaimed by the OS when the process exits.

### Design notes

- Cancellation uses a plain `std::atomic<bool>` (`LibraryScanner::m_cancelRequested`) polled by the worker loop, not a queued signal/slot — a queued call would never be processed while the worker thread is busy inside a long-running `fullScan()`/`statCheck()` call, since queued slots only run when that thread's event loop is free.
- The flag is reset to `false` at the start of both `fullScan()` and `statCheck()`, so a cancellation triggered by one shutdown attempt doesn't permanently block a future scan.
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
both decks together when `m_crossfading` is true, so a paused fade doesn't leave the
standby deck silently continuing to ramp.

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
4. If the queue is empty, `pickNextCandidate()` (below) selects one track and
   `PlaybackEngine::addTrack()` adds it — `addTrack`'s existing auto-play-when-empty
   behavior starts it playing immediately, satisfying "add the first track immediately
   and play it" with no `PlaybackEngine` changes. If no candidate exists at all (the
   library has nothing matching the current filters), `start()` returns without
   activating — the button stays green.
5. Otherwise (queue already has content), `m_active` becomes `true` and the poll timer
   starts at the configured interval — no immediate top-up; the first addition beyond
   an empty-queue kickstart always happens on the first tick (see below).
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

### Alternate: playback stalls at end of queue

`advanceToNext()`'s existing "no next track" branch (queue exhausted) now also emits a
new `PlaybackEngine::queueExhausted()` signal — needed because neither
`queueCountChanged` nor `currentIndexChanged` fires in that branch, so nothing would
otherwise notice playback has silently stopped. `AutoPlayController::onQueueExhausted()`
reacts immediately (not on the next poll tick, since music has already stopped):
`pickNextCandidate()`, and if found, `addTrack()` followed by an explicit `playAt()` on
the new index; if not found, `stop(true)`.

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

A frameless (`flags: Qt.Window | Qt.FramelessWindowHint`) `Window` base:
- `default property alias contentData: contentItem.data` — subclasses just nest
  their content directly inside `FloatingPane { ... }` (see `BigCoverWindow.qml`).
- **Move**: a whole-pane `MouseArea`'s left-press calls `Window.startSystemMove()` —
  an OS-native interactive move (Qt 6.8+; confirmed supported on Windows), not manual
  x/y math, so it's correct across monitors with different DPI/scaling without any
  extra code. `cursorShape: Qt.PointingHandCursor` + `hoverEnabled: true` on the same
  `MouseArea`, matching `NowPlaying`'s Play/Pause cursor exactly.
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
`BigCoverWindow`) — free resize via `startSystemResize()`, default size 460×230.
Went through two rounds of shrinking: 460×420 (original) → 460×280 → 460×230, each
time reducing the default and tightening internal padding/spacing/the specs-box
height, since content sitting in a top-anchored `Column` with no explicit height
never grows to fill the pane — any extra height just shows through as empty themed
background below the technical-specs box. **The pane's *saved* geometry
(`Topaz.config`'s `tagInfoPane` entry) always wins over this default once the user
has resized the pane even once** — confirmed directly from a real user's config
during round 2 (a genuine 1658×592 saved size on real hardware) — so shrinking the
default only affects a pane that's never been touched; an already-resized pane needs
a manual resize-down to benefit from a tighter default.

**Content scales with pane size**: a single computed property,
```qml
readonly property real scaleFactor:
    Math.max(0.55, Math.min(2.2, Math.min(width / 460, height / 230)))
```
multiplies every `font.pixelSize` and layout padding/spacing value in the pane. It's
derived from *both* width and height (via `Math.min`) so a pane resized narrow-but-tall
or short-but-wide doesn't overflow in the constrained dimension; clamped to `[0.55,
2.2]` so text never becomes unreadably tiny or absurdly oversized at extreme sizes.

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
(no saved geometry yet) is 460×230, centered on the primary screen.

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

