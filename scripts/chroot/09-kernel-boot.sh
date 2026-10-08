#!/bin/bash
# =============================================================================
#  Stadio 09 (nel chroot) — kernel Linux e GRUB per UEFI (LFS cap. 10 + BLFS)
#
#  Il kernel parte da `make defconfig` e vi viene unito config/kernel/
#  arcbase.config. La configurazione del bootloader (fstab, grub.cfg,
#  grub-install) dipende dal disco: la esegue arcbase-bootloader, chiamato
#  dallo stadio 12 (immagine) o a mano per un'installazione su partizione.
# =============================================================================
STAGE=ch10
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
in_chroot || die "questo script va eseguito nel chroot (make kernel)"

KVER=$(pkg_ver linux)

build_linux() {
    make mrproper
    make defconfig
    scripts/kconfig/merge_config.sh -m .config "$ARCBASE_DIR/config/kernel/arcbase.config"
    make olddefconfig
    # Controllo: le opzioni essenziali devono essere attive
    local opt
    for opt in DEVTMPFS CGROUPS USER_NS EXT4_FS EFI_STUB BLK_DEV_NVME SATA_AHCI \
               VIRTIO_BLK USB_STORAGE USB_UAS USB_XHCI_HCD MMC_BLOCK DRM \
               BLK_DEV_INITRD RD_GZIP BLK_DEV_LOOP BLK_DEV_SR ISO9660_FS SQUASHFS \
               SQUASHFS_ZSTD OVERLAY_FS; do
        grep -q "^CONFIG_$opt=y" .config || { echo "CONFIG_$opt non attiva"; exit 1; }
    done
    make
    make modules_install
    cp -v arch/x86/boot/bzImage "/boot/vmlinuz-$KVER-arcbase"
    cp -v System.map "/boot/System.map-$KVER"
    cp -v .config "/boot/config-$KVER"
    install -v -m755 -d /etc/modprobe.d
    cat > /etc/modprobe.d/usb.conf <<"EOF"
# Arcbase Desktop — /etc/modprobe.d/usb.conf (LFS 10.3)
install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true
EOF
}

build_grub_efi() {
    # BLFS "GRUB-2.12 for EFI": installa /usr/lib/grub/x86_64-efi accanto a i386-pc
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    echo depends bli part_gpt > grub-core/extra_deps.lst
    ./configure --prefix=/usr        \
                --sysconfdir=/etc    \
                --disable-efiemu     \
                --with-platform=efi  \
                --target=x86_64      \
                --disable-werror
    make
    make install
    mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions 2>/dev/null || :
}

build linux
build grub efi

msg "Kernel $KVER e GRUB (BIOS+UEFI) installati."
msg "Prossimo passo: make package-managers"
