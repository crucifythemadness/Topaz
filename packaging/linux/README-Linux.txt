Topaz 1.0.0 for Linux
=====================

A self-contained Linux build of Topaz (built on Ubuntu 24.04 with Qt 6.10.2).
It bundles its own Qt, projectM and GLEW, so nothing needs to be installed to
run it beyond what any desktop Linux already has.

Requirements
------------
- 64-bit (x86_64) desktop Linux with glibc 2.38 or newer, e.g. Ubuntu 24.04+
  and its flavours, Linux Mint 22+, Debian 13+, Fedora 39+
- X11 or Wayland
- PulseAudio or PipeWire (with pipewire-pulse)
- For Milkdrop: OpenGL 3.3 Core Profile (see below)

Tested on real hardware: Linux Mint 22.2 (Cinnamon, X11, NVIDIA) and Ubuntu
Studio (Wayland).

How to run
----------
    ./run-topaz.sh

Do not run ./topaz-bin directly: the wrapper script sets LD_LIBRARY_PATH so
the bundled lib/ directory is used. If the files lost their executable bit
(always the case after unpacking the .7z archive, and common after copying
from Windows or a FAT/exFAT USB stick):

    chmod +x run-topaz.sh topaz-bin install-topaz-launcher.sh

(The executable is called "topaz-bin" rather than "topaz" because it must sit
next to a directory literally named "Topaz/", and this folder was assembled
on Windows, whose filesystem cannot tell "topaz" and "Topaz" apart.)

App icon / application menu entry
---------------------------------
The window icon is set by Topaz itself. To also get a "Topaz" entry with its
icon in your application menu and panel (and a proper icon on Wayland), run
once from this folder:

    sh ./install-topaz-launcher.sh

It writes ~/.local/share/applications/topaz.desktop, pointing at this folder.
Run it again if you move the folder. Undo with:

    sh ./install-topaz-launcher.sh --remove

Where Topaz keeps its settings
------------------------------
~/.config/Topaz/   (Topaz.config, the library cache, playlists/, ratings)

Milkdrop needs OpenGL 3.3 (Core Profile)
----------------------------------------
Milkdrop needs a graphics driver that provides OpenGL 3.3 Core Profile or
newer. On older GPUs/drivers (and some virtual machines) the Milkdrop pane
shows "MILKDROP UNAVAILABLE". Check what your machine offers with:

    glxinfo -B | grep "core profile version"        (package: mesa-utils)

It must say 3.3 or higher. If Milkdrop is unavailable, milkdrop_debug.log in
this folder records what the driver actually offers.

BASS audio backend
------------------
Topaz never bundles the BASS audio library (licensing -- see
https://www.un4seen.com/). To use the BASS backend, place your own licensed
copies of:
    libbass.so
    libbassflac.so
    libbassopus.so
directly next to topaz-bin in this folder. Without them Topaz uses the FFmpeg
backend, which needs nothing extra.

Auto Loudness Correction (Setup > PLAYBACK) only works with the BASS backend.
Its "Audiophile/Critical Listening" strategy needs nothing more. Its
"Consistent Background Music" strategy (a compressor) additionally needs the
BASS_FX add-on, also supplied by you and placed next to topaz-bin:
    libbass_fx.so
Topaz never modifies your audio files; it only stores its results in
~/.config/Topaz/Topaz.volumeNormalization.json.

Export: "Convert to MP3"
-----------------
The Export Playlist dialog can convert FLAC/Opus tracks to MP3 (44.1 kHz,
stereo, CBR 320 kbps) in the exported copies -- your library files are never
changed. This needs the ffmpeg program, which Topaz does not bundle:
    sudo apt install ffmpeg
(or place an ffmpeg binary next to topaz-bin). It must include the libmp3lame
encoder, which the Ubuntu/Mint package does. Without ffmpeg the "Convert to
MP3" checkbox stays greyed out; its tooltip says why.

What's bundled
--------------
- topaz-bin            the executable
- Topaz/               QML module metadata (qmldir + topaz.qmltypes) --
                       required next to the executable
- lib/                 Qt 6.10.2 + projectM + GLEW runtime libraries,
                       libstdc++/libgcc for cross-distro safety, and the
                       "system" libraries verified missing on a bare machine
                       (OpenGL/GLX dispatch, the X11/XCB extension libraries
                       the Qt xcb platform plugin needs, Kerberos/GSSAPI for
                       Qt Network, PulseAudio's codec chain)
- plugins/             Qt platform, image-format, multimedia (FFmpeg), TLS
                       plugins
- qml/                 Qt's own QML modules
- qt.conf              tells Qt where plugins/ and qml/ are
- topaz.png, install-topaz-launcher.sh   see "App icon" above
- Topaz User Guide.pdf the user manual
- LICENSE              GNU General Public License v3 (Topaz itself; the
                       bundled libraries keep their own licenses, see the
                       project page)

Assumed already present on the target system (not bundled): libx11-6,
libxrandr2, libxrender1, libxi6, libxext6, libxkbcommon0, libxkbcommon-x11-0,
libfontconfig1, libfreetype6, libdbus-1-3, libxcb1, libglib2.0-0t64, libgl1,
libglx0, libegl1, libpulse0 (Ubuntu/Debian names; every normal desktop Linux
install has the equivalents).

If something doesn't work
--------------------------
Run from a terminal (not a file-manager double-click) so you can see any
message, and report what you see at
https://github.com/crucifythemadness/Topaz/issues

For the Audio Visualizer specifically: start Topaz from a terminal, play a
track, open the AUDIO VISUALIZER pane, and copy everything the terminal prints
from that moment. Lines starting "WindowChrome:" and "AudioVisualizerController:"
say whether the window got its alpha channel, which graphics API is in use,
whether audio reaches the visualizer, and whether the bars are being computed.
