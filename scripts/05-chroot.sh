#!/bin/bash
# =============================================================================
#  Stadio 05 — gestione del chroot (LFS cap. 7.2–7.4)
#
#  Uso:
#    05-chroot.sh run <script>   esegue scripts/chroot/<script> dentro $LFS
#    05-chroot.sh enter          shell interattiva nel chroot
#    05-chroot.sh merge-usr      unifica /usr/sbin in /usr/bin e /lib64 -> usr/lib
#                                (layout compatibile con i pacchetti Arch)
#    05-chroot.sh umount         smonta i file system virtuali
# =============================================================================
STAGE=chroot
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_root

[[ -n $LFS && -d $LFS/usr ]] || die "$LFS non contiene un sistema LFS (eseguire prima gli stadi 01-04)"

change_owner() {
    is_done chroot-owner && return 0
    msg "Proprietà dei file di \$LFS a root (LFS 7.2)"
    chown --from lfs -R root:root "$LFS"/{usr,var,etc,tools}
    chown --from lfs -h root:root "$LFS"/{bin,lib,sbin}
    [[ -L $LFS/lib64 ]] || chown --from lfs -R root:root "$LFS/lib64"
    mark_done chroot-owner
}

# Con ARC_ALLOW_UNMOUNTED=1 $LFS è una semplice directory: nel chroot "/" non
# sarebbe un punto di montaggio e pacman ("CheckSpace") rifiuterebbe ogni
# installazione. Come arch-chroot, si monta $LFS su se stesso (prima degli altri
# mount, che altrimenti verrebbero nascosti) e lo si ricorda in /run.
SELFBIND_MARK="/run/arcbase-selfbind-$(printf '%s' "$LFS" | tr / _)"

mount_vkfs() {
    if ! mountpoint -q "$LFS"; then
        mount -v --bind "$LFS" "$LFS"
        touch "$SELFBIND_MARK"
    fi
    mkdir -pv "$LFS"/{dev,proc,sys,run}
    mountpoint -q "$LFS/dev"     || mount -v --bind /dev "$LFS/dev"
    mountpoint -q "$LFS/dev/pts" || mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
    mountpoint -q "$LFS/proc"    || mount -vt proc proc "$LFS/proc"
    mountpoint -q "$LFS/sys"     || mount -vt sysfs sysfs "$LFS/sys"
    mountpoint -q "$LFS/run"     || mount -vt tmpfs tmpfs "$LFS/run"
    if [[ -h $LFS/dev/shm ]]; then
        install -v -d -m 1777 "$LFS$(realpath /dev/shm)"
    else
        mountpoint -q "$LFS/dev/shm" || mount -vt tmpfs -o nosuid,nodev tmpfs "$LFS/dev/shm"
    fi
    # Rete nel chroot (servirà a pacman e debootstrap). Il link a
    # systemd-resolved viene creato solo nell'immagine finale.
    rm -f "$LFS/etc/resolv.conf"
    cp -L /etc/resolv.conf "$LFS/etc/resolv.conf" 2>/dev/null || :
}

umount_vkfs() {
    local m
    for m in dev/shm dev/pts dev run proc sys; do
        if mountpoint -q "$LFS/$m"; then
            umount "$LFS/$m" 2>/dev/null || umount -l "$LFS/$m"
        fi
    done
    if [[ -e $SELFBIND_MARK ]]; then
        umount "$LFS" 2>/dev/null || umount -l "$LFS"
        rm -f "$SELFBIND_MARK"
    fi
}

chroot_exec() {
    local -a cfg
    mapfile -t cfg < <(config_env)
    chroot "$LFS" /usr/bin/env -i "${cfg[@]}" \
        HOME=/root                         \
        TERM="${TERM:-xterm}"              \
        PS1='(arcbase chroot) \u:\w\$ '    \
        PATH=/usr/bin:/usr/sbin            \
        MAKEFLAGS="$MAKEFLAGS"             \
        TESTSUITEFLAGS="$MAKEFLAGS"        \
        LFS=""                             \
        LFS_TESTS="$LFS_TESTS"             \
        LFS_VERBOSE="$LFS_VERBOSE"         \
        ARCBASE_IN_CHROOT=1                \
        "$@"
}

merge_usr() {
    local f name
    if [[ ! -L $LFS/usr/sbin ]]; then
        msg "Unificazione di /usr/sbin in /usr/bin"
        for f in "$LFS"/usr/sbin/* ; do
            [[ -e $f || -L $f ]] || continue
            name=${f##*/}
            if [[ -e $LFS/usr/bin/$name || -L $LFS/usr/bin/$name ]]; then
                warn "/usr/sbin/$name esiste anche in /usr/bin: mantengo /usr/bin"
                mkdir -p "$LFS/usr/share/arcbase/sbin-conflicts"
                mv "$f" "$LFS/usr/share/arcbase/sbin-conflicts/"
            else
                mv "$f" "$LFS/usr/bin/"
            fi
        done
        rmdir "$LFS/usr/sbin"
        ln -sfnv bin "$LFS/usr/sbin"
    fi
    if [[ ! -L $LFS/lib64 ]]; then
        msg "/lib64 -> usr/lib"
        rm -rf "${LFS:?}/lib64"
        ln -sfnv usr/lib "$LFS/lib64"
    fi
    [[ -e $LFS/usr/lib64 ]] || ln -sv lib "$LFS/usr/lib64"
}

case ${1:-} in
    run)
        script=${2:?specificare lo script da eseguire}
        [[ -f $ARCBASE_DIR/scripts/chroot/$script ]] || die "script inesistente: scripts/chroot/$script"
        sync_tree
        change_owner
        trap umount_vkfs EXIT
        mount_vkfs
        chroot_exec /bin/bash --noprofile --norc "/arcbase/scripts/chroot/$script"
        ;;
    enter)
        sync_tree
        change_owner
        trap umount_vkfs EXIT
        mount_vkfs
        chroot_exec /bin/bash --login
        ;;
    merge-usr)
        merge_usr
        ;;
    umount)
        umount_vkfs
        ;;
    *)
        die "uso: $0 run <script> | enter | merge-usr | umount"
        ;;
esac
