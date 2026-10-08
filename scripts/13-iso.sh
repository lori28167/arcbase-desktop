#!/bin/bash
# =============================================================================
#  Stadio 13 — ISO di installazione (sessione live + Calamares)
#
#  Esegue scripts/chroot/12-live-iso.sh nel chroot e sposta la ISO in
#  $ARC_OUT_DIR. Richiede gli stadi fino a "desktop" completati.
# =============================================================================
STAGE="iso-host"
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_root

[[ -x $LFS/usr/bin/pacman ]] || die "sistema incompleto: eseguire prima gli stadi fino a 'make desktop'"
compgen -G "$LFS/boot/vmlinuz-*" >/dev/null || die "nessun kernel in $LFS/boot (make kernel)"

"$ARCBASE_DIR/scripts/05-chroot.sh" run 12-live-iso.sh

iso="$LFS/arcbase-iso/arcbase-desktop-$ARC_VERSION-x86_64.iso"
[[ -f $iso ]] || die "ISO non generata"
mkdir -p "$ARC_OUT_DIR"
mv -f "$iso" "$ARC_OUT_DIR/"
iso="$ARC_OUT_DIR/${iso##*/}"
(cd "$ARC_OUT_DIR" && sha256sum "${iso##*/}" > "${iso##*/}.sha256")
rm -rf "$LFS/arcbase-iso"

msg "ISO pronta: $iso ($(du -h "$iso" | cut -f1))"
cat <<EOF

  Proxmox: carica la ISO in uno storage "ISO image" e crea una VM con
    - BIOS: SeaBIOS oppure OVMF (UEFI, con disco EFI) — entrambi supportati
    - Macchina: q35 · CPU: host · RAM: 4 GB o più · disco: 32 GB o più (VirtIO SCSI)
    - Display: VirtIO-GPU oppure Standard VGA
  All'avvio si apre la sessione live: "Installa Arcbase Desktop" è sul desktop.

  Chiavetta USB (cancella /dev/sdX!):
    dd if=$iso of=/dev/sdX bs=4M status=progress conv=fsync
EOF
