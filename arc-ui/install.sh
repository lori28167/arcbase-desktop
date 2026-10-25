#!/bin/bash
# =============================================================================
#  arc-ui/install.sh — installa temi, sessione e configurazione di arc UI
#
#  Uso: install.sh [--user NOME] [DESTDIR]
#    DESTDIR   radice del sistema (default /); una cartella vuota per i test
#    --user    copia le impostazioni anche nella home di quell'utente
#              (oltre a /etc/skel per gli utenti creati dopo)
#
#  arc-shell (il programma) si compila a parte con CMake da arc-ui/shell:
#  qui si installa tutto il resto. Non richiede rete; serve python3.
# =============================================================================
set -o errexit -o nounset -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
USER_NAME=''
DEST=/

while (($#)); do
    case $1 in
        --user) USER_NAME=${2:?--user richiede un nome}; shift 2 ;;
        -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
        -*) echo "opzione sconosciuta: $1" >&2; exit 2 ;;
        *) DEST=$1; shift ;;
    esac
done
DEST=${DEST%/}

put() { # put MODE SORGENTE DESTINAZIONE (relativa a DEST)
    mkdir -p "$(dirname "$DEST/$3")"
    install -m "$1" "$2" "$DEST/$3"
}

# --- Temi generati (Kvantum, decorazioni KWin) --------------------
python3 "$HERE/theme/generate.py" --out "$DEST/usr/share"

# --- Tema icone predefinito: Ticly Sequoia (archivio fissato con checksum) ----
# Si installa così com'è, senza toccare le icone.
ticly=$HERE/icons/ticly-sequoia
(cd "$ticly" && { sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS; } >/dev/null) \
    || { echo "install.sh: checksum di ticly-sequoia.tar.gz errato" >&2; exit 1; }
rm -rf "$DEST/usr/share/icons/ticly-sequoia"
mkdir -p "$DEST/usr/share/icons"
tar -xzf "$ticly/ticly-sequoia.tar.gz" -C "$DEST/usr/share/icons" --no-same-owner \
    --exclude ticly-sequoia/install.sh
# Icone aggiunte al tema (es. Launchpad): in cartelle già elencate in index.theme
cp -R "$ticly/extra/." "$DEST/usr/share/icons/ticly-sequoia/"
chmod -R a+rX "$DEST/usr/share/icons/ticly-sequoia"
if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache -q -f -t "$DEST/usr/share/icons/ticly-sequoia" || true
fi

# --- File condivisi ------------------------------------------------------------
share=usr/share
for w in "$HERE"/wallpaper/*.jpg; do
    put 644 "$w" "$share/arcbase/arc-ui/wallpaper/${w##*/}"
done
put 644 "$HERE/theme/ArcUI.colors"      "$share/color-schemes/ArcUI.colors"
# Font di sistema: Google Sans Flex (OFL 1.1, da github.com/google/fonts)
put 644 "$HERE/fonts/GoogleSansFlex.ttf" "$share/fonts/google-sans-flex/GoogleSansFlex.ttf"
put 644 "$HERE/fonts/OFL.txt"            "$share/licenses/google-sans-flex/OFL.txt"
if [[ -z $DEST ]] && command -v fc-cache >/dev/null; then
    fc-cache -f "/$share/fonts/google-sans-flex" >/dev/null || true
fi

lnf=$share/plasma/look-and-feel/org.arcbase.arcui
put 644 "$HERE/theme/lookandfeel/metadata.json"                     "$lnf/metadata.json"
put 644 "$HERE/theme/lookandfeel/contents/defaults"                 "$lnf/contents/defaults"
put 644 "$HERE/theme/lookandfeel/contents/lockscreen/LockScreen.qml" "$lnf/contents/lockscreen/LockScreen.qml"
put 644 "$HERE/theme/lookandfeel/contents/logout/Logout.qml"         "$lnf/contents/logout/Logout.qml"

sddm=$share/sddm/themes/arc
for f in Main.qml metadata.desktop theme.conf; do
    put 644 "$HERE/theme/sddm/$f" "$sddm/$f"
done
put 644 "$HERE/shell/qml/ArcIcon.qml"                  "$sddm/ArcIcon.qml"
put 644 "$HERE/shell/qml/assets/arc-wordmark-light.svg" "$sddm/arc-wordmark-light.svg"

put 644 "$HERE/theme/tabbox/metadata.json"        "$share/kwin/tabbox/arc/metadata.json"
put 644 "$HERE/theme/tabbox/contents/ui/main.qml" "$share/kwin/tabbox/arc/contents/ui/main.qml"

# --- Sessione: startarc al posto di plasmashell --------------------------------
put 755 "$HERE/session/startarc"                    usr/bin/startarc
put 644 "$HERE/session/arc.desktop"                 "$share/wayland-sessions/arc.desktop"
put 644 "$HERE/session/arc-shell.service"           usr/lib/systemd/user/arc-shell.service
put 644 "$HERE/session/plasmashell-arc.conf"        usr/lib/systemd/user/plasma-plasmashell.service.d/arc.conf
put 644 "$HERE/session/org.arcbase.shell.desktop"   "$share/applications/org.arcbase.shell.desktop"
put 644 "$HERE/session/org.arcbase.launcher.desktop" "$share/applications/org.arcbase.launcher.desktop"
put 644 "$HERE/session/org.arcbase.launcher.desktop" "$share/kglobalaccel/org.arcbase.launcher.desktop"
put 644 "$HERE/session/org.freedesktop.Notifications.service" \
    usr/local/share/dbus-1/services/org.freedesktop.Notifications.service
# Equivale a `systemctl --global enable arc-shell.service`
mkdir -p "$DEST/etc/systemd/user/plasma-workspace.target.wants"
ln -sfn /usr/lib/systemd/user/arc-shell.service \
    "$DEST/etc/systemd/user/plasma-workspace.target.wants/arc-shell.service"

# --- Impostazioni predefinite di sistema (/etc/xdg, letto da KDE) --------------
xdg=etc/xdg
# kdeglobals = impostazioni generali + i gruppi di colori dello schema
mkdir -p "$DEST/$xdg"
{
    cat "$HERE/config/kdeglobals"
    echo
    awk '/^\[/ { keep = ($0 !~ /^\[(General|KDE)\]$/) } keep' "$HERE/theme/ArcUI.colors"
} > "$DEST/$xdg/kdeglobals"
chmod 644 "$DEST/$xdg/kdeglobals"
for f in kwinrc ksplashrc kscreenlockerrc kcminputrc; do
    put 644 "$HERE/config/$f" "$xdg/$f"
done
put 644 "$HERE/config/arc-shell.conf" "$xdg/arcbase/arc-shell.conf"
put 644 "$HERE/config/sddm.conf"      etc/sddm.conf.d/10-arcbase-arc.conf

# --- Impostazioni per utente (/etc/skel e l'utente indicato) -------------------
user_files() { # user_files HOME_RELATIVA_A_DEST [UID:GID]
    local home=$1 owner=${2:-}
    put 644 "$HERE/config/user/kvantum.kvconfig"    "$home/.config/Kvantum/kvantum.kvconfig"
    put 644 "$HERE/config/user/kglobalshortcutsrc"  "$home/.config/kglobalshortcutsrc"
    put 644 "$HERE/config/gtk-settings.ini"         "$home/.config/gtk-3.0/settings.ini"
    put 644 "$HERE/config/gtk-settings.ini"         "$home/.config/gtk-4.0/settings.ini"
    if [[ -n $owner ]]; then
        chown -R "$owner" "$DEST/$home/.config"
    fi
}
user_files etc/skel
if [[ -n $USER_NAME ]]; then
    home=home/$USER_NAME
    if [[ -d $DEST/$home ]]; then
        owner=$(stat -c %u:%g "$DEST/$home" 2>/dev/null || stat -f %u:%g "$DEST/$home")
        user_files "$home" "$owner"
    else
        echo "attenzione: $DEST/$home non esiste, impostazioni utente saltate" >&2
    fi
fi

echo "arc UI installato in ${DEST:-/}"
