#!/bin/bash
# =============================================================================
#  /init dell'initramfs della ISO live (copiato da scripts/13-iso.sh)
#
#  Il sistema installato non usa initramfs; la ISO sì, perché la root live è
#  composta: squashfs in sola lettura (dal CD/USB) + overlay scrivibile in RAM.
#    1. trova il supporto con l'etichetta arcbase.label= (default ARCBASE_LIVE)
#    2. monta /arcbase/rootfs.sfs dal supporto
#    3. overlay squashfs + tmpfs su /new_root, poi switch_root a systemd
#  Opzioni del kernel: arcbase.label=<etichetta>  arcbase.shell (shell di debug)
# =============================================================================
PATH=/usr/bin
export PATH

label=ARCBASE_LIVE
debug_shell=0
init=/usr/lib/systemd/systemd

rescue() {
    echo "arcbase-live: $*" >&2
    echo "arcbase-live: shell di emergenza (exit per riprovare l'avvio)" >&2
    bash -i </dev/console >/dev/console 2>&1
}

mkdir -p /proc /sys /dev /run /new_root
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run

read -r -a cmdline < /proc/cmdline
for arg in "${cmdline[@]}"; do
    case $arg in
        arcbase.label=*) label=${arg#*=} ;;
        arcbase.shell) debug_shell=1 ;;
        init=*) init=${arg#*=} ;;
    esac
done

LIVE=/run/arcbase-live
mkdir -p "$LIVE"/{medium,sfs,rw}

# Il lettore CD / la chiavetta possono comparire dopo qualche secondo
dev=''
for (( i = 0; i < 60; i++ )); do
    dev=$(blkid -L "$label" 2>/dev/null) && [[ -b $dev ]] && break
    dev=''
    sleep 0.5
done
[[ -n $dev ]] || rescue "nessun supporto con etichetta '$label' trovato"
[[ -n $dev ]] || dev=$(blkid -L "$label")

until mount -o ro "$dev" "$LIVE/medium"; do rescue "impossibile montare $dev"; done
until mount -t squashfs -o ro,loop "$LIVE/medium/arcbase/rootfs.sfs" "$LIVE/sfs"; do
    rescue "impossibile montare arcbase/rootfs.sfs"
done
mount -t tmpfs -o mode=0755 tmpfs "$LIVE/rw"
mkdir -p "$LIVE/rw/upper" "$LIVE/rw/work"
until mount -t overlay overlay \
        -o "lowerdir=$LIVE/sfs,upperdir=$LIVE/rw/upper,workdir=$LIVE/rw/work" /new_root; do
    rescue "impossibile creare l'overlay della root"
done

(( debug_shell )) && rescue "arcbase.shell richiesto: root live pronta in /new_root"

# switch_root sposta /run (con i mount live annidati) dentro la nuova root
exec switch_root /new_root "$init"
