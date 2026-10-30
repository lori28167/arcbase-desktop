#!/bin/bash
# =============================================================================
#  Stadio 13 — ISO live ibrida (BIOS + UEFI, CD/DVD e chiavetta USB)
#
#  Crea out/arcbase-desktop-<versione>-x86_64.iso:
#    /arcbase/rootfs.sfs        il sistema di $LFS compresso (squashfs zstd)
#    /boot/vmlinuz              kernel di $LFS
#    /boot/initramfs.img        initramfs minimale (solo live): bash, mount,
#                               blkid, switch_root + rootfs/usr/lib/arcbase/live-init.sh
#    /boot/grub                 GRUB i386-pc (El Torito) e x86_64-efi (ESP)
#  All'avvio la root è un overlay: squashfs in sola lettura + tmpfs in RAM.
#
#  Richiede sull'host: mksquashfs (squashfs-tools), xorriso, mkfs.vfat.
# =============================================================================
STAGE=iso
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_root

for t in mksquashfs xorriso mkfs.vfat; do
    command -v "$t" >/dev/null || die "$t non trovato sull'host (pacchetti: squashfs-tools, libisoburn/xorriso, dosfstools)"
done
[[ -x $LFS/usr/bin/arcbase-bootloader ]] || die "sistema incompleto: eseguire prima tutti gli stadi"
for t in grub-mkimage bsdtar ldd bash mount switch_root blkid; do
    [[ -x $LFS/usr/bin/$t ]] || die "$t mancante in $LFS/usr/bin"
done
[[ -d $LFS/usr/lib/grub/i386-pc && -d $LFS/usr/lib/grub/x86_64-efi ]] \
    || die "GRUB per i386-pc e x86_64-efi mancante in $LFS (make kernel)"

KERNEL=$(find "$LFS/boot" -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' | sort -V | tail -n1)
[[ -n $KERNEL ]] || die "nessun kernel in $LFS/boot"
# config-<versione> per il kernel LFS, config-<versione>-arcbase per i pacchetti
KCONFIG="$LFS/boot/config-${KERNEL#vmlinuz-}"
[[ -f $KCONFIG ]] || KCONFIG="$LFS/boot/config-$(sed -e 's/^vmlinuz-//' -e 's/-arcbase$//' <<<"$KERNEL")"
if [[ -f $KCONFIG ]]; then
    for opt in BLK_DEV_INITRD RD_GZIP BLK_DEV_LOOP BLK_DEV_SR ISO9660_FS SQUASHFS \
               SQUASHFS_ZSTD OVERLAY_FS; do
        grep -q "^CONFIG_$opt=y" "$KCONFIG" \
            || die "il kernel non ha CONFIG_$opt=y: ricompilarlo (rm dello stamp ch10 linux, make kernel)"
    done
else
    warn "$KCONFIG non trovato: impossibile verificare le opzioni del kernel per il live"
fi

"$ARCBASE_DIR/scripts/05-chroot.sh" umount || :

mkdir -p "$ARC_OUT_DIR"
ISO="$ARC_OUT_DIR/arcbase-desktop-$ARC_VERSION-x86_64.iso"
WORK="$ARC_OUT_DIR/iso-work"
TREE="$WORK/iso"
STAGING="$WORK/rootfs"
# I file generati con gli strumenti del sistema LFS (via chroot) passano da qui
CHWORK_REL=/tmp/arcbase-iso
CHWORK="$LFS$CHWORK_REL"
EFIMNT=''

cleanup() {
    set +o errexit
    [[ -n $EFIMNT ]] && mountpoint -q "$EFIMNT" && umount "$EFIMNT"
    "$ARCBASE_DIR/scripts/05-chroot.sh" umount
    rm -rf "$WORK" "$CHWORK"
}
trap cleanup EXIT

# Strumenti del sistema LFS (ldd, bsdtar, grub-mkimage) eseguiti nel chroot
in_lfs() { chroot "$LFS" /usr/bin/env -i PATH=/usr/bin HOME=/root "$@"; }

rm -rf "$WORK" "$CHWORK"
mkdir -p "$TREE"/{arcbase,boot/grub} "$STAGING" "$CHWORK"

# --- 1. root filesystem (squashfs) -------------------------------------------
msg "Copia del sistema per lo squashfs"
tar -C "$LFS" -cpf - \
    --exclude=./sources --exclude=./arcbase --exclude=./tools \
    --exclude=./lost+found --exclude='./proc/*' --exclude='./sys/*' \
    --exclude='./dev/*' --exclude='./run/*' --exclude='./tmp/*' \
    --xattrs --acls --numeric-owner . \
  | tar -C "$STAGING" -xpf - --xattrs --acls --numeric-owner

info "configurazione live"
ln -sfn /run/systemd/resolve/stub-resolv.conf "$STAGING/etc/resolv.conf"
: > "$STAGING/etc/machine-id"
cat > "$STAGING/etc/fstab" <<'EOF'
# Arcbase Desktop — sessione live
# La root è un overlay (squashfs + tmpfs) montato dall'initramfs: niente da montare.
EOF
mkdir -p "$STAGING"/{dev,proc,sys,run,tmp}
chmod 1777 "$STAGING/tmp"

# Installer, solo nella live (nel sistema installato non deve poter ripartire):
# l'interfaccia grafica (Calamares: configurazione, branding, lanciatore) se lo
# stadio desktop l'ha compilato, altrimenti il lanciatore di arcbase-install
# da terminale. In entrambi i casi il lanciatore è arcbase-install.desktop (la
# dock lo mette per primo), che arcbase-install toglie dal sistema installato.
if [[ -x $STAGING/usr/bin/calamares && ${ARC_CALAMARES:-auto} != no ]]; then
    info "installer grafico (Calamares)"
    # unpackfs copia con rsync
    [[ -x $STAGING/usr/bin/rsync ]] || die "rsync mancante in $LFS: serve a Calamares (rilanciare make desktop)"
    "$ARCBASE_DIR/calamares/install.sh" --live-user "$ARC_USER" --timezone "$ARC_TIMEZONE" "$STAGING"
else
    info "installer da terminale (arcbase-install): Calamares non compilato o ARC_CALAMARES=no"
    cat > "$STAGING/usr/share/applications/arcbase-install.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Installa Arcbase Desktop
Name[en]=Install Arcbase Desktop
Comment=Installa il sistema su un disco
Comment[en]=Install the system to a disk
Exec=konsole -e sudo arcbase-install
Icon=system-software-install
Terminal=false
Categories=System;
EOF
fi
home="$STAGING/home/$ARC_USER"
if [[ -d $home ]]; then
    desk=$(sed -n 's/^XDG_DESKTOP_DIR="$HOME\/\(.*\)"/\1/p' "$home/.config/user-dirs.dirs" 2>/dev/null)
    desk="$home/${desk:-Desktop}"
    owner=$(stat -c %u:%g "$home")
    install -d -o "${owner%:*}" -g "${owner#*:}" "$desk"
    install -m755 -o "${owner%:*}" -g "${owner#*:}" \
        "$STAGING/usr/share/applications/arcbase-install.desktop" "$desk/"
fi

msg "Compressione dello squashfs (può richiedere diversi minuti)"
mksquashfs "$STAGING" "$TREE/arcbase/rootfs.sfs" \
    -comp zstd -Xcompression-level 15 -b 1M -noappend -xattrs -no-progress
rm -rf "$STAGING"

mount --bind /dev "$LFS/dev"
mount -t proc proc "$LFS/proc"

# --- 2. kernel e initramfs ----------------------------------------------------
msg "Kernel e initramfs live"
cp "$LFS/boot/$KERNEL" "$TREE/boot/vmlinuz"

IRD="$CHWORK/initramfs"
mkdir -p "$IRD"/{usr/bin,usr/lib,dev,proc,sys,run,new_root}
ln -s usr/bin "$IRD/bin"
ln -s usr/bin "$IRD/sbin"
ln -s usr/lib "$IRD/lib"
ln -s usr/lib "$IRD/lib64"
mknod -m 600 "$IRD/dev/console" c 5 1
mknod -m 666 "$IRD/dev/null" c 1 3
install -m755 "$ARCBASE_DIR/rootfs/usr/lib/arcbase/live-init.sh" "$IRD/init"

declare -A libs=()
for b in bash mount umount switch_root blkid mkdir sleep; do
    cp -L "$LFS/usr/bin/$b" "$IRD/usr/bin/$b"
    # "libfoo.so.1 => /usr/lib/libfoo.so.1 (0x...)" oppure "/lib64/ld-linux-x86-64.so.2 (0x...)"
    while read -r lib; do
        libs[$lib]=1
    done < <(in_lfs ldd "/usr/bin/$b" | grep -oE '/[^ ]+\.so[^ ]*')
done
for lib in "${!libs[@]}"; do
    cp -L "$LFS$lib" "$IRD/usr/lib/${lib##*/}"
done
info "initramfs: ${#libs[@]} librerie"
in_lfs /usr/bin/bash -c "cd $CHWORK_REL/initramfs && bsdtar --format newc --uid 0 --gid 0 -cf - . | gzip -9" \
    > "$TREE/boot/initramfs.img"

# --- 3. GRUB (BIOS El Torito + UEFI) -----------------------------------------
msg "GRUB per BIOS e UEFI"
cat > "$CHWORK/early.cfg" <<EOF
search --no-floppy --set=root --label $ARC_ISO_LABEL
set prefix=(\$root)/boot/grub
EOF
GRUB_MODS="iso9660 part_gpt part_msdos fat search search_label normal configfile linux echo test all_video"
# shellcheck disable=SC2086
in_lfs grub-mkimage -O i386-pc-eltorito -p /boot/grub -c "$CHWORK_REL/early.cfg" \
    -o "$CHWORK_REL/bios.img" biosdisk $GRUB_MODS
# shellcheck disable=SC2086
in_lfs grub-mkimage -O x86_64-efi -p /boot/grub -c "$CHWORK_REL/early.cfg" \
    -o "$CHWORK_REL/BOOTX64.EFI" $GRUB_MODS efi_gop

cp "$CHWORK/bios.img" "$TREE/boot/grub/bios.img"
for p in i386-pc x86_64-efi; do
    mkdir -p "$TREE/boot/grub/$p"
    cp "$LFS/usr/lib/grub/$p"/*.{mod,lst} "$TREE/boot/grub/$p/"
done
mkdir -p "$TREE/EFI/BOOT"
cp "$CHWORK/BOOTX64.EFI" "$TREE/EFI/BOOT/BOOTX64.EFI"

# ESP come immagine FAT (partizione EFI dell'ISO ibrida)
EFIIMG="$WORK/efiboot.img"
mkfs.vfat -C -n ARCBASE_EFI "$EFIIMG" 8192 >/dev/null
EFIMNT=$(mktemp -d /tmp/arcbase-efi.XXXXXX)
mount -o loop "$EFIIMG" "$EFIMNT"
mkdir -p "$EFIMNT/EFI/BOOT"
cp "$CHWORK/BOOTX64.EFI" "$EFIMNT/EFI/BOOT/BOOTX64.EFI"
umount "$EFIMNT"
rmdir "$EFIMNT"
EFIMNT=''

# console=ttyS0 permette di seguire (e testare) l'avvio anche via seriale;
# l'ultima console= (tty0) resta quella principale.
LIVE_CMDLINE="arcbase.label=$ARC_ISO_LABEL console=ttyS0,115200 console=tty0"
cat > "$TREE/boot/grub/grub.cfg" <<EOF
# Arcbase Desktop $ARC_VERSION — ISO live
set default=0
set timeout=5
insmod all_video
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial

menuentry "Arcbase Desktop $ARC_VERSION (live)" {
    linux /boot/vmlinuz $LIVE_CMDLINE quiet
    initrd /boot/initramfs.img
}

menuentry "Arcbase Desktop $ARC_VERSION (live, modalità testo)" {
    linux /boot/vmlinuz $LIVE_CMDLINE systemd.unit=multi-user.target
    initrd /boot/initramfs.img
}

menuentry "Arcbase Desktop $ARC_VERSION (live, shell di debug nell'initramfs)" {
    linux /boot/vmlinuz $LIVE_CMDLINE arcbase.shell
    initrd /boot/initramfs.img
}

if [ "\$grub_platform" = "efi" ]; then
    menuentry "Impostazioni firmware UEFI" {
        fwsetup
    }
fi
EOF

# --- 4. ISO ibrida -------------------------------------------------------------
msg "Creazione di $ISO"
rm -f "$ISO"
xorriso -as mkisofs \
    -iso-level 3 -full-iso9660-filenames -joliet -rational-rock \
    -volid "$ARC_ISO_LABEL" \
    -appid "$ARC_NAME $ARC_VERSION" \
    -partition_offset 16 --mbr-force-bootable \
    --grub2-mbr "$LFS/usr/lib/grub/i386-pc/boot_hybrid.img" \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$EFIIMG" \
    -appended_part_as_gpt \
    -eltorito-boot boot/grub/bios.img -no-emul-boot -boot-load-size 4 \
        -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot -e --interval:appended_partition_2:all:: -no-emul-boot \
    -output "$ISO" "$TREE"

cleanup
trap - EXIT

(cd "$ARC_OUT_DIR" && sha256sum "${ISO##*/}" > "${ISO##*/}.sha256")
msg "ISO pronta: $ISO ($(du -h "$ISO" | cut -f1))"
cat <<EOF

  Test automatico in QEMU (BIOS e UEFI, senza root):
    make iso-test

  Avvio manuale in QEMU:
    qemu-system-x86_64 -enable-kvm -m 4G -smp 4 -cpu host -cdrom $ISO

  Chiavetta USB (ATTENZIONE: cancella il dispositivo):
    dd if=$ISO of=/dev/sdX bs=4M status=progress conv=fsync

  Accesso live: utente '$ARC_USER' (password: vedi config/arcbase.conf).
EOF
