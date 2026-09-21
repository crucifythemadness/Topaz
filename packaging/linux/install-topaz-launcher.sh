#!/bin/sh
# Adds a "Topaz" entry (with icon) to this user's application menu, or removes it.
#
#   ./install-topaz-launcher.sh            install / update the launcher
#   ./install-topaz-launcher.sh --remove   remove it again
#
# The launcher points at THIS folder, so run it again if you move the folder
# (e.g. from a USB stick to your home directory). Nothing outside
# ~/.local/share/applications is touched, and no root access is needed.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ENTRY="$APPS/topaz.desktop"

if [ "$1" = "--remove" ]; then
    rm -f "$ENTRY"
    echo "Removed $ENTRY"
    exit 0
fi

if [ ! -f "$DIR/run-topaz.sh" ] || [ ! -f "$DIR/topaz-bin" ]; then
    echo "run-topaz.sh / topaz-bin not found next to this script -- run it from the Topaz folder." >&2
    exit 1
fi

# Files copied from a Windows machine or a FAT/exFAT USB stick often lose their
# executable bit; restore it so the launcher can actually start Topaz.
chmod +x "$DIR/run-topaz.sh" "$DIR/topaz-bin" 2>/dev/null || true

mkdir -p "$APPS"
cat > "$ENTRY" <<EOF
[Desktop Entry]
Type=Application
Name=Topaz
Comment=Audio jukebox
Exec="$DIR/run-topaz.sh"
Icon=$DIR/topaz.png
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=Topaz
EOF

echo "Installed $ENTRY"
echo "Look for \"Topaz\" in your application menu (it can take a few seconds to appear)."
