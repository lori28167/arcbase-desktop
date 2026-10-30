#!/bin/bash
# =============================================================================
#  calamares/install.sh — installa l'installer grafico nella ISO live
#
#  Uso: install.sh [--live-user NOME] [--timezone ZONA] DESTDIR
#    DESTDIR      radice dove installare (la squashfs in preparazione, o una
#                 cartella vuota per i test). Non si accetta "/": l'installer
#                 serve solo nella live e va tolto dal sistema installato.
#    --live-user  utente della sessione live (ARC_USER, default arc): lo toglie
#                 il passo removeuser e la sua home non si copia sul disco
#    --timezone   fuso orario predefinito della pagina "Località" (ARC_TIMEZONE)
#
#  Il programma (Calamares) lo compila lo stadio desktop (scripts/chroot/
#  11-desktop.sh, ARC_CALAMARES); qui si mette tutto il resto: configurazione,
#  branding, i moduli arcbase_*, il lanciatore, l'helper per root e il criterio
#  polkit. Non richiede rete.
# =============================================================================
set -o errexit -o nounset -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
LIVE_USER=arc
TIMEZONE=Europe/Rome
DEST=''

die() { echo "calamares/install.sh: $*" >&2; exit 1; }

while (($#)); do
    case $1 in
        --live-user) LIVE_USER=${2:?--live-user richiede un nome}; shift 2 ;;
        --timezone)  TIMEZONE=${2:?--timezone richiede una zona}; shift 2 ;;
        -h|--help)   sed -n '3,16p' "$0"; exit 0 ;;
        -*)          die "opzione sconosciuta: $1" ;;
        *)           DEST=$1; shift ;;
    esac
done
DEST=${DEST%/}
[[ -n $DEST ]] || die "serve la cartella di destinazione (non /): vedi --help"

# L'utente finisce in un'esclusione di rsync e in userdel: niente di strano
[[ $LIVE_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ && $LIVE_USER != root ]] || die "nome utente della live non valido: $LIVE_USER"

# Fuso orario: Calamares vuole regione e zona, con la regione tra quelle note
REGION=Europe ZONE=Rome
if [[ $TIMEZONE =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)+$ ]]; then
    case ${TIMEZONE%%/*} in
        Africa|America|Antarctica|Arctic|Asia|Atlantic|Australia|Europe|Indian|Pacific)
            REGION=${TIMEZONE%%/*} ZONE=${TIMEZONE#*/} ;;
        *) echo "calamares/install.sh: regione di $TIMEZONE sconosciuta a Calamares: uso $REGION/$ZONE" >&2 ;;
    esac
else
    echo "calamares/install.sh: fuso orario '$TIMEZONE' non utilizzabile: uso $REGION/$ZONE" >&2
fi

put() {  # put MODE SORGENTE DESTINAZIONE (relativa a DEST)
    mkdir -p "$(dirname "$DEST/$3")"
    install -m "$1" "$2" "$DEST/$3"
}
put_template() {  # come put, sostituendo i segnaposto @LIVE_USER@ @REGION@ @ZONE@
    mkdir -p "$(dirname "$DEST/$3")"
    sed -e "s|@LIVE_USER@|$LIVE_USER|g" -e "s|@REGION@|$REGION|g" -e "s|@ZONE@|$ZONE|g" "$2" > "$DEST/$3"
    chmod "$1" "$DEST/$3"
}

# --- Configurazione ----------------------------------------------------------
put 644 "$HERE/settings.conf" etc/calamares/settings.conf
for f in "$HERE"/modules/*.conf; do
    put_template 644 "$f" "etc/calamares/modules/${f##*/}"
done

# --- Moduli di Calamares scritti per Arcbase (Python) -------------------------
for d in "$HERE"/python/*/; do
    name=$(basename "$d")
    put 644 "$d/module.desc" "usr/lib/calamares/modules/$name/module.desc"
    put 644 "$d/main.py"     "usr/lib/calamares/modules/$name/main.py"
done

# --- Branding: logo e testi dai file del rootfs -------------------------------
b=usr/share/calamares/branding/arcbase
for f in branding.desc show.qml stylesheet.qss; do
    put 644 "$HERE/branding/arcbase/$f" "$b/$f"
done
put 644 "$REPO/rootfs/usr/share/icons/hicolor/scalable/apps/arcbase-logo.svg" "$b/logo.svg"
put 644 "$REPO/rootfs/usr/share/arcbase/branding/arcbase-wordmark.svg"        "$b/welcome.svg"

# --- Avvio: lanciatore, helper per root, criterio polkit ----------------------
put 755 "$HERE/bin/arcbase-install-gui" usr/bin/arcbase-install-gui
put 755 "$HERE/bin/installer-root"      usr/lib/arcbase/installer-root
put 644 "$HERE/polkit/org.arcbase.installer.policy" usr/share/polkit-1/actions/org.arcbase.installer.policy
put 644 "$HERE/arcbase-install.desktop" usr/share/applications/arcbase-install.desktop

# Nessun segnaposto deve restare
if grep -rlE '@(LIVE_USER|REGION|ZONE)@' "$DEST/etc/calamares" 2>/dev/null; then
    die "segnaposto non sostituiti (vedi sopra)"
fi
echo "Calamares: configurazione installata in $DEST (utente live: $LIVE_USER, fuso: $REGION/$ZONE)"
