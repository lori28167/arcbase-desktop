#!/bin/bash
# =============================================================================
#  Stadio 12 — immagine disco avviabile (BIOS + UEFI)
#
#  Crea out/arcbase-desktop-<versione>.img con tabella GPT:
#    1. BIOS boot (1 MiB)   2. ESP FAT32 (512 MiB)   3. root ext4 (resto)
#  copia il sistema da $LFS (esclusi sorgenti e file di build), installa GRUB
#  per entrambe le piattaforme con arcbase-bootloader e finalizza il sistema.
#  L'immagine si scrive su una chiavetta con dd oppure si avvia in QEMU.
# =============================================================================
STAGE=image
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_root

for t in losetup sfdisk mkfs.ext4 mkfs.vfat; do
    command -v "$t" >/dev/null || die "$t non trovato sull'host"
done
[[ -x $LFS/usr/bin/arcbase-bootloader ]] || die "sistema incompleto: eseguire prima tutti gli stadi"
compgen -G "$LFS/boot/vmlinuz-*" >/dev/null || die "nessun kernel in $LFS/boot"

"$ARCBASE_DIR/scripts/05-chroot.sh" umount || :

mkdir -p "$ARC_OUT_DIR"
IMG="$ARC_OUT_DIR/arcbase-desktop-$ARC_VERSION-x86_64.img"
MNT=$(mktemp -d /tmp/arcbase-img.XXXXXX)
LOOP=''

cleanup() {
    set +o errexit
    local m
    for m in dev/pts dev proc sys run boot/efi ''; do
        mountpoint -q "$MNT/$m" && umount "$MNT/$m"
    done
    [[ -n $LOOP ]] && losetup -d "$LOOP"
    rmdir "$MNT" 2>/dev/null
}
trap cleanup EXIT

msg "Creazione di $IMG ($ARC_IMAGE_SIZE)"
rm -f "$IMG"
truncate -s "$ARC_IMAGE_SIZE" "$IMG"
sfdisk --quiet "$IMG" <<EOF
label: gpt
size=1MiB,   type=21686148-6453-6F6E-6F74-746F6E656564, name="bios"
size=512MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="esp"
             type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, name="arcbase"
EOF

LOOP=$(losetup --find --show --partscan "$IMG")
udevadm settle 2>/dev/null || sleep 2
info "dispositivo: $LOOP"
mkfs.vfat -F 32 -n ARCBASE_EFI "${LOOP}p2" >/dev/null
mkfs.ext4 -q -F -L arcbase "${LOOP}p3"

mount "${LOOP}p3" "$MNT"
mkdir -p "$MNT/boot/efi"
mount "${LOOP}p2" "$MNT/boot/efi"

msg "Copia del sistema"
tar -C "$LFS" -cpf - \
    --exclude=./sources --exclude=./arcbase --exclude=./tools \
    --exclude=./lost+found --exclude='./proc/*' --exclude='./sys/*' \
    --exclude='./dev/*' --exclude='./run/*' --exclude='./tmp/*' \
    --xattrs --acls --numeric-owner . \
  | tar -C "$MNT" -xpf - --xattrs --acls --numeric-owner

msg "Finalizzazione"
# DNS tramite systemd-resolved, machine-id generato al primo avvio
ln -sfn /run/systemd/resolve/stub-resolv.conf "$MNT/etc/resolv.conf"
: > "$MNT/etc/machine-id"
mkdir -p "$MNT"/{dev,proc,sys,run,tmp}
chmod 1777 "$MNT/tmp"

mount --bind /dev "$MNT/dev"
mount -t devpts devpts "$MNT/dev/pts"
mount -t proc proc "$MNT/proc"
mount -t sysfs sysfs "$MNT/sys"
mount -t tmpfs tmpfs "$MNT/run"

chroot "$MNT" /usr/bin/env -i PATH=/usr/bin HOME=/root \
    /usr/bin/arcbase-bootloader --disk "$LOOP" --root "${LOOP}p3" --esp "${LOOP}p2" --removable

cleanup
trap - EXIT
LOOP=''

if [[ $ARC_IMAGE_QCOW2 == yes ]] && command -v qemu-img >/dev/null; then
    msg "Conversione in qcow2"
    qemu-img convert -O qcow2 "$IMG" "${IMG%.img}.qcow2"
fi

msg "Immagine pronta: $IMG"
cat <<EOF

  Provala in QEMU (UEFI):
    qemu-system-x86_64 -enable-kvm -m 4G -smp 4 -cpu host \\
        -bios /usr/share/ovmf/OVMF.fd -device virtio-vga-gl -display gtk,gl=on \\
        -drive file=$IMG,format=raw,if=virtio

  Oppure scrivila su una chiavetta USB (ATTENZIONE: cancella il dispositivo):
    dd if=$IMG of=/dev/sdX bs=4M status=progress conv=fsync

  Accesso: utente '$ARC_USER' (password iniziale: vedi config/arcbase.conf) —
  cambiala subito con 'passwd'.
EOF
