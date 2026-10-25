#!/bin/bash
# =============================================================================
#  arc-ui/preview/run.sh — anteprima interattiva di arc UI senza KDE
#
#  Uso: run.sh [shell|sddm] [--shots]
#    shell    desktop arc: topbar, widget, dock, launcher, notifiche (default)
#    sddm     schermata di accesso
#    --shots  salva le schermate in arc-ui/preview/.out ed esce
#    --anim   salva i fotogrammi dell'ingrandimento di una finestra ed esce
#    --anim-launchpad  fotogrammi della topbar che diventa la ricerca
#    --trailer  registra il trailer (fotogrammi in .out/trailer, poi trailer.sh)
#
#  Serve Qt 6 con CMake (macOS: brew install qt cmake). I file QML di
#  arc-ui/shell/qml e arc-ui/theme/sddm si ricaricano da soli quando cambiano.
#  Le parti in C++ e KDE sono simulate (mock/), le icone sono segnaposto e la
#  sfocatura imita quella di KWin.
# =============================================================================
set -o errexit -o nounset -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
BUILD=$HERE/.build
OUT=$HERE/.out

mode=shell
while (($#)); do
    case $1 in
        shell|sddm) mode=$1 ;;
        --shots) export ARC_PREVIEW_SHOTS=1 ;;
        --anim) export ARC_PREVIEW_ANIM=window ;;
        --anim-launchpad) export ARC_PREVIEW_ANIM=launcher ;;
        --trailer) export ARC_PREVIEW_TRAILER=1 ;;
        -h|--help) sed -n '3,16p' "$0"; exit 0 ;;
        *) echo "argomento sconosciuto: $1" >&2; exit 2 ;;
    esac
    shift
done

prefix=${QT_PREFIX:-}
if [[ -z $prefix ]] && command -v brew >/dev/null; then
    prefix=$(brew --prefix qt 2>/dev/null || :)
fi
cmake -S "$HERE/runner" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release ${prefix:+-DCMAKE_PREFIX_PATH="$prefix"} >/dev/null
cmake --build "$BUILD" >/dev/null
mkdir -p "$OUT"
# Icone come sul sistema: Ticly Sequoia, poi le icone originali (Breeze, che
# Ticly eredita; scaricato la prima volta). Le app senza icona hanno un segnaposto.
rm -rf "$BUILD/ticly" && mkdir -p "$BUILD/ticly"
tar -xzf "$REPO/arc-ui/icons/ticly-sequoia/ticly-sequoia.tar.gz" -C "$BUILD/ticly"
cp -R "$REPO/arc-ui/icons/ticly-sequoia/extra/." "$BUILD/ticly/ticly-sequoia/"
if [[ ! -d $BUILD/breeze/icons/apps/48 ]]; then
    rm -rf "$BUILD/breeze"
    git clone -q --depth 1 --filter=blob:none --sparse https://invent.kde.org/frameworks/breeze-icons.git "$BUILD/breeze" 2>/dev/null \
        && git -C "$BUILD/breeze" sparse-checkout set icons/apps/48 icons/places/64 2>/dev/null || true
fi
ARC_ICONS=""
for size in scalable 512x512 256x256 128x128 96x96 64x64 48x48; do
    for ctx in apps places devices mimetypes; do
        ARC_ICONS+="$BUILD/ticly/ticly-sequoia/$size/$ctx:"
    done
done
# Icone originali delle app di terze parti (sul sistema le installa l'app
# stessa in hicolor): quelle pubblicate da Flathub, scaricate la prima volta
originals=$BUILD/originals
mkdir -p "$originals"
while read -r name appid; do
    [[ -s $originals/$name.png ]] && continue
    curl -fsSL -o "$originals/$name.png" \
        "https://dl.flathub.org/repo/appstream/x86_64/icons/128x128/$appid.png" 2>/dev/null \
        || rm -f "$originals/$name.png"
done <<'EOF'
firefox org.mozilla.firefox
gimp org.gimp.GIMP
inkscape org.inkscape.Inkscape
blender org.blender.Blender
darktable org.darktable.Darktable
shotwell org.gnome.Shotwell
telegram org.telegram.desktop
discord com.discordapp.Discord
zoom us.zoom.Zoom
signal org.signal.Signal
thunderbird org.mozilla.Thunderbird
chromium org.chromium.Chromium
filezilla org.filezillaproject.Filezilla
transmission com.transmissionbt.Transmission
bitwarden com.bitwarden.desktop
keepassxc org.keepassxc.KeePassXC
vlc org.videolan.VLC
audacity org.audacityteam.Audacity
spotify com.spotify.Client
obs com.obsproject.Studio
libreoffice-writer org.libreoffice.LibreOffice
calibre com.calibre_ebook.calibre
code com.visualstudio.code
steam com.valvesoftware.Steam
EOF
export ARC_ICONS+="$BUILD/breeze/icons/apps/48:$BUILD/breeze/icons/places/64:$originals"

qml=$HERE/Preview.qml
if [[ $mode == sddm ]]; then
    # Il tema come lo installa install.sh, ma con collegamenti ai sorgenti
    # (così le modifiche si vedono subito)
    theme=$BUILD/sddm-theme
    mkdir -p "$theme"
    ln -sfn "$REPO/arc-ui/theme/sddm/Main.qml" "$theme/Main.qml"
    ln -sfn "$REPO/arc-ui/shell/qml/ArcIcon.qml" "$theme/ArcIcon.qml"
    ln -sfn "$REPO/arc-ui/shell/qml/assets/arc-wordmark-light.svg" "$theme/arc-wordmark-light.svg"
    export SDDM_MAIN=$theme/Main.qml
    qml=$HERE/SddmPreview.qml
fi

exec "$BUILD/arc-preview" "$qml" "$HERE/mock" "$OUT" "$REPO"
