#!/bin/bash
# =============================================================================
#  Stadio 12 (nel chroot) — ISO live con installer Calamares
#
#  1. strumenti per la ISO (cpio, squashfs-tools, xorriso, mtools) da Arch
#  2. Calamares compilato da sorgente come pacchetto pacman (makepkg)
#  3. configurazione e branding di Calamares per Arcbase
#  4. squashfs del sistema, initramfs live, GRUB BIOS+UEFI -> ISO ibrida
#
#  La ISO avvia una sessione live (utente "live", login automatico) da cui si
#  lancia "Installa Arcbase Desktop". Calamares copia sul disco la squashfs,
#  cioè il sistema pulito, poi esegue arcbase-postinstall (GRUB, pulizia).
# =============================================================================
STAGE=iso
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
in_chroot || die "questo script va eseguito nel chroot (make iso)"

WORK=/arcbase-iso
ISO_DIR=$WORK/iso
LABEL=ARCBASE_LIVE
ISO_NAME="arcbase-desktop-$ARC_VERSION-x86_64.iso"
CAL_DIR="$ARCBASE_DIR/config/calamares"

iso_tools() {
    pacman -S --needed --noconfirm cpio squashfs-tools libisoburn mtools dosfstools \
        efibootmgr rsync
}

# Dipendenze lette dal PKGBUILD (depends + makedepends)
# shellcheck disable=SC2034,SC2154
calamares_deps() {
    (
        pkgver=0
        # shellcheck source=/dev/null
        source "$CAL_DIR/PKGBUILD.in"
        printf '%s\n' "${depends[@]}" "${makedepends[@]}"
    )
}

calamares_pkg() {
    local work=/var/tmp/arcbase-calamares
    local -a deps missing
    mapfile -t deps < <(calamares_deps)
    # Solo le dipendenze non ancora soddisfatte: quelle fornite dal base LFS
    # (python, icu...) non vanno installate da Arch, andrebbero in conflitto
    mapfile -t missing < <(pacman -T "${deps[@]}" || :)
    if (( ${#missing[@]} )); then
        pacman -S --needed --noconfirm --asdeps "${missing[@]}"
    fi

    rm -rf "$work"
    mkdir -p "$work"
    sed "s/@VERSION@/$(pkg_ver calamares)/" "$CAL_DIR/PKGBUILD.in" > "$work/PKGBUILD"
    cp "$(pkg_file calamares)" "$work/"
    chown -R nobody: "$work"
    # makepkg non gira come root
    (cd "$work" && runuser -u nobody -- env HOME="$work" BUILDDIR="$work/build" \
        PKGDEST="$work" SRCDEST="$work" makepkg -f --nodeps --noconfirm)
    pacman -U --noconfirm "$work"/calamares-*.pkg.tar.*
    # Gli strumenti di compilazione non servono nel sistema finale
    pacman -Rns --noconfirm cmake extra-cmake-modules qt6-tools || :
    rm -rf "$work"
}

calamares_config() {
    install -dm755 /etc/calamares/modules /usr/share/calamares/branding/arcbase
    install -m644 "$CAL_DIR/settings.conf" /etc/calamares/settings.conf
    install -m644 "$CAL_DIR"/modules/*.conf /etc/calamares/modules/
    install -m644 "$CAL_DIR"/branding/arcbase/{logo.svg,welcome.svg,show.qml} \
        /usr/share/calamares/branding/arcbase/
    sed -e "s|@NAME@|$ARC_NAME|g" -e "s|@VERSION@|$ARC_VERSION|g" -e "s|@URL@|$ARC_HOME_URL|g" \
        "$CAL_DIR/branding/arcbase/branding.desc.in" > /usr/share/calamares/branding/arcbase/branding.desc
    # Il modulo locale legge l'elenco delle lingue da /etc/locale.gen
    if [[ ! -f /etc/locale.gen && -f /usr/share/i18n/SUPPORTED ]]; then
        sed 's/^/#/' /usr/share/i18n/SUPPORTED > /etc/locale.gen
    fi
    # Utente di build da rimuovere durante l'installazione (arcbase-postinstall pre)
    mkdir -p /etc/arcbase
    [[ -f /etc/arcbase/build-user ]] || echo "$ARC_USER" > /etc/arcbase/build-user
}

make_squashfs() {
    msg "squashfs del sistema (può richiedere 15-40 minuti)"
    rm -rf "$WORK"
    mkdir -p "$ISO_DIR/arcbase" "$ISO_DIR/boot/grub"
    rm -rf /var/cache/pacman/pkg/*

    # Stato "da installare": machine-id generato al primo avvio, DNS via resolved
    local resolv_bak=/arcbase-resolv.conf
    cp -a /etc/resolv.conf "$resolv_bak"
    ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    : > /etc/machine-id

    mksquashfs / "$ISO_DIR/arcbase/rootfs.sfs" -noappend -no-progress \
        -comp zstd -Xcompression-level 15 -b 1M -wildcards \
        -e proc/'*' sys/'*' dev/'*' run/'*' tmp/'*' var/tmp/'*' \
           sources arcbase arcbase-iso arcbase-resolv.conf tools lost+found \
           'var/cache/pacman/pkg/*' || { rm -f /etc/resolv.conf; mv "$resolv_bak" /etc/resolv.conf; die "mksquashfs fallito"; }

    rm -f /etc/resolv.conf
    mv "$resolv_bak" /etc/resolv.conf
}

make_boot() {
    local kernel
    kernel=$(find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' | sort -V | tail -n1)
    [[ -n $kernel ]] || die "nessun kernel in /boot (eseguire make kernel)"
    cp "/boot/$kernel" "$ISO_DIR/boot/vmlinuz"
    arcbase-mkinitramfs-live "$ISO_DIR/boot/initramfs.img"

    # Configurazione della sessione live, copiata nel tmpfs dall'initramfs
    cp -a "$ARCBASE_DIR/config/live" "$ISO_DIR/arcbase/live"

    cat > "$ISO_DIR/boot/grub/grub.cfg" <<EOF
# Arcbase Desktop — menu della ISO live
set default=0
set timeout=10
insmod all_video
insmod gfxterm
terminal_output gfxterm
search --no-floppy --set=root --label $LABEL

menuentry "$ARC_NAME $ARC_VERSION — sessione live e installazione" {
    linux /boot/vmlinuz arcbase.label=$LABEL quiet
    initrd /boot/initramfs.img
}
menuentry "$ARC_NAME $ARC_VERSION — grafica di base (nomodeset)" {
    linux /boot/vmlinuz arcbase.label=$LABEL nomodeset
    initrd /boot/initramfs.img
}
menuentry "$ARC_NAME $ARC_VERSION — shell di emergenza nell'initramfs" {
    linux /boot/vmlinuz arcbase.label=$LABEL arcbase.shell
    initrd /boot/initramfs.img
}
if [ "\$grub_platform" = "efi" ]; then
    menuentry "Impostazioni firmware UEFI" { fwsetup }
fi
EOF
}

make_iso() {
    msg "ISO ibrida BIOS + UEFI"
    grub-mkrescue -o "$WORK/$ISO_NAME" "$ISO_DIR" -- -volid "$LABEL"
    info "$(du -h "$WORK/$ISO_NAME" | cut -f1) — $WORK/$ISO_NAME"
}

step iso-tools         iso_tools
step calamares         calamares_pkg
step calamares-config  calamares_config
# La ISO si rigenera a ogni esecuzione (riflette lo stato attuale del sistema)
[[ ${ARCBASE_DRY_RUN:-0} == 1 ]] && exit 0
make_squashfs
make_boot
make_iso
