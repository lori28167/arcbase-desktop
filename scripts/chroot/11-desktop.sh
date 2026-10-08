#!/bin/bash
# =============================================================================
#  Stadio 11 (nel chroot) — ambiente desktop
#
#  1. allinea glibc/gcc-libs ai repository Arch se più recenti (ABI)
#  2. adotta i certificati CA di Arch (p11-kit, update-ca-trust)
#  3. installa i pacchetti comuni (firmware, rete, audio, font, browser)
#  4. installa il desktop scelto (config/desktop/$ARC_DESKTOP.list)
#  5. abilita display manager e NetworkManager, configura sudo
#  6. crea il layer Debian e vi installa $ARC_DEBIAN_PACKAGES
# =============================================================================
STAGE=desktop
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
in_chroot || die "questo script va eseguito nel chroot (make desktop)"

LIST="$ARCBASE_DIR/config/desktop/$ARC_DESKTOP.list"
if [[ $ARC_DESKTOP != none && ! -f $LIST ]]; then
    die "desktop sconosciuto: $ARC_DESKTOP (disponibili: $(find "$ARCBASE_DIR/config/desktop" -name '*.list' -printf '%f ' | sed 's/\.list//g')none)"
fi

pac() { pacman --noconfirm "$@"; }

runtime_sync() {
    pac -Sy
    if [[ $ARC_RUNTIME_SYNC == auto ]]; then
        arcbase-runtime-sync --noconfirm
    fi
}

adopt_ca() {
    pac -S --needed --overwrite '/etc/ssl/*' --overwrite '/etc/ca-certificates/*' \
        ca-certificates ca-certificates-mozilla
}

common_packages() {
    # shellcheck disable=SC2086
    pac -S --needed $ARC_COMMON_PACKAGES
}

desktop_packages() {
    [[ $ARC_DESKTOP == none ]] && return 0
    local -a pkgs
    mapfile -t pkgs < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$LIST")
    pac -S --needed "${pkgs[@]}"
}

configure_desktop() {
    local dm=''
    if [[ -f $LIST ]]; then
        dm=$(sed -n 's/^#[[:space:]]*display-manager:[[:space:]]*//p' "$LIST" | head -n1)
    fi
    systemctl disable systemd-networkd.service systemd-networkd.socket 2>/dev/null || :
    systemctl enable NetworkManager.service
    if [[ -n $dm ]]; then
        systemctl enable "$dm.service"
        systemctl set-default graphical.target
    fi
    # sudo per il gruppo wheel
    install -dm750 /etc/sudoers.d
    echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-arcbase-wheel
    chmod 440 /etc/sudoers.d/10-arcbase-wheel
    # Cartelle utente (Documenti, Scaricati, ...)
    if command -v xdg-user-dirs-update >/dev/null; then
        runuser -u "$ARC_USER" -- env LANG="$ARC_LOCALE" xdg-user-dirs-update || :
    fi
    # Tastiera in X11/Wayland come in console
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$ARC_KEYMAP"
EndSection
EOF
}

debian_layer() {
    [[ $ARC_DEBIAN_INIT_AT_BUILD == yes ]] || return 0
    arc deb init
    if [[ -n $ARC_DEBIAN_PACKAGES ]]; then
        # shellcheck disable=SC2086
        arc install --deb -y $ARC_DEBIAN_PACKAGES
    fi
    apt-get clean || :
}

cleanup() {
    rm -rf /var/cache/pacman/pkg/*
    gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || :
}

step runtime-sync runtime_sync
step ca           adopt_ca
step common       common_packages
step desktop-pkgs desktop_packages
step desktop-conf configure_desktop
step debian-layer debian_layer
step cleanup      cleanup

msg "Desktop '$ARC_DESKTOP' installato."
msg "Prossimo passo (fuori dal chroot): make image"
