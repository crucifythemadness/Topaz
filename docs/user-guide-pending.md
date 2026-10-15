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

### Release housekeeping
- Title page "Version 1.0.0" and the text "Topaz 1.0.0" in the introduction → the new version.
- "Document history": add a line for the new edition.
