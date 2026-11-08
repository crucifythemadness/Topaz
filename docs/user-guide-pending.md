# User Guide — pending changes for the next release

Every user-visible change made since the last release is listed here as it happens. The
`Topaz User Guide.md` itself is updated **once, right before a release**, by working through
this list: guide text, one screenshot session for all images below, version number +
"Document history" line, PDF rebuild (`bash docs/build-user-guide-pdf.sh`). Afterwards this
list is emptied again.

Each entry: what changed for the user · which guide section(s) · screenshots to (re)take.

## Pending

- **New top bar look** — the Topaz logo now sits left of a new retro neon "TOPAZ JUKEBOX"
  lettering with a soft neon glow (pink/violet TOPAZ, cyan JUKEBOX, the same on every
  system); the speaker, gear
  and ⓘ icons were replaced by matching line icons (speaker / crossed-out speaker when muted,
  info, gear — the same on Windows and Linux), and the order on the right is now
  speaker · gear · info · **full screen / window button** (same as F11; tooltip shows which).
  **In full screen only**, two more buttons follow: **minimize** and a **close (✕)** button
  that turns red on hover — so Topaz can be minimized or closed with the mouse in full screen.
  Restoring after minimizing from full screen returns to full screen.
  A thin **ring around the speaker** now shows the current system volume at a glance (like a
  small version of the volume knob; dimmed when muted), and its tooltip shows the value
  ("System volume: 60 %").
  · Guide sections: "First start" (the "gear icon ⚙" wording), "The main window" (callout
  table row 2 "Speaker · gear · ⓘ" → new order and the full-screen button), "Adjusting the
  layout" / "Detachable panes and full screen" (mention the button next to F11, and minimize/
  close in full screen), "System volume and mute" (the ring + tooltip).
  · Screenshots: the main-window overview (new top bar, windowed, volume ring at ~60 %), plus a crop of the top bar
  in full screen showing minimize + close; any screenshot that shows the old gear/ⓘ icons.

- **New app icon** — a glowing neon retro jukebox (pink/violet cabinet, a record in the
  cyan dome window, cyan base), in the colours of the new lettering; used everywhere:
  Topaz.exe, the taskbar/window, the AUTO PLAY notification, the top bar, the About dialog
  and the Linux launcher.
  · Guide sections: "Getting Topaz running" (Windows/Linux, if they describe or show the icon),
  the title page / introduction if it shows the icon.
  · Screenshots: anything showing the old icon (top bar, taskbar, About dialog, Linux app menu).

- **About dialog reworked** — TOPAZ tab: new icon + neon lettering; the description now says
  that versions newer than 1.1.0 are made with the support of Claude Opus 5.5 (also in
  DEVELOPED BY). POWERED BY tab: instead of a scrolling list of logos and links, a grid of
  eight cards (Qt, FFmpeg, projectM, KISS FFT, GLEW, miniz, BASS, Monoton), each showing what
  it does and its license; clicking a card opens a details page (version, license, what it
  does in Topaz, what it is, copyright, links) with BACK and NEXT.
  · Guide section: the About part (currently "The **ⓘ** icon … shows the version, the build
  date and some statistics") — describe the three tabs and the POWERED BY details.
  · Screenshots: About dialog TOPAZ tab, POWERED BY grid, one details page (e.g. Qt).

- **8 more audio visualizer colours** — Setup → AUDIO VISUALIZER now offers 40 colour
  swatches in two rows of 20 (was 32 in two rows of 16), including the four neon colours of
  the new lettering (pink, violet, cyan, blue), hot magenta, electric lime, mint and a warm
  white.
  · Guide section: the audio visualizer settings (colour choice; mention the count only if
  the guide does).
  · Screenshots: Setup → AUDIO VISUALIZER tab.

- **Queue height adjustable from above and below** — drag the thin strip directly above or
  below the playback queue to make the queue shorter; the freed area shows a faint "FREE
  SPACE" placeholder and can hold a docked pane (see "Docking panes" below). Dragging the
  strip back to the edge removes the area again. After a restart only a free space that holds a
  docked pane comes back (at its size — remembered separately for the window and for full screen,
  like the panel widths); empty free space is gone again.
  · Guide section: "Adjusting the layout".
  · Screenshots: main window with free space above and/or below the queue (ideally with the
  visualizer placed there).

- **New Audio Meter** — a sixth button **AUDIO METER** in the bottom bar (between AUDIO
  VISUALIZER and MILKDROP) opens a movable, resizable meter window in a 90s HiFi look: two rows
  (L/R) of segments from green over yellow to orange, a digital dB scale (−50 … 0 dB, where 0 dB
  is the loudest level a track can contain), a peak-hold segment and a red **OVER** lamp that
  lights when a track reaches 0 dB. With the BASS Audio Library the levels come from BASS,
  otherwise Topaz measures them itself (shown small under the OVER lamp: BASS / TOPAZ). Right-click
  closes it, like the other panes. New Setup tab **AUDIO METER**: style (one style so far, "90s
  HiFi") with a **Colours** switch below it — **HIFI** (default, the classic green/yellow/orange)
  or **TOPAZ** (teal, violet and neon pink like the rest of Topaz; OVER stays red) — Peak Hold
  on/off, Pane Opacity.
  The bottom-bar icons changed too: AUDIO VISUALIZER now shows vertical bars (was ≡), AUDIO METER
  two horizontal level bars.
  · Guide sections: the bottom bar description (six buttons, icons), a new "Audio Meter" section next to
  the audio visualizer, the Setup tab list (new AUDIO METER tab; MILKDROP and MISC move one to the
  right).
  · Screenshots: Audio Meter pane while music plays (ideally with OVER lit; optionally both colour
  sets), Setup → AUDIO METER,
  the bottom bar.

- **Docking panes** — the Audio Meter, the audio visualizer and Milkdrop can be docked into the
  free space above or below the queue: hover over the pane and click one of the small buttons in
  its top-right corner (**Dock above the queue** / **Dock below the queue**; a button only shows
  while that space is empty). A docked pane fills the space; hovering it shows **Float as a
  separate window** and **Close** (right-click closes too). Closing a docked pane and opening it
  again with its bottom-bar button puts it back in the same place. Panes that are docked when
  Topaz is closed come back docked at the next start. Docked Milkdrop has no F10 full
  screen and no double-click positions — float it again for that.
  · Guide sections: "Adjusting the layout" (free space), the audio visualizer / Milkdrop / Audio
  Meter sections (mention docking).
  · Screenshots: main window with a docked pane (e.g. Audio Meter below the queue), a crop of the
  dock buttons on a hovered pane.

### Release housekeeping
- Title page "Version 1.1.0" and the text "Topaz 1.1.0" in the introduction → the new version.
- "Document history": add a line for the new edition.
