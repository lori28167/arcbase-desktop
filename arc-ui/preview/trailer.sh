#!/bin/bash
# =============================================================================
#  Trailer di Arcbase Desktop (arc UI) per YouTube: registra l'anteprima
#  guidata da Trailer.qml e monta un MP4 1920×1080 a 30 fps (H.264).
#  Uso: arc-ui/preview/trailer.sh   → arc-ui/preview/.out/arcbase-desktop-trailer.mp4
#  Serve ffmpeg (brew install ffmpeg).
# =============================================================================
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/.out
command -v ffmpeg >/dev/null || { echo "trailer.sh: serve ffmpeg (brew install ffmpeg)" >&2; exit 1; }

"$HERE/run.sh" --trailer
cd "$OUT/trailer"
ffmpeg -y -loglevel error -f concat -safe 0 -i frames.ffconcat \
    -vf "fps=30,format=yuv420p" -c:v libx264 -preset slow -crf 16 -movflags +faststart \
    "$OUT/arcbase-desktop-trailer.mp4"
echo "Trailer: $OUT/arcbase-desktop-trailer.mp4"
