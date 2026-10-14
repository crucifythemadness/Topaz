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

### Release housekeeping
- Title page "Version 1.0.0" and the text "Topaz 1.0.0" in the introduction → the new version.
- "Document history": add a line for the new edition.
