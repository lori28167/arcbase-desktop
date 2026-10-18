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
# Icone come sul sistema: arc icons, poi WhiteSur (scaricato la prima volta,
# alla stessa versione di config/arcbase.conf)
python3 "$REPO/arc-ui/icons/generate.py" --out "$BUILD"
if [[ ! -d $BUILD/whitesur ]]; then
    tag=$(sed -n 's|.*ARC_ICON_THEME_URL=.*/tags/\([^/]*\)\.tar\.gz.*|\1|p' "$REPO/config/arcbase.conf")
    rm -rf "$BUILD/whitesur-src"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" \
        https://github.com/vinceliuice/WhiteSur-icon-theme.git "$BUILD/whitesur-src" 2>/dev/null
    python3 "$HERE/flatten-icons.py" "$BUILD/whitesur-src" "$BUILD/whitesur"
fi
export ARC_ICONS=$BUILD/icons/arc-icons/scalable/apps:$BUILD/whitesur

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
