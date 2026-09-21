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
| **Goal** | User defines the list of genre names used to organize/scan the library, and chooses which subset of them appear as toggle buttons in `GenreBar`. |
| **Actor** | User |
| **Precondition** | Setup dialog is open on the GENRES tab. |
| **Trigger** | User interacts with genre management controls. |

Two related but distinct lists are involved: `AppConfig.genres` (up to 40, the full
configured set — drives library scanning/filtering via
`LibraryModel::startFullScan()`/`startStatCheck()`, and is what the SetupDialog grid
manages) and `AppConfig.enabledGenres` (a subset of it, up to 30, the set actually
shown as `GenreBar` buttons). Deliberately kept separate so hiding a genre's button
never excludes its tracks from the scanned library — only from the `GenreBar` filter
row.

### Normal Flow — Add genre

1. User types a genre name into the text input (e.g. "Techno").
2. User presses **Enter** or clicks **ADD**.
3. `SetupDialog.doAddGenre()` calls `appConfig.addGenre(name)`.
4. `AppConfig` performs a case-insensitive duplicate check, rejects the add if
   `genres` is already at its 40-entry ceiling, otherwise appends the name to
   `m_genres`. If fewer than 30 genres are currently enabled, the new genre is
   also added to `m_enabledGenreSet` (so it behaves exactly as before for anyone
   under the enabled cap — new genres just work). Emits `genresChanged` (and
   `enabledGenresChanged` if newly enabled), auto-saves to `Topaz.config`.
5. `LibraryData` receives `genresChanged`/`enabledGenresChanged` →
   `rebuildGenreModel()` clears and repopulates `genreModel` from
   `appConfig.enabledGenres` (not the full `genres` list).
6. `GenreBar` `Repeater` re-evaluates → the new genre button appears immediately,
   if it was auto-enabled.

### Normal Flow — Enable/disable a genre in GenreBar

1. In the SetupDialog GENRES grid, each cell has a small checkbox in its top-right
   corner reflecting `appConfig.isGenreEnabled(name)`.
2. User clicks the checkbox → `appConfig.setGenreEnabled(name, !current)`.
3. If enabling and `enabledGenres` is already at its 30-entry cap, the call is
   rejected (returns `false`, no state change) — the checkbox simply doesn't
   flip. Unchecked checkboxes are visually dimmed and their cursor reverts to
   the default arrow once the cap is reached, so the "why didn't this work"
   case still reads as blocked rather than broken.
4. Otherwise `m_enabledGenreSet` is mutated, `enabledGenresChanged` emitted,
   config auto-saved.
5. `LibraryData.rebuildGenreModel()` fires → the genre's `GenreBar` button
   appears or disappears immediately. The genre itself remains fully configured
   and scanned regardless of this state.
6. Clicking the checkbox does not also select the cell for deletion (its own
   `MouseArea` sits above the cell-wide selection `MouseArea`, `z: -1` on the
   latter — the same layering convention `SetupDialog`'s folder list uses for
   its per-row subfolders checkbox).

### Normal Flow — Delete selected genre

1. User clicks a genre cell in the grid to select it (highlighted in `secondaryContainer` colour).
2. User clicks **DELETE SELECTED**.
3. `appConfig.removeGenreAt(index)` removes the entry from `m_genres` and, if it
   was enabled, also removes it from `m_enabledGenreSet`; emits `genresChanged`
   (and `enabledGenresChanged` if it had been enabled), auto-saves.
4. `LibraryData.rebuildGenreModel()` fires; the button disappears from `GenreBar`
   if it had been enabled.

### Normal Flow — Reorder a genre

1. User drags a genre cell's drag handle to a new position in the grid.
2. `appConfig.moveGenre(from, to)` moves the entry within `m_genres` (a plain
   list `move`, so no gap is ever created), emits `genresChanged` (and
   `enabledGenresChanged` only if the derived `enabledGenres()` value
   actually changed), auto-saves.
3. `LibraryData.rebuildGenreModel()` fires whenever `enabledGenresChanged`
   was emitted → `GenreBar` buttons re-render in the new order.

See **UC-33** for the full drag mechanism (2D hit-testing, drop indicator,
selection-index remapping).

### Normal Flow — Delete all genres

1. User clicks **DELETE ALL**.
2. `appConfig.clearGenres()` empties both `m_genres` and `m_enabledGenreSet`, emits `genresChanged` (and `enabledGenresChanged` if any had been enabled), auto-saves.
3. `GenreBar` shows empty state; `LibraryTree` and `AlbumBrowser` show their no-genres hints.

### Rules

- Duplicate names (case-insensitive) are silently ignored.
- Genre names are stored in their original casing and displayed upper-cased in `GenreBar`.
- **Configured genres** (`AppConfig.genres`): capped at 40 (`addGenre()` silently
  rejects beyond that, same convention as the duplicate check). The GENRES tab in
  `SetupDialog` lays out all configured genres in a fixed 5-column × 8-row grid
  (40 cells) sized to always fit without a scrollbar.
- **Enabled genres** (`AppConfig.enabledGenres`, persisted separately as
  `enabledGenres` in `Topaz.config`): capped at 30, matching `GenreBar`'s own fixed
  "Grid 30" (3 rows × 10 columns) capacity exactly, so it can never receive more
  entries than it has room for. Display order always follows `genres`' order —
  membership is tracked as a plain set (`QSet<QString>`), never a separately
  ordered list, so it can't desync from add/remove/reorder of the configured list.
  The user controls that order directly by dragging genre cells in the GENRES
  grid — see UC-33.
- **Migration**: config files predating this feature have no `enabledGenres` key.
  On load, `AppConfig` treats that as "enable every configured genre, up to 30" —
  every pre-existing install keeps showing exactly the `GenreBar` buttons it did
  before, until the user configures more than 30 and starts using the checkboxes.

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
   `includeSubfolders: true, active: true`, emits `foldersChanged`, and auto-saves.
6. The new row appears in the folder list with both the **ACTIVE** and
   **SUBFOLDERS** checkboxes ticked. If the folder's volume is later
   unmounted (disk unplugged, moved elsewhere), the row dims and shows a
   "not connected" indicator instead of removing itself from the list —
   `AppConfig::folders()` still returns the entry, just with an empty
   resolved `path` and `available: false` (see "Config file format" below).

### Normal Flow — Toggle active

1. User clicks the checkbox in the **ACTIVE** column of any folder row.
2. `appConfig.setFolderActive(index, !current)` flips the flag, emits
   `foldersChanged`, auto-saves.
3. The checkbox visual updates immediately, and the row dims (same as an
   unavailable/disconnected-volume row) to signal it's excluded from
   scanning. The folder itself stays configured — this does not delete or
   forget it, and does not trigger an immediate rescan: it takes effect the
   same way toggling SUBFOLDERS or adding/removing a folder already does,
   on the next scan (manual rescan button or app restart) — see UC-05.

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
- The `active` flag also defaults to `true` when a folder is first added, and
  for every folder in a config file predating this feature (`AppConfig::load()`
  treats a missing `active` key as `true`) — every pre-existing monitored
  folder keeps scanning exactly as before until the user unchecks it.

### Design notes

- **Auto-rescan on close**: `SetupDialog` tracks a session-scoped
  `_foldersDirty` flag, set explicitly by each of the 5 folder-editing
  actions above (add / remove / clear / toggle SUBFOLDERS / toggle
  ACTIVE) right where each one calls its `AppConfig` method. Deliberately
  *not* inferred from `AppConfig::foldersChanged` firing anymore — that
  signal is also emitted by `AppConfig::refreshFolderAvailability()`
  after any background scan completes (see UC-07's live-refresh of this
  same folder list), which is not a user edit and must not queue an
  extra rescan on close. (Before UC-07's parent-directory watch existed,
  `foldersChanged` really was only ever emitted by these 5 actions, so a
  blanket `Connections` listener was equivalent and simpler; that
  invariant no longer holds.) Deliberately does **not** react to
  `genresChanged`/other settings changes elsewhere in the dialog. Reset
  to `false` in `onAboutToShow` (so only changes made *during the
  current open session* count) and consumed in `onClosed`, which calls
  `libraryModel.startFullScan()` if the flag is set — `closePolicy:
  Popup.NoAutoClose` means the header's ✕ button is the dialog's only way
  to close, so this is a single, reliable hook. See UC-05 for the
  resulting scan.

---

## UC-05 Scan Audio Directories

| Field | Detail |
|-------|--------|
| **Goal** | Topaz scans all configured folders for audio files whose genre matches a configured genre and populates the library. |
| **Actor** | User / System |
| **Precondition** | At least one genre and one folder are configured in `AppConfig`. |
| **Trigger** | User clicks **SCAN FOLDERS** in `BottomBar`, OR startup/watcher stat-check finds new/changed files, OR `SetupDialog` closes after a FILE MONITORING change (see UC-04's "Auto-rescan on close"). |

### Normal Flow — Full scan

1. `BottomBar` emits `scanRequested()`.
2. `Main.qml` calls `libraryModel.startFullScan()`.
3. `LibraryModel` copies genres from `AppConfig` and folders from its own
   `activeFolders()` helper — `AppConfig.folders()` filtered down to entries
   whose `active` key (default `true`) is truthy — then emits
   `_requestFullScan` to the worker thread. An inactive folder's files are
   excluded from discovery entirely (not scanned, not watched) until
   reactivated and rescanned; `LibraryScanner` itself stays unaware of the
   active/inactive distinction, same as it's unaware of which genres are
   `GenreBar`-enabled vs merely configured (see UC-03). The startup/watcher
   stat-check below uses the same `activeFolders()` filter.
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
- `BottomBar` SCAN FOLDERS button is visually disabled (label changes to
  "SCANNING…") while a scan is in progress, for every trigger listed
  above — including the file-system-watcher's own debounced auto-rescan
  (UC-07), which `LibraryScanner::performScan()` surfaces via a
  `scanStarted()` signal (`LibraryModel::onScanStarted()`) since that
  trigger runs entirely on the worker thread without `LibraryModel`
  ever having requested it itself.

### Genre Matching Rule (Version 2)

The genre tag value read from the audio file (TCON for MP3, GENRE for FLAC/Opus) is
compared **case-insensitively** against the configured genre names in `AppConfig`.

```
File tag:    "techno"        → normalised: "techno"
Configured:  ["Techno", …]  → normalised: ["techno", …]
Result:      match → include
```

Each audio file must have **exactly one genre** that matches a configured genre.

**Multi-genre (delimited) tags — first genre wins.** `TagReader::firstGenre()`
(`tagreader.h`/`.cpp`) splits the raw tag value on the *earliest* occurrence of any
of four delimiters — `;`, `/`, `,`, or a raw NUL byte (`0x00`) — and keeps only the
text before it, trimmed:
```
File tag:    "Rock/Pop;Jazz"  → split at '/' (earliest) → "Rock"
Configured:  ["Rock", …]      → normalised: ["rock", …]
Result:      match → include
```
Called once at each of `TagReader`'s three genre-assignment points (MP3's `TCON`,
FLAC's and Opus's `GENRE` Vorbis comment) — no other file needed changes, since
`TrackInfo::genre` is only ever *read* everywhere else. The NUL case is ID3v2.4's
own spec-defined mechanism for a `TCON` frame containing multiple genre values —
several tagger GUIs (e.g. Mp3tag) render this as a visual placeholder (often `\\`)
rather than a literal null character, which is how such tracks tend to be
noticed in the first place. `decodeTextFrame()`'s byte→`QString` conversion is
length-based for all four ID3v2 text encodings (never relies on NUL-termination),
so an embedded separator NUL survives decoding intact — `firstGenre()` is the
single point that then strips it back out. Before this, a `TCON` value like
`"Rock\0Pop"` didn't just look wrong in a tag editor — it silently matched no
configured genre at all (a raw NUL can never appear in a user-typed genre name),
making the track invisible to every genre-scoped view (`filteredAlbums`,
`buildLibraryTree`, `autoPlayCandidatePool`, etc.) without any visible error.

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
| **Goal** | Topaz automatically detects when audio files are added or removed while the application is running — including a configured root folder itself being deleted. |
| **Actor** | System |
| **Precondition** | At least one folder is configured; a scan has completed. |
| **Trigger** | `QFileSystemWatcher::directoryChanged` fires. |

### Normal Flow

1. `QFileSystemWatcher` (owned by `LibraryScanner` on the worker thread)
   watches every configured folder's root path, **plus each root's own
   parent directory**. The parent watch exists specifically because
   `QFileSystemWatcher` does not reliably fire `directoryChanged` when
   the *watched directory itself* is deleted — only when something
   changes *inside* a still-existing watched directory. Watching the
   parent turns "the configured folder itself was deleted" into an
   ordinary "child removed from a watched directory" event, the same
   already-reliable mechanism that detects e.g. an Artist folder
   appearing/disappearing directly under a watched Genre root. Computed
   fresh on every `performScan()` call (`libraryscanner.cpp:234`) as
   pure string manipulation (`QFileInfo(path).absolutePath()`) — no
   extra filesystem access, and it runs unconditionally for every
   configured folder even during a UC-31 scoped rescan, so it needs no
   caching. Folders sharing one parent (the common case — most users put
   every Genre folder directly under one Music root) naturally dedupe to
   a single extra watched path.
2. OS signals a directory change.
3. A 2-second debounce timer (re)starts; rapid successive changes are coalesced.
4. Timer fires → `statCheck` is triggered automatically.
5. Updated library is emitted via `scanCompleted` → `LibraryModel::
   onScanCompleted()` applies the new track list **and** calls
   `AppConfig::refreshFolderAvailability()` (a one-line `emit
   foldersChanged()`, `AppConfig.h`) so Setup Dialog's FILE MONITORING
   list — if open — immediately shows the folder as disconnected/missing
   (or reconnected) instead of only reflecting reality after the next
   restart. This is the *only* non-edit source of `foldersChanged`;
   `SetupDialog.qml`'s `_foldersDirty` auto-rescan-on-close tracking
   (UC-04) is deliberately set by its 5 explicit edit actions rather than
   inferred from the signal, so a background scan completing while the
   dialog happens to be open never triggers a spurious extra rescan on
   close.

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
├── HiResAudioLogo       C++ QML_ELEMENT + QML_SINGLETON — stateless, same pattern as WindowChrome; Q_INVOKABLE url() returns a file:// URL for "Hi-Res_Audio.svg" only if that file exists directly beside Topaz.exe (QCoreApplication::applicationDirPath()), else "". The logo is trademarked and Topaz has no redistribution rights, so it is deliberately never bundled as a Qt resource/compiled into Topaz.exe — TopBar.qml's Hi-Res Audio badge (shown next to "TOPAZ JUKEBOX" while the current track is FLAC) only appears if the user supplies their own copy at runtime.
├── AppConfig           C++ QML_ELEMENT — reads/writes Topaz.config JSON; exposes genres & folders
├── LibraryModel        C++ QML_ELEMENT — QAbstractListModel + scanner orchestration
│                         property AppConfig appConfig
│                         Q_INVOKABLE: loadCacheAndStartStatCheck(), startFullScan()
│                         Q_INVOKABLE queries: genres(), artistsForGenre(), albumsForArtist(), filteredAlbums(), buildLibraryTree(), searchLibrary()  — see UC-21; buildStandaloneTrackCards()  — see UC-22
├── LibraryData.qml     shared state model — genre toggle, selection, tree builder
│                         property AppConfig appConfig
│                         property LibraryModel libraryModel
│                         property string activeTab  (one-way bound from Main.qml's own activeTab; suppresses genre auto-selection in toggleGenre() while SEARCH is active, see UC-01/UC-21)
│                         property int albumScrollIndex, property real albumScrollOffset  (AlbumBrowser's top-visible-row anchor, persisted here so it survives the Loader swap; index-based, not a raw contentY pixel, because AlbumCard's content-derived height makes contentHeight only an estimate — see UC-12/UC-21)
├── SearchData.qml      independent search state model — see UC-21 (deliberately not coupled to LibraryData beyond one read-only property)
│                         property LibraryModel libraryModel
│                         property var activeGenreNames  (one-way bound from LibraryData.activeGenreNames by Main.qml)
│                         property string query, mode ("all"/"artists"/"albums"/"tracks"), property bool considerGenre, property bool matchWholeWord, property var results
│                         property int resultScrollIndex, property real resultScrollOffset  (SearchResultBrowser's top-visible-row anchor, persisted here so it survives the Loader swap; index-based for the same reason as albumScrollIndex/Offset above — see UC-12/UC-21)
├── PlaylistsData.qml   independent playlists-tab state model — see UC-22 (deliberately not coupled to LibraryData/SearchData beyond one read-only property)
│                         property PlaylistManager playlistManager, property LibraryModel libraryModel
│                         property var engine  (one-way ref to PlaybackEngine, read-only — used only to recognize the playlist currently active in the queue)
│                         property var playlists, property string selectedFileName/selectedDisplayName, property var albums, property var selectedRawTracks, property var selectedMissingTracks
│                         property int resultScrollIndex, property real resultScrollOffset  (PlaylistViewer's top-visible-row anchor, persisted here so it survives the Loader swap; index-based for the same reason as LibraryData.albumScrollIndex/Offset — see UC-12/UC-22)
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
├── SetupDialog.qml     Modal setup popup (tabs: GENRES | FILE MONITORING | PLAYBACK | AUTO PLAY | AUDIO VISUALIZER | MILKDROP, see UC-15 / UC-14 / UC-19 / UC-20)
├── NewPlaylistDialog.qml Modal popup — user enters a name; calls PlaylistManager.createPlaylist(); shows MessageBox on name collision
│                         signal playlistCreated()  ← emitted on success; Main.qml calls playlistsData.refreshPlaylists() so the PLAYLISTS tab stays live even while already active, see UC-22
├── MessageBox.qml      Themed single-message popup with OK button; reusable across the application
├── MissingTracksDialog.qml Informational popup listing tracks (artist/album/title/location)
│                         a playlist LOAD couldn't find on disk; opened from both NowPlaying and
│                         PlaylistViewer's LOAD flows via a missingPlaylistTracks(missingTracks)
│                         signal — see UC-10/UC-22
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
└── BottomBar.qml       Footer toolbar  height 56 px  (signal scanRequested; scanning property; autoPlayReady property — bound to libraryModel.ratingsReady, gates whether AUTO PLAY is clickable at all (together with autoPlay.genreRequirementMet/ratingRequirementMet, but those only while no session is running); autoPlay property — bound to the AutoPlayController instance; button color reads autoPlay.active (green/red traffic light), click calls autoPlay.toggle(), see UC-16)
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
| `SystemVolumeController` | `systemvolumecontroller.h/cpp` | OS master-volume control with live sync: Core Audio COM on Windows, native libpulse (PulseAudio / PipeWire) on Linux |

### SystemVolumeController — OS master volume (Windows: Core Audio, Linux: libpulse)

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

**Linux port, step 1**: the entire Windows COM implementation above (from the
`<windows.h>`/`<mmdeviceapi.h>`/`<endpointvolume.h>` includes through the end of
`setVolume()`) is wrapped in `#ifdef Q_OS_WIN` in `systemvolumecontroller.cpp`,
alongside a `#else` Linux branch with its own, differently-shaped `Impl` (only this
one `.cpp` ever touches it, so the header stays free of both Windows and libpulse
headers).

**Linux implementation — native libpulse client** (PulseAudio, and PipeWire through
its pulseaudio-compatible server `pipewire-pulse`; links `libpulse` via
`pkg_check_modules(PULSE ... libpulse)` in `CMakeLists.txt`, needs `libpulse-dev` in
`Dockerfile.linux`, and `libpulse.so.0` + `libpulsecommon-*.so` are bundled into
`deploy-linux/lib/`). It replaced a first version that shelled out to `pactl`
(no live sync, a blocking process spawn per call on the GUI thread, a hard dependency
on that binary, first-channel-only text parsing).

- **Threading.** A `pa_threaded_mainloop` runs libpulse on its own thread. Every
  libpulse callback runs there with the mainloop lock held and therefore never touches
  Qt state directly: like the Windows `IAudioEndpointVolumeCallback` it posts to the
  owner with `QMetaObject::invokeMethod(owner, ..., Qt::QueuedConnection)` (dropped
  safely if the owner is destroyed). The GUI thread takes `pa_threaded_mainloop_lock()`
  before touching the context or the shared fields, and **never waits for a server
  reply**: `setVolume()`/`refresh()` only send a request; the answer comes back through
  the callback path. The static callbacks live in a class named `VolumeChangeCallback`
  in the `.cpp` (the same name as the Windows COM class, because the header already
  declares that name a `friend` to reach the private `applyLevel()`).
- **Flow / live sync.** Connect with `PA_CONTEXT_NOFAIL | PA_CONTEXT_NOAUTOSPAWN`
  (wait for a server that isn't up yet; Topaz never launches a sound server). On
  `READY`: subscribe to SINK + SERVER events → server info → default sink name → that
  sink's info (index + `pa_cvolume`). A SERVER event (default sink switched) repeats
  the lookup, so Topaz **follows the default output device** (which the Windows branch
  does not); a SINK event for the followed sink re-reads its volume — that is the push
  sync for keyboard volume keys, the panel applet and other apps; a sink-removed event
  re-resolves the default sink.
- **Volume mapping.** The reported volume is the **loudest channel** (`pa_cvolume_max`
  / `PA_VOLUME_NORM`), and `setVolume()` uses `pa_cvolume_scale()`, which also sets the
  loudest channel: read and write agree and a left/right balance configured elsewhere
  is preserved (an all-zero sink gets every channel set). Values above 100 % clamp to
  100 in `applyLevel()`. Mute state is not mirrored (as on Windows).
- **Echo suppression.** Server reports arriving < 250 ms after Topaz's own
  `setVolume()` are ignored: they are the echoes of the slider drag itself
  (38, 39, 40 … trailing behind a slider already at 41) and would make it jump back and
  forth. Later changes go through `applyLevel()` normally. `setVolume()` is otherwise
  optimistic (updates `m_volume` + `volumeChanged()` immediately), like Windows.
- **Recovery.** If the connection fails or the server restarts (`FAILED`/`TERMINATED`),
  the GUI thread rebuilds the context after 3 s and keeps retrying every 3 s; one
  warning per outage, not per retry. Destruction clears the callbacks, disconnects, and
  stops (joins) the mainloop thread before the object goes away.
- **Startup value.** `volume()` is seeded asynchronously, a moment after construction
  (Windows seeds synchronously); `refresh()` (called by `TopBar.qml` before the popup
  opens) is now a non-blocking re-query.
- **Diagnostics.** One `qInfo` line when a sink is followed (`SystemVolumeController:
  following PulseAudio sink "<name>" (NN%)`) and a single warning when no server is
  reachable / `setVolume()` finds no sink — useful in tester logs.

**Verification (Linux, real server, no UI):** a throw-away test harness (not in the
repo) built `systemvolumecontroller.cpp` into a tiny `QCoreApplication` against a real
PulseAudio server with two null sinks in a container and confirmed: initial read;
`setVolume` reaching the server; external `pactl` changes pushed live; multi-channel
read + balance-preserving write; following a default-sink switch (and writing to the
new sink only); a 60-step burst with no property bounce; recovery after killing and
restarting the server; and — with an unreachable server — no hang, a single warning,
and a clean destruction. The bundled `deploy-linux/` was also run in a bare
`ubuntu:24.04` container (Xvfb, xcb platform plugin, PulseAudio): `ldd` clean and the
sink volume read at startup.

**Linux port, step 4 (final) — first real Linux build, via Docker Desktop**:
steps 1-3 above were all written and reasoned about blind, with no Linux
environment to actually compile against. Step 4 built a real one —
`Dockerfile.linux` at the repo root (Ubuntu 24.04 base; an official prebuilt
Qt 6.10.2 install via `aqtinstall`, matching the Windows build's own pinned
version, since Ubuntu's own apt-packaged Qt6 is 6.4.2 and too old for
`QQmlApplicationEngine::loadFromModule()` (needs 6.5+) and
`QAudioBufferOutput` (needs 6.8+), both discovered the hard way on the first
real attempt) — and used it to actually run `cmake`/`ninja` against Topaz's
source inside a container for the first time. Every `#ifdef Q_OS_WIN`/
`#else` branch from steps 1-3 (`CMakeLists.txt`'s platform gating,
`SystemVolumeController`, `WindowChrome`, `BassLibrary`, `BassAudioDeck`,
`AppConfig::bassLibraryAvailable()`) compiled and linked correctly on the
first real try — no fixes needed to any of them. Two genuine, previously-
unknown bugs surfaced instead, both now fixed and confirmed to also leave
the Windows build unaffected (rebuilt and smoke-tested after each):

1. **`Qt6::Concurrent` was linked but never `find_package`'d.**
   `CMakeLists.txt`'s `target_link_libraries` included `Qt6::Concurrent`,
   but the `find_package(Qt6 REQUIRED COMPONENTS ...)` call never listed
   `Concurrent` — it happened to work on Windows/MinGW only because some
   other requested component transitively pulled the `Qt6::Concurrent`
   imported target in as a side effect there; Ubuntu's Qt6 packaging (and,
   presumably, any other Qt6 distribution) doesn't guarantee that. Fixed by
   adding `Concurrent` to the `COMPONENTS` list — a genuine cross-platform
   correctness fix, not a platform-gated one.
2. **The Linux executable can't be named `Topaz` (capitalized) like
   Windows' `Topaz.exe` is.** `qt_add_qml_module(topaz URI Topaz ...)`
   generates a companion `Topaz/` directory (matching the QML module URI)
   next to the built executable in the build directory. On Windows this
   never collides with `Topaz.exe` (different name, thanks to the `.exe`
   suffix). On a case-sensitive Linux filesystem, an executable literally
   named `Topaz` collides directly with that same-named directory — the
   linker fails with "cannot open output file Topaz: Is a directory".
   Fixed in `CMakeLists.txt`: `OUTPUT_NAME` is now `Topaz` only on Windows
   (`if (WIN32)`); on Linux it's left as CMake's default, the target's own
   name `topaz` (lowercase) — distinct from the `Topaz/` directory, and a
   more idiomatic lowercase binary name for Linux besides. (This exact
   collision was initially masked, not caught, when first tested through a
   Windows-host bind-mounted directory inside the container — NTFS's
   case-insensitivity leaks through Docker Desktop's file sharing even
   into a Linux container, so `Topaz`/`topaz` looked identical there too.
   Confirmed genuinely case-sensitive, and the fix genuinely verified, only
   after moving the build directory to a Docker named volume — backed by
   the Docker Desktop Linux VM's own real, case-sensitive filesystem, not
   a bind-mounted Windows path.)

With both fixed, a full `cmake -B ... -G Ninja -DCMAKE_BUILD_TYPE=Release &&
cmake --build ...` succeeded end-to-end (249/249) against Qt 6.10.2 on real
Linux/GCC 13.3.0, and the resulting `topaz` binary was smoke-tested via Qt's
`offscreen` QPA platform plugin (no X server in the container) for 5 seconds
with zero `TypeError`/`ReferenceError`/QML-type-loading errors — only
already-known, pre-existing `SetupDialog.qml` layout warnings identical to
every Windows smoke test this project has ever run, plus the *expected*
`SystemVolumeController: pactl get-default-sink failed ... -- volume
unavailable` message (the graceful-degradation path of the original
`pactl`-based Linux implementation, since replaced by the native libpulse
client described above, which degrades the same way with its own warning,
since no real PulseAudio/PipeWire server runs inside the minimal
container). This is the first genuinely verified (not just
statically reviewed) confirmation that the whole Linux port initiative
actually works.

**Linux port, step 5 — real-hardware integration test (Linux Mint 22.2
X11/NVIDIA, Ubuntu Studio Wayland)**: the first test on physical machines
(via the self-contained `deploy-linux/` folder — see `CLAUDE.md`) found OS
volume, library scan, BASS, AUTO PLAY, playlists and the Setup dialog all
working, and four problems:

- **Backup / Restore / Export Playlist could not write** — a real bug, not a
  permissions problem. The three dialogs converted the `FolderDialog`/
  `FileDialog` URL with `substring(8)` after `file:///`, right on Windows
  (`file:///C:/x` → `C:/x`) but wrong on Linux (`file:///media/usb/x` →
  `media/usb/x`, a *relative* path, so Topaz wrote relative to its own
  working directory instead of the chosen folder). Library scanning had
  worked because it hands the raw URL to C++ (`QUrl::toLocalFile()`).
  Fixed in all three dialogs with
  `s.replace(/^file:\/\/(\/(?=[A-Za-z]:))?/, "")`, which drops the third
  slash only when a Windows drive letter follows; `NowPlaying.qml`'s
  `"file:///" + playlistDirectory()` got the matching fix (four slashes on
  Linux). **Rule for new code: never strip `file:///` by a fixed length —
  pass the URL to C++ or use that regex.**
- **No app icon on Linux** — nothing set a window icon (Windows gets it from
  the `app.rc` resource only). `main.cpp` now calls
  `setWindowIcon(QIcon(":/Topaz/app.ico"))` and
  `setDesktopFileName("topaz")` under `#ifndef Q_OS_WIN` (Windows unchanged),
  and `deploy-linux/` ships `topaz.png` + `install-topaz-launcher.sh`
  (`packaging/linux/`), which writes `~/.local/share/applications/topaz.desktop`
  so the app menu/panel/Wayland get an icon too.
- **Config folder was `~/.config/topaz-bin/`** — Topaz never set an
  application name, so Qt derived it from the executable's filename
  (`Topaz.exe` → `Topaz` on Windows; the renamed `topaz-bin` on Linux, which
  also fed `WM_CLASS`/the Wayland app id). `main.cpp` now calls
  `setApplicationName("Topaz")` on every platform (a no-op on Windows, where
  it already resolved to `Topaz`; config stays at `%LOCALAPPDATA%\Topaz\`).
  Linux config/library cache is now `~/.config/Topaz/`; data from the earlier
  test builds under `~/.config/topaz-bin/` is not migrated (`mv` it over).
- **Milkdrop failed on Ubuntu Studio** — that machine's driver could not
  provide the OpenGL 3.3 Core Profile Milkdrop needs (see UC-20 for the
  requirement and the improved failure reporting).
- **Audio Visualizer pane opened but drew nothing on Mint (X11/NVIDIA), while
  working on Ubuntu Studio (Wayland)** — cause **not yet determined**. The
  "Wayland-only" theory is unproven: the two machines also differ in GPU/
  driver and audio server, and the visualizer's audio input
  (`PlaybackEngine::audioBufferAvailable`, `Float`/`Int16` only) and pane
  creation (`FloatingPane` → `WindowChrome::prepareWindow()`) are identical to
  Milkdrop's, which does render on Mint. One-shot terminal diagnostics were
  added to split the possibilities without another blind round-trip:
  `WindowChrome::prepareWindow()` logs the platform, the alpha channel
  requested vs *granted* by the native window, the scene graph's graphics API
  and any scene graph error; `AudioVisualizerController` logs the first audio
  buffer's format, the first non-zero bar level ("analysis works, so it is a
  drawing problem") and — instead of silently skipping — a warning when a
  sample format is unsupported.

### TagReader — supported formats

| Format | Tag standard | Fields read |
|--------|-------------|-------------|
| MP3 | ID3v2.2, ID3v2.3, ID3v2.4 | TIT2, TPE1, TPE2, TALB, TRCK, TCON, TLEN, TYER/TDRC, APIC |
| FLAC | Vorbis Comment + STREAMINFO + PICTURE | TITLE, ARTIST, ALBUMARTIST, ALBUM, TRACKNUMBER, GENRE, DATE |
| Opus | Ogg container; `OpusTags` packet (Vorbis-comment layout) | TITLE, ARTIST, ALBUMARTIST, ALBUM, TRACKNUMBER, GENRE, DATE |

**GENRE/TCON values are run through `TagReader::firstGenre()`** for all three
formats — a delimited or ID3v2.4 NUL-separated multi-genre tag keeps only its
first genre. See "Genre Matching Rule (Version 2)" above (UC-01).

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
| `ratingCount` | Number of tracks in the model with a rating set (`rating > 0`). Recomputed alongside `albumCount` in the same `applyTracks()` pass, and again by `applyRating()` whenever a rating changes at runtime (`updateRatingCount()`). Shown on the About dialog's TOPAZ tab (red dot, `Theme.error` — same accent `PlaylistViewer`'s OFFLINE indicator uses). |
| `applyRating(ratingId, rating)` | invokable. Applies a rating just stored at runtime (a star click / rating deletion in `NowPlaying`, forwarded from `PlaybackEngine::ratingStored` by a `Connections` block in `Main.qml`) to every library track carrying that `ratingId`; `rating` 0 = removed. Updates `ratingCount` and emits `ratingsChanged()`. Before this, ratings reached `m_tracks` only through scan-time enrichment, so a rating given during a session was invisible to AUTO PLAY until the next scan. Does not touch `Topaz.library.json` (`Topaz.rating.json` stays authoritative; a scan re-applies it). |
| `autoPlayCandidateCount(activeGenres, considerGenre, considerRating, minimumRating)` | C++-only. How many tracks `autoPlayCandidatePool()` would return for the same arguments, via the same shared `passesAutoPlayFilters()` helper (so the two can't disagree), without building per-track maps. Backs `AutoPlayController::ratingRequirementMet`. |
| `ratingsReady` | `true` once a scan (full or stat-check) has completed at least once in this session with rating enrichment applied (see UC-14). Gates the AUTO PLAY button in `BottomBar`; never reset back to `false`. |
| `loadCacheAndStartStatCheck()` | Load cache instantly, then dispatch stat-check |
| `startFullScan()` | Trigger a full rescan on the worker thread |
| `genres()` | Distinct genre strings present in the library |
| `artistsForGenre(genre)` | Album artists for a genre, sorted |
| `albumsForArtist(artist, genre)` | Album titles for an artist, sorted |
| `filteredAlbums(activeGenres, selectedArtist, selectedAlbum)` | Album display objects for AlbumBrowser. **Single O(N_tracks) pass** using `QHash` to group tracks by `(albumArtist\|album)` key; cover thumb and year (first non-zero seen per album, same defensive pattern as the cover thumb) collected in the same pass; no per-album full rescan. Replaces the former O(N_tracks × N_albums) three-pass algorithm. Result sorted by albumArtist ascending, then (unless `AppConfig.albumBrowserSortOrder === "artistAlbum"`) year descending, then albumTitle ascending (case-insensitive); unknown-year albums (`year == 0`) sort last within their artist group when the year tiebreak is active. Sort order is configurable — Setup Dialog's MISC tab "Album Browser & Search Result Sort Order" — and shared with `searchLibrary()` below via `serializeAlbumAccum()`'s `sortByYear` parameter (`LibraryModel::albumBrowserSortByYear()`). |
| `buildLibraryTree(activeGenres)` | **Single-pass** tree builder: returns `[ { genre, artists: [ { name, albums: [{title}] } ] } ]` for `LibraryData._rebuildTree()`. One O(N_tracks) scan replaces the former N_genres + N_artists separate full-list scans. |
| `coverThumbForAlbum(album, albumArtist)` | Base64 thumbnail for an album |
| `searchLibrary(query, mode, activeGenres, considerGenre, matchWholeWord)` | Substring search across `albumArtist`/`album`/`title` — see UC-21. `matchWholeWord=true` requires the match to be bounded by non-alphanumeric characters (or field start/end) via a plain-`QString` `matchesWholeWord()` helper, not `QRegularExpression`; `false` (default) uses ordinary substring `contains()`, chosen once per call via a small lambda rather than branching per field. `mode` is `"all"` \| `"artists"` \| `"albums"` \| `"tracks"` (unrecognized values behave as `"all"`). **Single O(N_tracks) pass, all modes** — `albumArtist`/`album` are constant across every track in their group (the same invariant `filteredAlbums()`'s grouping key relies on), so a match on either field for one track is guaranteed to match every sibling track in that album too; no second "find matches, then rescan for siblings" pass is needed. A title-only match is inherently per-track already, which is exactly the "just this track, not its album siblings" behavior `"tracks"` mode needs. `considerGenre=false` ignores `activeGenres` entirely; `considerGenre=true` with an empty `activeGenres` returns no results (mirrors `filteredAlbums()`'s equivalent short-circuit). Empty/whitespace-only `query` returns no results. Shares its post-filter grouping/sort/serialize tail with `filteredAlbums()` via a private `serializeAlbumAccum()` helper (an anonymous-namespace `AlbumAccum` struct, extracted from the two functions' ~60 lines of previously-duplicated logic) — same `QVariantList` shape as `filteredAlbums()`, including honoring `AppConfig.albumBrowserSortOrder` via the same `LibraryModel::albumBrowserSortByYear()` call, except `isActive` is always `false` (no search-result card is naturally "selected"). **Cover fix-up**: since `"tracks"`-mode (and `"all"`-mode title-only) matches only include the matching track(s), not the rest of the album, a second pass over `m_tracks` fills in any still-missing album cover from any track carrying one (skipped entirely if every matched album already has a cover) — otherwise a track whose own tag lacks embedded art would show no cover even though a sibling track has one. `filteredAlbums()`/`buildLibraryTree()` never need this since they always include an album's full track list already. |
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
    "windowX": 100, "windowY": 100, "windowScreenName": "DISPLAY1",
    "windowPositionConfigured": true,
    "startFullscreen":    false,
    "deleteCurrentRatingEnabled": false,
    "libraryTreeWidth":   286,
    "playbackQueueWidth": 374,
    "nowPlayingWidth":    359,
    "playback": {
        "crossfadeEnabled": false,
        "crossfadeSeconds": 5.0,
        "audioBackend": "ffmpeg"
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

Settings are grouped into a nested object per `SetupDialog` tab (`playback`,
`autoPlay`, `audioVisualizer`); genres/folders/window-layout stay flat at the top
level. The `AppConfig` property/method names (`crossfadeEnabled`, `crossfadeSeconds`,
`autoPlayQueueHorizon`, and their setters) are unchanged by this grouping — the
on-disk JSON object/key names now match them exactly (`playback.crossfadeEnabled`/
`playback.crossfadeSeconds`, previously `crossfade.enabled`/`crossfade.seconds` —
a deliberate rename, not a migration; old config files simply get the documented
defaults for these two keys on next load, same as any other missing key). `bigCoverPane`/`tagInfoPane`/`audioVisualizerPane` are
also nested; unlike the others, their *presence* in the file (not a stored bool) is
what "configured" means — absent means that pane has never been positioned yet, so
`Main.qml` uses a centered default instead of its saved `X`/`Y` (see UC-17/UC-18/UC-19).

### AppConfig public API

| Method | Description |
|--------|-------------|
| `addGenre(name)` | Append genre (deduplicates case-insensitively); auto-saves. |
| `removeGenreAt(index)` | Remove genre by index; auto-saves. |
| `moveGenre(from, to)` | Move genre from one index to another, shifting the entries between them; auto-saves. See UC-33. |
| `clearGenres()` | Remove all genres; auto-saves. |
| `addFolder(rawPath, includeSubfolders)` | Converts `rawPath` to a volume-anchored `VolumePath` (`volumepath.h`) and appends it (deduplicates by `(volume, relPath)`); auto-saves. |
| `removeFolderAt(index)` | Remove folder by index; auto-saves. |
| `clearFolders()` | Remove all folders; auto-saves. |
| `setFolderSubfolders(index, flag)` | Toggle the includeSubfolders flag; auto-saves. |
| `setFolderActive(index, flag)` | Toggle whether this folder is scanned at all (default `true`); auto-saves. Takes effect on the next scan, not immediately — see UC-04/UC-05. |
| `saveLayout(windowWidth, windowHeight, libraryTreeWidth, playbackQueueWidth, nowPlayingWidth)` | Persist the current window size and resizable panel widths in a single atomic JSON write. Called from QML via a 500 ms debounce timer on every resize event. Window dimensions are not overwritten while in fullscreen. |
| `windowX` / `windowY` / `windowScreenName` / `windowPositionConfigured` / `saveWindowPosition(x, y, screenName)` | Persist the main window's last windowed (non-fullscreen) position and which monitor it was on; same debounce timer and calling convention as `saveLayout` above (called alongside it). `windowPositionConfigured` distinguishes "never positioned yet" (fresh config) from "restore to this position", same convention as `bigCoverPaneConfigured` below. `windowScreenName` is also consulted on startup to pick which monitor `Window.FullScreen` lands on — see UC-28. |
| `crossfadeEnabled` / `setCrossfadeEnabled(enabled)` | Whether crossfade is active between tracks (default `false`); auto-saves. Set from `SetupDialog`'s PLAYBACK tab toggle (see UC-15). |
| `crossfadeSeconds` / `setCrossfadeSeconds(seconds)` | Crossfade length in seconds (default `5.0`); clamped to `[2.0, 12.0]` and snapped to the nearest `0.5` s; auto-saves. Set from `SetupDialog`'s PLAYBACK tab slider. |
| `audioBackend` / `setAudioBackend(mode)` | Playback backend, `"ffmpeg"` (default) or `"bass"`; ignored for any other value; auto-saves. Set from `SetupDialog`'s PLAYBACK tab radio group. Selecting `"bass"` is only honored once `bassLibraryAvailable()` is true — inert until `PlaybackEngine` gains a real dual-backend abstraction (see UC-15). |
| `bassLibraryAvailable()` | `true` only if `bass.dll`, `bassflac.dll`, and `bassopus.dll` (Linux: `libbass.so`/`libbassflac.so`/`libbassopus.so`) are all present next to the running executable. Checked before `audioBackend` can be set to `"bass"` (see UC-15). |
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
   │  appConfig.addGenre(name)  /  removeGenreAt(i)  /  moveGenre(from, to)  /  clearGenres()
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

| Resolution | ColumnLayout behaviour |
|-----------|------------------------|
| 1280 × 720 (minimum) | All four panels visible; minimum enforced |
| 1920 × 1080 | Design baseline — all four panels fully visible |
| 1920 × 1200 | Extra vertical space absorbed by AlbumBrowser |
| 2560 × 1440 | Font scale and spacing scale up proportionally (future) |
| 3840 × 2160 | Font scale and spacing scale up proportionally (future) |
| 4096 × 2160 | AlbumBrowser gains a 2-column card grid (future) |

**Startup fullscreen/windowed is a user preference, not resolution-driven.**
Earlier versions auto-triggered `Window.FullScreen` whenever the monitor was
exactly 1920×1080, 1920×1200, 2560×1440, or 3840×2160. That resolution
sniffing has been replaced by an explicit `AppConfig.startFullscreen` bool
(Setup → MISC → "Start Topaz in Full Screen", default **off**/Windowed — see
UC-24's MISC tab and the Config file format section below).

**Startup logic** (`Main.qml`): the root window starts hidden
(`visibility: Window.Hidden`, `minimumWidth: 1280`, `minimumHeight: 720`, no
`width`/`height`/`visible` bindings). Its `Component.onCompleted` restores the
saved screen, size and position and only then shows it with
`root.visibility = appConfig.startFullscreen ? Window.FullScreen : Window.Windowed`
— see "Layout persistence" below for why the order matters.

> Topaz starts Windowed at 1920×1080 by default (the `windowWidth`/
> `windowHeight` defaults), on every resolution. The user opts into fullscreen
> startup via Setup → MISC; the toggle takes effect on the next launch.
> AlbumBrowser absorbs surplus width as the user resizes, regardless of
> startup mode.

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

The window size, position/monitor, and the three resizable panel widths are
persisted in `Topaz.config` so that the layout is restored exactly on the
next startup.

**Save mechanism** — `Main.qml` watches `onWidthChanged`/`onHeightChanged`
on the `ApplicationWindow` (for window resizing), `onXChanged`/`onYChanged`/
`onScreenChanged` (for window moves and monitor changes), and `onWidthChanged`
on each resizable panel (for handle dragging). All of these restart a single
500 ms debounce `Timer`. When the timer fires it calls `appConfig.saveLayout(...)`
(writes `windowWidth`, `windowHeight`, `libraryTreeWidth`, `playbackQueueWidth`,
`nowPlayingWidth` in one atomic JSON write) and `appConfig.saveWindowPosition(...)`
(writes `windowX`, `windowY`, `windowScreenName`, `windowPositionConfigured`).
While in fullscreen mode the stored window dimensions *and* position are not
overwritten (fullscreen collapses `x`/`y` to the screen origin and `width`/
`height` to the screen resolution, which must not clobber the last windowed
geometry) — `windowScreenName` is the one exception, refreshed regardless of
fullscreen state, since monitor identity is meaningful in both modes.
Nothing is persisted at all until `settleTimer` (~1.2 s after the window is
shown) has fired (`Main.layoutSettled`), so transient startup geometry — a DPI
re-scale, a `SplitView` squeeze — can never overwrite what the user configured.

**Restore mechanism** — On startup, `AppConfig::load()` reads these values
from JSON (falling back to the design-baseline defaults when absent, or to
`windowPositionConfigured: false` on a fresh config — same "never positioned
yet, let the platform place it" convention as `bigCoverPaneConfigured`, see
below). Each resizable panel binds `SplitView.preferredWidth` to the
corresponding appConfig property; `SplitView` breaks those QML bindings the
first time the user drags a handle, taking over management of
`preferredWidth` from that point onward.

The **main window** is restored in the root `ApplicationWindow`'s
`Component.onCompleted`, and the *order* is the point. A QML `Window` is
created and shown in its own `componentComplete()`, which runs **before**
`Component.onCompleted`, so a window declared `visible: true` (as this one
used to be) already exists, on the platform-default screen, by the time any
restore code in `onCompleted` runs. That was wrong three ways: `Window.screen`
assigned after creation moves nothing (Qt docs), so a fullscreen start could
never reach the saved monitor; a position for a display with a different
scale factor was converted with the *primary's* origin/scale (Qt's logical→
native mapping is per screen), so on an additional display — especially one
left of the main display, with negative coordinates — the window landed in
the wrong place and was then re-scaled by the OS; and the resulting squeezed
window made `SplitView` shrink the panels, whose transient widths were saved.
(An earlier version of this section claimed the opposite — that `onCompleted`
ran before native window creation, "the same ordering the floating panes rely
on". It does for the panes, which declare `visible: false` and show themselves
after positioning; it did not for the root window.) So the root is now hidden
until restored, exactly like the panes:

1. **Target screen**: a fullscreen start goes by the saved `windowScreenName`
   (`screenByName()`, then the screen containing the saved rect's center,
   `screenAtPoint()`); a windowed start by the rect's center first, then the
   name. Identical monitor models (same `name`), renamed connectors and a
   changed arrangement therefore no longer silently pick the primary display.
2. **Size**: the saved `windowWidth`/`windowHeight`, clamped *down* to the
   target screen's logical size (the primary if the saved monitor is gone),
   never below `minimumWidth`/`minimumHeight`.
3. **Position**: the saved `windowX`/`windowY` if at least **half** of that rect
   is visible on the connected screens (`visibleFraction() >= 0.5`, shared with
   the panes — an "overlaps at all" test restored a window saved on an unplugged
   left display as a barely reachable sliver on the remaining one); if less is
   visible but the target screen is known, centered on it; if the monitor is
   gone, the platform default.
4. Assign `root.screen`, then `width`/`height`, then `x`/`y` (all still on the
   hidden window — assigning `width`/`height` here also replaces the old
   `width: appConfig.windowWidth` bindings, which were what shrank a
   fullscreen window ~0.5 s after entering fullscreen: every
   `saveWindowPosition()` emits `windowGeometryChanged`, the NOTIFY of
   `windowWidth`/`windowHeight`, re-evaluating them), and only then show the
   window with `root.visibility = startFullscreen ? FullScreen : Windowed`.
   The whole block is `try/finally` so the window is always shown even if the
   restore throws.

The window is hidden through `visibility: Window.Hidden`, **not**
`visible: false`: declaring `visible` and later assigning `visibility` makes Qt
log "Conflicting properties 'visible' and 'visibility'" and the window came up
minimized (found in testing).

`settleTimer` then logs where the window actually landed versus where it was
restored to (`Main: window after startup: ...` on stderr, for multi-display /
mixed-DPI reports) and, for a windowed start that is off by more than 8 px,
re-applies the wanted geometry once (the window now lives on the right screen,
so the mapping is correct). The logged screen name and `dpr` say which
display it landed on.

Before the position/monitor persistence existed, the main window had none at
all (only the floating panes did) — every launch opened wherever the
platform/WM defaulted a new top-level window. Found via real-hardware testing
(Windows and a dual-monitor Linux Mint machine); the restore *order* above was
found in a later round of dual-display testing (additional display to the
left, different scaling per display).

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
      +ratingCount int
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
      +autoPlayCandidateCount(activeGenres, considerGenre, considerRating, minimumRating) int
      +applyRating(ratingId, rating)
      +buildStandaloneTrackCards(tracks) QVariantList
      ~libraryRefreshed()
      ~ratingsChanged()
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
      +selectedMissingTracks QVariantList
      +resultScrollIndex int
      +resultScrollOffset real
      +refreshPlaylists()
      +selectPlaylist(fileName)
      +clearSelection()
      +selectNeighborOf(fileName)
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
      +moveGenre(from, to)
      +addFolder(path, subfolders)
      +removeFolderAt(index)
      +setFolderActive(index, active)
      +setCrossfadeEnabled(enabled)
      +setCrossfadeSeconds(seconds)
      +setAudioBackend(mode)
      +bassLibraryAvailable()
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
      +ratingRequirementMet bool
      +playPauseAllowed bool
      +trackNavigationAllowed bool
      +toggle()
      +clearQueueAndHistory()
      +clearHistory()
      ~activeChanged()
      ~manualQueueEditingAllowedChanged()
      ~queueClearAllowedChanged()
      ~genreRequirementMetChanged()
      ~ratingRequirementMetChanged()
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
    PlaybackEngine --> AudioDeck     : owns ×2 (dual-deck, see UC-15)
    AudioDeck <|-- FfmpegAudioDeck   : wraps QMediaPlayer/QAudioOutput
    AudioDeck <|-- BassAudioDeck     : wraps BASS HSTREAM (Step 2b)
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

### Normal Flow — Double-click cover art to add the whole album (AlbumBrowser only)

See **UC-34** for the full design — summary: `AlbumBrowser.qml`'s delegate
sets a new opt-in `AlbumCard.wholeAlbumDoubleClickEnabled: true`, which
arms a `MouseArea` scoped to just the 160×160 cover-art `Item` (never the
whole card); double-clicking it calls `root.engine.addTracks(root.tracks)`
— the same batch-capable invokable as above, just with every track of the
album instead of one. `SearchResultBrowser`/`PlaylistViewer` leave the
property at its default `false`, so they get none of this.

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
- **No album drag**: the cover area is not a drag source; only individual track rows are draggable. It is, however, a double-click target in AlbumBrowser only — see UC-34.
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

`queueArea.autoScrollToCurrent()` (`PlaybackQueue.qml`) runs on both
`PlaybackEngine::queueCountChanged` **and** `PlaybackEngine::currentIndexChanged`
(via a `Connections` block, each deferred one tick with `Qt.callLater` so
`queueList.contentHeight`/the new current row are already settled) — i.e. on
every add (`addTrack`/`addTracks`), every remove (`removeAt`/`clearQueue`),
and every time the currently-playing track itself changes, from any source.
It sets `queueList.contentY = currentIndex * 68` (clamped to the content's
end), pinning the currently-playing row to the top of the visible viewport —
already-played rows scroll out of view above it, and as many upcoming/queued
tracks as the panel's height can hold become visible below. It's a no-op
whenever the queue doesn't overflow the panel (`contentHeight <= height`, no
scrollbar showing), so a short queue is never force-scrolled. This behavior
is **independent of AUTO PLAY vs. MANUAL MODE vs. a loaded playlist** — it
was already written to not distinguish between them, but originally only
had the `queueCountChanged` trigger wired, so AUTO PLAY (which keeps adding
tracks to maintain its horizon) worked by coincidence while a playlist
playing straight through (queue size never changes, only `currentIndex`
does) or a manually-built queue with nothing further adding to it did not.
The `currentIndexChanged` trigger closes that gap — `currentIndexChanged`
is the single choke point every real transition (hard cut, the natural
crossfade midpoint, UC-23's queue-replacing crossfade midpoint) and every
manual navigation (NEXT/PREVIOUS/clicking a queue row) already shares, so
this one addition covers all of them uniformly.

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
| Delete rating (trash-bin) | Opt-in via Setup → MISC (`AppConfig.deleteCurrentRatingEnabled`, default off) — rendered immediately left of the star row when enabled, hidden entirely otherwise. Calls `engine.deleteCurrentRating()` after a "DELETE RATING" confirmation. See UC-29. |
| Elapsed time | `engine.positionString` ("M:SS") |
| Total time | `engine.durationString` ("M:SS") |
| Progress ratio | `engine.position / engine.duration` |

---

## PlaybackEngine Component

`PlaybackEngine` is a C++ `QAbstractListModel` subclass marked `QML_ELEMENT`.
It serves as **both the queue model** (rows = `TrackInfo` records) and the **playback controller**.  The queue is the single source of truth; `PlaybackQueue.qml` binds its `ListView.model` directly to the engine instance.

**Dual-deck playback (crossfade)**: rather than a single playback backend
instance, `PlaybackEngine` owns two independent `AudioDeck` instances
(`m_decks[2]`, "decks") because neither backend (FFmpeg's `QMediaPlayer` nor
BASS) can play two sources from one instance — a real crossfade needs the
outgoing and incoming track playing simultaneously on separate decks while
their volumes ramp in opposite directions. `m_deck` is an **alias pointer**,
always equal to `m_decks[m_activeDeck]`; every pre-existing single-deck code
path (`position()`, `duration()`, `seek()`, etc.) is unchanged and simply
operates on "whichever deck is active." Only the crossfade-specific code
(`startCrossfade()`, `onFadeTick()`, `cancelCrossfade()`) reasons about both
decks explicitly. See UC-15 for the full crossfade flow and the `AudioDeck`
abstraction that makes this backend-agnostic.

### Public API

| Method / Property | Type | Description |
|-------------------|------|-------------|
| `currentIndex` | `int` | Index of the currently loaded track (−1 = nothing) |
| `isPlaying` | `bool` | `true` when the active `AudioDeck` reports it's playing (`false` if no deck exists yet — see UC-15 "AudioDeck abstraction") |
| `userPaused` | `bool` | `true` only while the current track is paused via `togglePlay()`'s explicit pause branch — never for any other "not playing" state (see UC-07's design note). Drives `NowPlaying`'s Play/Pause button blink. |
| `position` | `qint64` | Playback position in milliseconds |
| `duration` | `qint64` | Duration of current track in milliseconds |
| `positionString` | `QString` | `position` formatted as "M:SS" |
| `durationString` | `QString` | `duration` formatted as "M:SS" |
| `remainingString` | `QString` | `duration - position` formatted as "M:SS" (added for `TagInfoWindow`'s DURATION countdown, UC-18) |
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
| `setCurrentRating(rating)` | invokable | Set the current track's rating (1-10; no-op otherwise or if no track is loaded). Updates the queue entry and calls `RatingCache::setRating(genre, ratingId, rating)` to persist immediately, then emits `currentRatingChanged()` and `ratingStored(ratingId, rating)`. |
| `deleteCurrentRating()` | invokable | Permanently remove the current track's rating (no-op if no track is loaded or it has no rating). Resets the queue entry's rating to 0 and calls `RatingCache::removeRating(ratingId)` to persist immediately, then emits `currentRatingChanged()` and `ratingStored(ratingId, 0)`. See UC-29. |
| `ratingStored(ratingId, rating)` | signal | Emitted right after a rating was written to / removed from `Topaz.rating.json` (`rating` 0 = removed). `Main.qml` forwards it to `LibraryModel::applyRating()`; `PlaybackEngine` deliberately knows nothing about `LibraryModel`. |
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
visualizer, UC-19; also consumed by Milkdrop, UC-20)**: not a `Q_PROPERTY`/QML-facing
signal — `AudioVisualizerController` and `MilkdropView` (both plain C++) independently
connect to it. Emitted from each deck's `AudioDeck::audioBufferReceived` (a shared
interface signal both `FfmpegAudioDeck` and `BassAudioDeck` provide — see UC-15
"Step 3"), filtered to `m_activeDeck` only (a deliberate simplification during
crossfades — see UC-19's "Known limitations"). `FfmpegAudioDeck` sources it from
`QAudioBufferOutput` (Qt Multimedia's FFmpeg backend); `BassAudioDeck` polls
`BASS_ChannelGetData()` on its own timer, since BASS has no equivalent push
notification.

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
- **Single action**: reuses `clearQueue()` which already handles the playlist name reset.
- **Real bug fixed after initial ship**: `clearQueue()` originally bailed
  out early whenever `m_queue.isEmpty()`, on the assumption that an empty
  queue never has an associated playlist. That's false —
  `PlaybackEngine::removeAt()` (per-track ✕ removal in `PlaybackQueue`)
  can empty the queue one track at a time without ever touching
  `m_activePlaylistName`, leaving a playlist "active" with zero tracks.
  In that state the old guard made REMOVE a permanent no-op (it returned
  before reaching the `m_activePlaylistName.clear()` line), and since
  `PlaylistViewer.isSelectedActiveInQueue` stayed `true` for that
  playlist, its DELETE button in the PLAYLISTS tab stayed disabled too —
  the playlist could be neither unloaded nor deleted. Fixed by widening
  the guard to `m_queue.isEmpty() && m_activePlaylistName.isEmpty() &&
  !m_playlistLocked` — it now only skips work when there's genuinely
  nothing to reset, not merely when the queue itself is empty.

---

## UC-10 Load Existing Playlist

| Field | Detail |
|-------|--------|
| **Goal** | User loads an existing XSPF playlist from disk into the queue. |
| **Actor** | User |
| **Precondition** | Application is running. |
| **Trigger** | User clicks **LOAD** in the `NowPlaying` panel. |

> A file picked from outside `PlaylistManager::playlistDirectory()` is
> imported into that folder first — see UC-30 — before continuing with
> the flow below.

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

### Alternate: All or some tracks missing

`VolumePath::resolve()` (`volumepath.cpp`) already calls `QFileInfo::exists()`
at every candidate it tries, so `loadPlaylist()`'s per-track resolution
failure *is* "this file no longer exists on disk" — not merely "its volume
isn't mounted." Rather than silently dropping these, `loadPlaylist()`
collects them into `result.missing`, one entry per skipped track, built
entirely from what the XSPF itself stored (`artist`, `album`, `title`,
`location`) since there's no file left to re-read tags from. `onAccepted`
loads whatever's in `result.tracks` as normal (empty queue, nothing plays,
if *every* track was missing) and, if `result.missing` is non-empty, emits
`missingPlaylistTracks(result.missing)` — `Main.qml` opens
`MissingTracksDialog` with it, listing every missing track's artist/album/
title/location. The playlist file on disk is never rewritten by this —
purely an in-memory filter for this one load.

### Alternate: Load from PlaylistViewer (PLAYLISTS tab)

`PlaylistViewer`'s own **LOAD** button (see UC-22) triggers the identical
effect — same step-6/7 branch (`loadPlaylistTracks()` if a playlist was
already active, else `addTracks()`), `setActivePlaylistName()` — but skips
steps 1-5 entirely: the file was already selected via `PlaylistsPanel`, and
`PlaylistManager.loadPlaylist()` was already called once (to build the
preview) by `PlaylistsData.selectPlaylist()`. The already-parsed track list
is reused from `PlaylistsData.selectedRawTracks` rather than re-reading and
re-parsing the XSPF file and re-running `TagReader::read()` on every track
a second time. `result.missing` from that same earlier call is cached as
`PlaylistsData.selectedMissingTracks` and only surfaced (via the same
`missingPlaylistTracks` signal/`MissingTracksDialog`) when LOAD is actually
clicked, not at selection/preview time.

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
| **Trigger** | User presses the left mouse button on the thumb in `LibraryTree`, `AlbumBrowser`, `SearchResultBrowser`, `PlaylistViewer`, or `PlaybackQueue` and drags vertically. |

Two variants exist, split by whether the panel's delegate has a fixed or
content-derived height:

### Normal Flow — fixed-height panels (`LibraryTree`, `PlaybackQueue`)

1. User presses the thumb. The `MouseArea` on the thumb records the press position (mapped into the track's coordinate space via `mapToItem`) and the list's current `contentY`.
2. User drags up or down. Each move event re-maps the cursor into track space, scales the pixel delta by the ratio of scrollable content range to available track range (`(contentHeight - height) / (trackHeight - thumbHeight)`), and assigns the result to the list's `contentY` (clamped to `[0, contentHeight - height]`).
3. The thumb's existing position/size bindings (`y`/`height` driven by `ListView.visibleArea.yPosition`/`heightRatio`) follow automatically as `contentY` changes — no separate redraw logic is needed.

This pixel-delta approach is correct here specifically because both panels'
delegates have a small, fixed set of possible heights known upfront
(`LibraryTree`: 44/40/28/36 px by row type; `PlaybackQueue`: a flat 68 px)
— `contentHeight` is exact from the very first layout pass, never an
estimate.

### Normal Flow — variable-height panels (`AlbumBrowser`, `SearchResultBrowser`, `PlaylistViewer`)

These three all use `AlbumCard` as their delegate, whose height is
content-derived (`implicitHeight: cardRow.implicitHeight + 40`, driven by
a per-track `Repeater` at 30 px/row) — so `contentHeight` is only an
*estimate*, extrapolated from the running average of already-realized
delegates, until every delegate has actually been laid out. Pixel-delta
math against an estimate that keeps shifting mid-drag doesn't work (see
"Why the variable-height panels use index-based positioning" below), so
these three panels drive the drag by model **index** instead:

1. User presses the thumb. The `MouseArea` records only the press point's
   offset *inside* the thumb (`pressGrabY`) — no `contentY`/track-position
   baseline is captured.
2. User drags up or down. Each move computes an absolute fraction along
   the track from the cursor's absolute position, maps it onto the
   reachable top-item index range (`count * (1 - visibleArea.heightRatio)`),
   and calls `positionViewAtIndex(idx, ListView.Beginning)` — `count` is
   exact and known upfront, unlike accumulated pixel height. The
   just-realized delegate's real height is then read via `itemAtIndex()`
   and the fractional remainder applied as a small `contentY` nudge, so
   dragging through a handful of very tall cards still feels continuous.
   Dragging to within 0.05% of either end of the track calls
   `positionViewAtBeginning()`/`positionViewAtEnd()` directly instead —
   both use real laid-out geometry and land on the true visual start/end
   regardless of how far off the global estimate is.
3. The thumb's `y`/`height` bindings are unchanged from the fixed-height
   variant — still driven by `visibleArea.yPosition`/`heightRatio`,
   purely cosmetic, and self-correcting as Qt's estimate settles.

### Normal Flow — shared (all 5 panels)

4. The thumb shifts to `Theme.secondary` while the drag is active, and to `Theme.fgSurfaceVariant` on hover when idle, mirroring the color language already used for the `SplitView` panel-resize handles (rest → hover → active-drag).
5. User releases the mouse button; the thumb returns to its rest color (`Theme.outlineVariant`).

### Why the variable-height panels use index-based positioning

The original implementation used the identical pixel-delta formula for
all five panels, and worked for none of `AlbumBrowser`/
`SearchResultBrowser`/`PlaylistViewer` — dragging down would often flip
back up partway, flicker/jitter, and eventually get stuck unable to go
further down (up still worked). Root cause, confirmed by comparing against
the two panels that did work:

1. `AlbumCard`'s `implicitHeight` is content-derived (proportional to a
   per-album/per-track-card track count), so `ListView.contentHeight` for
   these three panels is never exact until every delegate is realized —
   it's an extrapolation from the running average of already-realized
   delegates' heights, and that average — along with `originY`, the
   coordinate frame `contentY` is measured against — gets revised every
   time a new delegate is realized inside the `cacheBuffer` window, which
   is exactly what happens continuously while dragging.
2. The old handler captured a `contentY` baseline once at press-time and
   added a scaled pixel delta to it on every move, implicitly assuming a
   stable frame (its `Math.max(0, …)` clamp assumes `originY === 0`,
   which only holds for fixed/near-uniform-height lists). When the
   estimate is revised mid-drag, that assumption breaks: jitter (the
   scale factor changes on every move), snap-back (a downward revision of
   the estimate + the clamp yanks `contentY` back), and stuck-going-down
   (downward drag keeps pushing into the unrealized "estimation
   frontier" and gets clamped there, while upward drag revisits
   already-realized, already-stable geometry — matching the reported
   asymmetry exactly).
3. `count` (the number of items in the model) is exact and known upfront,
   unlike accumulated pixel height — so re-expressing the drag target as
   an index rather than a `contentY` pixel value sidesteps the estimate
   entirely for the scroll *target itself* (only the thumb's own
   cosmetic `y`/`height` still derive from the estimate, same as before).
4. The index scale `count * (1 - heightRatio)` (not `count` or
   `count - 1`) is a deliberate choice, not an approximation: for a
   uniform-height list it reduces algebraically to exactly the old pixel
   formula (`contentY = frac * (contentHeight - height)`), which is why
   this is a strict generalization rather than a behavior change for
   `LibraryTree`/`PlaybackQueue` — they were left untouched precisely
   because applying the same formula there would have been a no-op.
   `count` alone would leave a dead zone at the bottom of the track
   proportional to `heightRatio`; `count - 1` would make a single very
   tall card (one album, e.g.) effectively undraggable except at the
   extremes.
5. Endpoints use `positionViewAtBeginning()`/`positionViewAtEnd()` rather
   than a manual `contentY = 0` / `contentY = contentHeight - height`,
   because Qt's own helpers force layout of the first/last delegate and
   align it against real, current geometry — a manual pixel assignment
   would inherit whatever error the estimate still has for the
   unrealized region.
6. This supersedes commit `0b28e9f`'s deferred "AlbumBrowser Scrollbar is
   still not working properly when there are many albums shown" note —
   the underlying instability was never specific to "many albums," but
   to *content-derived delegate height*, which is why it also affected
   `SearchResultBrowser`/`PlaylistViewer` (added later, inheriting the
   same `AlbumCard` delegate) identically.
7. **Known residual, not fixed here**: because the thumb's own `y` is
   still parameterized by pixel fraction while the drag target is now
   parameterized by index fraction, the thumb can drift slightly out from
   under the cursor during a drag through very unevenly-sized cards. This
   is cosmetic only and strictly better than the prior behavior; a
   documented follow-up (not implemented) would pin the thumb to the
   cursor's actual position while `pressed`.
8. **Not done in this change**: unifying all five panels' "Custom
   scrollbar" blocks into one shared `ScrollbarThumb.qml` component. The
   two variants are no longer literally identical (one pixel-based, one
   index-based), and this was a bugfix, not a refactor — extracting a
   shared component would have forced touching the two files that
   already worked correctly. Recorded here as a possible future
   consolidation once the index-based variant has soaked.

The same root cause (and the same index-based fix) also applies to
cross-tab scroll-position *restore* for these three panels — see UC-22.
`PlaylistViewer` additionally guards its live-queue auto-scroll against an
in-progress thumb drag — also see UC-22.

### Design notes

- Implemented as five separate local "Custom scrollbar" blocks (not a
  shared component — see point 8 above), one per panel: `LibraryTree.qml`
  (`treeList`/`treeScrollTrack`/`treeScrollThumb`/`treeThumbMA`),
  `PlaybackQueue.qml` (`queueList`/`queueScrollTrack`/`queueScrollThumb`/
  `queueThumbMA`), `AlbumBrowser.qml` (`albumList`/`albumScrollTrack`/
  `albumScrollThumb`/`albumThumbMA`), and `SearchResultBrowser.qml`/
  `PlaylistViewer.qml` (both use the identical `resultList`/
  `resultScrollTrack`/`resultScrollThumb`/`resultThumbMA` ids).
- Reuses the `mapToItem`-based drag-tracking approach already used for `AlbumCard`'s track drag and `PlaybackQueue`'s queue-reorder drag handle (see UC-06 and UC-11) rather than introducing a new interaction technique.
- `preventStealing: true` on the thumb's `MouseArea` keeps the `ListView`'s own flick gesture from stealing the drag, the same technique already used for the queue-reorder drag handle.
- Mouse-wheel scrolling and click-drag on the list content itself are unaffected — this only adds a second way to scroll, via the thumb.
- Row/track delegates in `LibraryTree`, `AlbumCard` (used by `AlbumBrowser`/`SearchResultBrowser`/`PlaylistViewer`), and `PlaybackQueue` all reserve the rightmost 8 px for the scrollbar thumb's column — either by making the delegate itself narrower (`LibraryTree`, `width: treeList.width - 8`) or by trimming the row's click-catching `MouseArea` with `anchors.rightMargin: 8` (`AlbumCard`'s `trackMA`, `PlaybackQueue`'s `rowHover`) — so row interaction never competes with the scrollbar thumb for the same mouse press. Without this, a row's own `MouseArea` can win the press instead of the thumb (identical idle cursor on both makes this invisible until the user drags), reinterpreting the gesture as that row's own drag instead of a scroll. The scrollbar track `Rectangle` in each panel also sets `z: 2` as a defensive guarantee that it hit-tests above delegate content.

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
   filled stars. `PlaybackEngine` then emits `ratingStored(ratingId, n)`; a
   `Connections` block in `Main.qml` forwards it to `LibraryModel::applyRating()`,
   which updates every library track with that `ratingId`, `ratingCount`, and emits
   `ratingsChanged()`. Without this step the library's own tracks kept their
   scan-time ratings for the whole session, so a rating given now was invisible to
   AUTO PLAY (its candidate pool and the button's Consider Rating gate) until the
   next scan or restart. `deleteCurrentRating()` (UC-29) does the same with rating 0.
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
- **`RatingCache::removeRating(ratingId)`** (added for UC-29) is a third,
  symmetric persistence path — a single delete-by-`ratingId` through the
  same `loadEntries()`/`saveEntries()` pair, used by
  `PlaybackEngine::deleteCurrentRating()` for NowPlaying's opt-in
  delete-rating trash-bin button. Returns `false` (no write) if the id is
  null or no matching entry exists, same "no-op on nothing to do" shape as
  `setRating()`'s own validation.
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

> The next track's file existence is checked right at that trigger point,
> before the fade-in deck's `setSource()` call — see UC-31.

### Normal Flow — Configure crossfade

1. User opens **Setup → PLAYBACK** (renamed from CROSSFADE — this tab now also hosts
   the playback-backend choice below, see "Normal Flow — Choose playback backend").
2. User toggles the **Crossfade** switch (same visual pattern as `PlaybackQueue`'s LOCK
   PLAYLIST toggle) → `appConfig.setCrossfadeEnabled(...)` → auto-saves to
   `Topaz.config`. The **Length** row (label, value, slider, min/max) dims to 35%
   opacity and the slider is disabled while crossfade is off.
3. User drags the **Length** slider (`QtQuick.Controls.Slider`, `2.0`–`12.0` s,
   `stepSize: 0.5`, restyled to match the theme). The live value is shown above the
   slider (bound to the slider's own `value`, so it updates smoothly while dragging);
   `"2.0 s"`/`"12.0 s"` labels flank the track as the min/max. `onMoved` (fires only on
   user interaction, not programmatic changes) calls `appConfig.setCrossfadeSeconds(...)`,
   which clamps to `[2.0, 12.0]`, snaps to the nearest `0.5`, and auto-saves.
4. `PlaybackEngine` reads both settings live from `appConfig` on every eligibility
   check (never cached), so a change takes effect starting with the very next
   transition — no restart needed.

### Normal Flow — Choose playback backend

Step 1 of a multi-step initiative to offer BASS Audio Library as an
alternative to today's FFmpeg-based playback (`QMediaPlayer`/`QAudioOutput`),
aimed at eliminating occasional audible stutter some users hit. Selecting
BASS here only changes the *stored preference* — see "AudioDeck abstraction
(Step 2)" below for how (and when) that preference actually takes effect,
now that a real `BassAudioDeck` (Step 2b) exists. The Audio Visualizer
(UC-19) and Milkdrop (UC-20) also work under BASS (Step 3) — both consume
`PlaybackEngine::audioBufferAvailable`, which now fires for either backend.

1. At the top of the PLAYBACK tab, above the Crossfade switch, a "Playback
   with" row shows two radio options — **FFmpeg** (default) and **BASS Audio
   Library** — using the same radio-button idiom as AUTO PLAY's "Play a
   Title" row (UC-14: circular border/dot `Rectangle`, label `Text`,
   `MouseArea`), bound to `AppConfig.audioBackend`.
2. Clicking **FFmpeg** always calls `appConfig.setAudioBackend("ffmpeg")`
   directly.
3. Clicking **BASS Audio Library** first calls
   `appConfig.bassLibraryAvailable()` — `true` only if `bass.dll`,
   `bassflac.dll`, and `bassopus.dll` (Linux: `libbass.so`/`libbassflac.so`/
   `libbassopus.so` — see "Linux port, step 3" below) are all present next
   to `Topaz.exe` (checked via `QCoreApplication::applicationDirPath()`). BASS's core
   library natively decodes MP3/OGG/WAV only; FLAC and Opus (both of which
   Topaz already plays, see `TagReader`) each need their own official add-on
   for feature parity with today's FFmpeg playback, hence checking for all
   three rather than `bass.dll` alone.
4. If unavailable, a `MessageBox` (`missingBassDllsBox`) opens explaining
   which files are needed and linking to `https://www.un4seen.com/` — the
   radio selection does not change. `MessageBox.qml`'s message `Text` was
   extended (`textFormat: Text.RichText`, `onLinkActivated:
   Qt.openUrlExternally(link)`) so a caller can embed a clickable link;
   every pre-existing plain-text call site renders identically, since plain
   text contains no markup for `RichText` to interpret differently.
5. If available, `appConfig.setAudioBackend("bass")` is called and
   auto-saves. `audioBackend` is persisted as a new field inside the
   existing `crossfade` JSON object (`"ffmpeg"` or `"bass"`; any other value
   or a missing key both default to `"ffmpeg"`) — deliberately not renamed
   alongside the tab, to avoid a migration path for existing config files.

### AudioDeck abstraction (Step 2)

`PlaybackEngine`'s dual-deck crossfade code never talked to `QMediaPlayer`/
`QAudioOutput` for its own sake — only to load/play/pause/stop/seek and to
read position/duration/playing-state/end-of-track. `AudioDeck` (`audiodeck.h`)
is an abstract interface capturing exactly that surface (`setSource()`,
`play()`/`pause()`/`stop()`, `position()`/`setPosition()`/`duration()`,
`isPlaying()`, `setVolume()`, and signals `positionChanged`/
`durationChanged`/`playingChanged(bool)`/`endOfMedia`), so
`startCrossfade()`/`onFadeTick()`/`cancelCrossfade()`/
`onDeckPositionChanged()`'s eligibility math/`switchCurrentIndexTo()` needed
**zero** changes when this landed — they already only ever needed this
generic surface. `m_players[2]`/`m_audioOutputs[2]` became `AudioDeck
*m_decks[2]`; the `m_player`/`m_audioOutput` alias pair collapsed into one
`AudioDeck *m_deck` (volume is now a deck-level concern, not a separate
audio-output object).

- **`FfmpegAudioDeck`** (`ffmpegaudiodeck.h`/`.cpp`, Step 2a, shipped):
  wraps one `QMediaPlayer`+`QAudioOutput`+`QAudioBufferOutput` trio,
  functionally identical to the pre-abstraction code. Sources the
  audio-buffer visualizer/Milkdrop tap (UC-19/UC-20) from
  `QAudioBufferOutput::audioBufferReceived`, connected straight through to
  the inherited `AudioDeck::audioBufferReceived` signal (promoted into the
  shared interface in Step 3, below — no longer FFmpeg-specific).
- **`BassAudioDeck`** (`bassaudiodeck.h`/`.cpp`, Step 2b, shipped): wraps one
  BASS `HSTREAM` handle, created via `BassLibrary::instance()`. Two
  consequences of BASS's plain-C, callback-based API (vs. `QMediaPlayer`'s
  Qt signals):
  - No push-based position/duration notifications — a ~100 ms `QTimer`
    polls `BASS_ChannelGetPosition()` and re-emits `positionChanged()`,
    which drives the UI progress bar and the crossfade proximity check
    exactly as `QMediaPlayer::positionChanged` already did for
    `FfmpegAudioDeck`. `duration()` is cached once per `setSource()` call
    (`BASS_ChannelGetLength()` converted via `BASS_ChannelBytes2Seconds()`)
    rather than queried live, since it doesn't change mid-stream.
  - End-of-stream is BASS's `BASS_SYNC_END` sync callback
    (`BASS_ChannelSetSync()`), which fires on **BASS's own internal
    thread** — `BassAudioDeck::syncEndProc()` (a `static` function, the
    callback BASS actually invokes) does nothing but marshal to the deck's
    own thread via `QMetaObject::invokeMethod(self,
    &BassAudioDeck::handleStreamEnded, Qt::QueuedConnection)`;
    `handleStreamEnded()` is what actually stops the poll timer and emits
    `endOfMedia()`. Touching `QObject`/Qt state directly from
    `syncEndProc()` itself would be a cross-thread violation.
  - FLAC/Opus support comes from `BASS_PluginLoad()`-ing `bassflac.dll`/
    `bassopus.dll` once (in `BassLibrary::load()`, after `BASS_Init()`),
    not separate functions — `BASS_StreamCreateFile()` then transparently
    handles those formats too. On Windows, all file paths (the plugin
    filenames and every track's path) are passed with the `BASS_UNICODE`
    flag, since neither is guaranteed ASCII-safe — see "Linux port, step 3"
    below for the non-Windows equivalent (plain UTF-8, no such flag).
  - Volume ramping during crossfade uses the same plain
    `setVolume()`/`BASS_ChannelSetAttribute(BASS_ATTRIB_VOL, ...)` calls
    `onFadeTick()` already made for `FfmpegAudioDeck` — crossfade behavior
    is identical regardless of backend.
- **`BassLibrary`** (`basslibrary.h`/`.cpp`, Step 2b, shipped): a singleton
  runtime loader (`QLibrary`, never linked at build time — `bass.dll` isn't
  bundled, see "Choose playback backend" above) that hand-declares the
  stable subset of BASS's C ABI actually needed (function-pointer members
  named after their BASS export, e.g. `BASS_Init`/`BASS_StreamCreateFile`/
  `BASS_ChannelSetSync` — a hand-written interface description, not a copy
  of BASS's source or binary). `load()` resolves every entry point, calls
  `BASS_Init(-1, 44100, 0, nullptr, nullptr)`, then `BASS_PluginLoad()`s
  `bassflac.dll`/`bassopus.dll`; idempotent (returns `true` immediately once
  already loaded) and safe to call every time `createDecksIfNeeded()`
  considers BASS. Returns `false` if `bass.dll` itself can't be
  loaded/resolved or `BASS_Init()` fails — a plugin individually failing to
  load is only logged, not fatal, since losing one format shouldn't take
  down the other.
- **Linux port, step 3**: `BassLibrary::load()`, `BassAudioDeck::setSource()`,
  and `AppConfig::bassLibraryAvailable()` each gained an `#if defined(_WIN32)`
  / `#else` split so the BASS backend actually works on Linux once the user
  supplies their own licensed binaries there too (same never-bundled
  redistribution situation as the Windows `.dll`s). The Linux branch looks
  for `libbass.so`/`libbassflac.so`/`libbassopus.so` (the standard Unix
  `lib<name>.so` naming BASS's own official Linux SDK distribution uses)
  and passes every file path through `QFile::encodeName()` with flags `0`
  instead of `std::wstring`/`BASS_UNICODE` — non-Windows BASS has no
  UTF-16/ANSI distinction, it always takes plain UTF-8 `char*`. The
  `BASSCALL` calling-convention macro (`basslibrary.h`) already handled
  this correctly beforehand (`__stdcall` on Windows, plain cdecl
  elsewhere) and needed no change. Not yet tested on an actual Linux
  machine — see the `future_linux_port` project memory for the roadmap.
- **Construction timing and backend selection**: decks are created by
  `createDecksIfNeeded()`, called once from `setAppConfig()` the first time
  a non-null `AppConfig` is bound — not in the constructor, since choosing
  FFmpeg vs BASS needs `audioBackend()`/`bassLibraryAvailable()`, neither
  available that early. It picks BASS only if all three hold: `audioBackend()
  == "bass"`, `bassLibraryAvailable()` is `true`, and
  `BassLibrary::instance().load()` itself succeeds; if BASS was the stored
  preference but any of those fails (DLLs removed since being selected, or
  `load()` fails for some other reason), it falls back to `FfmpegAudioDeck`
  **and** calls `appConfig->setAudioBackend("ffmpeg")` to correct the
  persisted setting, so Setup's UI never shows BASS selected while Topaz is
  actually running FFmpeg underneath. This construction-timing requirement
  is also why every `Q_PROPERTY` getter that touches `m_deck`
  (`isPlaying()`/`position()`/`duration()`) must tolerate it being null —
  QML evaluates properties reactively and can reach them before
  `setAppConfig()` ever runs, which a first attempt at this refactor
  didn't account for (crashed on every launch with `STATUS_ACCESS_VIOLATION`
  until every such getter got a null guard).
- **Not hot-swapped**: the backend is read once per launch; changing the
  PLAYBACK tab's radio while running updates the persisted setting for the
  *next* launch only, not the live engine — a "Takes effect after
  restarting Topaz." hint is shown under the radio group for this reason.

### Audio-buffer tap for the Audio Visualizer/Milkdrop (Step 3)

The Audio Visualizer (UC-19) and Milkdrop (UC-20) both independently
subscribe to the same `PlaybackEngine::audioBufferAvailable(QAudioBuffer)`
signal, each doing their own `QAudioFormat::Float`/`Int16` interleaved
downmix — neither has any BASS-specific coupling. This meant a single tap
added to `BassAudioDeck`, wired through the same signal path
`FfmpegAudioDeck` already used, fixed both features under BASS at once
(what could have been two separate future steps collapsed into one).

- `void audioBufferReceived(const QAudioBuffer &buffer)` was **promoted
  into `AudioDeck` itself** (previously `FfmpegAudioDeck`-only, per Step
  2's original doc comment) — a plain Qt signal-inheritance promotion, no
  different from `QAbstractButton::clicked` being inherited by every
  button subclass. `FfmpegAudioDeck` now connects
  `QAudioBufferOutput::audioBufferReceived` straight to the inherited
  `AudioDeck::audioBufferReceived` instead of redeclaring its own.
  `PlaybackEngine::createDecksIfNeeded()`'s connect for this signal is now
  a single, type-agnostic `connect(deck, &AudioDeck::audioBufferReceived,
  ...)` for every deck — the `qobject_cast<FfmpegAudioDeck*>` special-case
  it used during Step 2 is gone.
- **`BassAudioDeck`'s tap**: BASS has no push-based buffer notification
  (unlike `QAudioBufferOutput`), so a second `QTimer` (`m_bufferTapTimer`,
  ~25ms — much tighter than the existing 100ms position-poll timer, since
  1024 samples at 44.1kHz is ~23ms and the Audio Visualizer's KissFFT
  pipeline needs roughly that cadence to stay fed) pulls PCM via
  `BASS_ChannelGetData(handle, buf, byteLen | BASS_DATA_FLOAT)` — BASS's
  own documented mechanism for feeding a visualizer, which returns the
  most recently played audio regardless of the stream's native format.
  Started/stopped in lockstep with the existing position-poll timer at the
  same `play()`/`pause()`/`stop()`/`setSource()` call sites. `freq`/`chans`
  are queried once per `setSource()` via `BASS_ChannelGetInfo()` (cached,
  same "cache what's static, poll what's dynamic" convention `duration()`
  already uses) and sanity-checked (`freq` in `[8000, 192000]`, `chans` in
  `[1, 8]`) before trusting them to build a `QAudioFormat` — mitigation for
  not having a local `bass.h` to double-check `BASS_CHANNELINFO`'s layout
  against. The returned byte count is truncated to a whole number of
  frames before wrapping it in a `QAudioBuffer`, since BASS can legitimately
  return less than requested (e.g. right after `play()`) and a partial
  trailing frame would misalign either consumer's interleaved sample math.
  Unlike `BASS_SYNC_END`, this runs entirely on the deck's own (Qt/GUI)
  thread — it's driven by our own `QTimer`, not a BASS-internal callback —
  so no `QMetaObject::invokeMethod` marshaling is needed here.
- `BassLibrary` gained `BASS_ChannelGetInfo`/`BASS_ChannelGetData` and the
  `BASS_CHANNELINFO` struct/`BASS_DATA_FLOAT` constant alongside its
  existing resolved entry points.
- The crossfade dual-deck simplification (only the active deck's buffers
  reach `PlaybackEngine::audioBufferAvailable`, via the `d == m_activeDeck`
  filter) needed no changes — `BASS_ChannelGetData` is a non-destructive,
  monitoring-style read, so tapping the standby deck redundantly (its
  result then gets dropped by the filter) has no side effect on that
  deck's actual audio output.
- No changes needed in `AudioVisualizerController` or `MilkdropView` —
  both already handle arbitrary buffer sizes/cadence and only require
  `QAudioFormat::Float`/`Int16`, exactly what the synthesized BASS buffer
  advertises.

### Normal Flow — Crossfade a transition

1. On every `positionChanged` tick of the **active** deck, `PlaybackEngine` checks: is
   crossfade enabled, is a next track queued, and — **the eligibility rule** — do
   *both* the active track's live `AudioDeck::duration()` and the next track's tag
   `TrackInfo.duration` exceed the configured crossfade length? If not, nothing
   happens and the transition falls through to the existing hard-cut path
   (`AudioDeck::endOfMedia()` → `onDeckEnded()` → `advanceToNext()` → `loadTrack()`).
2. Once `position >= duration − crossfadeMs`, `startCrossfade()` captures
   `m_fadeOutDeck = m_activeDeck` and `m_fadeInDeck = 1 - m_activeDeck` — fixed for
   this fade's whole lifetime, independent of when the UI-facing `m_activeDeck` alias
   itself later swaps (see step 4) — loads the next track into `m_fadeInDeck` at
   volume `0`, starts it playing, and starts `m_fadeTimer` (~40 ms tick).
3. Each tick (`onFadeTick()`) advances a simple elapsed-ms counter (not wall-clock —
   stopping the `QTimer` freezes the fade exactly in place, which is what makes pause
   trivial) and linearly sets `m_fadeOutDeck.volume = 1 − frac`,
   `m_fadeInDeck.volume = frac`.
4. At the **midpoint** (`frac >= 0.5`, fired once): `m_activeDeck` (and the `m_deck`
   alias pointer) swap to `m_fadeInDeck` **here**, not at
   fade-completion — immediately followed by `switchCurrentIndexTo(nextIdx)`
   (`m_currentIndex` advances, `rating`/`ratingId` resolve for the incoming track, the
   cover fetch kicks off, `currentIndexChanged`/`currentTrackChanged`/
   `currentRatingChanged` fire) and explicit `durationChanged()`/`positionChanged()`/
   `isPlayingChanged()` emissions. This is the single point that satisfies "update
   *everything* in `NowPlaying` — including the length label and play/pause icon, which
   read through the now-swapped `m_deck` alias — and `PlaybackQueue`'s highlighted
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

- **Why dual-deck**: neither backend (`QMediaPlayer` nor BASS) can play two
  sources at once, so a real crossfade requires two independent `AudioDeck`
  instances. `m_deck` is kept as an alias pointer to `m_decks[m_activeDeck]`
  specifically so every pre-existing single-deck code path continues to
  work unchanged — see "AudioDeck abstraction (Step 2)" above.
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

1. User clicks AUTO PLAY. The button is only clickable/green once
   `autoPlayReady` (`libraryModel.ratingsReady`) is `true` **and** the criteria leave
   something to play:
   - `autoPlay.genreRequirementMet` — always `true` when `autoPlayConsiderGenre` is
     off, otherwise it requires `activeGenreNames` (bound from `lib.activeGenreNames`)
     to be non-empty, since with Consider Genre on and zero active genres AUTO PLAY
     could never find a single eligible candidate.
   - `autoPlay.ratingRequirementMet` — always `true` when `autoPlayConsiderRating` is
     off, otherwise `LibraryModel::autoPlayCandidateCount(activeGenreNames,
     considerGenre, true, minimumRating) > 0`: at least one library track must pass
     the very filters `pickNextCandidate()` will apply (Consider Genre included, so a
     rated track in a *non-active* genre doesn't count; a minimum rating above every
     rating in the library leaves nothing either). Before this gate existed, Consider
     Rating with no qualifying rating left the button green: `start()` silently did
     nothing on an empty/finished queue, and with something playing it activated and
     starved on the first poll tick. The value is recomputed live — it re-notifies on
     changes to Consider Rating / Minimum Rating / Consider Genre, to the active genres,
     and to the library (`libraryRefreshed`, and `ratingsChanged` from a star click or
     rating deletion, see UC-14), so rating a track this session turns the button
     green without a rescan.

   `BottomBar` combines these into a local `autoPlayGated` property for its color and
   click-handler: `autoPlayReady && (!autoPlay || autoPlay.active || (genreRequirementMet
   && ratingRequirementMet))`. **The criteria only guard *starting* a session** — the
   `autoPlay.active` term keeps a running session's button live (red, clickable) even if
   the criteria stop being met mid-session (all genres untoggled, a rating deleted, the
   minimum raised); before this the same gate also disabled the click, so such a
   session could no longer be stopped from the button. It then starves on its own at
   the next top-up (below). `start()` re-checks `genreRequirementMet()` and
   `ratingRequirementMet()` itself (defense in depth) before doing anything else, so it
   refuses to start regardless of how `toggle()` was invoked.
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
loaded — **or by `seek()`** (see below). This applies uniformly to AUTO
PLAY additions and manual ones (`AlbumCard`'s double-click, drag-and-drop
into `PlaybackQueue`) alike, since both call through `addTrack()`/
`addTracks()`. `PlaybackEngine` also exposes a plain public
`queueFinished()` getter (not `Q_PROPERTY`/`Q_INVOKABLE` — C++-only) so
`AutoPlayController::start()` can apply the exact same "empty or finished"
test when deciding whether *starting* a session should also play
immediately (Normal Flow step 4 above), not just `addTrack()`/
`addTracks()` themselves.

**Real bug fixed after initial ship — a third state the original design
missed**: a manual seek doesn't fit either "queue naturally finished" or
"merely paused." A user who lets a track play to its natural end, then
drags the NowPlaying position slider back ~30s to re-listen to the
ending, is in a state `seek()` used to leave completely alone —
`m_queueFinished` stayed `true` (only `loadTrack()`/`clearQueue()` cleared
it), so adding a track right after that seek still satisfied
`addTrack()`/`addTracks()`'s auto-play condition and immediately hijacked
playback out from under the track the user was actively re-listening to.
Fixed by having `seek()` also clear `m_queueFinished` — a manual seek is a
deliberate re-listen, not "I'm done with this queue." This has a
deliberate, consistent knock-on effect on `AutoPlayController::start()`
(reading the same flag): pressing AUTO PLAY right after seeking back into
a finished track no longer auto-plays immediately either, falling back to
the normal poll-tick top-up like the "something's actually playing or
paused" case already does — the same underlying signal ("is the user
actively re-listening to something") applied consistently everywhere
`m_queueFinished` gates a decision, not a one-off patched around the
single reported call site.

### Alternate: starvation

Whenever `pickNextCandidate()` returns nothing during an active session (a poll tick's
top-up, or stall recovery), `stop(true)` runs: the poll timer stops, `m_active` becomes
`false`, and the three gating/active signals fire. `BottomBar` turns green again purely
as a consequence of `activeChanged()` — no separate "reset" step needed. A `starved()`
signal fires alongside, and a system-tray notification is shown (see "Desktop
notifications" below). Per the current design, nothing more sophisticated happens on
starvation: AUTO PLAY simply stops and MANUAL MODE resumes.

### Alternate: stopped by a missing track

`setEngine()` also connects `PlaybackEngine::trackMissing` (see UC-31) to a
third private slot, `onTrackMissing()`, which calls `stop(false)` if a
session is active — the same manual-deactivation path the footer button
uses, not the starvation path (no `starved()` signal, no starvation tray
message), since this isn't "no candidates left," it's "the file Topaz was
about to hand to a deck no longer exists." The MISSING TRACK dialog and
folder rescan themselves are entirely `PlaybackEngine`/QML concerns (see
UC-31) — `AutoPlayController` only needs to know to get out of the way.

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

**Linux port, step 1**: steps 1-2 above (`setFormat()`/`create()`) are plain
cross-platform `QQuickWindow`/`QSurfaceFormat` calls and now run unconditionally on
every platform. Only step 3 (the actual `DwmSetWindowAttribute()` call, plus the
`<windows.h>`/`<dwmapi.h>` includes and the hardcoded constants) is wrapped in
`#ifdef Q_OS_WIN` in `windowchrome.cpp` — a no-op on Linux, where most window
managers don't draw this kind of per-window accent border in the first place. Same
guarding approach as `SystemVolumeController`; see the `future_linux_port` project
memory for the roadmap.

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
function visibleFraction(x, y, w, h) { ... }          // share of the rect on Qt.application.screens
function restorePaneGeometry(win, configured, sx, sy, sw, sh, defaultW, defaultH) { ... }

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
            // saved geometry (size clamped to its screen, >= half visible) or the
            // 400x400 centered-on-primary default -- shared by all four panes
            root.restorePaneGeometry(bigCoverWindow, appConfig.bigCoverPaneConfigured,
                                     appConfig.bigCoverPaneX, appConfig.bigCoverPaneY,
                                     appConfig.bigCoverPaneWidth, appConfig.bigCoverPaneHeight,
                                     400, 400)
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
- **Screen validation on restore**: `Main.qml`'s `restorePaneGeometry()` (one shared
  helper for all four panes — the four copies of this logic used to drift apart)
  guards against a monitor having been unplugged or rearranged since the pane was
  last positioned. `visibleFraction()` sums the saved rect's overlap with every
  connected screen's geometry (`Qt.application.screens[i].virtualX/Y` +
  `width`/`height`, the same virtual-desktop coordinate space `Window.x/y` use);
  the saved spot is only used if **at least half** of it is visible — the earlier
  "overlaps at all" test restored a pane saved on an unplugged display as a
  barely reachable sliver. Otherwise the pane falls back to a centered default on
  the primary screen. The saved size is also clamped to the screen the pane lands
  on (the one containing the saved rect's center), never below the pane's minimum
  size, and scaled *uniformly* for an aspect-locked pane (Big Cover) so it stays
  square.
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

**DURATION's live remaining-time countdown**: unlike every other field in this
pane (all of which reuse `currentTrackChanged`, firing once per track — see
above), the DURATION spec field shows `remaining | total` (e.g. `0:34 | 5:10`), where
the left half is a live countdown that ticks once per position update while the
track plays — the pane's first field bound to the high-frequency
`positionChanged` signal, the same one that already drives `NowPlaying`'s
ascending elapsed-time counter, just running in reverse. `PlaybackEngine` gained
one new getter for this, `remainingString()` (`Q_PROPERTY`, `NOTIFY
positionChanged`, matching `positionString`'s own NOTIFY choice for the same
reason — duration only changes once per track, but remaining time must tick at
playback cadence): `msToString(duration() - position())`, reusing the existing
private `msToString()` helper `positionString()`/`durationString()` already share.
`msToString()`'s existing `ms <= 0 → "0:00"` floor means a timing-granularity
overshoot right at track-end shows `0:00`, never a negative value.

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
FOLDERS (Main.qml owns a plain bool; the button just emits `scanRequested()` and
reflects the externally-bound `scanning` property back). TAG INFORMATION follows the
**SCAN FOLDERS** idiom — there's no gating logic here, just open/closed — via a
new `signal tagInfoToggleRequested()` and `property bool tagInfoPaneOpen` (bound from
`Main.qml`), with the button's color reading `tagInfoPaneOpen` the same way the
generic `modelData.active` path already did.

### `Main.qml` wiring

Exact structural mirror of the `bigCoverLoader` block from UC-17 (`tagInfoLoader` /
`tagInfoPaneOpen` / `TagInfoWindow` in place of `bigCoverLoader` / `bigCoverPaneOpen`
/ `BigCoverWindow`), including the same `Loader.onLoaded: { item.engine = engine }`
pattern (required for the same Component-root scoping reason as UC-17), the same
`restorePaneGeometry()` reuse for geometry restore/validation, and the same
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
discovered mid-implementation. This was written before the BASS dual-backend work
(UC-15 "Step 2") existed; see below for how the tap generalized to cover both backends.

`PlaybackEngine` runs two independent `AudioDeck` instances for crossfading (see
UC-15) — originally two `QMediaPlayer`/`QAudioOutput` pairs directly, refactored
behind the `AudioDeck` interface in Step 2, with `FfmpegAudioDeck` now owning the
`QAudioBufferOutput` internally. `void audioBufferReceived(const QAudioBuffer&)` is
a signal on `AudioDeck` itself (promoted there in Step 3, once `BassAudioDeck`
gained an equivalent tap — see "Audio-buffer tap for the Audio Visualizer/Milkdrop
(Step 3)" under UC-15). `PlaybackEngine::createDecksIfNeeded()` connects it
identically for every deck, regardless of concrete type, to a `[this, d]` lambda
that emits `PlaybackEngine`'s own public signal, `void audioBufferAvailable(const
QAudioBuffer &buffer)`, **only when `d == m_activeDeck`** (see the `PlaybackEngine`
Public API section above for the signal's own doc comment) — this filtering is
backend-agnostic and needed no changes when BASS's tap was added.

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
identically to the PLAYBACK/AUTO PLAY tabs it was built from: custom-styled
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

   **Minimum OpenGL: 3.3 Core Profile (GLSL 3.30).** That is what this step
   requests (`setProfile(CoreProfile)` + `setVersion(3, 3)`) and what
   projectM's own shaders are written for (`#version 330`; projectM's only
   alternative is an OpenGL ES 3 build, `ENABLE_GLES`, Linux-only, which Topaz
   does not use). `glxinfo -B | grep "core profile version"` (Mesa's
   `mesa-utils`) shows what a Linux machine offers. Found on an Ubuntu Studio
   test machine whose driver could not provide it. Failure handling: a failed
   `create()`/`makeCurrent()` **or** a granted `format().version()` below 3.3
   (Qt does not guarantee the granted format matches the request; the
   *profile* field is deliberately not checked, so a driver that renders fine
   is never rejected on a metadata technicality) sets `initFailed`, and
   `MilkdropWindow.qml` shows a placeholder naming the requirement. Both
   paths also log — via `logDiagnostic()`, so into `milkdrop_debug.log` — what
   the driver actually offers when asked for nothing in particular
   (`GL_VERSION`/`GL_RENDERER` of a default-format probe context), so a "too
   old" report says *how* old.
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

**The name update itself is deliberately delayed to match projectM's crossfade.**
`preset_switched_event_callback` fires the instant a switch is *requested*,
not once the new preset actually fills the screen — for anything other than
a hard cut, projectM blends the outgoing and incoming preset together over
`projectm_get_soft_cut_duration()` seconds (`ProjectM.hpp`'s
`m_softCutDuration{3.0}`, never overridden by Topaz, so effectively always
3s). Updating `m_currentPresetName`/emitting `currentPresetNameChanged()`
synchronously in the callback therefore made the toast visibly name the
*next* preset several seconds before it actually took over the screen. The
callback now instead captures the resolved name and defers the actual
property update via `QTimer::singleShot()`, delayed by
`projectm_get_soft_cut_duration(m_projectM)` seconds for a soft cut, or `0`
for a hard cut (`isHardCut`, the callback's own first parameter — a hard cut
has no blend, so there's nothing to wait for). Safe to call directly (no
cross-thread marshaling) since the callback already runs on the GUI thread.

**A superseded switch's deferred toast is suppressed via a generation
counter.** The delay above assumes each switch is a single, tidy event, but
with Hard Cuts enabled (`AppConfig.milkdropHardCutsEnabled` +
`milkdropHardCutSensitivity`) that isn't always true: projectM's own
beat-driven hard-cut logic can fire a second, independent switch just 0-2s
after a duration-triggered soft cut, confirmed in practice via
`milkdrop_debug.log` (a `hardCut=0` switch immediately followed by a
`hardCut=1` switch to an unrelated preset). Since the soft cut's toast is
still waiting out its ~3s delay when that happens, it would otherwise land
right after the hard cut's — naming a preset that never actually finished
crossfading in, i.e. two different, both-wrong names popping up in quick
succession. `MilkdropView::m_presetSwitchGeneration` is incremented on every
switched-event callback; each deferred `QTimer::singleShot` update captures
the value at scheduling time and is a no-op if the counter has since moved
on, so only the most recent switch's name ever actually reaches the screen.

### Known limitations (not fixed, not requested)

- No bundled presets — see above; the pane renders nothing until the user
  configures at least one preset folder.
- **`.milk2` presets are not supported — a projectM limitation, not
  Topaz's.** MilkDrop3 introduced `.milk2` as a distinct "double-preset"
  format (two presets rendered simultaneously, composited together) —
  genuinely different from classic `.milk`, not just a renamed variant.
  Verified directly against projectM's source, both the pinned `v4.1.7`
  vendored via `FetchContent` and the current upstream `master` branch:
  `MilkdropPreset::Factory::supportedExtensions()` returns exactly `".milk
  .prjm"`, and `Playlist::AddPath()` hardcodes `entry.path().extension() ==
  ".milk"` for both recursive and non-recursive folder scans — no
  `.milk2` parser or discovery path exists anywhere in libprojectM, at any
  version, so `.milk2` files are silently skipped when scanning a preset
  folder and would fail to load even if added individually. (Some
  preset-pack forum posts claim `.milk2` "loads perfectly in projectM
  v4.0+" — likely conflating projectM with NestDrop, a separate,
  independently-developed VJ engine mentioned in the same sentence in those
  posts, which may have implemented `.milk2` compositing itself; not
  something confirmed in projectM's own source or documentation.) Adding
  real support would mean implementing dual-preset compositing from
  scratch — out of scope unless projectM itself adds it upstream.
- **Some plain `.milk` presets from the same MilkDrop3-era packs also fail
  — not a file-extension issue this time, a shader-function one.** Some
  MilkDrop3-authored presets call custom shader functions
  (`get_fft(pos)`/`get_fft_hz(freq)`, `get_bar_height(...)` — used by
  presets that read live FFT/spectrum data directly inside a custom
  warp/comp pixel shader, e.g. an equalizer-bar visualizer) that MilkDrop3
  added to its own shader runtime but that don't exist anywhere in
  projectM — confirmed by grepping projectM's entire source tree (zero
  matches for either name) and reading its actual shader-header include
  (`MilkdropPreset/Shaders/PresetShaderHeaderGlsl330.inc`, which lists
  every built-in macro/function a preset's shader code can call —
  `GetPixel`/`GetBlur1-3`/named samplers/etc., nothing FFT-related). A
  preset calling an undefined shader function fails to compile, so it
  can't render as intended — same underlying story as `.milk2` above
  (MilkDrop3 extended the shader model beyond classic MilkDrop 2, which is
  what projectM implements), just surfacing through an otherwise-ordinary
  `.milk` file instead of the `.milk2` extension. Found by direct
  inspection of one user-reported broken preset
  (`MilkDrop3 - Equalizer1b.milk`, whose own header comment literally
  named `get_fft(pos)`/`get_fft_hz(freq)` as "Functions used"); a
  collection-wide grep found 9 of 311 `.milk` files in that pack affected
  (all from the same "Equalizer" preset series) — deleted from disk at the
  user's request rather than left as silently-broken entries in a preset
  folder. Not fixable on Topaz's side; would require projectM itself to
  add these functions to its shader environment.
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
   `considerGenre`/`matchWholeWord`/`activeGenreNames`/`enabledGenreNames`
   change (the latter two gated so only the one actually in effect
   re-triggers a search — see "Alternate: Consider Genre" below). When it
   fires, it calls `LibraryModel.searchLibrary(query.trim(), mode,
   considerGenre ? activeGenreNames : enabledGenreNames, true,
   matchWholeWord)` and assigns the result to `SearchData.results`.
   `considerGenre` is always passed as `true` to the C++ call now — search
   is always genre-restricted, only the source list changes.
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
  to `SearchData.considerGenre`. Search is **always** genre-restricted
  (`searchLibrary()`'s `considerGenre` parameter is always passed `true`);
  the checkbox only chooses which list `t.genre` is checked against:
  - **Unchecked (baseline)**: `AppConfig.enabledGenres` — every genre
    currently enabled in Setup, i.e. every genre that has a button in
    `GenreBar` at all, regardless of whether that button is currently
    toggled on. This is what keeps a *disabled* genre's tracks out of search
    results even without the user touching this checkbox — see UC-03.
  - **Checked**: `LibraryData.activeGenreNames` — narrows further to only
    the genres currently toggled *active* in `GenreBar` this session.
  `SearchData` therefore has two deliberate, read-only dependencies now
  (`activeGenreNames` from `LibraryData`, `enabledGenreNames` from
  `AppConfig`) — nothing else couples it to either.

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
  Deliberately has no equivalent enabled-genre restriction: a playlist's
  saved tracks remain fully browsable/loadable regardless of any genre's
  enabled/disabled state in `GenreBar` — `PlaylistsData`/`PlaylistsPanel`/
  `PlaylistViewer` have no genre-filtering path at all, unlike `SearchData`.
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
  across the swap, unlike `LibraryTree`'s: each `ListView`'s top-visible
  row is mirrored into `LibraryData.albumScrollIndex`/`albumScrollOffset`
  and `SearchData.resultScrollIndex`/`resultScrollOffset`
  (`onContentYChanged`, computed via `ListView.indexAt()`) — since those
  data objects, unlike the views themselves, survive the `Loader` swap —
  and restored via `positionViewAtIndex()` (plus the sub-offset) inside a
  `Qt.callLater` the next time that view is (re)created (`onLibChanged`/
  `onSearchDataChanged`, both of which fire exactly once per (re)creation,
  not on every ordinary model refresh while the view stays loaded). This
  is index-based rather than a raw `contentY` pixel value for the same
  reason the scrollbar-drag fix is (see UC-12, "Why the variable-height
  panels use index-based positioning"): `AlbumCard`'s content-derived
  height makes `contentHeight` only an estimate until every delegate is
  realized, and right after a `Loader` recreates the view only the first
  few delegates exist — restoring a saved pixel value against that
  still-top-biased estimate can land on a different logical row than
  where the user actually was, and a single `Qt.callLater` tick doesn't
  guarantee enough delegates get realized to fix that. The `Qt.callLater`
  defer is still required for a different reason: the model
  (`currentAlbums`) needs to have actually been assigned before
  `positionViewAtIndex()`/`count` are meaningful. `LibraryTree`'s own
  scroll offset and expand-state remain unpreserved (see previous point)
  since those stay genuinely tied to the destroyed/recreated view
  instance itself, with no natural home on `LibraryData` the way a scroll
  anchor has.

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
   (case-insensitive). If `PlaylistsData.selectedFileName` is currently
   empty (nothing selected yet this session), the first playlist that isn't
   already active in the queue is auto-selected via `selectPlaylist()` —
   this only fires on empty selection, so re-entering PLAYLISTS after
   browsing LIBRARY/SEARCH preserves whatever was already selected instead
   of resetting it.
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
   prop), so drag-to-queue and double-click-to-queue work the same way
   (see UC-06) — except when the previewed playlist is the one active in
   the queue, see "Alternate: Playlist already active in the queue"
   below. The header shows the track count, total playtime, and playlist
   name on the right — `N TRACKS | <playtime>  —  NAME`, the playtime
   summed from each track's `durationMs` and formatted `M:SS` under 100
   total minutes or `H:MM:SS` from 100 minutes up, the identical rule
   `ExportPlaylistDialog.qml` uses for its own playtime caption (UC-26);
   the left side (where `AlbumBrowser`/`SearchResultBrowser` show
   "ALBUM BROWSER"/"SEARCH RESULT") instead shows a compact **LOAD**
   button (see step 6).
6. User clicks **LOAD** — active for *any* selected playlist, empty or
   not (as long as it isn't already the active one), rather than being
   gated on track count. Three outcomes depending on what's selected:
   - **Non-empty** (`selectedRawTracks.length > 0`): identical effect to
     UC-10's LOAD button, except no `FileDialog` is shown (the file was
     already picked in step 4) and no `PlaylistManager.loadPlaylist()`
     re-parse happens — the already-cached `PlaylistsData.selectedRawTracks`
     is handed straight to `PlaybackEngine.loadPlaylistTracks()`, which
     **always** replaces the queue, crossfading into it if eligible (see
     UC-23), followed by `engine.setActivePlaylistName(selectedFileName)`
     — exactly the same step-6 flow UC-10 uses.
   - **Genuinely empty** (0 tracks, 0 missing): still calls
     `loadPlaylistTracks([])` + `setActivePlaylistName(selectedFileName)`
     — the playlist becomes active with an empty queue, so
     LIBRARY/SEARCH additions start syncing to it (`PlaybackEngine`'s
     per-mutation XSPF sync), which is otherwise the *only* way a track
     can ever be added to a playlist file. A plain "EMPTY PLAYLIST" /
     "The playlist is still empty." `MessageBox` (`emptyPlaylistBox`,
     `PlaylistViewer.qml`) explains why nothing started playing. From
     here the user can add tracks (now that it's active), click REMOVE in
     `NowPlaying` to unload it — correctly clears `activePlaylistName`
     even at 0 tracks, see UC-09's `clearQueue()` fix — or, after REMOVE,
     DELETE it from PLAYLISTS (still disabled while active, by the
     unchanged "can't delete what's active" rule below).
   - **All tracks missing** (0 resolved, ≥1 missing): unchanged from
     before — no queue/active-playlist change, just opens
     `MissingTracksDialog` listing them (see UC-10's "All or some tracks
     missing").

   In every case the selection deliberately stays on the just-loaded
   playlist — it isn't moved to a neighbor — so an activated one now
   simply renders as "(IN QUEUE)" in `PlaylistsPanel` on the next redraw
   (see "Alternate: Playlist already active in the queue" below).
   `PlaylistsData.selectNeighborOf()` still exists and is used by the
   trash-bin DELETE flow, whose target really does stop existing.

### Alternate: Playlist already active in the queue

A playlist row whose `fileName` matches `engine.activePlaylistName` (the
playlist currently loaded into the queue) is rendered dimmed with an
"(IN QUEUE)" label in `PlaylistsPanel`, but remains fully selectable —
clicking it previews its tracks like any other playlist. What's disabled
instead lives in `PlaylistViewer`, gated by a single readonly property,
`isSelectedActiveInQueue` (true when the *selected* playlist's `fileName`
equals `engine.activePlaylistName`):
- **LOAD** (`loadBtn.active`) and the **trash-bin** (`deletePlaylistBtn.active`)
  both gain `&& !isSelectedActiveInQueue` — re-loading or deleting the
  playlist file backing the live queue while it's active doesn't make
  sense.
- Each track card's drag-to-queue and double-click-to-queue are disabled
  via a new `AlbumCard.queueInteractionEnabled` property (default `true`
  everywhere else), bound to `!isSelectedActiveInQueue` here — the
  per-track `MouseArea` that owns both interactions is simply `enabled:
  queueInteractionEnabled`, so neither can fire while the previewed
  playlist is the active one.

This is a plain reactive binding on `engine.activePlaylistName`
(`NOTIFY`-backed `Q_PROPERTY`), so all of the above updates immediately if
the active playlist changes elsewhere (e.g. REMOVE/LOAD in `NowPlaying`)
while PLAYLISTS is the active tab — including while the active-in-queue
playlist is the one currently selected/previewed.

**Live mirror of the queue, not the XSPF file.** While
`isSelectedActiveInQueue` is true, `currentAlbums` and the new
`currentRawTracks` are sourced from `_liveQueueAlbums`/
`_liveQueueRawTracks` instead of `PlaylistsData.albums`/
`selectedRawTracks` (the last disk read). The XSPF file isn't a reliable
live source for the active playlist specifically — `PlaybackEngine` skips
`rewritePlaylist()` while `playlistLocked` is `true`, flushing only once
unlocked — so both mirror arrays are rebuilt in one pass straight from
`engine.trackList()` (`_liveQueueAlbums` via
`LibraryModel.buildStandaloneTrackCards()`, the same conversion
`PlaylistsData.selectPlaylist()` uses) by `refreshLiveQueue()`. That
function is called imperatively, never bound declaratively —
`trackList()` is `Q_INVOKABLE`, not a `NOTIFY`-backed `Q_PROPERTY`, and a
binding on it would freeze at first paint. It's triggered from a
`Connections` block on `engine`'s own `rowsInserted`/`rowsRemoved`/
`rowsMoved`/`modelReset` signals (`PlaybackEngine` is itself the queue's
`QAbstractListModel`), so the preview stays live while AUTO PLAY appends
tracks or the user reorders the queue via `PlaybackQueue` — always
visible in its own `SplitView` slot regardless of which TopBar tab is
active — all without leaving PLAYLISTS. `currentRawTracks` is what
`exportBtn.active`, `totalPlaylistDurationMs`, and `Main.qml`'s
`exportPlaylistRequested` handler (`exportPlaylistDialog.tracks =
item.currentRawTracks`) all read — reading `PlaylistsData.selectedRawTracks`
directly for the active playlist would show EXPORT permanently disabled
and the playtime caption stuck at 0:00, since that property is never
refreshed while the live mirror is in use (a real regression hit once,
fixed by routing all three through `currentRawTracks`).

**Auto-scroll to now-playing.** Also while `isSelectedActiveInQueue`,
`scrollToNowPlaying()` calls `resultList.positionViewAtIndex(engine.currentIndex,
ListView.Beginning)` — `buildStandaloneTrackCards()` preserves input
order 1:1, so `engine.currentIndex` (`NOTIFY`-backed) indexes directly
into `_liveQueueAlbums` with no separate id-matching needed. Every
`refreshLiveQueue()` call re-settles it too (deferred via `Qt.callLater`,
since `resultList`'s `contentHeight` needs a tick to catch up with the
new model array first) — without this, an AUTO PLAY addition mid-session
would reset `resultList` to the top (a wholesale model-array replacement
resets scroll position) with nothing to re-correct it until the next
track advance, since adding a track doesn't itself change
`engine.currentIndex`. Between `refreshLiveQueue()`'s own call, the
`Connections` block's `onCurrentIndexChanged` (track advances),
`onIsSelectedActiveInQueueChanged` (manually clicking the (IN QUEUE) row
while already on PLAYLISTS), and `onPlaylistsDataChanged` (switching into
PLAYLISTS while it's already selected), the scroll position holds correct
regardless of *what* changed or *how* the active playlist became the
previewed one. Both `scrollToNowPlaying()` and `refreshLiveQueue()` are
no-ops while the user is mid-drag on the scrollbar thumb — see "Scrollbar
drag and live-queue updates no longer fight each other" below and UC-12.

**Re-sync on every PLAYLISTS entry.** `PlaylistViewer`'s
`onPlaylistsDataChanged` — which, since `Main.qml`'s `Loader` destroys and
recreates this component on every PLAYLISTS↔LIBRARY/SEARCH switch, fires
once per *entry into* PLAYLISTS, not just once ever — now always
re-syncs the current selection: `refreshLiveQueue()` if it's the active
playlist, otherwise a fresh `PlaylistsData.selectPlaylist()` disk re-read
(covering the case where the selected-but-inactive playlist's file
changed via some other means while the user was away). Previously this
handler only restored the saved scroll position and left whatever was
cached in `PlaylistsData` untouched.

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
  `PlaylistViewer`'s top-visible-row anchor mirrors into
  `PlaylistsData.resultScrollIndex`/`resultScrollOffset` and is restored
  via `positionViewAtIndex()` inside a `Qt.callLater` on
  `onPlaylistsDataChanged` — only for the non-active-playlist branch;
  the active/now-playing branch keeps using `scrollToNowPlaying()`
  (already index-based, see below).
- **Scrollbar drag and live-queue updates no longer fight each other**:
  `scrollToNowPlaying()` and `refreshLiveQueue()` are both no-ops while
  `resultThumbMA.pressed` (the scrollbar thumb's `MouseArea`, see UC-12).
  A bare track advance during a drag is simply dropped — the user's
  manual scroll position wins, since nothing about *where* they're
  looking needs to change just because a track advanced. A live-queue
  content change (AUTO PLAY appending a track, a reorder) during a drag
  is instead deferred: `_liveQueueRefreshPending` is set, and a
  `Connections` block on `resultThumbMA.pressedChanged` replays the
  suppressed `refreshLiveQueue()` once the drag ends (covering both a
  normal release and a cancelled/stolen grab) — losing a live update
  entirely would leave `_liveQueueRawTracks`/`_liveQueueAlbums` stale
  (wrong EXPORT payload, wrong playtime caption), which dropping-only
  would have caused.

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

---

## UC-24 Remove Abandoned Ratings (MISC Tab)

| Field | Detail |
|-------|--------|
| **Goal** | One-click cleanup of `Topaz.rating.json` entries whose track no longer exists in the library, without ever touching genre selection/scanning state. |
| **Actor** | User |
| **Precondition** | Topaz is running; the library has been loaded at least once this session. |
| **Trigger** | User clicks **REMOVE** in Setup → MISC. |

A new **MISC** tab (`SetupDialog.qml`, `tabBar.currentTab === 6`) hosts this
single action for now — the first tab in this dialog with no per-setting
persistence of its own, just a one-shot maintenance operation.

### `RatingCache` — exposing the entry API

`Topaz.rating.json` already stores exactly `{genre, ratingId, rating}` per
entry (see UC-14's schema), but the struct and its load/save helpers
(`Entry`, `loadEntries()`, `saveEntries()`) were `private` — only
`RatingCache::load()` (which collapses to a `ratingId → rating` hash,
discarding `genre`) and `setRating()` (single upsert) were public, neither
sufficient for a bulk remove-and-rewrite pass. These three were simply
moved to `public` — no implementation changes — since they already did
exactly what this feature needs.

### `LibraryModel::removeAbandonedRatings()` — the operation

Lives on `LibraryModel` (`Q_INVOKABLE`) since it already owns both
`m_tracks` (the live library) and needs no other component's data.
Exposes two new `Q_PROPERTY`s mirroring the existing `scanning`/
`scanProgress` shape — `removingAbandonedRatings` (bool, busy flag) and
`abandonedRatingsProgress` (int, 0-100) — plus a completion signal,
`abandonedRatingsRemovalFinished(int removedCount, int genreCorrectedCount,
int remainingCount)` (`remainingCount` is the kept list's final size —
every rating still in `Topaz.rating.json` now matches a track in the
library).

**Match semantics — existence only, no genre dependency.** A rating is
"abandoned" (removed) if no track anywhere in the current library has a
matching `ratingId` — a UUIDv5 hash of `albumArtist;artist;album;title`
(`TrackInfo::computeRatingId()`, `trackinfo.h`) that never encodes genre.
This was **deliberately designed without any genre-enabled dependency**
after confirming that `LibraryScanner` filters scanned files only against
`AppConfig.genres()` (the full configured list, up to 40) and never
`AppConfig.enabledGenres()` (the GenreBar-shown subset, up to 30) — see
`libraryscanner.cpp`'s filter logic. A track in a genre that's configured
but currently *disabled* in GenreBar is still fully scanned and present in
`LibraryModel`/`Topaz.library.json`, so checking existence against the
full live track list is equally reliable for enabled and disabled genres
alike; no extra genre-active safeguard is needed for correctness, and none
is applied. (An earlier draft of this feature included such a safeguard as
a caution layer before this was confirmed — removed once the underlying
data was shown to already be fully trustworthy either way.)

**Genre-drift self-correction.** Since `ratingId` doesn't encode genre, a
track re-tagged to a different genre after being rated leaves its
`Topaz.rating.json` entry's `genre` field stale — the only other write
path, `PlaybackEngine::setRating()`, always writes the *current* genre at
rating time, so nothing else ever refreshes it later. Because this pass
already builds a `QHash<QUuid, QString>` mapping every live track's
`ratingId` to its *current* genre (to answer the existence question), it
gets genre-drift correction for free: any surviving entry (track still
exists) whose stored `genre` no longer matches the live value has it
corrected in place before the file is rewritten, counted separately
(`genreCorrectedCount`) from removals.

**Synchronous with chunked progress, not a worker thread.** `RatingCache`
reads/writes already happen synchronously on the main thread today (every
track change and every star click, see UC-14) with no perceptible-lag
mitigation, and a ratings file is realistically far smaller than the
library itself (bounded by the same order of magnitude as "12K tracks in
<100ms", `librarymodel.h`). Rather than introduce a new threading pattern
for what's fundamentally a small, fast, one-off batch, `removeAbandonedRatings()`
runs synchronously, emitting `abandonedRatingsProgressChanged()` and
calling `QCoreApplication::processEvents()` roughly every 25 entries so
the MISC tab's progress bar animates and the UI stays responsive, even
though the whole pass typically completes in well under a second.

### `SetupDialog.qml` — MISC tab UI

A label ("Remove Abandoned Ratings") + a **REMOVE** button using this
dialog's established action-button idiom (`Rectangle` + hover-driven color
+ centered `Text` + `MouseArea`, same as e.g. FILE MONITORING's ADD
FOLDER button) — `onClicked: libraryModel.removeAbandonedRatings()`,
hidden while the operation is already running. A small custom progress
bar (`Rectangle` track + a filled child `Rectangle` whose `width` is bound
to `abandonedRatingsProgress`) is the first progress-bar *visual* anywhere
in the app — `LibraryScanner`'s own `scanProgress` percentage has existed
in C++ since UC-05 but was never wired to a QML visual, so no existing
pattern was available to copy; this one is themed directly with `Theme.*`
tokens to match. On completion, a `MessageBox` (`title: "ABANDONED
RATINGS"`, matching the "PLAYBACK ENGINE" title convention introduced for
UC-15's Setup notices) reports the removed count, a second line for the
corrected-genre count only when it's non-zero, and a third line always
stating the final remaining-rating count ("The N existing ratings now
match the tracks in the library.").

---

## UC-25 Cleanup Incompatible Milkdrop Presets (MISC Tab)

| Field | Detail |
|-------|--------|
| **Goal** | Scan configured Milkdrop preset folders for presets known to be incompatible with Topaz's projectM integration and delete them, via an extensible, growable "checker engine" rather than a one-off hardcoded check. |
| **Actor** | User |
| **Precondition** | Topaz is running. |
| **Trigger** | User clicks CLEANUP in Setup → MISC, then CLEANUP again in the resulting dialog. |

Grew directly out of two real incompatibilities found in the same session:
MilkDrop3's `.milk2` "dual-preset" format (invisible to projectM's playlist
scanner and preset parser at any version — confirmed via source, both the
pinned `v4.1.7` and current upstream `master`) and plain `.milk` files
calling MilkDrop3-only shader functions (`get_fft`, `get_fft_hz`,
`get_bar_height`) that don't exist anywhere in projectM (confirmed via a
full source grep, including projectM's own shader-header include listing
every built-in a preset's custom shader code can call). The user's explicit
ask: encode this knowledge as a standalone, deliberately extensible engine
— "we can then from now on always extend that engine when we find new use
cases of Milkdrops that are not working properly" — not a hardcoded check
bolted directly into the UI.

**A third pattern, found the same session and initially left as inference-only,
was later confirmed broadly enough to become Rule 3** (see below): a handful
of `Equalizer`-series presets had an essentially empty placeholder shader
(just "sample previous frame, decay it") combined with every visible
overlay at zero alpha. A user-reported broken preset outside that series
(`MilkDrop2077 - Dude the walls are moving1.milk`, no relation to
"Equalizer" by name) turned out to share the *exact* same signature —
including an unrecognized `MD31=`/`MD32=` marker field, present but inert
in projectM — which is what moved this from "looks incomplete, might be
deliberate" to "a real, reproducible technical pattern" worth encoding. A
targeted scan of the whole collection for the combined signature (see Rule
3) found 18 candidates; two were caught and correctly excluded during
validation before implementation — one had enabled custom waveforms
(`wavecode_0_enabled=1`/`wavecode_1_enabled=1`, a legitimate alternate
content source untouched by the other two rules), the other superficially
matched (short shader, zero overlay alpha) but its shader genuinely samples
a noise texture and does real math. Both false-positive traps are why Rule
3 checks three conditions together rather than any one alone.

### `MilkdropPresetChecker` (`milkdroppresetchecker.h`/`.cpp`) — the engine

Static-methods-only, no `QObject` — same convention as `TagReader`/
`RatingCache`. One entry point, `checkFile(filePath) ->
MilkdropCompatibilityResult { bool compatible; QString reason; }`:
1. Suffix (case-insensitive) is `milk2` → incompatible, no file read needed.
2. Otherwise, read the file as a raw `QByteArray` (not decoded to `QString`
   first — every needle is pure ASCII, and raw-byte `contains()` sidesteps
   any embedded-NUL/non-UTF-8 author-comment byte entirely) and check
   against a small static table of `{ functionCall, description }` rows
   (`get_fft(`, `get_fft_hz(`, `get_bar_height(`, `tanh(`, `sinh(`, `cosh(`,
   `mul(cross(`, `double2`, `double3`, `double4` today) — first match wins.
   Table rows fall into four categories, each equally fatal since matching
   fails the whole warp/composite shader (a hard parse error in projectM's
   vendored HLSL parser, silently swallowed the same way as any other shader
   compile failure — see `MilkdropShader.cpp`/`PerPixelMesh.cpp`), but for
   different underlying reasons — the struct field is named `needle`, not
   `functionCall`, precisely because not every row is a function call:
   MilkDrop3-only additions never in projectM at all (`get_fft`/etc.);
   standard HLSL intrinsics real MilkDrop2/3 support that are simply missing
   from this vendored parser's intrinsic table (`tanh`/`sinh`/`cosh` —
   confirmed absent while `sin`/`cos`/`exp2`/etc. are all present); a
   known-invalid *argument combination* for an otherwise-fully-implemented
   intrinsic (`mul(cross(...), vector)` — projectM registers dozens of
   `mul()` overloads, scalar/vector/matrix in every combination, but HLSL
   itself has no `mul(vector, vector)` overload at all, so this fails in
   real DirectX too, not just projectM); and a bare type keyword projectM's
   parser never implements at all (`double2`/`double3`/`double4` — no
   `double`-precision support anywhere in its type table, unlike real HLSL
   since Shader Model 5; MilkDrop shaders never legitimately need double
   precision, so any occurrence is an authoring typo, not a real feature
   gap). `tanh()` in particular is a common Shadertoy-style tonemap idiom
   (`o = tanh(o / N)`) in modern ported presets — found via `XorDev -
   MilkDrop2077 - Flutter3.milk`, whose entire warp shader (a raymarched
   fractal effect, otherwise fully compatible) is dropped over that one
   call, leaving only the near-static default warp plus overlays that are
   already invisible for unrelated reasons (`ob_size`/`ib_size` both 0,
   `fWaveAlpha` 0.001). `mul(cross(` was found identically in both
   `MilkDrop2077 - Lasers from the Sky1.milk` and `...Sky2.milk`'s composite
   shader (`mul(cross(ts,-t),screen3)`, almost certainly meant to be
   `dot(cross(ts,-t),screen3)` — a scalar depth value, which is what the
   surrounding division expects) — a shared-template bug across the preset
   family, not a one-off typo, but still narrow enough that a blanket
   `"mul("` match was deliberately avoided: the vast majority of `mul()`
   calls in presets are valid vector·matrix/matrix·matrix uses and would
   false-positive constantly. `double3` was found via `martin - a milkdrop
   edit of XorDevs starship MilkDrop2077 rmx007.milk`'s warp shader
   (`double3 crisp = tex2D(...)`, almost certainly meant to be `float3`) —
   a single-occurrence typo, unlike `mul(cross(`'s shared-template pattern,
   but the compound token is specific enough to encode safely without
   colliding with ordinary preset text the way bare `"double"` might.

This table is the intended extension point: a newly-discovered
substring-based incompatibility is one more row; a structurally different
future rule (not "contains this substring") is a new branch in `checkFile()`
itself. Deliberately returns `compatible = true` for anything unreadable or
unrecognized — this engine only flags *known* incompatibilities, it isn't a
general preset-health validator.

**Rule 3 — no visible content is possible anywhere in the render pipeline.**
A preset is flagged only if *all three* hold together (each one alone
produced a real false positive during validation, see above):
1. Every overlay that could draw new pixels each frame is off:
   `mv_a` (motion vectors) and `fWaveAlpha` (the built-in waveform) are
   both `≤ 0.01`, and each border (outer/inner) is invisible via *either*
   its alpha (`ob_a`/`ib_a` `≤ 0.01`) *or* its size (`ob_size`/`ib_size`
   `≤ 0.001`) — confirmed against projectM's actual `Border::Draw()`
   (`Border.cpp`): a border's quad spans `1-size` to `1`, so a `size` of 0
   collapses it to a zero-area strip and draws nothing *regardless of
   alpha*. Missed originally — a checked-with-alpha-only version let
   `XorDev - MilkDrop2077 - martin - Starship Red Lines.milk` through
   (`ob_a=1.000` but `ob_size=0.000`, genuinely invisible; every other
   overlay already zero, same MD3 marker + "this shader will work only
   with md3" author comment as the rest of this rule's cases) until it was
   reported not working and traced back to this gap. Values are pulled via
   `keyValueOrDefault()`, a small manual line-scanner (matching a `key=` at
   the start of a line, consistent with `TagReader`'s own preference for
   manual byte parsing over `QRegularExpression` elsewhere in this
   codebase) — a **missing** key defaults to `1.0` for both alpha and size
   (assume visible), deliberately biased against false-flagging, since
   Milkdrop's own built-in default for an omitted key isn't something this
   engine tracks.
2. No custom shape/waveform is enabled (`shapecode_N_enabled=1` /
   `wavecode_N_enabled=1` for `N` in `0..3`, the exact key names confirmed
   from projectM's own `CustomShape.cpp`/`CustomWaveform.cpp`) — a
   legitimate, separate content source from the built-in overlay system
   that condition 1 alone can't see.
3. The warp+composite shader's own code (extracted by concatenating just
   the `warp_N`/`comp_N` line values — mirroring `PresetFileParser::GetCode()`'s
   own numbered-key extraction, and deliberately excluding
   `per_frame_*`/`per_pixel_*` equation code, which legitimately uses many
   of the same math functions checked next for entirely unrelated purposes
   like driving motion vectors) contains none of a fixed list of HLSL
   constructs a shader needs to generate any real content from scratch —
   other named samplers, `sin(`/`cos(`/`pow(`/`sqrt(`/`saturate(`/etc.,
   loops. A shader containing only a `sampler_main` feedback read plus a
   flat scalar decay/flip trips none of these.

Reason string returned when all three hold: the preset "likely relies on a
proprietary MilkDrop3 rendering feature with no portable expression of its
actual content" — several confirmed instances carry an `MD3<N>=<huge
number>` field (e.g. `MD31=18385496672307631707`) that is not referenced
anywhere in projectM's source at any version, consistent with this theory
without being provable from outside MilkDrop3PRO's own (closed) internals.

### `MilkdropCleanupController` (`milkdropcleanupcontroller.h`/`.cpp`) — `QObject`, `QML_ELEMENT`

Instantiated once in `Main.qml` (`appConfig: appConfig`), same convention as
every other stateful controller in this app (`LibraryModel`,
`AutoPlayController`, etc.) — not instantiated locally inside the dialog
that uses it, because `Main.qml`'s new `onClosing` veto (below) needs direct
visibility into its `cleaning` property.

- `presetFolders()` (`Q_INVOKABLE`): one `{ path, presetCount, exists }` map
  per `AppConfig.milkdropPresetFolders` entry. `exists` (`QDir(path).exists()`)
  is surfaced separately from a bare zero count, so a folder that's been
  moved/deleted since being configured shows "(folder not found)" in the
  dialog rather than a misleadingly-identical "0 presets" a genuinely-empty
  folder would also show. Synchronous, recursive — fine for
  `MilkdropCleanupDialog.qml` (UC-25), which only calls it once, behind the
  user's own deliberate CLEANUP click.
- `presetFolderExistence()` (`Q_INVOKABLE`) / `scanPresetFolderCountsAsync()`
  (`Q_INVOKABLE`) / `presetFolderCountReady(path, presetCount)` (signal) —
  the async counterpart used by `SetupDialog.qml`'s MILKDROP tab instead of
  `presetFolders()`, added because that tab used to call `presetFolders()`
  synchronously on every open/tab-switch, visibly blocking the UI for
  folders with thousands of presets. `presetFolderExistence()` stays
  synchronous (a single `QDir::exists()` stat per folder, no recursion) so
  "not found" rows still render immediately; `scanPresetFolderCountsAsync()`
  then fires one `QtConcurrent::run()` task per *existing* folder on the
  global thread pool, each calling the same `discoverPresetFiles()` used by
  `presetFolders()`/`startCleanup()` (side-effect-free `const`, safe to call
  concurrently), and reports back via `future.then(this, ...)` — the
  continuation runs on the controller's own thread, so
  `presetFolderCountReady` is emitted from the main thread with no manual
  `QFutureWatcher` bookkeeping. Results arrive in no particular order;
  `SetupDialog.qml` matches each one to its row by path (not index) and
  shows a small rotating-dot `BusySpinner` in the PRESETS column until then.
- `startCleanup(folderPaths)` (`Q_INVOKABLE`): re-entrancy-guarded
  (`if (m_cleaning) return;`, copied verbatim from
  `LibraryModel::removeAbandonedRatings()`'s own guard). Builds one combined
  flat work list across every requested folder up front (so overall
  progress reflects the true combined total, not per-folder), then a single
  pass: `MilkdropPresetChecker::checkFile()` per entry, `QFile::remove()` if
  incompatible — **removed and failed counts tracked separately per
  folder**, unlike this codebase's other two `QFile::remove()` call sites
  (`librarycache.cpp`/`ratingcache.cpp`, both fire-and-forget), since this
  feature's results screen promises an accurate count and a folder with
  thousands of entries realistically hits the occasional permission/lock
  failure. Emits `cleanupFinished({ path, removed, failed, total }[])` at the
  end.
- The recursive preset-file walk (shared by `presetFolders()` and
  `startCleanup()` — written once, not duplicated) mirrors
  `LibraryScanner::discoverAudioFiles()`'s exact shape (manual
  `QDir::entryInfoList()` recursion, suffix allowlist) rather than
  introducing `QDirIterator` as a second recursive-scan idiom into the
  codebase — with one addition `discoverAudioFiles()` doesn't have,
  `QDir::NoSymLinks`, cheap insurance against a Windows junction looping
  back to an ancestor directory in a large third-party-curated preset pack
  Topaz doesn't control the structure of.
- No "is `MilkdropView` currently rendering one of these folders" guard:
  `MilkdropView::rebuildPresetList()` only reacts to the *folder list*
  changing (an `m_appliedPresetFolders` equality check), never re-validates
  folder contents against disk, and projectM already has a
  `preset_switch_failed` event callback for exactly this "a playlist entry
  disappeared out from under it" case (already wired up in
  `MilkdropView::ensureInitialized()`, already logged) — a live render
  session is already stale-tolerant by construction.

**Progress reporting at real scale.** One of the user's configured folders
has ~9800 preset files — each needing an actual disk read + text scan, not
an in-memory lookup like the near-instant ratings cleanup this pattern is
otherwise modeled on. `cleanupProgress`/`currentFileName` are updated (cheap
signal emissions) every single file, matching the user's explicit ask for
per-file granularity, but `QCoreApplication::processEvents()` itself is only
pumped when a `QElapsedTimer` shows ≥16ms since the last pump (~60fps cap)
— avoiding per-call overhead at 10,000-file scale while keeping the UI
visibly live. Runs synchronously on the main thread rather than a worker
thread, matching this codebase's established "fine to do file-cache work
synchronously" convention (UC-24) rather than introducing real threading for
what's still fundamentally a one-off batch, just a longer one.

### `Main.qml` — the first `onClosing` veto in this codebase

`LibraryScanner`'s own long-running full-library scan never calls
`processEvents()`, so the window simply freezes solid while it runs today —
there's no delivery window for a close event to land mid-scan.
`startCleanup()`'s throttled-but-real `processEvents()` pumping is
different: for a multi-second-to-tens-of-seconds pass, the event loop
*is* actively running and genuinely can deliver a window-close event while
the controller is still on the call stack, risking a use-after-free on the
next loop iteration if the QML engine (and the controller with it) got torn
down mid-loop. `ApplicationWindow.onClosing` now vetoes the close while
`milkdropCleanupController.cleaning` is `true`:
```qml
onClosing: (close) => {
    if (milkdropCleanupController.cleaning)
        close.accepted = false
}
```
`MilkdropCleanupDialog.qml`'s own ✕ close button is hidden under the same
condition, for the same reason at the dialog level.

### `SetupDialog.qml` / `MilkdropCleanupDialog.qml` — UI

MISC tab gains a second row below "Remove Abandoned Ratings": label
"Cleanup Incompatible Milkdrop Presets" + a CLEANUP button. Unlike the
plain `Theme.primary`-styled REMOVE button next to it, this one uses
`Theme.error`/`Theme.errorContainer` — the same destructive-action styling
the MILKDROP tab's own "DELETE SELECTED" (folder-entry removal) button
already established in this file — since clicking through actually deletes
real files from disk, permanently, unlike the ratings cleanup's
cache-file-only edit. No extra "are you sure?" confirmation dialog: matches
the user's own spec (none requested) and the Remove-Abandoned-Ratings
precedent (single click, no confirm); the color change is the cheap
mitigation for the higher stakes here.

`MilkdropCleanupDialog.qml` (new, chrome modeled on `NewPlaylistDialog.qml`
— header + ✕ close + fixed size, not `MissingTracksDialog.qml`'s
resize-grip version, since nothing here needs resizing) shows three
mutually-exclusive states in one `Popup` via plain `visible:` toggling (this
codebase's established convention for state-dependent panels, e.g. the
Setup tabs themselves) rather than a `StackLayout`:
- **Idle**: a `ListView` of configured folders (row style — height, mono
  font, `ElideMiddle` — matches the MILKDROP tab's own existing preset-folder
  list) populated into a local `ListModel` when the dialog opens, each row
  with a checkbox (visual copied from the GENRES tab's per-genre enable
  checkbox) defaulting to checked, the path, and its preset count (or
  "(folder not found)"); a CLEANUP button, disabled while nothing's checked.
- **Running**: the same two-`Rectangle` progress-bar visual UC-24 introduced
  (still the only progress-bar idiom in the app) + a "Checking: `<filename>`"
  label bound to `currentFileName`.
- **Done**: a per-folder "`X` of `Y` removed" list (plus a failed-count note
  when non-zero), and a CLOSE button.

Checkbox state is pure ephemeral UI state, tracked only in the dialog's
local `ListModel` and a plain `checkedCount` integer maintained imperatively
in each checkbox's click handler (not via a JS function re-evaluated inside
a binding, out of the same caution documented for the GENRES tab's own
checkbox binding — see the invokable-in-binding gotcha noted elsewhere in
this doc) — never persisted anywhere.

## UC-26 Export Playlist to External Destination

| Field | Detail |
|-------|--------|
| **Goal** | Copy every audio file in a playlist (either the currently-loaded queue, or a playlist merely selected in the PLAYLISTS tab's list) to a chosen destination folder (typically a USB stick, for car use) under a generated `<prefix><index>_<title>.<ext>` filename, after confirming the destination has enough free space and is actually writable. |
| **Actor** | User |
| **Precondition** | Either a named playlist is loaded into the queue and non-empty (`PlaybackEngine.activePlaylistName`/`queueCount`), or a playlist with at least one resolvable track is selected in the PLAYLISTS tab (`PlaylistsData.selectedRawTracks`). |
| **Trigger** | User clicks EXPORT in NowPlaying's playlist-management row, or EXPORT next to LOAD in the PLAYLISTS tab's `PlaylistViewer.qml`, then EXPORT again inside `ExportPlaylistDialog`. |

EXPORT (`NowPlaying.qml`'s Row 2, next to REMOVE) was a permanently-disabled
placeholder from the day that row was first laid out. It's gated the same
way `removePlaylistBtn` is —
`engine.activePlaylistName !== "" && engine.queueCount > 0` — but
deliberately *not* also gated on `autoPlay.queueClearAllowed`: that guard
protects against *clearing* the queue while AUTO PLAY manages it (see
UC-16), and exporting never mutates the queue.

**Open design question the user raised directly**: what happens if Topaz
can't write to the chosen destination — should Topaz attempt Windows UAC
elevation? Resolved explicitly against it: a `ShellExecute` `"runas"`
relaunch (or a separate elevated helper process) would need an entirely
different, not-yet-designed Linux equivalent (`pkexec`/`sudo`) for a
scenario — writing to a USB stick or an ordinary user-owned folder — that
essentially never actually requires admin rights in practice. Instead,
non-writability is detected proactively (see `analyzeDestination()` below)
and surfaced as a blocking dialog state with a specific, distinct message,
the same way "not enough free space" is — no elevation prompt, ever.

### `PlaylistExportController` (`playlistexportcontroller.h`/`.cpp`)

`QObject`/`QML_ELEMENT`, instantiated once in `Main.qml` (same convention as
every other stateful controller in this app).

- `Q_INVOKABLE QVariantMap analyzeDestination(const QString &destPath)` —
  fast, synchronous (a handful of `QFileInfo`/`QStorageInfo` calls, the same
  scale of work `MilkdropCleanupController::presetFolders()` already does
  synchronously). Returns `{ exists, writable, isRemovable, volumeLabel,
  freeBytes, totalBytes }`:
  - `freeBytes`/`totalBytes` via `QStorageInfo::bytesAvailable()`/
    `bytesTotal()` — the same class `VolumePath` already uses elsewhere,
    just a different accessor.
  - `writable` is determined by actually creating and removing a hidden
    probe file (`.topaz_write_test`) in the destination, not by trusting
    `QFileInfo::isWritable()` alone (unreliable on some network/FAT
    volumes) — this *is* the concrete answer to the UAC question above.
  - `isRemovable` distinguishes a USB stick from a fixed HDD/SSD, purely to
    pick which icon `ExportPlaylistDialog` shows. `QStorageInfo` has no
    removable/fixed accessor, so this is new, Windows-only platform code:
    `GetDriveTypeW()` on the volume's root path, compared against
    `DRIVE_REMOVABLE`, called only from the `.cpp` (never the header) —
    the same header/`.cpp` isolation discipline `SystemVolumeController`
    already uses to keep `<windows.h>` macro clashes away from any header
    that also pulls in Qt types. Always returns `false` (treated as a fixed
    drive) on non-Windows builds until a real Linux port adds an actual
    check (e.g. reading `/sys/block/<dev>/removable`) — tracked as a
    Windows-only-for-now gap alongside `VolumePath`'s own platform notes.
  - **Destination path from the folder picker**: `ExportPlaylistDialog`
    converts `FolderDialog.selectedFolder` to a plain path with
    `s.replace(/^file:\/\/(\/(?=[A-Za-z]:))?/, "")` (drop the third slash only
    before a Windows drive letter). It used to `substring(8)` unconditionally,
    which turned `file:///media/usb/x` into the *relative* path
    `media/usb/x` on Linux — `analyzeDestination()` then reported the
    (nonexistent, working-directory-relative) folder as "not writable". See
    the "Linux port, step 5" note above.
  - Accepts both plain paths and `file://` URLs, same convention as
    `AppConfig::addFolder()`/`addMilkdropPresetFolder()`.
- `Q_INVOKABLE qint64 computeRequiredBytes(const QVariantList &filePaths)` —
  sums `QFileInfo(path).size()` per path, queried live rather than trusting
  `TrackInfo::fileSize`, which the in-memory queue never actually populates
  (`PlaybackEngine::trackFromMap()` doesn't set it, and `trackList()`
  doesn't emit it) — making it unreliable as a source for this calculation.
- `Q_INVOKABLE void startExport(tracks, destFolder, prefix)` /
  `Q_INVOKABLE void cancelExport()` — delegate to the worker thread below.
- `Q_PROPERTY`s `exporting`/`exportProgress`/`currentFileName` and signal
  `exportFinished(QVariantList results)` mirror the exact shape
  `MilkdropCleanupController` already established for its own
  scan-with-progress flow.

### `PlaylistExportWorker` (`playlistexportworker.h`/`.cpp`) — the actual copy

Runs on a dedicated `QThread` owned by `PlaylistExportController`, built
with the exact `moveToThread()` setup `LibraryModel`/`LibraryScanner`
already established (worker constructed parentless, moved to the thread,
`QThread::finished → QObject::deleteLater`, all cross-thread signals
`Qt::QueuedConnection`) — **not** `MilkdropCleanupController`'s
main-thread-with-throttled-`processEvents()`-pump approach. Copying
multi-GB of audio is exactly the file I/O CLAUDE.md's "never do file I/O
directly on the main thread" rule is for: a single large `QFile::copy()`
call can't be chunked with periodic `processEvents()` calls the way
per-file stat/delete checks could, so a big enough playlist would otherwise
visibly freeze the whole window for the duration of that one file.

`runExport(tracks, destFolder, prefix)`: for each `{filePath, title}` entry
in queue order, builds the zero-padded index width as
`qMax(2, digits in tracks.size())` (2 digits for ≤99 tracks, 3 for
100-999 tracks, etc.), strips Windows-reserved characters
(`\/:*?"<>|`) from the title, and copies to
`prefix + paddedIndex + "_" + sanitizedTitle + "." + originalExtension`,
removing any leftover file of the same name from a previous export attempt
first (`QFile::copy()` refuses to overwrite). Emits `progress(done, total,
currentFileName)` after every file and `finished(results)` at the end,
where each result is `{sourcePath, destPath, success, errorString}`.
Cancellation (`cancelExport()`) is the same cooperative
`std::atomic<bool>`-checked-between-iterations shape as
`LibraryScanner::cancelScan()` — the loop simply stops before its next
file and emits `finished()` with whatever partial results it already has.

### `ExportPlaylistDialog.qml` — UI

Chrome modeled on `MilkdropCleanupDialog.qml`: header + ✕ close (hidden
while exporting, same "no safe way to tear this down mid-copy" reasoning),
three mutually-exclusive `visible:`-toggled body states (idle/config,
running, done) in one `Popup`.

**Idle/config state** — translates the user-supplied mockup's layout into
this app's own `Theme.qml` tokens and dialog idioms rather than the
mockup's literal styling:
- Left panel: `Harddisk_Icon.svg` or `UsbStick_Icon.svg` (new assets,
  registered as `qt_add_qml_module` `RESOURCES`, referenced the same way
  the About dialog's logo PNGs are — `qrc:/Topaz/<name>`) chosen from
  `analyzeDestination()`'s `isRemovable`, plus the volume label.
  `UsbStick_Icon.svg` was authored fresh (same 120×120 circle-badge
  construction and `#38BDF8` glow as the harddisk asset) rather than reusing
  the mockup's own USB glyph, which was only available as an
  externally-hosted image — never fetched or embedded, since Topaz makes no
  runtime network calls for assets.
- Destination folder row: read-only path field + BROWSE… button opening a
  `FolderDialog`, same shape as `SetupDialog.qml`'s existing folder pickers.
- Storage & capacity panel: "PLAYLIST REQUIRED SPACE" / "DESTINATION
  AVAILABLE SPACE" readouts (GiB, `Theme.fontFamilyMono`) plus a small
  status dot — green `"#00C853"` / red `"#FF1744"`, the exact literal hex
  values `BottomBar.qml`'s AUTO PLAY button already uses for its on/off
  state, reused here verbatim rather than inventing new `Theme.qml` tokens
  for a one-off — green only when both writable AND enough free space;
  otherwise red, with an inline message distinguishing which condition
  failed ("DESTINATION NOT WRITABLE" vs "NOT ENOUGH FREE SPACE"). The
  "PLAYLIST REQUIRED SPACE" caption reads "N tracks | \<playtime\>" —
  total duration summed from every track's `durationMs`, shown as `M:SS`
  under 100 total minutes or `H:MM:SS` from 100 minutes up (e.g.
  `8 tracks | 43:33` vs `23 tracks | 1:52:39`) — added so playlists built
  for Minidisc recording (80-minute capacity) can be eyeballed against
  that limit without opening the destination and counting.
- Track prefix input (optional — labeled "FILE NAMING / TRACK PREFIX
  (OPTIONAL)") + a live filename preview recomputed on every keystroke from
  the first track, always visible regardless of whether a prefix was
  typed — an empty prefix simply falls back to `<index>_<title>.<ext>`.
- EXPORT (inside the dialog) is enabled once destination chosen AND
  writable AND enough free space AND not already exporting — no longer
  requires a non-empty prefix.
- The dialog is draggable by its header (`x`/`y` bindings instead of
  `anchors.centerIn`, recomputed in `onOpened`, plus a header `MouseArea`),
  same technique and same reason `SetupDialog.qml` already uses it (see
  that dialog's own "Geometry" comment) — `Popup.anchors.centerIn` is
  backed by `QQuickPopupAnchors`, which keeps reasserting `x`/`y` from C++
  and fights a drag `MouseArea`'s direct assignment otherwise.

**Running state**: current filename + the same thin recessed progress-bar
visual UC-24/UC-25 already established (`Theme.surfaceContainerHigh` track,
`Theme.primary` fill, `Behavior on width`).

**Done state**: "Exported `X` of `Y` tracks" summary, with any per-file
failures listed (source path + reason) below.

### Two export entry points, one dialog: `tracks` instead of `engine`

`ExportPlaylistDialog` originally read `engine.trackList()`/
`engine.queueCount` directly, coupling it to "whatever is currently
loaded/playing." Adding a second EXPORT button to the PLAYLISTS tab's
`PlaylistViewer.qml` (next to its existing LOAD button) exposed why that
coupling was wrong in general: LOAD there operates on whichever playlist
row is *selected* in `PlaylistsPanel.qml`'s list
(`PlaylistsData.selectedRawTracks`/`selectedFileName`), which is
independent of and routinely different from `engine.activePlaylistName` —
`PlaylistsPanel` explicitly disables selecting whatever IS the current
queue's playlist, so a selected row is *never* what's currently playing.

The dialog now takes an explicit `property var tracks: []` (the same
`{filePath, title, ...}` map shape `PlaybackEngine.trackList()` and
`PlaylistManager.loadPlaylist()`'s `tracks` result already share, since
both already flow into `engine.loadPlaylistTracks()` elsewhere) instead of
an `engine` reference. Each caller sets `tracks` immediately before
`.open()`:
- NowPlaying's EXPORT (`Main.qml`'s `NowPlaying.onExportPlaylistRequested`):
  `exportPlaylistDialog.tracks = engine.trackList()`.
- `PlaylistViewer`'s new EXPORT button (next to LOAD, narrower —
  `width: 100` vs LOAD's `140` — so the header's "N TRACKS — NAME" text
  anchored to its right edge still has room): emits its own
  `exportPlaylistRequested()` signal, wired in the same `Loader.onLoaded`
  block that already connects `missingPlaylistTracks`
  (`Main.qml`'s PLAYLISTS-tab Loader), which sets
  `exportPlaylistDialog.tracks = playlistsData.selectedRawTracks` before
  opening. Unlike LOAD, this button has no `autoPlay.queueClearAllowed`
  gate — exporting reads the XSPF file directly and never touches the
  queue, so AutoPlay's queue-mutation guard doesn't apply.

### Delete a playlist — the one deliberate exception to "no confirm dialogs"

`PlaylistViewer.qml` also gained a small circular trash-bin icon button
(top right of its header, above the "N TRACKS — NAME" text, sharing its
`rightMargin: 32`) that deletes the selected playlist via a new
`PlaylistManager::deletePlaylist(nameWithExt)` (`QFile::remove()` on
`playlistDirectory() + "/" + nameWithExt`, following the exact naming
convention `appendTrack`/`rewritePlaylist` already use). The icon is a new
monochrome SVG asset (`TrashBin_Icon.svg`, stroke color baked in as
`Theme.fgSurfaceVariant`'s literal hex `#CBC3D7` — the same "bake the theme
color into the SVG" approach `Harddisk_Icon.svg`/`UsbStick_Icon.svg` use,
since plain `Image` has no theme-reactive tinting in this app, and an emoji
🗑 glyph would render in full color on most systems, clashing with every
other monochrome icon button here).

This is the one place in the whole app that shows an "are you sure?"
confirmation before a destructive action — every other delete (SetupDialog's
various "DELETE SELECTED"/"DELETE ALL" buttons, UC-24's abandoned-ratings
cleanup, UC-25's Milkdrop preset cleanup) deliberately has none, per the
documented convention in UC-25 above ("single click, no confirm" + an
error-colored button as the only mitigation). The user explicitly asked for
a confirmation dialog here, with a specific caption ("DELETE PLAYLIST") and
wording — rather than build a one-off dialog for this single case,
`MessageBox.qml` gained an opt-in `confirmMode` (default `false`, so every
existing OK-only call site — e.g. `SetupDialog.qml`'s
`abandonedRatingsResultBox` — is unaffected): when `true`, it shows CANCEL
+ a caller-supplied `confirmButtonText` (styled `Theme.error`/
`Theme.errorContainer`, matching this app's existing destructive-button
color convention) instead of a single OK, and emits a new `accepted()`
signal only when the confirm button (not CANCEL) is clicked.

On confirm, the handler calls `deletePlaylist()`, then
`PlaylistsData.selectNeighborOf(fileName)` **before**
`PlaylistsData.refreshPlaylists()` — `selectNeighborOf()` looks up
`fileName`'s position in the *current* (not-yet-refreshed) `playlists`
array to pick an adjacent entry, so refreshing first would make the just-
deleted name un-findable. Both functions already existed for exactly this
"the current selection just became invalid" scenario (LOAD's own flow uses
`selectNeighborOf()` the same way after a playlist becomes the active
queue and thus unselectable — see UC-22).

## UC-27 Backup and Restore Topaz Environment (MISC Tab)

| Field | Detail |
|-------|--------|
| **Goal** | Zip Topaz's own config/playlists/ratings into a single portable `*.zip` for safekeeping, and later restore playlists/ratings from such a zip, with per-conflict user choices rather than silent overwrite or silent skip. |
| **Actor** | User |
| **Precondition** | Topaz is running. |
| **Trigger** | User clicks BACKUP or RESTORE in Setup → MISC, then the matching action button inside `BackupDialog.qml`/`RestoreDialog.qml`. |

Topaz had zero ZIP/archive capability before this, and Qt's public API has
none either (`QZipReader`/`QZipWriter` are private, undocumented Qt
internals used by Qt Creator/the Installer Framework). Rather than depend
on that private API, this vendors **miniz** (public-domain, single-file C
library, `third_party/miniz/miniz.h`/`.c`, v3.1.2) following the exact
precedent `third_party/kissfft/` already set for the audio visualizer:
committed amalgamated source, no `FetchContent`/`find_package`, its own
`LICENSE` file, compiled straight into the `topaz` target.

**miniz never touches a filesystem path directly** — only its `_mem` APIs
are used (`mz_zip_writer_init_heap`/`add_mem`/`finalize_heap_archive` for
building; `mz_zip_reader_init_mem`/`extract_to_mem` for reading), fed
buffers `QFile` already read from/will write to disk. The `_file`-suffixed
miniz functions go through plain narrow-char `fopen()` internally, not
guaranteed Unicode-safe on Windows the way `QFile` already is everywhere
else in this codebase — since every file this feature touches is small,
there's no performance reason to accept that risk.

**Deliberately synchronous — no worker `QThread`**, unlike
`PlaylistExportController` (built for potentially multi-GB audio copies).
Backup/restore only ever touches small text files (one JSON config, XML
playlists tens of KB each, one ratings JSON realistically under a few MB
even for a huge library) — the same scale of work `MilkdropCleanupController`
already does synchronously. `BackupRestoreController` therefore has no
progress properties or `*Finished` signals; every `Q_INVOKABLE` call *is*
the entire operation, answered synchronously in the same statement.

**Dialog URL → path conversion (Linux fix)**: `BackupDialog` (destination
folder) and `RestoreDialog` (zip file) convert the `FolderDialog`/`FileDialog`
URL with `s.replace(/^file:\/\/(\/(?=[A-Za-z]:))?/, "")` — drop the third
slash only when a Windows drive letter follows (`file:///C:/x` → `C:/x`,
`file:///home/x` → `/home/x`). They originally used `substring(8)`, which
on Linux produced a *relative* path (`media/usb/x`), so backups were written
relative to Topaz's working directory and failed with "Could not write to the
destination folder" — found in the first real-hardware Linux test (see
"Linux port, step 5"). The C++ controllers themselves always handled URLs
correctly (`normalizePath()` → `QUrl::toLocalFile()`); only the QML-side
pre-conversion was Windows-specific.

### The zip contract

```
<zip root>
├── config/Topaz.config
├── playlists/<name>.xml     (one entry per playlist, same fileName
│                              PlaylistManager::listPlaylists() returns)
└── ratings/Topaz.rating.json
```
A category with nothing on disk is silently skipped, not an error; if
*every* checked category produces nothing, `runBackup()` fails with a
"nothing to back up" error rather than writing an empty zip.

### `BackupRestoreController` (`backuprestorecontroller.h`/`.cpp`)

`QObject`/`QML_ELEMENT`, instantiated once in `Main.qml`, bound to both
`PlaylistManager` (for `playlistDirectory()`/`listPlaylists()`) and
`AppConfig` (for `restoreConfig()` below) — config/ratings paths are
computed independently via
`QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation)`, the
same way `RatingCache`'s own private path helper already does.

- `runBackup(categories, destFolder, zipFileName)` — builds the zip
  entirely in heap memory, then writes the finished buffer to disk with
  `QFile`. Returns `{success, error, zipPath, fileCount}`.
- `backupTargetExists(destFolder, zipFileName)` — lets `BackupDialog.qml`
  show `MessageBox`'s existing `confirmMode` overwrite prompt before
  calling `runBackup()`; normalizes the path identically so the two never
  disagree about the final destination.
- `inspectZip(zipFilePath)` — read-only, extracts nothing. Returns which
  categories are present and, for playlists, which entries would conflict
  with a same-named local file (`{playlists: [{fileName, conflict}, ...],
  ratingsConflict, hasConfig, ...}` — `hasConfig` tells `RestoreDialog.qml`
  whether "Restore Config" has anything to do).
- `restorePlaylistEntry(zipFilePath, entryFileName, action)` — one
  playlist, one decision (`"overwrite"|"skip"|"rename"`). Stateless: reopens
  the zip per call rather than holding a live archive handle between calls
  (re-parsing a small zip's central directory is sub-millisecond, far
  simpler than a stateful "session" object surviving a dialog's lifetime).
- `restoreRatings(zipFilePath, mode)` — the whole ratings file, one
  decision (`"overwrite"|"skip"|"mergeNew"|"mergeAll"`). Merge logic goes
  through `RatingCache::loadEntries()`/`saveEntries()` (existing bulk
  entry API, atomic `.tmp`+rename write) — `mergeNew` appends backup
  entries whose `ratingId` isn't already local, never touching existing
  entries; `mergeAll` does the same but also overwrites a local entry's
  `genre`/`rating` when its `ratingId` already exists. `RatingCache`
  gained one small addition to support this without duplicating its JSON
  parser: `loadEntries()` now reads the file then delegates to a new
  `static QList<Entry> parseEntries(const QByteArray&)`, so
  `restoreRatings()` can feed it zip-extracted bytes directly.
- `restoreConfig(zipFilePath)` — extracts `config/Topaz.config` the same
  way `restoreRatings()` extracts the ratings file (`mz_zip_reader_locate_file`
  → `mz_zip_reader_file_stat` → `mz_zip_reader_extract_to_mem`), then hands
  the raw bytes straight to `AppConfig::restoreFromJson()`. No conflict
  dialog — config restore is a single always-apply operation, unlike
  playlists/ratings. Originally RESTORE refused to touch config at all
  ("overwriting live app settings while Topaz is running is riskier than
  useful"); that changed once a safe exception was identified: preserve
  the *currently running* `audioBackend` instead of the backup's, since
  switching FFmpeg/BASS requires re-initializing the playback deck — not
  safe mid-session — while every other setting can simply be swapped in
  live.

  `AppConfig` itself gained the actual apply logic. `load()`
  (file-read/parse, then populate every member from the parsed
  `QJsonObject`) was split: the populate-every-member half moved into a
  new private `applyJson(const QJsonObject&)`, shared by `load()` and the
  new `Q_INVOKABLE QVariantMap restoreFromJson(const QByteArray &json)`.
  `restoreFromJson()` saves `m_audioBackend` before calling `applyJson()`,
  restores it immediately after (undoing whatever the backup's JSON just
  set), calls `save()` to persist the merged result, then emits every
  `NOTIFY` signal the class has **except** `audioBackendChanged`.

  This is what makes the restore live for nearly everything, with no new
  reactivity plumbing: every `AppConfig` consumer in this app (GenreBar,
  AUTO PLAY, crossfade, the audio visualizer, Milkdrop, the delete-rating
  button, etc.) already reads its settings through these same `NOTIFY`-backed
  `Q_PROPERTY`s, specifically so an ordinary Setup Dialog edit takes effect
  immediately — a config restore is just many such edits landing at once.
  One existing mechanism is worth calling out specifically: `SetupDialog.qml`
  already has a `Connections` on `appConfig.foldersChanged` that sets
  `_foldersDirty = true`, triggering `libraryModel.startFullScan()` when
  the dialog closes (see UC-04/UC-05) — since RESTORE lives in this same
  dialog's MISC tab, `foldersChanged()` firing during a config restore is
  picked up by that *existing* auto-rescan flow for free. The values that
  *don't* take effect immediately (window/panel widths, the three
  detachable panes' geometry, `startFullscreen`) were never live for any
  write path, restore included — they're read once at window/pane
  creation and simply persisted for next time, exactly like a manual
  drag/resize already behaves today.

### RENAME retry algorithm

`" - Copy 0N"` inserted before the extension, `N` zero-padded to 2 digits,
1 through 9 (`"Foo.xml"` → `"Foo - Copy 01.xml"` → … → `"Foo - Copy 09.xml"`).
First candidate not already present in `playlistDirectory()` wins. If all
9 are taken, the restore for that file is reported as failed — no further
fallback (no `- Copy 10`, no timestamp suffix).

### `ChoiceDialog.qml` — new generic N-button dialog

`MessageBox.qml`'s `confirmMode` (added alongside UC-26's delete-playlist
feature) maxes out at exactly 2 buttons by construction. Rather than bolt
on a second special-cased branch, `ChoiceDialog.qml` is a small reusable
component (`title`/`message`/`choices: []` rendered via a `Repeater`,
`signal choiceMade(string)`) serving both of RESTORE's multi-choice
prompts: PLAYLIST EXISTS (YES/NO/RENAME) and RATINGS EXIST (YES/NO/MERGE
NEW/MERGE ALL) — one component, two differently-configured instances.

### `RestoreDialog.qml` — sequential conflict state machine

`inspectZip()` runs once up front; non-conflicting playlists and a
non-conflicting ratings file are restored immediately with no dialog.
Actual conflicts are collected into a plain JS array
(`pendingPlaylistConflicts`) plus an index cursor
(`conflictCursor`) and a `ratingsConflictPending` flag; an `advance()`
function shows the next pending `ChoiceDialog` (one `ChoiceDialog`
instance reused across every playlist conflict, its `fileName` property
mutated between opens; a second instance for the single possible ratings
conflict) or, once nothing remains, reveals the results screen — so
exactly one decision dialog is ever open at a time, regardless of how many
playlists conflict. Each `onChoiceMade` handler calls the matching
`BackupRestoreController` method, appends an entry to a `resultsLog`
array, and calls `advance()` again.

**Real bug fixed after initial ship**: `ChoiceDialog`'s choice button used
to emit `choiceMade` *then* call `root.close()`. QML signal handlers run
synchronously with the emit, so for the playlist case, `onChoiceMade`'s
call to `advance()` could reopen the very same `playlistConflictDialog`
instance for the *next* conflict before the click handler's own trailing
`root.close()` had run — that `close()` then executed immediately after
the reopen, silently closing the dialog the user was meant to see next.
Symptoms: only the first of several conflicting playlists ever actually
got restored, and the results screen never appeared at all whenever 2+
playlists conflicted (the state machine hung waiting for a click on a
dialog that had already silently closed itself). Fixed by reordering to
close first, emit second — a reopen triggered by the handler now always
sticks, since nothing runs after the emit in the click handler anymore.

**Restore summary feedback**: beyond the per-file `resultsLog` breakdown,
the Done screen also shows one or two plain-language summary sentences
(`summaryLines`, built by `buildSummaryLines()` right before
`showResult` flips true) — "`N` Playlist File(s) have been copied to the
Topaz Playlist Folder." (only if Restore Playlists was checked; `N` counts
every successful copy, immediate or conflict-resolved YES/RENAME alike,
never NO/skip or a failed rename) and one ratings line depending on
whichever mode actually ran (only if Restore Ratings was checked and a
ratings file was actually present in the archive): "Topaz Rating File has
been overwritten." (`overwrite` — covers both a YES conflict resolution
and the silent no-conflict copy, since both call the same
`restoreRatings(..., "overwrite")`), "No updates regarding Topaz Rating
File." (`skip`/NO), or "`N` Ratings have been updated in the Topaz Rating
File." (`mergeNew`/`mergeAll`, `N` = `addedCount + updatedCount` — for
`mergeNew` this is just the added count since it never updates existing
entries, for `mergeAll` it's the combined total of newly-added and
overwritten-in-place entries).

### `BackupDialog.qml`/`RestoreDialog.qml` — checkbox rows

Both dialogs' fixed (2-3 item, not dynamically scanned) category checkbox
lists use a local `component CheckboxRow: Item { ... }` (the same "define
a local reusable piece with `component Name: BaseType`" idiom
`TagInfoWindow.qml`'s `MetadataField`/`SpecField` already established) —
deliberately an `Item`, not a `RowLayout`, so its click-handling
`MouseArea` (a direct child, unlike `MilkdropCleanupDialog.qml`'s
checkbox, which nests its `MouseArea` inside the checkbox `Rectangle`
itself) isn't itself layout-managed — Qt Quick Layouts only tolerate
`anchors` on children that aren't direct layout children, and an `Item`
wrapping a plain `Row` sidesteps that restriction entirely.

**Real bug fixed after initial ship**: both dialogs originally mirrored
each `CheckboxRow.checked` into a same-named root property via a
declarative binding plus an `onCheckedChanged` write-back (e.g.
`checked: root.restorePlaylistsChecked` / `onCheckedChanged:
root.restorePlaylistsChecked = checked`). `CheckboxRow` itself toggles on
click via the imperative `checkboxRow.checked = !checkboxRow.checked` —
and assigning to a property that already has a declarative binding
permanently severs that binding, standard QML behavior. The very first
click on any checkbox therefore broke its sync with the mirrored root
property for good; `onOpened`'s reset of the root property (e.g.
`restorePlaylistsChecked = true`) kept "working" from the logic's point of
view while the checkbox's on-screen state silently stopped following it —
so a user could uncheck "Restore Playlists," reopen the dialog, and get a
PLAYLIST EXISTS prompt anyway, despite the checkbox visibly still showing
unchecked. Fixed by deleting the mirrored root properties entirely and
reading each `CheckboxRow`'s own `checked` directly by `id` everywhere
(`onOpened` resets, `anyChecked`/`canBackup`/`canRestore`, and the
category-list building in `performBackup()`/`startRestore()`) — one source
of truth per checkbox, no binding left to break.

### Font sizes

Per explicit user instruction, every string in these three new dialogs
uses `ExportPlaylistDialog.qml`'s current (already-enlarged) sizes as the
floor — `Theme.labelMd` for section labels, `Theme.monoLg` for path/
filename/results text, `Theme.headlineSm` Bold for dialog titles. Action-
button labels are the one deliberate exception, staying at `Theme.labelSm`
(10px) to match every other button in the app (`EXPORT`/`CANCEL`/`CLOSE`/
`BROWSE…` in `ExportPlaylistDialog.qml` itself included) — bumping only
this feature's buttons would make them visibly inconsistent with
everything else, and the "too small" feedback was clearly about body/
caption text, not this app-wide button chrome.

### MISC-tab button row: stuck hover color after closing a dialog

**Real bug fixed after initial ship.** The CLEANUP/BACKUP/RESTORE row
buttons color themselves via a `MouseArea`'s hover state. A modal `Popup`
grabs all mouse input while open, so the button's `MouseArea` underneath
never receives a hover-leave event for the click that opened it —
`containsMouse` freezes `true`, and Qt Quick does not re-evaluate it once
the grab releases, since nothing generated a new mouse-move event. The
button kept rendering its hover background indefinitely after the dialog
closed, until the mouse physically left and re-entered it.

**First fix attempt failed**: toggling `MouseArea.hoverEnabled` off and
back on in the dialog's `onClosed`, on the assumption this would force a
re-hit-test. It doesn't — `hoverEnabled` only governs whether *future*
hover events are processed, it never retroactively re-queries the cursor's
current position, so `containsMouse` stayed stuck exactly as before.

**Working fix**: stop reading `containsMouse` directly. Each button's
`MouseArea` now tracks its own `property bool hovered: false` via
`onEntered`/`onExited`, and the button's `color:` binding reads `hovered`
instead of `containsMouse`. The corresponding dialog's `onClosed` then
does a plain, unconditional `xHover.hovered = false` — a direct assignment
that doesn't depend on Qt generating any event at all. Once the user's
mouse genuinely leaves and re-enters the button afterward, real
`onEntered`/`onExited` events resume firing normally (the grab is long
over by then), so hover tracking self-corrects for every subsequent hover
with no further intervention needed.

---

## UC-28 Start Topaz in Full Screen (MISC Tab)

| Field | Detail |
|-------|--------|
| **Goal** | Let the user choose whether Topaz launches Windowed or Fullscreen, replacing the previous resolution-sniffing auto-fullscreen. |
| **Actor** | User |
| **Trigger** | User flips the "Start Topaz in Full Screen" toggle in Setup → MISC; takes effect on the next launch. |

A new `AppConfig.startFullscreen` bool (`Q_PROPERTY` + `Q_INVOKABLE
setStartFullscreen(bool)`, same READ/NOTIFY + invokable-setter shape as
every other `AppConfig` bool, e.g. `autoPlayFlickerNewTracks`), persisted
as `Topaz.config`'s top-level `startFullscreen` key, default `false`. MISC
tab gains a third toggle row (after Backup/Restore): label "Start Topaz in
Full Screen" + the same 48×24/18×18 pill switch already used for the
PLAYBACK tab's Crossfade on/off row (`SetupDialog.qml`).

`Main.qml`'s root `ApplicationWindow` — formerly `Screen.width`/`Screen.height`
checks against four fixed resolutions (see the "Supported Resolutions"
section above) — now shows itself once restored, with
`root.visibility = appConfig.startFullscreen ? Window.FullScreen : Window.Windowed`
(see "Layout persistence" for the whole startup sequence). The existing F11
`Shortcut` and the `saveLayoutTimer`'s fullscreen guard (skip persisting
`windowWidth`/`windowHeight` while fullscreen) are unchanged — F11 still
imperatively reassigns `root.visibility` at runtime.

**The toggle takes effect on the next launch, as documented above.** It used
to be a live `visibility:` binding, which also flipped a *running* window when
the switch was toggled in Setup (as long as F11 had not been pressed, which
severs such a binding) — an undocumented side effect. The startup sequence now
applies it once.

**Multi-monitor fullscreen**: `Window.FullScreen` alone doesn't say *which*
monitor to fill. The saved monitor (`AppConfig.windowScreenName`, refreshed
whenever `root.screen` changes, even while fullscreen) is resolved back to a
live `Screen` and assigned to `root.screen` **before** the window is created
(see "Layout persistence" — assigning it after creation, as the first version
of this fix did, moves nothing). A fullscreen start prefers that name and falls
back to the screen containing the saved windowed rect.

**Fullscreen fall-back bug (fixed)**: entering fullscreen — via F11 or at
startup — used to snap the window back to its windowed size ~0.5 s later while
keeping the borderless fullscreen style, because every position save emitted
`windowGeometryChanged` and re-evaluated the old `width: appConfig.windowWidth`
bindings. Those bindings no longer exist.

### Cursor auto-hide in fullscreen

While Topaz is fullscreen — via F11 *or* "Start Topaz in Full Screen", it is the
same `root.visibility === Window.FullScreen` state — the mouse cursor hides after
5 seconds without mouse activity and comes back as soon as the mouse is used, so
it doesn't sit over the artwork on a kiosk/party display. Leaving fullscreen
restores it immediately.

`Main.qml` instantiates one `CursorAutoHider` (`cursorautohider.h/.cpp`,
`QML_ELEMENT`) with `enabled: root.visibility === Window.FullScreen`,
`idleSeconds: 5` (hardcoded; no Setup option). It is C++ because QML has no
global cursor override and a per-item `cursorShape` cannot work for the main
window (dozens of items set their own, and an overlay `MouseArea` would swallow
clicks). Hiding is `QGuiApplication::setOverrideCursor(Qt::BlankCursor)`, which
covers every Topaz window (main window, all four panes, dialogs) and overrides
every item's own `cursorShape`; a `m_hidden` flag keeps the override stack
balanced (pushed once, always popped on disable/destruction).

Idle detection is an application-wide event filter, installed only while
`enabled`, watching `MouseMove`, `MouseButtonPress/Release/DblClick` and `Wheel`
on any Topaz window; it never consumes an event. A `MouseMove` only counts if the
*global position changed*, so Qt's synthesized hover re-deliveries on a stationary
cursor don't keep re-showing it. Activity shows the cursor and restarts a
single-shot timer; when it fires the cursor is hidden unless a mouse button is
held (a long press or slow drag is mouse use, so it re-checks later).

Independent of, and compatible with, Milkdrop's own F10 idle-hide (2 s, per item
via `FloatingPane.cursorHidden`): both blank the cursor and both undo it on
mouse movement; with the main window windowed only the F10 one exists. Limits:
only Topaz's own windows are affected (the OS taskbar, other applications and a
native file dialog keep their normal cursor), and a hidden cursor stays hidden
until the mouse moves, clicks or wheels. Verified on Windows through the real
cursor handle (`GetCursorInfo`): hides after ~5 s idle, returns on a 6 px move,
hides again, never hides when windowed, and reappears at once when fullscreen ends.

### Kiosk mode (fullscreen + panes over the taskbar)

While Topaz is fullscreen it is effectively a kiosk display (e.g. a party setup
with the additional display showing the panes). `FloatingPane.kiosk` is set by
`Main.qml` to `root.visibility === Window.FullScreen` for all four detachable
panes (Big Cover, Tag Info, Audio Visualizer, Milkdrop); while true the pane's
`flags` include `Qt.WindowStaysOnTopHint`, so it can be placed over the OS
taskbar and stays above the fullscreen main window, and Milkdrop's F10 fills the
whole display including the taskbar strip. Leaving fullscreen removes the hint;
panes are then ordinary windows again ("and ONLY then"). It is visual only —
nothing blocks other applications.

**Topmost alone does not keep a pane above the taskbar (found on a dual-display
setup, and reproduced on a single display).** The Windows taskbar is topmost
too, and the shell puts it back on top of the topmost band whenever the
foreground window changes — clicking the fullscreen Jukebox covered a pane that
was sitting over the additional display's taskbar again. Measured with a
Z-order probe (`EnumWindows`, top to bottom): a focused topmost pane was *still*
below the taskbar after the shell re-raised it. So kiosk panes actively
re-assert their stacking with `raise()` (which puts a topmost window back on top
of the band without activating it):
- `FloatingPane.kioskBurst()`: raise now, then three more times 80 ms apart (the
  shell re-sorts a moment *after* the focus change). Triggered when the pane
  loses keyboard focus, and by `Main.qml` when the main window gains it.
- `kioskRaiseTimer`: a 400 ms safety net while kiosk and visible (taskbar
  clicked, another app popped up).

Both key on **`activeFocusItem`, not `Window.active`**: the panes are transient
children of the main window, and Qt counts a window as active while any window in
its transient chain has focus — `active` was measured to fire but stay `true` on
*both* windows however the focus moved, so it can't detect "focus left this
pane". `activeFocusItem` follows the real OS focus window (measured: it
alternates cleanly). Measured effect: with the pane's focus moving to the main
window and the taskbar re-raised immediately after, the pane was back on top
within 130 ms in 5 of 5 tries (1–2 of 5 with the slow timer alone). Windows
offers no way to permanently outrank the taskbar without UIAccess signing, so
this is "re-assert quickly" (a brief flash is possible), not "pin".

Other known limits: topmost also means the panes stay above other apps while in
kiosk; on Linux the hint is `_NET_WM_STATE_ABOVE`, which many window managers
(Cinnamon's panel) still stack *below* docks, so covering a panel there is
unverified and may need a per-pane fullscreen state.

### Which display a pane's F10 / double-click uses

`Milkdrop`'s F10 fullscreen and the double-click placements (Big Cover / Milkdrop
center-right-left cycle, Tag Info maximize-width) used the `Screen` attached
property, which did not follow a pane dragged to another display — F10 always
filled the main display. `FloatingPane.currentScreenRect()` now returns the
logical rect of the screen containing the pane's center (fallback: largest
overlap, then the first screen), and all of them use it.

## UC-29 Delete Rating for the Currently Playing Track (NowPlaying + MISC Tab)

| Field | Detail |
|-------|--------|
| **Goal** | Let the user permanently clear a track's rating, closing a real gap: `setCurrentRating()` only accepts 1-10, so before this there was no way to un-rate a track once given. |
| **Actor** | User |
| **Trigger** | User clicks the trash-bin button next to NowPlaying's rating stars, then DELETE in the "DELETE RATING" confirmation. |
| **Precondition** | Setup → MISC → "Delete the Rating for the Track currently playing" is enabled (default off), a track is loaded, and it currently has a rating. |

A new `AppConfig.deleteCurrentRatingEnabled` bool — identical shape to
UC-28's `startFullscreen` (`Q_PROPERTY` + `Q_INVOKABLE
setDeleteCurrentRatingEnabled(bool)`), persisted as `Topaz.config`'s
top-level `deleteCurrentRatingEnabled` key, default `false`. MISC tab
gains a fourth toggle row (after Start Topaz in Full Screen), same
48×24/18×18 pill switch.

Unlike UC-28's setting (a startup preference, takes effect next launch),
this one gates a live UI element: `NowPlaying.qml` takes a new `appConfig`
property (wired from `Main.qml`, previously not forwarded to this panel)
and binds a trash-bin button's `visible` directly to
`appConfig.deleteCurrentRatingEnabled` — flipping the toggle in Setup
shows/hides the button in NowPlaying immediately, no restart or dialog
close needed. The button is the visual twin of `PlaylistViewer.qml`'s
`deletePlaylistBtn` (32×32, `Theme.radiusFull`, `TrashBin_Icon.svg`),
anchored `right: ratingStarsRow.left; rightMargin: 12` — the identical
12px gap `PlaylistViewer.qml`'s EXPORT→trash-bin buttons use
(`leftMargin: 12`) — and `verticalCenter: parent.verticalCenter`, so it's
always vertically centered on the star row regardless of which anchors on
which side. Its own `active` state (full opacity + clickable vs. 0.35
dimmed) is separate from `visible` — dimmed whenever `currentRating` is 0
(nothing to delete), exactly mirroring `deletePlaylistBtn`'s/`exportBtn`'s
own active/dimmed convention in `PlaylistViewer.qml`.

Clicking it (while active) opens a `MessageBox` styled like
`PlaylistViewer.qml`'s "DELETE PLAYLIST" confirmation (`confirmMode: true`,
title "DELETE RATING", message "Would you like to delete the rating for
the track currently playing?", confirm button "DELETE"). Accepting calls
the new `PlaybackEngine::deleteCurrentRating()` (`playbackengine.cpp`),
which resets the current queue entry's `rating` to 0 and calls the new
`RatingCache::removeRating(ratingId)` to delete the entry from
`Topaz.rating.json`, then emits the existing `currentRatingChanged()` —
the star row (and the trash-bin button's own `active` binding) update
immediately, same signal `setCurrentRating()` already relies on.

**Build note**: this change (plus UC-28's earlier MISC addition) pushed
`SetupDialog.qml` — already this codebase's largest QML file — past
MinGW's ~32k-COFF-section-per-object ceiling, failing the build with
"too many sections" / "file too big" from `as` on the generated
`.rcc/qmlcache/topaz_SetupDialog_qml.cpp.obj`. Fixed by adding
`-Wa,-mbig-obj` to the `topaz` target's compile options for MinGW builds
(`CMakeLists.txt`) — the standard fix for this MinGW/COFF limit, inert on
non-Windows toolchains.

---

## UC-30 Import an Externally-Located Playlist (NowPlaying LOAD)

| Field | Detail |
|-------|--------|
| **Goal** | Close a real gap in UC-10's LOAD flow: a playlist picked from outside Topaz's own playlist folder played correctly, but `PlaylistsPanel`/`PlaylistViewer` never saw it (both only ever list `PlaylistManager::playlistDirectory()`), and every subsequent queue-sync write (`appendTrack()`/`removeTrackByPath()`/`rewritePlaylist()`, which all build their target path as `playlistDirectory() + "/" + activePlaylistName`) silently wrote into the playlist folder under the same bare file name — never touching the original file, and silently overwriting any unrelated same-named playlist already there if one happened to exist. |
| **Actor** | User |
| **Trigger** | User clicks **LOAD** in `NowPlaying`, then picks an `.xml` file outside `PlaylistManager::playlistDirectory()` via the native file picker. |

### Normal Flow

1. `loadPlaylistDialog.onAccepted` (`NowPlaying.qml`) calls the new
   `PlaylistManager::classifyPlaylistSource(pathOrUrl)` *before* touching
   the queue at all. It resolves the picked path (accepting both a plain
   path and a `file://` URL, same convention as `loadPlaylist()`) and
   returns `{ fileName, alreadyInPlaylistDirectory, collidesWithExisting }`
   — `alreadyInPlaylistDirectory` is a case-insensitive directory compare
   (Windows), `collidesWithExisting` is only meaningful when that's
   `false` (a same-named file already sitting in the playlist folder).
2. **Already in the playlist folder** (the common case — picking a file
   that happens to already live there, or re-loading one already active):
   behaves exactly as before UC-30 existed — straight to `loadPlaylist()`
   → the queue.
3. **Outside the folder, no name collision**: silently imported — no
   prompt. `PlaylistManager::importPlaylistFile(sourcePathOrUrl, fileName)`
   copies the source into `playlistDirectory()/fileName` while
   `ImportPlaylistDialog.qml` is open (see "Import dialog" below), then
   loads the in-folder copy.
4. **Outside the folder, name collision**: a `ChoiceDialog` — title
   "PLAYLIST EXISTS", message "Would you like to import the Playlist and
   overwrite the Playlist that exists in the Playlist Folder?\nIf 'NO'
   then the Playlist will be imported as a new Playlist with a Postfix
   like '-1'", `choices: ["YES", "NO"]` (the same reusable N-button
   component `RestoreDialog.qml` already uses for its own
   playlist-conflict prompt, just two choices instead of three) —
   - **YES**: same as step 3, overwriting the existing in-folder file
     (`importPlaylistFile()` removes the destination first — `QFile::copy()`
     itself refuses to overwrite — mirroring
     `BackupRestoreController::restorePlaylistEntry()`'s own "overwrite"
     action).
   - **NO**: still imported, just not under the colliding name — a real
     bug in the first shipped version of UC-30 loaded directly from the
     original external location instead, leaving `activePlaylistName` set
     to a bare file name that collided with the *unrelated* existing
     in-folder playlist; since `PlaylistsPanel`'s "(IN QUEUE)" badge is a
     plain `activePlaylistName === fileName` string match, that unrelated
     playlist got badged "(IN QUEUE)" even though it wasn't what was
     playing. Fixed by generating a de-conflicted name instead:
     `PlaylistManager::findAvailableCopyName(nameWithExt)` tries
     `"<base>-1<ext>"` through `"<base>-9<ext>"` and imports under the
     first free one (a 9-slot cap, but a plain `"-N"` suffix rather than
     `BackupRestoreController::restorePlaylistEntry()`'s own zero-padded
     `"- Copy 0N"` scheme for RESTORE's equivalent playlist-name
     collision, UC-27 — the two are independent methods on different
     classes, deliberately not sharing an implementation). If all 9 are
     taken, the import is aborted outright — no fallback — with an
     "AMBIGUOUS PLAYLIST" / "Too many ambiguous Playlists are in the
     Playlist Folder.\nThe Playlist could not be imported." `MessageBox`;
     the queue and active playlist are left exactly as they were.
5. Every successful branch funnels through one shared `NowPlaying.qml`
   function, `_finishLoad(result)` — the exact body
   `loadPlaylistDialog.onAccepted` had before UC-30 (crossfade-eligible
   `loadPlaylistTracks()` + `setActivePlaylistName()` +
   `missingPlaylistTracks()` for any unresolvable entries) — so every
   outcome (in-folder, imported under its own name, or imported under a
   de-conflicted copy name) finishes identically once a `loadPlaylist()`
   result is in hand. As a result every successful LOAD-via-NowPlaying now
   ends up as some real, listed file in the playlist folder — the
   "(IN QUEUE)" badge can no longer point at the wrong entry.

### Import dialog (`ImportPlaylistDialog.qml`)

Chrome matches `ChoiceDialog.qml`/`RestoreDialog.qml`'s header bar; the
body matches `ExportPlaylistDialog.qml`'s running-state view exactly — a
centered mono "Importing: `<name>`" label (elide middle) above an 8px
rounded `Theme.primary` progress `Rectangle` with a
`Behavior on width { NumberAnimation { duration: 400 } }`. Opened via
`startImport(sourcePath, fileName)`; `closePolicy: Popup.NoAutoClose` and
no manual close button — it only ever closes itself.

The copy itself is synchronous on the main thread (`QFile::copy()`
inside `importPlaylistFile()`) — a single small XSPF file is the same
"small file, no worker thread" scale of work `MilkdropCleanupController`/
`BackupRestoreController` already do synchronously; `PlaylistExportWorker`'s
dedicated `QThread` exists specifically because multi-GB *audio* copies
would visibly freeze the UI, which a playlist XML file doesn't come
close to. Since one synchronous `QFile::copy()` call has no meaningful
mid-copy progress to sample, the bar is a short, fixed-duration *cosmetic*
sweep to 100% — visually consistent with `ExportPlaylistDialog`'s real
byte-progress bar, but not itself a byte count. `Qt.callLater()` defers
the actual `importPlaylistFile()` call by one event-loop tick so the
popup visibly paints at 0% before the sweep starts, rather than opening
already full; a 400 ms `Timer` (matching the width `Behavior`'s duration)
then closes the popup and emits `importFinished(success, fileName)`.
`NowPlaying.qml` reacts by loading the in-folder copy on success, or
showing a plain "IMPORT FAILED" `MessageBox` on failure (e.g. the
destination was locked/read-only) — the queue is left untouched either
way.

### Design decisions

- **Detection is directory-based, not folder-membership-based**: a file
  is only ever "already in the playlist folder" if its *containing
  directory* matches `playlistDirectory()` — a same-named file living
  anywhere else is always treated as external, even if byte-identical.
- **`PlaylistManager` owns import, not a new controller**: it already
  owns every other piece of playlist file I/O (`createPlaylist`/
  `loadPlaylist`/`deletePlaylist`/`appendTrack`/`removeTrackByPath`/
  `rewritePlaylist`); two more small file-I/O methods fit the existing
  class rather than justifying a new one.
- **No change to UC-10's other LOAD entry points**: `PlaylistViewer.qml`'s
  own LOAD button only ever operates on `PlaylistsData.selectedRawTracks`
  — playlists already selected from `PlaylistsPanel`'s listing of
  `playlistDirectory()` — so it can never pick a file from outside the
  folder in the first place; UC-30 is specific to `NowPlaying`'s native
  file-picker LOAD.

## UC-31 Detect a Missing Queued Track Before Playing It

| Field | Detail |
|-------|--------|
| **Goal** | A queued track's file can be deleted (or its containing folder removed) after it was added to the queue — including mid-playlist, since UC-10's own pre-check only covers the moment a playlist is *loaded*. Before this use case, neither audio backend surfaces that failure at all: `BASS_StreamCreateFile()` returns 0 and `QMediaPlayer::setSource()` on a missing file never reaches `PlayingState`, so playback simply stalled at 0:00 with no message and no auto-skip. Topaz now checks every track's existence right before handing it to a deck, stops cleanly the instant one is missing, and self-heals the library index for just the affected folder. |
| **Actor** | System |
| **Trigger** | Any of: the first track added to an empty/finished queue; the crossfade lookahead reaching its trigger point; a manual NEXT/PREVIOUS/queue-row selection landing on a track whose file is gone; the natural end-of-track hard cut advancing onto one. |

### Normal Flow

1. **Layer A — `PlaybackEngine::loadTrack(int idx)`** is the single choke
   point all 8 hard-cut/manual queue-transition call sites funnel through
   (`addTrack`, `addTracks`, `removeAt` ×2, `playAt`, `togglePlay`,
   `next`, `previous`, `advanceToNext`). It now returns `bool`: if
   `QFileInfo::exists(m_queue.at(idx).filePath)` is `false`, it calls
   `handleMissingTrack()` (below) and returns `false` *without* calling
   `switchCurrentIndexTo()` — `m_currentIndex` and the displayed "now
   playing" track are left exactly as they were, so the missing track
   never becomes "current." Every call site changed its trailing
   `m_deck->play()` to `if (loadTrack(idx)) m_deck->play();`, so a failed
   load never plays a deck with no valid source.
   - This single guard is also what satisfies "the first track the user
     adds must be checked immediately": `addTrack()`/`addTracks()`'s
     existing auto-play branch (queue was empty, or every track had
     already finished — `m_queueFinished`) calls `loadTrack()`
     synchronously at add time. There's no separate special case for
     this — it falls out of the shared guard for free, since there's no
     "currently playing" track yet to give a lookahead window.
   - `TrackInfo.filePath` is always an absolute, already-resolved local
     path by the time it's in `m_queue` (`PlaylistManager` resolves URLs
     before storing; `LibraryCache` stores `VolumePath::quickPath()`
     output), so a plain `QFileInfo::exists()` needs no further
     volume/URL resolution here.
2. **Layer B — the crossfade lookahead.** `onDeckPositionChanged()`'s
   existing trigger (`pos >= dur - fadeMs`, where `fadeMs` is the
   configured 2–12 s crossfade length) calls `startCrossfade()`, which
   calls `m_decks[m_fadeInDeck]->setSource()` on the *next* track
   directly — bypassing `loadTrack()` entirely, while the current track
   is still audibly playing. `startCrossfade()` now checks the next
   track's existence itself, right before that `setSource()` call; if
   missing, it calls `handleMissingTrack()` and returns without ever
   flipping `m_crossfading` or starting `m_fadeTimer` — the crossfade
   never begins, so there's no audible fade-into-silence. The identical
   guard was added to `loadPlaylistTracks()`'s separate queue-replacing
   crossfade `setSource()` call (UC-23): if the incoming playlist's
   first track vanished in the narrow race between `loadPlaylist()`'s own
   pre-check and this call, the whole queue replacement is aborted
   (old queue/deck untouched) rather than attempting a partial fallback.
   - No separate timer/lead-time exists for the crossfade-*disabled*
     case: there, `advanceToNext()` already runs essentially instantly
     after the current track's natural `endOfMedia`, and Layer A's guard
     inside `loadTrack()` catches it right there — a hard cut has no
     "fade into nothing" window to get ahead of.
3. **`handleMissingTrack(const TrackInfo &t)`** — the shared handler
   both layers call:
   ```cpp
   void PlaybackEngine::handleMissingTrack(const TrackInfo &t)
   {
       if (m_deck) m_deck->pause();
       emit trackMissing(t.artist, t.album, t.title, t.filePath);
   }
   ```
   `m_deck->pause()` freezes whatever's still audible immediately (the
   *currently* playing track in the Layer B case; a no-op if nothing was
   playing in the Layer A case) and reuses the existing deck →
   `playingChanged` → `isPlayingChanged()`/row `dataChanged` relay
   (already wired for `togglePlay()`) — no new UI plumbing needed for
   "stopped" to show up correctly. `m_userPaused` is deliberately *not*
   reused here — it's documented as exclusively `togglePlay()`'s
   explicit-pause flag, and setting it here would misrepresent why
   playback stopped.
4. **AUTO PLAY stops immediately.** `AutoPlayController::setEngine()`
   connects the new `trackMissing` signal to a third private slot,
   `onTrackMissing()`, alongside its existing `trackPlayedToCompletion`/
   `queueExhausted` connections — see UC-16's "Alternate: stopped by a
   missing track" for why this reuses the manual `stop(false)` path, not
   the starvation path.
5. **The MISSING TRACK dialog** (`MissingTrackDialog.qml`) — wired
   directly to `engine.trackMissing` in `Main.qml`, the same
   decoupling pattern `missingPlaylistTracks` already uses (UC-10):
   `PlaybackEngine` has no knowledge of `LibraryModel`/`AppConfig`
   folders. Shows:
   > Track could not be found and can not be played
   > Artist: `<artist>`
   > Album: `<album>`
   > Track: `<title>`

   with a single OK button. `Main.qml` also kicks off the targeted
   rescan (step 6) from the same handler.
6. **Targeted single-folder rescan.** `LibraryModel::
   rescanFolderContaining(filePath)` matches `filePath` against
   `activeFolders()`'s entries (`path` prefix, respecting
   `includeSubfolders`'s "direct child only" rule when `false`) and, if
   one matches, dispatches `LibraryScanner::scanFolder()` — a rescan
   scoped to just that folder, so the library self-heals without
   touching every other configured folder's cache. No-op if a scan is
   already running, or if no configured folder matches (e.g. it was
   removed from FILE MONITORING in the meantime).

### Why the folder rescan needed a `performScan()` change, not just a filtered call

`LibraryScanner::performScan(genres, folders, existingCache)` always
treated `folders` as the *complete* authoritative set — any folder left
out of that list had every one of its cached tracks silently dropped
from the result (`LibraryCache::save(result)` persists whatever
`performScan()` builds, replacing the whole cache). Calling it with a
single-folder subset would have wiped out every other folder's tracks,
both in memory and on disk. Instead, `performScan()` gained an optional
`scanOnlyFolderPath` parameter (empty for `fullScan()`/`statCheck()` —
byte-for-byte unchanged behavior):
- `rootDirs` (which `updateWatcher()` uses) is still built from *every*
  folder regardless of scope, so the file-system watcher's coverage
  never shrinks.
- For every folder that doesn't match `scanOnlyFolderPath`,
  `discoverAudioFiles()` is skipped entirely and its `existingCache`
  entries (matched by `filePath` prefix) are carried into `result`
  verbatim instead — the same "reuse the cached entry as-is" principle
  already used for an individual unchanged file, just extended to
  "every file in an unscanned folder."
- Only the matching folder is actually walked/tag-read. Cover-art
  resolution and rating enrichment still run over the full merged
  `result` (both already documented as deterministic/order-independent,
  so this is safe whether or not a given track was touched this pass).

`LibraryScanner::scanFolder()` is a thin wrapper mirroring `fullScan()`/
`statCheck()`; `LibraryModel::_requestFolderScan` is a new queued signal
into the worker thread mirroring `_requestFullScan`/`_requestStatCheck`.
Both `fullScan`/`statCheck`/`scanFolder` still funnel into the same
`scanCompleted`/`onScanCompleted` signal, so `LibraryModel.scanning`
resets correctly regardless of which one triggered it.

### Design decisions

- **Two layers, not one**: a single check inside `loadTrack()` would
  catch every case eventually, but not early enough for the
  crossfade-enabled path — the fade-in deck's `setSource()` is a
  separate call that bypasses `loadTrack()` entirely, so it needed its
  own guard to avoid starting an audible fade into a file that isn't
  there.
- **Genuine always-on-top window for the dialog, not a `Popup`**:
  Milkdrop/AudioVisualizer/BigCover/TagInfo are all separate top-level
  `Window`s (`FloatingPane.qml`), which could legitimately be floating
  above the main `ApplicationWindow` when this fires — a `Popup` anchored
  to the main window's own `Overlay.overlay` has no guaranteed stacking
  order against another independent `Window`. `MissingTrackDialog.qml`
  is its own `Window` with `flags: Qt.Dialog | Qt.FramelessWindowHint |
  Qt.WindowStaysOnTopHint`, `modality: Qt.ApplicationModal`, and calls
  `raise()`/`requestActivate()` on open — genuinely renders above every
  other Topaz window. It is *not* built on `FloatingPane.qml`: that
  base's whole design is drag-to-move + resize + right-click-to-close,
  the wrong interaction model for a fixed, OK-only error alert. It does
  reuse `WindowChrome.prepareWindow()` (same alpha-capable-surface +
  DWM-border-removal prep every `FloatingPane` uses) so its rounded
  corners render correctly and Windows 11's accent border doesn't leak
  through.
- **No queue mutation on detection**: the queue is left exactly as it
  was — "the rest is up to the user" per the request. The user manually
  navigates elsewhere, removes the bad entry, or clears the queue; no
  automatic skip-past or removal happens.

## UC-32 Configurable Album Browser & Search Result Sort Order (MISC Tab)

| Field | Detail |
|-------|--------|
| **Goal** | Let the user choose between two album sort orders for AlbumBrowser and Search results, instead of the previously-fixed rule. |
| **Actor** | User |
| **Trigger** | User picks a radio option in Setup → MISC → "Album Browser & Search Result Sort Order"; applies immediately, no restart needed. |

A new `AppConfig.albumBrowserSortOrder` string (`Q_PROPERTY` + `Q_INVOKABLE
setAlbumBrowserSortOrder(mode)`, same validate-and-silently-ignore-invalid
shape as `autoPlaySongRepeat`/`autoPlayTransportAccess`), persisted as
`Topaz.config`'s top-level `albumBrowserSortOrder` key, default
`"artistYearAlbum"`. Allowed values:
- `"artistYearAlbum"` (default) — Artist ascending → Year descending →
  Album ascending (the original, previously-fixed behavior).
- `"artistAlbum"` — Artist ascending → Album ascending (no year tiebreak
  at all).

MISC tab gains a new radio group (after Delete the Rating for the Track
currently playing) — label, then the two options stacked vertically in a
`Column` (`Layout.leftMargin: 24`), each reusing the identical 18px
circle/dot radio delegate `SetupDialog.qml`'s three existing radio
groups (`audioBackend`, `autoPlaySongRepeat`, `autoPlayTransportAccess`)
already use, just swapping their `Row`/`Grid` wrapper for a `Column` —
those groups lay options out horizontally since their labels are short;
this group's two labels are long, so vertical stacking reads better and
was explicitly requested.

### Wiring into the sort itself

`LibraryModel::filteredAlbums()` and `searchLibrary()` share their
grouping/sort/serialize tail via a private `serializeAlbumAccum()`
helper (`librarymodel.cpp`) — the two are deliberately kept "in
lockstep" on behavior, so the new setting applies to both, not just
AlbumBrowser. `serializeAlbumAccum()` gained a `sortByYear` parameter
(default `true`, preserving exact prior behavior for its third caller,
`buildStandaloneTrackCards()`, which never sorts at all via
`preserveOrder=true` regardless): when `false`, the comparator's year
tiebreak is skipped entirely, falling straight through to the
album-title comparison. A new private `LibraryModel::
albumBrowserSortByYear()` reads `AppConfig.albumBrowserSortOrder() !=
"artistAlbum"` and is passed into both `filteredAlbums()`'s and
`searchLibrary()`'s calls.

### Live refresh, no new property plumbing needed

`AlbumBrowser.qml` and `SearchData.qml` already had indirect access to
`AppConfig` through properties they already hold — `AlbumBrowser.qml`'s
`lib` (`LibraryData.qml`, which already exposes `property AppConfig
appConfig`) and `SearchData.qml`'s `libraryModel` (`LibraryModel` itself
already exposes `property AppConfig appConfig`) — so making the change
apply immediately needed no new properties threaded through `Main.qml`,
just one additional `Connections` block in each file reusing their
existing refresh functions (`AlbumBrowser.qml`'s `_scheduleRefresh()`,
`SearchData.qml`'s `_scheduleSearch()`) whenever `AppConfig.
albumBrowserSortOrderChanged` fires.

## UC-33 Reorder Genres in the Setup Dialog GENRES Grid

| Field | Detail |
|-------|--------|
| **Goal** | User drags a genre cell in Setup → GENRES onto another position; every other genre shifts to close the gap; the new order persists and `GenreBar`'s buttons immediately re-render in it. |
| **Actor** | User |
| **Precondition** | GENRES tab open, at least 2 configured genres. |
| **Trigger** | User presses and drags a genre cell's drag handle (⠇, left edge). |

The grid order shown here (`AppConfig.genres`) is the single source of
truth genres are identified *and* ordered by; `enabledGenres()` (the
`GenreBar`-visible subset, see UC-03) is always derived fresh from
`genres`' own order, so reordering the full list automatically reorders
`GenreBar` too, with no changes needed to `GenreBar.qml`/`LibraryData.qml`.

### Normal Flow

1. User presses the drag handle on a genre cell. `genreGridArea.reorderFrom`
   and `reorderTo` are both set to that cell's index (a no-op if fewer than
   2 genres are configured).
2. User moves the mouse. `genreDragMA.onPositionChanged` maps the cursor
   directly into `genreManageGrid`'s local coordinate space (no
   scroll-offset correction needed — this grid, unlike UC-11's `ListView`,
   has no `Flickable` ancestor and never scrolls) and computes:
   - `col = clamp(floor(pt.x / pitchX), 0, columns - 1)`
   - `row = floor(pt.y / pitchY)`
   - `flat = row * columns + col`, clamped to `[0, genreCount - 1]`
   `reorderTo` is set to `flat`.
3. The source cell dims to 45% opacity; a single shared outline `Rectangle`
   (not a per-delegate highlight) is drawn over the target cell at
   `(reorderTo % columns, reorderTo / columns)`.
4. User releases. `reorderFrom`/`reorderTo` reset to `-1` first (so the
   outline disappears before the model changes), then
   `Qt.callLater(commitGenreMove, from, to)` runs one tick later —
   deferred because `moveGenre()` fires `genresChanged` synchronously,
   which resets the `Repeater`'s `QStringList` model and would otherwise
   tear down the very delegate/`MouseArea` whose handler is running.
5. `commitGenreMove()` calls `appConfig.moveGenre(from, to)`, which moves
   the entry within `m_genres` (a plain list `move` — hole-free by
   construction) and emits `genresChanged` (+ `enabledGenresChanged` only
   if the derived enabled-subset's order actually changed), then
   auto-saves.
6. `commitGenreMove()` also remaps `root.selectedGenreIndex` (used by
   DELETE SELECTED) with the same shift arithmetic
   `PlaybackEngine::moveTrack` uses for `m_currentIndex`
   (`playbackengine.cpp`), plus an extra case for "the selected cell is the
   one that was just dragged" — without this, DELETE SELECTED could
   silently target the wrong genre after a reorder.
7. If `enabledGenresChanged` fired, `LibraryData.rebuildGenreModel()` runs
   and `GenreBar`'s buttons re-render in the new order.

### Alternates

- Same-cell release (`from === to`): no-op, `moveGenre` is never called,
  nothing is saved.
- Drag released past the grid's edges or onto a trailing empty placeholder
  slot: clamped, not rejected — lands at the nearest valid index (first or
  last configured genre).
- No Escape-to-cancel: any release commits to wherever `reorderTo` last
  resolved, same as UC-11.

### Why an outline instead of an insertion caret

`moveGenre(from, to)`'s `to` is the *final index* the dragged genre will
occupy, not an insert-before position — the honest indicator is therefore
"this cell is where your genre lands" (an outline over that cell), not a
line between two cells. A caret is also ambiguous in a 2D grid at row
wraps (is "after the last cell of row 1" the same gap as "before the
first cell of row 2"?), which a 1D vertical list like UC-11's queue never
has to resolve.

### Relationship to UC-11's drag mechanism

The drag mechanism itself — pure mouse-position tracking, no
`Drag`/`DropArea` — and *why* it was chosen are documented once in
**UC-11 → "Why pure mouse tracking instead of `Drag`/`DropArea`"** and are
not repeated here; UC-33 is that same mechanism generalized from a 1D
vertical list to a 2D grid. The two differ in exactly the ways a
dimensionality change requires: UC-11's index math is `floor(pt.y /
rowHeight)`, purely vertical; UC-33's is a genuine `(row, col)` pair
flattened via `row * columns + col`. UC-11 maps into a `ListView`'s
`contentItem` to account for scrolling; UC-33 maps directly into the grid
itself, since the GENRES grid is fixed-size and never scrolls.

### Design decisions

- **Every genre cell is draggable, enabled or disabled** — order
  (`m_genres`) and enabled-membership (`m_enabledGenreSet`) are orthogonal;
  a disabled genre's slot still matters for when it's later enabled.
- **Dedicated 24px drag-handle column on the cell's left edge**, not
  whole-cell drag with a movement threshold. The cell already reserves
  non-overlapping hit-columns for the enable checkbox and the
  select-for-delete click (see UC-03); a third reserved column preserves
  that convention instead of fighting it with press/move disambiguation
  logic.
- **`selectedGenreIndex` remapped, not cleared, after a move** — clearing
  it would silently discard the user's DELETE SELECTED intent for no
  reason; remapping (item 6 above) keeps it pointing at the same genre.
- **`enabledGenresChanged` emitted only when the derived value actually
  changes** — reordering two *disabled* genres past each other changes
  `m_genres`' order but not `enabledGenres()`'s value, so `LibraryData`'s
  selection-resetting `rebuildGenreModel()` is skipped in that case.
- **All 40 slots rendered, trailing ones as inert placeholders** — a
  second, `MouseArea`-free `Repeater` renders `maxGenres() -
  genres.length` empty outlined cells after the real ones, making the
  fixed-size board and the "no gaps" invariant (empty slots can only ever
  be trailing, because the order is a single dense list) visually
  self-evident.

## UC-34 Double-Click an Album's Cover Art to Queue All Its Tracks (AlbumBrowser only)

| Field | Detail |
|-------|--------|
| **Goal** | Double-clicking an album's cover art in `AlbumBrowser` adds every track of that album to the queue in one action, instead of double-clicking each track row individually. |
| **Actor** | User |
| **Precondition** | At least one album is visible in `AlbumBrowser`. |
| **Trigger** | User double-clicks an album's cover art thumbnail. |

`AlbumCard.qml` is shared, unmodified-per-host, by three panels —
`AlbumBrowser.qml`, `SearchResultBrowser.qml`, and `PlaylistViewer.qml` —
which pass it an identical prop set today. This feature is explicitly
scoped to `AlbumBrowser` only; `SearchResultBrowser`'s true album
groupings and `PlaylistViewer`'s one-track-per-card pseudo-albums (from
`LibraryModel::buildStandaloneTrackCards()`, see UC-10) are deliberately
left untouched.

### Normal Flow

1. User double-clicks the 160×160 cover-art image on an `AlbumBrowser`
   album card.
2. A `MouseArea` scoped to just that cover-art `Item` (not the whole
   card) fires `onDoubleClicked`, calling `root.addAllTracksToQueue()`.
3. `addAllTracksToQueue()` applies the same `autoPlay.
   manualQueueEditingAllowed` gate the existing per-track double-click
   uses, then calls `root.engine.addTracks(root.tracks)` — `root.tracks`
   is already the complete per-album track array every delegate carries
   (the same array the track-row `Repeater` iterates), so no new
   `LibraryModel`/`PlaybackEngine` API was needed.
4. `PlaybackEngine::addTracks()` (already batch-capable, see UC-06)
   appends every track in one `beginInsertRows`/`endInsertRows`, syncs to
   the active playlist file if one is loaded and unlocked, and
   auto-plays once if the queue was previously empty.

### Why the cover art, not the whole card

`AlbumCard` deliberately has no whole-card `MouseArea` — one existed
once (`cardHover`) and was removed because, sitting topmost, it
intercepted presses before the per-track `trackMA` could see them,
breaking track-row drag-to-queue (see UC-06, "Why `HoverHandler` instead
of `MouseArea` for card hover"). Scoping the new double-click handler to
just the cover-art `Item` — a plain, unshared `Item` entirely outside the
track-row `Repeater`'s bounds — sidesteps that failure mode completely:
it can never overlap or race with `trackMA`, so no z-order/event-stealing
risk is reintroduced.

### Why an opt-in property instead of a signal or a per-host wrapper

A new `AlbumCard` property, `wholeAlbumDoubleClickEnabled` (default
`false`), is set `true` only by `AlbumBrowser.qml`'s delegate. This
mirrors the existing `queueInteractionEnabled` idiom (also a plain
opt-out boolean, set only by the one host — `PlaylistViewer` — that needs
non-default behavior) rather than introducing a new signal-based contract
or forking `AlbumCard` into host-specific variants. `SearchResultBrowser`
and `PlaylistViewer` need zero changes; the property's default preserves
their exact prior behavior.

### Design decisions

- **Cover art only, not the whole card** — see above; the only region
  structurally guaranteed to never overlap a track row.
- **Default-off opt-in property** — `SearchResultBrowser.qml` and
  `PlaylistViewer.qml` require no changes at all; the feature is
  impossible to accidentally leak into them.
- **Reuses `addTracks()` and the `manualQueueEditingAllowed` gate
  verbatim** — no new C++ invocable, no new gating logic to keep in sync
  with the existing per-track double-click.
- **Cursor feedback gated the same way** — the cover shows
  `Qt.PointingHandCursor` only when `wholeAlbumDoubleClickEnabled` is
  true, so it doesn't look falsely interactive in the two excluded hosts.

