#!/bin/bash
# =============================================================================
#  Test di arc UI (arc-ui/) senza un desktop reale: lista dei pacchetti,
#  temi generati (SVG e kvconfig coerenti), installazione in una cartella di
#  prova, file di sessione e controlli statici dei sorgenti QML/C++.
#  La compilazione di arc-shell e la prova grafica si fanno nella VM.
#  Non richiede root né rete; serve python3.
# =============================================================================
set -o nounset -o pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
UI=$REPO/arc-ui
T=$(mktemp -d)
trap '[[ -n ${KEEP:-} ]] || rm -rf "$T"' EXIT

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  \e[32m✔\e[0m %s\n' "$1"; }
ko()   { fail=$((fail + 1)); printf '  \e[31m✘\e[0m %s\n' "$1"; [[ -n ${2:-} ]] && printf '      %s\n' "$2"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else ko "$d"; fi; }
has()   { grep -qF -- "$2" "$1" 2>/dev/null; }
hasnt() { ! grep -qF -- "$2" "$1" 2>/dev/null; }
py()    { python3 -I "$@"; }

echo "lista dei pacchetti (config/desktop/arc.list)"
LIST=$REPO/config/desktop/arc.list
check "display manager sddm"                 grep -qx '# display-manager: sddm' "$LIST"
check "base KDE: kwin e plasma-workspace"    bash -c 'grep -qx kwin "$0" && grep -qx plasma-workspace "$0"' "$LIST"
check "runtime di arc-shell"                 bash -c 'for p in layer-shell-qt qt6-declarative kservice kio kwindowsystem; do grep -qx "$p" "$0" || exit 1; done' "$LIST"
check "nessun pacchetto grafico di Plasma"   bash -c '! grep -qxE "plasma-desktop|breeze|breeze-gtk|kde-gtk-config|plasma-workspace-wallpapers" "$0"' "$LIST"
check "temi: kvantum, papirus, kdecoration"  bash -c 'for p in kvantum papirus-icon-theme kdecoration; do grep -qx "$p" "$0" || exit 1; done' "$LIST"
check "niente Aurorae (decorazione propria)" bash -c '! grep -qx aurorae "$0"' "$LIST"

echo "temi generati (theme/generate.py)"
GEN=$T/gen
if py "$UI/theme/generate.py" --out "$GEN"; then ok "generatore eseguito"; else ko "generatore eseguito"; fi
KV=$GEN/Kvantum/ArcGlass
check "SVG ben formati"                      py -c 'import sys, xml.dom.minidom as m; [m.parse(f) for f in sys.argv[1:]]' \
                                                 "$KV/ArcGlass.svg"
# Ogni elemento citato dal kvconfig deve esistere nello SVG (stato normal)
missing=$(py - "$KV/ArcGlass.kvconfig" "$KV/ArcGlass.svg" <<'EOF'
import re, sys
conf = open(sys.argv[1], encoding="utf-8").read()
ids = set(re.findall(r'id="([^"]+)"', open(sys.argv[2], encoding="utf-8").read()))
need = set()
for kind, name in re.findall(r'^(frame|interior|indicator)\.element=(\S+)', conf, re.M):
    if kind == "frame":
        need |= {"%s-normal-%s" % (name, p) for p in ("top", "bottom", "left", "right", "topleft", "topright", "bottomleft", "bottomright")}
    elif kind == "interior":
        need.add(name + "-normal")
    elif name == "arrow":
        need |= {"arrow-%s-normal" % d for d in ("up", "down", "left", "right")}
    else:
        need |= {name + "-normal", name + "-checked-normal"}
print(" ".join(sorted(need - ids)))
EOF
)
check "elementi del kvconfig presenti nello SVG" test -z "$missing"
[[ -z $missing ]] || printf '      mancano: %s\n' "$missing"
check "tutti gli stati dei pulsanti"         py -c '
import sys; s = open(sys.argv[1]).read()
sys.exit(any("id=\"button-%s-topleft\"" % st not in s for st in ("normal", "focused", "pressed", "toggled", "disabled")))' "$KV/ArcGlass.svg"
check "Kvantum: finestre traslucide e sfocate" bash -c 'grep -qx translucent_windows=true "$0" && grep -qx blurring=true "$0"' "$KV/ArcGlass.kvconfig"

echo "decorazione delle finestre (decoration/)"
DEC=$UI/decoration
check "plugin: sorgenti e metadati"          bash -c 'cd "$0" && test -f CMakeLists.txt && test -f arcdecoration.cpp && test -f arcdecoration.h' "$DEC"
check "plugin: id org.arcbase.arc"           py -c 'import json, sys; sys.exit(json.load(open(sys.argv[1]))["KPlugin"]["Id"] != "org.arcbase.arc")' "$DEC/arc.json"
check "plugin: sfocatura dichiarata"         py -c 'import json, sys; sys.exit(json.load(open(sys.argv[1]))["org.kde.kdecoration3"]["blur"] is not True)' "$DEC/arc.json"
check "plugin: nome del file = id"           has "$DEC/CMakeLists.txt" 'OUTPUT_NAME org.arcbase.arc'
check "angoli in basso arrotondati da KWin"  has "$DEC/arcdecoration.cpp" 'setBorderRadius'
check "barra del titolo sfocata da KWin"     has "$DEC/arcdecoration.cpp" 'setBlurRegion'
check "solo riduci, ingrandisci, chiudi"     bash -c 'grep -q "case DecorationButtonType::Minimize" "$0" && grep -q "case DecorationButtonType::Maximize" "$0" && grep -q "case DecorationButtonType::Close" "$0"' "$DEC/arcdecoration.cpp"
check "kwinrc: decorazione arc"              has "$UI/config/kwinrc" 'library=org.arcbase.arc'
check "kwinrc: pulsanti a destra IAX"        grep -qx 'ButtonsOnRight=IAX' "$UI/config/kwinrc"
check "11-desktop compila la decorazione"    has "$REPO/scripts/chroot/11-desktop.sh" 'arc-ui/decoration'

echo "Ticly Sequoia (tema icone predefinito)"
TS=$UI/icons/ticly-sequoia
check "checksum dell'archivio"               bash -c 'cd "$0" && { sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS; } >/dev/null' "$TS"
check "kdeglobals: Theme=ticly-sequoia"     grep -qx 'Theme=ticly-sequoia' "$UI/config/kdeglobals"
check "look-and-feel: Theme=ticly-sequoia"  grep -qx 'Theme=ticly-sequoia' "$UI/theme/lookandfeel/contents/defaults"
check "GTK: ticly-sequoia"                  grep -qx 'gtk-icon-theme-name=ticly-sequoia' "$UI/config/gtk-settings.ini"
check "shell: prima Ticly, poi le icone originali" grep -q 'ticly-sequoia' "$UI/shell/src/shell.cpp"
check "icone delle app così come sono"      bash -c 'for f in DockItem Launchpad NotificationCard; do grep -q "AppIcon {" "$0/$f.qml" || exit 1; done' "$UI/shell/qml"
check "dock: angoli concentrici, margini uguali" bash -c 'grep -q "dockHeight: dockIcon + 2 \* dockPadding$" "$0" && grep -q "iconCorner) + dockPadding" "$0"' "$UI/shell/qml/Theme.qml"
check "notifiche in alto al centro, a pila"  bash -c 'grep -q "Shell.AnchorTop," "$0/NotificationsWindow.qml" && ! grep -q "AnchorRight" "$0/NotificationsWindow.qml" && grep -q "win.mode === \"notifications\" ? Math.round" "$0/OverlayWindow.qml"' "$UI/shell/qml"
check "niente più arc icons e WhiteSur"      bash -c '! test -e "$0/arc-ui/icons/generate.py" && ! grep -rq "WhiteSur\|arc-icons" "$0/arc-ui/install.sh" "$0/config" "$0/scripts" "$0/arc-ui/shell"' "$REPO"
check "font Google Sans Flex (OFL) incluso"  bash -c 'test -s "$0/GoogleSansFlex.ttf" && grep -q "Open Font License" "$0/OFL.txt"' "$UI/fonts"
check "font in shell, KDE, GTK e SDDM"       bash -c 'grep -q "\"Google Sans Flex\"" "$0/shell/qml/Theme.qml" && grep -qx "font=Google Sans Flex,10" "$0/config/kdeglobals" && grep -q "Google Sans Flex" "$0/config/gtk-settings.ini" && grep -qx "font=Google Sans Flex" "$0/theme/sddm/theme.conf"' "$UI"
check "Sfondo in Impostazioni (Aspetto)"     bash -c 'grep -q "\"appearance\"" "$0/kcm/kcm_arcwallpaper.json" && grep -q "kcmutils_add_qml_kcm" "$0/kcm/CMakeLists.txt" && grep -q "arc-ui/kcm" "$1"' "$UI" "$REPO/scripts/chroot/11-desktop.sh"
check "Sfondo non più nel menu del desktop"  bash -c '! grep -q "Cambia sfondo" "$0/DesktopWindow.qml" && ! test -e "$0/WallpaperPicker.qml"' "$UI/shell/qml"
check "modulo sfondo di Plasma nascosto"     grep -qx 'kcm_wallpaper=false' "$UI/config/kdeglobals"
check "finestre: barra a pillole (nome, menu, pulsanti)"  bash -c 'grep -q "namePill" "$0/decoration/arcdecoration.cpp" && grep -q "ApplicationMenu" "$0/decoration/arcdecoration.cpp" && grep -q "org.arcos." "$0/decoration/arcdecoration.cpp"' "$UI"
check "velo dei pannelli sotto topbar e dock"  bash -c 'grep -q "LayerTop" "$0/shell/qml/VeilWindow.qml" && grep -q "VeilWindow" "$0/shell/qml/Main.qml"' "$UI"
check "Kvantum: contenuto incassato"         bash -c 'grep -q "\"content\", 20" "$0" && grep -q "frame__element=\"content\"" "$0"' "$UI/theme/generate.py"
check "Breeze per le icone ereditate"       grep -qx breeze-icons "$LIST"

echo "installazione in una cartella di prova (install.sh)"
R=$T/root
mkdir -p "$R/home/arc"
if bash "$UI/install.sh" --user arc "$R" >/dev/null; then ok "install.sh --user arc"; else ko "install.sh --user arc"; fi
for f in usr/bin/startarc usr/share/wayland-sessions/arc.desktop usr/lib/systemd/user/arc-shell.service \
         usr/lib/systemd/user/plasma-plasmashell.service.d/arc.conf usr/share/Kvantum/ArcGlass/ArcGlass.svg \
         usr/share/sddm/themes/arc/Main.qml usr/share/sddm/themes/arc/ArcIcon.qml \
         usr/share/plasma/look-and-feel/org.arcbase.arcui/contents/lockscreen/LockScreen.qml \
         usr/share/kwin/tabbox/arc/contents/ui/main.qml usr/share/color-schemes/ArcUI.colors \
         usr/share/arcbase/arc-ui/wallpaper/dolomiti.jpg usr/share/kglobalaccel/org.arcbase.launcher.desktop \
         etc/xdg/kwinrc etc/xdg/arcbase/arc-shell.conf etc/sddm.conf.d/10-arcbase-arc.conf \
         etc/skel/.config/Kvantum/kvantum.kvconfig home/arc/.config/Kvantum/kvantum.kvconfig; do
    check "installato: $f" test -f "$R/$f"
done
check "startarc eseguibile"                  test -x "$R/usr/bin/startarc"
check "arc-shell abilitata nella sessione"   test "$(readlink "$R/etc/systemd/user/plasma-workspace.target.wants/arc-shell.service")" \
                                                 = /usr/lib/systemd/user/arc-shell.service
check "kdeglobals: look-and-feel arc"        has "$R/etc/xdg/kdeglobals" 'LookAndFeelPackage=org.arcbase.arcui'
check "kdeglobals: stile kvantum"            has "$R/etc/xdg/kdeglobals" 'widgetStyle=kvantum'
check "kdeglobals: colori dello schema"      has "$R/etc/xdg/kdeglobals" '[Colors:Window]'
check "kdeglobals: un solo [General]"        test "$(grep -c '^\[General\]$' "$R/etc/xdg/kdeglobals")" -eq 1
check "kwinrc: Meta apre il launcher"        has "$R/etc/xdg/kwinrc" 'Meta=org.arcbase.Shell,/Shell,org.arcbase.Shell,toggleLauncher'
check "kwinrc: selettore finestre arc"       has "$R/etc/xdg/kwinrc" 'LayoutName=arc'
check "sddm: tema arc"                       has "$R/etc/sddm.conf.d/10-arcbase-arc.conf" 'Current=arc'
check "krunner (Plasma) disattivato"         has "$R/etc/skel/.config/kglobalshortcutsrc" '_launch=none'
check "ticly-sequoia installato con index.theme" test -f "$R/usr/share/icons/ticly-sequoia/index.theme"
check "ticly-sequoia: cartelle di Directories=" bash -c 'cd "$0" && for d in $(sed -n "s/^Directories=//p" index.theme | tr , " "); do test -d "$d" || exit 1; done' "$R/usr/share/icons/ticly-sequoia"
check "ticly-sequoia: icone come nell archivio" bash -c 'x=$(mktemp -d) && tar -xzf "$0" -C "$x" && rm "$x/ticly-sequoia/install.sh" && diff -r "$x/ticly-sequoia" "$1" -x icon-theme.cache -x arc-launchpad.svg >/dev/null; r=$?; rm -rf "$x"; exit $r' "$UI/icons/ticly-sequoia/ticly-sequoia.tar.gz" "$R/usr/share/icons/ticly-sequoia"
check "icona del Launchpad nel tema"       test -f "$R/usr/share/icons/ticly-sequoia/scalable/apps/arc-launchpad.svg"
check "/etc/xdg/kdeglobals: Theme=ticly-sequoia" grep -qx 'Theme=ticly-sequoia' "$R/etc/xdg/kdeglobals"
check "reinstallazione idempotente"          bash "$UI/install.sh" "$R"

echo "sessione"
S=$UI/session
check "plasmashell saltato con ARC_SESSION=1" has "$S/plasmashell-arc.conf" "test \"\$ARC_SESSION\" != 1"
check "arc-shell solo con ARC_SESSION=1"     has "$S/arc-shell.service" "test \"\$ARC_SESSION\" = 1"
check "startarc esporta ARC_SESSION"         has "$S/startarc" 'export ARC_SESSION=1'
check "startarc avvia la sessione KDE"       has "$S/startarc" 'exec /usr/bin/startplasma-wayland'
# KWin concede le interfacce riservate confrontando il percorso assoluto
check "desktop di arc-shell: Exec assoluto"  grep -qx 'Exec=/usr/bin/arc-shell' "$S/org.arcbase.shell.desktop"
check "desktop di arc-shell: window management" has "$S/org.arcbase.shell.desktop" 'org_kde_plasma_window_management'
check "notifiche attivate via arc-shell"     has "$S/org.freedesktop.Notifications.service" 'SystemdService=arc-shell.service'
check "nessuno stile Plasma per QtQuick"     hasnt "$S/startarc" 'org.kde.desktop'

echo "sorgenti di arc-shell (controlli statici)"
check "JSON validi"                          py -c 'import sys, json; [json.load(open(f)) for f in sys.argv[1:]]' \
                                                 "$UI/theme/lookandfeel/metadata.json" "$UI/theme/tabbox/metadata.json"
check "sorgenti C++ citati da CMake presenti" bash -c 'cd "$0" && for f in $(grep -o "src/[a-z]*\.cpp" CMakeLists.txt); do test -f "$f" || exit 1; done' "$UI/shell"
check "Main.qml caricato da main.cpp"        has "$UI/shell/src/main.cpp" 'qrc:/qml/Main.qml'
check "singleton dichiarati nel qmldir"      bash -c 'cd "$0" && while read -r kind name _ file; do [[ $kind == singleton ]] || continue; test -f "$file" && grep -q "pragma Singleton" "$file" || exit 1; done < qmldir' "$UI/shell/qml"
# Ogni tipo arc (con iniziale maiuscola) usato nei QML deve avere il suo file
unknown=$(py - "$UI/shell/qml" <<'EOF'
import os, re, sys
d = sys.argv[1]
local = {f[:-4] for f in os.listdir(d) if f.endswith(".qml")}
builtin = {"Item", "Rectangle", "Text", "TextInput", "Image", "MouseArea", "Row", "Column", "Grid", "Flow",
           "Repeater", "ListView", "GridView", "Loader", "Window", "Timer", "QtObject", "Instantiator",
           "Behavior", "NumberAnimation", "ColorAnimation", "SequentialAnimation", "Transition", "Shape",
           "ShapePath", "PathSvg", "WheelHandler", "Gradient", "GradientStop", "Translate", "Flickable",
           "Screen", "Qt", "Shell", "Applications", "Notifications", "Theme", "Clock", "TaskManager",
           "ListView", "Image", "Font", "Easing", "Locale", "Math", "Item", "Loader", "Text", "Component",
           "ShapePath", "Keys", "Date", "String", "JSON", "Connections", "HoverHandler", "ListModel",
           "PathAngleArc", "Scale", "TextEdit", "Media", "Osd"}
used = set()
for f in os.listdir(d):
    if not f.endswith(".qml"):
        continue
    src = open(os.path.join(d, f), encoding="utf-8").read()
    src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    src = re.sub(r'//[^\n]*', '', src)
    inline = set(re.findall(r'component (\w+)\s*:', src))
    for name in re.findall(r'(?m)^\s*([A-Z]\w*)\s*\{', src):
        if name not in inline:
            used.add(name)
print(" ".join(sorted(used - local - builtin)))
EOF
)
check "tipi QML usati ma non definiti"       test -z "$unknown"
[[ -z $unknown ]] || printf '      sconosciuti: %s\n' "$unknown"
# Parentesi bilanciate (esclusi stringhe e commenti): un errore qui rompe la shell
unbalanced=$(py - "$UI" <<'EOF'
import os, re, sys
bad = []
for root, _, files in os.walk(sys.argv[1]):
    for f in files:
        if not f.endswith((".qml", ".cpp", ".h")):
            continue
        p = os.path.join(root, f)
        src = open(p, encoding="utf-8").read()
        src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
        src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
        src = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", src)
        src = re.sub(r'//[^\n]*', '', src)
        src = re.sub(r'(?<=[(,=:])/(?:\\.|[^/\\\n])+/[gimsuy]*', '""', src)  # regex JS
        for o, c in ("{}", "()", "[]"):
            if src.count(o) != src.count(c):
                bad.append("%s %s%s" % (os.path.relpath(p, sys.argv[1]), o, c))
print(" ".join(bad))
EOF
)
check "parentesi bilanciate in QML e C++"    test -z "$unbalanced"
[[ -z $unbalanced ]] || printf '      %s\n' "$unbalanced"
check "materiale unico: niente tinte proprie" bash -c '! grep -qE "^[[:space:]]*(tint|edge):" "$0"/*.qml' "$UI/shell/qml"
check "widget: tutti i tipi hanno il file"   bash -c 'for k in Clock Calendar Media System Notes Weather; do test -f "$0/${k}Widget.qml" || exit 1; done' "$UI/shell/qml"
check "ricerca con KRunner"                  bash -c 'grep -q "KRunner::RunnerManager" "$0/src/search.cpp" && grep -q "KF6::Runner" "$0/CMakeLists.txt"' "$UI/shell"
check "pacchetti per la ricerca"             bash -c 'grep -qx krunner "$0" && grep -qx baloo "$0"' "$LIST"
check "Launchpad: cartelle salvate"          bash -c 'grep -q "Shell.launchpadLayout" "$0" && grep -q "function createFolder" "$0"' "$UI/shell/qml/Launchpad.qml"
check "Launchpad: topbar che diventa ricerca" has "$UI/shell/qml/Launchpad.qml" 'ActiveWindow.maximized'
check "stato a eventi (UPower, NetworkManager)" bash -c 'grep -q "org.freedesktop.UPower" "$0" && grep -q "org.freedesktop.NetworkManager" "$0" && grep -q "subscribe" "$0"' "$UI/shell/src/shell.cpp"
check "luce notturna nel centro di controllo" has "$UI/shell/qml/ControlCenter.qml" 'Shell.nightLight'
check "animazione di ingrandimento di KWin"  grep -qx 'maximizeEnabled=true' "$UI/config/kwinrc"
check "OSD su org.kde.plasmashell"           has "$UI/shell/src/osd.cpp" 'org.kde.plasmashell'
check "tutto schermo: niente decorazione"    grep -qx 'BorderlessMaximizedWindows=true' "$UI/config/kwinrc"
check "tutto schermo: topbar attaccata"      has "$UI/shell/qml/TopBarWindow.qml" 'ActiveWindow.maximized'
check "tutto schermo: dock nascosta"         has "$UI/shell/qml/DockWindow.qml" 'ActiveWindow.maximized'
check "margini delle superfici dinamici"     has "$UI/shell/src/shell.cpp" 'void Shell::updateLayer'
check "finestra attiva da libtaskmanager"    has "$UI/shell/qml/ActiveWindowTasks.qml" 'tasks.activeTask'
check "shell senza QtQuick.Controls (stile Plasma)" bash -c '! grep -rq "import QtQuick.Controls" "$0/shell" "$0/theme"' "$UI"
check "nessun import di Plasma nella shell"  bash -c '! grep -rqE "import org\.kde\.(plasma|ksvg)" "$0"' "$UI"

echo
echo "Risultato: $pass superati, $fail falliti"
(( fail == 0 ))
