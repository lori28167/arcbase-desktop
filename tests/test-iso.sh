#!/bin/bash
# =============================================================================
#  Test della ISO live e di Calamares senza compilare il sistema:
#  - arcbase-mkinitramfs-live costruisce davvero un initramfs (con i binari
#    dell'host) e se ne verifica il contenuto;
#  - coerenza tra initramfs, GRUB e Calamares (etichetta, percorso squashfs);
#  - configurazione di Calamares: YAML valido, moduli e istanze esistenti,
#    branding completo, sessione live completa.
# =============================================================================
set -o nounset -o pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0 fail=0 skip=0
ok()   { pass=$((pass + 1)); printf '  \e[32m✔\e[0m %s\n' "$1"; }
ko()   { fail=$((fail + 1)); printf '  \e[31m✘\e[0m %s\n' "$1"; }
sk()   { skip=$((skip + 1)); printf '  \e[33m-\e[0m %s (saltato: %s)\n' "$1" "$2"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else ko "$d"; fi; }
has()   { grep -qF -- "$2" "$1" 2>/dev/null; }

CAL=$REPO/config/calamares
LIVE=$REPO/config/live
INIT=$REPO/rootfs/usr/lib/arcbase/live-init
STAGE12=$REPO/scripts/chroot/12-live-iso.sh

echo "initramfs live"
check "init: sintassi bash valida"          bash -n "$INIT"
if command -v cpio >/dev/null && command -v switch_root >/dev/null; then
    ARC_LIVE_INIT=$INIT "$REPO/rootfs/usr/bin/arcbase-mkinitramfs-live" "$T/initramfs.img" >/dev/null
    check "initramfs creato"                test -s "$T/initramfs.img"
    gzip -dc "$T/initramfs.img" | cpio -t --quiet 2>/dev/null | sort > "$T/list"
    for f in init usr/bin/bash usr/bin/mount usr/bin/switch_root usr/bin/blkid usr/bin/sleep; do
        check "contiene $f"                 grep -qx "$f" "$T/list"
    done
    check "contiene l'interprete ELF (ld-linux)" grep -q '^usr/lib/ld-linux' "$T/list"
    check "contiene libc"                   grep -q '^usr/lib/libc\.so' "$T/list"
    check "/bin -> usr/bin"                 grep -qx 'bin' "$T/list"
    # Ogni libreria richiesta dai binari è presente
    mkdir "$T/root" && (cd "$T/root" && gzip -dc "$T/initramfs.img" | cpio -id --quiet 2>/dev/null)
    missing=''
    for b in "$T"/root/usr/bin/*; do
        while read -r lib; do
            [[ -e $T/root/usr/lib/${lib##*/} ]] || missing+=" ${lib##*/}"
        done < <(ldd "$b" 2>/dev/null | awk '/=> \// { print $3 }')
    done
    check "tutte le librerie dei binari incluse${missing:+ (mancano:$missing)}" test -z "$missing"
else
    sk "costruzione dell'initramfs" "cpio o switch_root assenti sull'host"
fi

echo "coerenza ISO / initramfs / Calamares"
label=$(sed -n 's/^LABEL=//p' "$STAGE12")
check "etichetta ISO = default dell'init"   grep -q "label=$label " "$INIT"
check "percorso squashfs dell'init"         has "$INIT" "sfs=/run/arcbase/medium/arcbase/rootfs.sfs"
check "Calamares copia la stessa squashfs"  has "$CAL/modules/unpackfs.conf" '"/run/arcbase/medium/arcbase/rootfs.sfs"'
check "la ISO crea arcbase/rootfs.sfs"      has "$STAGE12" '"$ISO_DIR/arcbase/rootfs.sfs"'
check "la ISO contiene la sessione live"    has "$STAGE12" '"$ISO_DIR/arcbase/live"'
check "l'init copia la sessione live"       has "$INIT" "/run/arcbase/medium/arcbase/live/."
check "kernel: driver live built-in"        bash -c 'for o in SQUASHFS OVERLAY_FS ISO9660_FS BLK_DEV_LOOP BLK_DEV_SR BLK_DEV_INITRD RD_GZIP; do grep -qx "CONFIG_$o=y" "$0" || exit 1; done' "$REPO/config/kernel/arcbase.config"

echo "configurazione di Calamares"
if python3 -c 'import yaml' 2>/dev/null; then
    check "YAML valido (settings + moduli + branding)" python3 - "$CAL" <<'PY'
import sys, yaml, glob, os
d = sys.argv[1]
files = [os.path.join(d, "settings.conf")] + glob.glob(os.path.join(d, "modules", "*.conf")) \
        + [os.path.join(d, "branding", "arcbase", "branding.desc.in")]
for f in files:
    yaml.safe_load(open(f))
PY
    python3 - "$CAL" > "$T/cal.txt" <<'PY'
import sys, yaml, os
d = sys.argv[1]
s = yaml.safe_load(open(os.path.join(d, "settings.conf")))
inst = {i["id"]: i for i in s.get("instances", [])}
for step in s["sequence"]:
    for kind, mods in step.items():
        for m in mods:
            print(kind, m)
for i in inst.values():
    print("instance", i["module"], i["config"])
b = yaml.safe_load(open(os.path.join(d, "branding", "arcbase", "branding.desc.in")))
for k, v in b["images"].items():
    print("image", v)
print("slideshow", b["slideshow"])
print("brand", s["branding"])
PY
    check "branding = arcbase"              grep -qx 'brand arcbase' "$T/cal.txt"
    cp "$T/cal.txt" "$T/cal.in"
    while read -r kind a b; do
        case $kind in
            instance) check "istanza $a: $b esiste"   test -f "$CAL/modules/$b" ;;
            image|slideshow) check "branding: $a esiste" test -f "$CAL/branding/arcbase/$a" ;;
            exec)
                m=${a%@*}
                case $m in
                    shellprocess) id=${a#*@}; check "istanza @$id dichiarata" grep -q "^instance shellprocess shellprocess-$id.conf" "$T/cal.txt" ;;
                esac ;;
        esac
    done < "$T/cal.in"
    check "partizione EFI in /boot/efi"     has "$CAL/modules/partition.conf" 'mountPoint: "/boot/efi"'
    check "niente btrfs/LUKS (nessun initramfs)" bash -c '! grep -q btrfs "$0" && grep -q "enableLuksAutomatedPartitioning: false" "$0"' "$CAL/modules/partition.conf"
    check "post-installazione nel sistema installato" has "$CAL/modules/shellprocess-post.conf" "arcbase-postinstall post"
else
    sk "validazione YAML di Calamares" "python3-yaml non installato"
fi
check "show.qml presente"                   test -s "$CAL/branding/arcbase/show.qml"
check "PKGBUILD con versione da packages.conf" grep -q '^pkgver=@VERSION@' "$CAL/PKGBUILD.in"
check "calamares in packages.conf"          grep -q '^calamares ' "$REPO/config/packages.conf"

echo "sessione live"
check "servizio live abilitato"             test -L "$LIVE/etc/systemd/system/multi-user.target.wants/arcbase-live-setup.service"
check "link del servizio valido"            test -f "$LIVE/etc/systemd/system/multi-user.target.wants/arcbase-live-setup.service"
check "eseguito prima del display manager"  has "$LIVE/etc/systemd/system/arcbase-live-setup.service" "Before=display-manager.service"
check "launcher dell'installer"             has "$LIVE/usr/share/applications/arcbase-installer.desktop" "Exec=/usr/bin/arcbase-installer"
check "script della sessione eseguibili"    test -x "$LIVE/usr/bin/arcbase-live-setup" -a -x "$LIVE/usr/bin/arcbase-installer"
check "autologin per sddm, gdm e lightdm"   bash -c 'grep -q sddm.conf.d "$0" && grep -q gdm/custom.conf "$0" && grep -q lightdm.conf.d "$0"' "$LIVE/usr/bin/arcbase-live-setup"

echo
echo "Risultato: $pass superati, $fail falliti, $skip saltati"
(( fail == 0 ))
