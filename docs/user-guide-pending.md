# User Guide — pending changes for the next release

Every user-visible change made since the last release is listed here as it happens. The
`Topaz User Guide.md` itself is updated **once, right before a release**, by working through
this list: guide text, one screenshot session for all images below, version number +
"Document history" line, PDF rebuild (`bash docs/build-user-guide-pdf.sh`). Afterwards this
list is emptied again.

Each entry: what changed for the user · which guide section(s) · screenshots to (re)take.

## Pending

### Setup → GENRES: 48 genres / 40 buttons, SCAN FOLDERS → FOUND GENRES (UC-36)
- **What changed:**
  - Up to **48** genres can be configured (GENRES grid 6 × 8, Setup dialog wider) and up to
    **40** shown in the genre bar (10 per row; with more than 30 a 4th row appears). Was 40 / 30.
  - New **SCAN FOLDERS** button (GENRES tab, bottom left; enabled when at least one music folder
    is ticked ACTIVE and connected). Opens **FOUND GENRES**: reads the genre tags of all files in
    the active folders; every genre appears at once with its track count while the scan runs
    (progress bar + STOP in the footer; STOP keeps what was found). Genres already in GENRES are
    dimmed ("already in GENRES"); new ones can be picked, also mid-scan, up to the free slots.
    **ADD SELECTED** adds them; closing Setup then scans the library automatically. Genres are
    shown exactly as tagged (first genre of a multi-genre tag). Files without a genre tag are
    counted in the footer. The scan only reads files.
- **Guide sections:**
  - *First start*: swap the steps — **Step 1: add your music folders**, **Step 2: add your
    genres** (SCAN FOLDERS needs folders first). In Step 2: "The easy way: let Topaz find your
    genres" (the walkthrough above), then "Typing a genre by hand"; update the limits in "Good to
    know" (48 / 40 / 4th row). *Step 3: scan*: also mention the automatic scan after adding found
    genres. Fix the two links in *Setup reference* (`#step-1-add-your-music-folders`,
    `#step-2-add-your-genres`).
  - *Setup reference → GENRES*: a small table of the controls (cells, checkbox, ADD,
    **SCAN FOLDERS** — not the same as SCAN FOLDERS in the bottom bar —, DELETE SELECTED/ALL).
  - *Troubleshooting*: "Some tracks are missing" → suggest Setup → GENRES → SCAN FOLDERS to see
    the exact tag spelling; "The library stays empty" → say "SCAN FOLDERS in the bottom bar".
- **Screenshots:** retake `setup-genres.png` (6-column grid, SCAN FOLDERS button); new
  `found-genres.png` (FOUND GENRES with the demo library, ideally mid-scan or with a selection).

### Setup → PLAYBACK: "Always measure instead of using ReplayGain / R128 tag" (UC-35)
> **IMPORTANT — describe this carefully.** Audiophile users will want to know exactly where
> the level Topaz applies comes from. Write it in plain words (no developer terms), but
> precisely; a small table or numbered list is fine.

- **What changed:** a new toggle switch under **Auto Loudness Correction → Audiophile/Critical
  Listening**, right below its Trim slider. Off by default.
- **What the guide must explain:**
  1. **How Topaz finds a track's level, option OFF (default)** — the first that applies wins:
     a) a value Topaz worked out earlier and remembered (only while the file is unchanged);
     b) otherwise a ReplayGain / R128 tag already in the file (track gain, not album gain);
     c) otherwise Topaz measures the track itself (EBU R128 / ReplayGain 2.0 method, target
        −18 LUFS) and remembers the result. Opus R128 tags are converted to that same target.
  2. **What the option does, ON:** tags in the files are ignored; every track is measured by
     Topaz itself. *Why you might want it:* tags written by other programs may use the older
     ReplayGain 1.0 method, may hold album gain instead of track gain, or may be out of date after
     a remaster/re-encode — so the levels across a library can be inconsistent. With the option on,
     everything is on one consistent scale. Measuring is fast (a few tenths of a second per
     track), but the first pass over a large library takes a while in the background. Your audio
     files are never changed.
  3. **When it has an effect:** only with the BASS Audio Library, Auto Loudness Correction on and
     *Audiophile/Critical Listening* selected — greyed out otherwise. Trim is still added on top.
  4. **Switching it ON:** values that came from tags are re-measured automatically; the playing
     track adjusts smoothly within a moment. No need to delete anything.
     **Switching it OFF again does not bring the tag values back:** tracks already measured keep
     their measured value. To start over completely, delete `Topaz.volumeNormalization.json`
     (in `%LOCALAPPDATA%\Topaz\` on Windows, `~/.config/Topaz/` on Linux) while Topaz is closed.
  5. **Export:** the Export dialog's *Replay Gain Normalization* follows this setting as well —
     even while Auto Loudness Correction is off. With the option on, an exported copy gets the
     measured value (+ Trim), not the value from the original file's tag.
- **Guide sections:** *Setup reference → PLAYBACK → Auto Loudness Correction* (main text, items
  1–4; also mention in the Audiophile description that tags are used "unless Always measure is
  on"); *Exporting a playlist → Replay Gain Normalization* (item 5, short, link back).
- **Screenshots:** retake the PLAYBACK tab screenshot (Auto Loudness Correction on, Audiophile
  selected, the new toggle visible).

### Setup → MISC: "Modify the Rating for the Track currently playing" (UC-29)
- **What changed:** the option *Delete the Rating for the Track currently playing* is renamed
  **Modify the Rating for the Track currently playing** and now covers the rating as a whole.
  It is **on by default**.
  - **On:** click a star to set or change the rating of the track currently playing; the
    trash-bin icon next to the stars deletes it (after a confirmation).
  - **Off:** the stars and the trash-bin icon are still shown — the stars still show the
    track's rating — but they can't be clicked. Use this to protect your ratings from
    accidental clicks (e.g. at a party, or when others use Topaz).
  - The trash-bin icon is now always shown next to the stars (dimmed when there is no rating
    to delete, or when the option is off). In 1.0.0 it was hidden unless the option was on.
  - Note for upgrading users: the old option setting is not carried over — everyone starts
    with the new option **on**.
- **Guide sections:** *Rating tracks* (rewrite the "To remove a rating completely, turn on …"
  sentence: the trash bin is always there; mention locking with the option off); *Setup
  reference → MISC* table (new name + description: "Lets you change or delete the rating of the
  playing track; when off, the rating is shown but locked").
- **Screenshots:** retake the MISC tab screenshot (new label). The NowPlaying screenshot now
  shows the trash-bin icon next to the stars — retake if the current one doesn't.

### Correct bitrate for VBR MP3s + VBR/CBR in NowPlaying
- **What changed:**
  - MP3 files with a variable bitrate (VBR) now show their real average bitrate in NowPlaying
    (and wherever the bitrate is shown) — e.g. 182 KBPS instead of 64 KBPS.
  - NowPlaying's format badge now says whether an MP3 has a variable or constant bitrate:
    `MP3 | VBR 182 KBPS`, `MP3 | CBR 320 KBPS`. FLAC and Opus show no prefix, as before
    (`FLAC | 950 KBPS`) — FLAC's bitrate always varies, being lossless.
  - After the update, Topaz re-reads the information of all MP3 files **once**, in the
    background, on the first start (the library stays usable meanwhile; ratings and playlists
    are kept).
- **Guide sections:** where the format/bitrate badge is explained (NowPlaying, item 8 "Format ·
  rating"): explain VBR / CBR (MP3 only) and that for VBR the average bitrate is shown.
  Optionally a "What's new in 1.1.0" line about the one-time background refresh.
- **Screenshots:** the NowPlaying screenshot(s) showing an MP3 badge now include "CBR" / "VBR" —
  retake them.

### NowPlaying: new Play/Pause, Previous and Next buttons
- **What changed:** only the look. The buttons are bigger and redesigned: a large round Play/Pause
  button in the Topaz purple-to-turquoise colours with a soft glow, flanked by round Previous and
  Next buttons that light up turquoise when you point at them. They work exactly as before, and
  Play/Pause still blinks while a track is paused. The playlist buttons (NEW, LOAD, EXPORT,
  REMOVE) sit a little lower. The progress bar's colour now runs from purple at the start to
  turquoise at the end of the track (before, the whole colour sweep was squeezed into the part
  already played).
- **Guide sections:** the NowPlaying overview (numbered callouts): check the callout positions
  for the transport and playlist buttons still match after retaking the screenshot.
- **Screenshots:** retake every screenshot that shows the NowPlaying panel.

### Panel sizes remembered separately for window and full screen
- **What changed:** the widths of the left panel (Library / Search / Playlists), the queue and
  NowPlaying are now remembered **separately** for the normal window and for full-screen mode
  (F11). Switching with F11 restores the sizes you last used in that mode, also after a restart.
  The first time you use full screen after the update, the panels keep their current sizes;
  adjust them once and Topaz remembers them. (Before, both modes shared one set of sizes.)
- **Guide sections:** wherever resizing the panels / F11 full screen is explained (the main
  window overview and the Full Screen description in *Setup reference → MISC* "Start Topaz in
  Full Screen"): one or two sentences. No screenshots needed.

### Export Playlist: "Create M3U Playlist" (UC-26)
- **What changed:** the EXPORT PLAYLIST dialog has a new checkbox **Create M3U Playlist** (off by
  default), where "Convert to MP3 (Stereo|CBR|320 kbps)" used to be; "Convert to MP3" now sits
  right below it. When checked, Topaz also writes a playlist file named after the playlist (e.g.
  `Road Trip.m3u`) into the export folder, listing the exported tracks in order. Why: some car
  stereos play the numbered files of a folder in order, others read an M3U playlist; with both on
  the stick, either kind works. The results screen confirms "M3U playlist created: …".
- **Guide sections:** *Exporting a playlist*: describe the checkbox (with the car-stereo
  reasoning) and update the position of "Convert to MP3".
- **Screenshots:** retake the EXPORT PLAYLIST dialog screenshot (new checkbox, taller dialog).

### Detachable panes: fine-tune the position with the arrow keys
- **What changed:** click a pane (Big Cover, Tag Information, Audio Visualizer or Milkdrop) to
  select it for fine-tuning: a thin **turquoise frame** shows which one. The **arrow keys** then
  move it **1 pixel** at a time; with **Shift** held, 10 pixels; holding a key keeps it moving.
  Works with several panes open, since only the selected one moves. The frame (and fine-tuning)
  ends with **Esc** or **Enter**, by clicking somewhere else, or by itself after 4 seconds without
  a key press. The new position is remembered like after dragging with the mouse. (Not while
  Milkdrop is in full screen with F10.)
- **Guide sections:** the section on the detachable panes (moving/resizing them), plus the
  keyboard-shortcut overview if the guide has one. No screenshots needed.

### Release housekeeping
- Title page "Version 1.0.0" and the text "Topaz 1.0.0" in the introduction → the new version.
- "Document history": add a line for the new edition.
