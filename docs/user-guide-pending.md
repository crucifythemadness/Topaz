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

### Release housekeeping
- Title page "Version 1.1.0" and the text "Topaz 1.1.0" in the introduction → the new version.
- "Document history": add a line for the new edition.
