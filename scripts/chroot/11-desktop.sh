#!/bin/bash
# =============================================================================
#  Stadio 11 (nel chroot) — ambiente desktop
#
#  1. allinea glibc/gcc-libs ai repository Arch se più recenti (ABI)
#  2. adotta i certificati CA di Arch (p11-kit, update-ca-trust)
#  3. installa i pacchetti comuni (firmware, rete, audio, font, browser)
#     e attiva il repository dei kernel Arcbase con $ARC_KERNEL_PACKAGE
#  4. installa il desktop scelto (config/desktop/$ARC_DESKTOP.list)
#  5. solo ARC_DESKTOP=arc: compila arc-shell e installa i temi di arc-ui/
#  6. abilita display manager e NetworkManager, configura sudo
#  7. crea il layer Debian e vi installa $ARC_DEBIAN_PACKAGES
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

# Repository [arcbase-kernel]: impostazioni in /etc/arcbase/kernel-repo.conf
# (le usa 'arcbase-kernel-mirror enable' senza argomenti), chiave fidata solo se
# ha l'impronta attesa, poi il kernel scelto
kernel_repo() {
    if [[ -z $ARC_KERNEL_REPO_URL || -z $ARC_KERNEL_KEY_FPR ]]; then
        warn "ARC_KERNEL_REPO_URL o ARC_KERNEL_KEY_FPR vuoti: repository dei kernel non configurato"
        return 0
    fi
    mkdir -p /etc/arcbase
    cat > /etc/arcbase/kernel-repo.conf <<EOF
# Arcbase Desktop — repository pubblico dei kernel (arcbase-kernel-mirror enable)
KERNEL_REPO_URL='$ARC_KERNEL_REPO_URL'
KERNEL_KEY_FPR=$ARC_KERNEL_KEY_FPR
EOF
    arcbase-kernel-mirror enable --no-sync
    pac -Sy
    if [[ -n $ARC_KERNEL_PACKAGE ]]; then
        pac -S --needed "$ARC_KERNEL_PACKAGE"
    fi
}

desktop_packages() {
    [[ $ARC_DESKTOP == none ]] && return 0
    local -a pkgs
    mapfile -t pkgs < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$LIST")
    pac -S --needed "${pkgs[@]}"
}

# Rigenera le cache che pacman aggiorna negli hook di fine transazione
# (schemi GLib, icone, font, moduli GTK/GIO, ...): se la transazione è stata
# interrotta durante gli hook, senza questo passo alcune app non partirebbero.
update_caches() {
    local d
    command -v glib-compile-schemas >/dev/null && glib-compile-schemas /usr/share/glib-2.0/schemas
    command -v gio-querymodules >/dev/null && gio-querymodules /usr/lib/gio/modules
    command -v gdk-pixbuf-query-loaders >/dev/null && gdk-pixbuf-query-loaders --update-cache
    command -v gtk-query-immodules-3.0 >/dev/null && gtk-query-immodules-3.0 --update-cache
    command -v update-mime-database >/dev/null && update-mime-database /usr/share/mime
    command -v update-desktop-database >/dev/null && update-desktop-database -q
    command -v fc-cache >/dev/null && fc-cache -s
    command -v dconf >/dev/null && dconf update
    if command -v gtk-update-icon-cache >/dev/null; then
        for d in /usr/share/icons/*/; do
            [[ -f $d/index.theme ]] && gtk-update-icon-cache -q -t -f "$d"
        done
    fi
    return 0
}

# Desktop arc: shell Qt/QML al posto di plasmashell (compilata qui, con le
# librerie Qt/KDE appena installate) più temi, sessione e configurazione
arc_ui() {
    [[ $ARC_DESKTOP == arc ]] || return 0
    local build=/tmp/arc-shell-build
    pac -S --needed cmake extra-cmake-modules
    rm -rf "$build"
    cmake -S "$ARCBASE_DIR/arc-ui/shell" -B "$build" \
        -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
    cmake --build "$build"
    cmake --install "$build"
    rm -rf "$build"
    # Modulo "Sfondo" di Impostazioni di sistema
    cmake -S "$ARCBASE_DIR/arc-ui/kcm" -B "$build" \
        -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
    cmake --build "$build"
    cmake --install "$build"
    rm -rf "$build"
    # Decorazione delle finestre (KDecoration3)
    cmake -S "$ARCBASE_DIR/arc-ui/decoration" -B "$build" \
        -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
    cmake --build "$build"
    cmake --install "$build"
    rm -rf "$build"
    "$ARCBASE_DIR/arc-ui/install.sh" --user "$ARC_USER" /
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
step kernel-repo  kernel_repo
step desktop-pkgs desktop_packages
step caches       update_caches
step arc-ui       arc_ui
step desktop-conf configure_desktop
step debian-layer debian_layer
step cleanup      cleanup

msg "Desktop '$ARC_DESKTOP' installato."
msg "Prossimo passo (fuori dal chroot): make image"
