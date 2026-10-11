#!/usr/bin/env bash
# Builds "docs/Topaz User Guide.pdf" from "docs/Topaz User Guide.md".
#
# Run from Git Bash on Windows (or a Linux shell):   bash docs/build-user-guide-pdf.sh
#
# Needs:
#   - Docker (Docker Desktop on Windows): pandoc runs in a throw-away ubuntu:24.04
#     container and turns the Markdown into ONE self-contained HTML file
#     (images and user-guide.css embedded).
#   - Microsoft Edge (Windows) or Chrome/Chromium: prints that HTML to the PDF,
#     headless, using user-guide.css's @page rules (A4).
# Re-run it after every change to the guide or its images; nothing is incremental.
set -euo pipefail

cd "$(dirname "$0")"
MD="Topaz User Guide.md"
PDF="Topaz User Guide.pdf"
HTML=".user-guide-build.html"

# Host path of this folder for the Docker bind mount (Windows path under Git Bash).
HOSTDIR="$(pwd -W 2>/dev/null || pwd)"

echo "1/2 Markdown -> HTML (pandoc in Docker) ..."
MSYS_NO_PATHCONV=1 docker run --rm -v "$HOSTDIR:/doc" -w /doc ubuntu:24.04 bash -c "
  apt-get update -qq >/dev/null 2>&1 &&
  apt-get install -y -qq pandoc >/dev/null 2>&1 &&
  pandoc '$MD' --from gfm --standalone --embed-resources \
         --css user-guide.css --metadata pagetitle='Topaz User Guide' \
         -o '$HTML'"

echo "2/2 HTML -> PDF (headless browser) ..."
BROWSER=""
for c in "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
         "/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
         "/c/Program Files/Google/Chrome/Application/chrome.exe" \
         "$(command -v chromium 2>/dev/null || true)" \
         "$(command -v chromium-browser 2>/dev/null || true)" \
         "$(command -v google-chrome 2>/dev/null || true)"; do
  if [ -n "$c" ] && [ -x "$c" ]; then BROWSER="$c"; break; fi
done
[ -n "$BROWSER" ] || { echo "No Edge/Chrome/Chromium found" >&2; exit 1; }

# A separate, throw-away browser profile is required: without it, an Edge/Chrome
# window that is already open swallows the headless call and nothing is printed.
PROFILE="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then
  OUT="$(cygpath -w "$PWD/$PDF")"; IN="file:///$(cygpath -m "$PWD/$HTML")"; PROF="$(cygpath -w "$PROFILE")"
else
  OUT="$PWD/$PDF"; IN="file://$PWD/$HTML"; PROF="$PROFILE"
fi
rm -f "$PDF"
"$BROWSER" --headless=new --disable-gpu --no-first-run --user-data-dir="$PROF" \
           --no-pdf-header-footer --print-to-pdf="$OUT" "$IN" >/dev/null 2>&1 || true

# msedge.exe on Windows hands the job to a background process and returns at
# once, so wait for the PDF itself: it must exist and its size stop changing.
last=-1; stable=0
for _ in $(seq 1 180); do
  if [ -s "$PDF" ]; then
    now=$(stat -c %s "$PDF")
    if [ "$now" = "$last" ]; then stable=$((stable + 1)); else stable=0; fi
    last=$now
    [ "$stable" -ge 3 ] && break
  fi
  sleep 1
done

# The browser can hold a lock file in the profile for a moment after exiting;
# a leftover temp folder is harmless, so cleanup is best-effort.
rm -f "$HTML"; sleep 2; rm -rf "$PROFILE" 2>/dev/null || true
[ -s "$PDF" ] || { echo "FAILED: the browser did not write $PDF" >&2; exit 1; }
echo "done: docs/$PDF ($(du -h "$PDF" | cut -f1))"
