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
#  6. con ARC_CALAMARES: compila l'installer grafico Calamares
#  7. con ARC_SSC: compila il plugin PipeWire del codec Bluetooth SSC (Galaxy Buds)
#  8. abilita display manager e NetworkManager, configura sudo
#  9. crea il layer Debian e vi installa $ARC_DEBIAN_PACKAGES
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

# --- Installer grafico: Calamares (https://calamares.io) ------------------------
# Non è nei repository di Arch: si compila dal sorgente di packages.conf (SHA-256
# fissato) con le librerie Qt e KDE appena installate. Qui va solo il programma;
# la configurazione (calamares/) la mette nella ISO live 13-iso.sh, così nel
# sistema installato l'installer non può ripartire da solo.
calamares_enabled() {
    case $ARC_CALAMARES in
        yes)  return 0 ;;
        auto) [[ $ARC_DESKTOP == kde || $ARC_DESKTOP == arc ]] ;;
        *)    return 1 ;;
    esac
}

# Moduli che calamares/settings.conf usa; tutti gli altri non si compilano
# (meno dipendenze: plasmalnf vorrebbe libplasma, interactiveterminal KParts...).
CALAMARES_MODULES=(welcome locale keyboard partition users summary finished mount unpackfs fstab removeuser
                   shellprocess preservefiles umount)
CALAMARES_SKIP_MODULES=(bootloader contextualprocess displaymanager dracut dracutlukscfg dummycpp dummyprocess
    dummypython finishedq fsresizer grubcfg hostinfo hwclock initcpio initcpiocfg initramfs initramfscfg
    interactiveterminal keyboardq license localecfg localeq luksbootkeyfile luksopenswaphookcfg machineid
    mkinitfs netinstall networkcfg notesqml oemid openrcdmcryptcfg packagechooser packagechooserq packages
    plasmalnf plymouthcfg rawfs services-openrc services-systemd summaryq tracking unpackfsc
    usersq welcomeq zfs zfshostid)

# rsync copia il sistema dalla squashfs della live (modulo unpackfs); kpmcore
# partiziona; polkit serve a pkexec (lanciatore della live)
calamares_deps() {
    pac -S --needed cmake extra-cmake-modules qt6-base qt6-declarative qt6-svg qt6-tools qt6-translations \
        kcoreaddons kpmcore yaml-cpp libpwquality libglvnd polkit rsync
}

build_calamares() {
    local m
    # Python di LFS (3.13, condiviso): pybind11 è incluso nel sorgente, niente Boost
    cmake -S . -B build -G Ninja                 \
        -DCMAKE_BUILD_TYPE=Release               \
        -DCMAKE_INSTALL_PREFIX=/usr              \
        -DCMAKE_INSTALL_LIBDIR=lib               \
        -DWITH_QT6=ON -DWITH_QML=ON              \
        -DWITH_PYTHON=ON -DWITH_PYBIND11=ON      \
        -DINSTALL_CONFIG=OFF                     \
        -DINSTALL_POLKIT=OFF                     \
        -DINSTALL_COMPLETION=OFF                 \
        -DBUILD_TESTING=OFF                      \
        -DBUILD_SCHEMA_TESTING=OFF               \
        -DBUILD_CRASH_REPORTING=OFF              \
        -DSKIP_MODULES="${CALAMARES_SKIP_MODULES[*]}" \
        -Wno-dev
    cmake --build build
    cmake --install build
    # Il lanciatore e il criterio polkit sono quelli di calamares/ (solo live)
    rm -f /usr/share/applications/calamares.desktop /usr/share/metainfo/io.calamares.calamares.appdata.xml
    # Un modulo che CMake salta in silenzio (es. partition senza kpmcore) darebbe
    # un installer che parte e poi non sa partizionare: meglio fermarsi qui
    [[ -x /usr/bin/calamares ]] || die "calamares non è stato installato"
    for m in "${CALAMARES_MODULES[@]}"; do
        [[ -e /usr/lib/calamares/modules/$m/module.desc ]] \
            || die "modulo $m non compilato: controllare l'output di CMake (dipendenza mancante?)"
    done
}

# --- Codec Bluetooth SSC (Galaxy Buds) ------------------------------------------
# Plugin PipeWire (sorgente di packages.conf, SHA-256 fissato). Prende lo slot
# "aptx" di pipewire-audio: lo compila e lo installa `arcbase-ssc build-here`
# (lo stesso passo di `arcbase-ssc rebuild`), poi l'hook 95-arcbase-ssc lo tiene
# al suo posto a ogni aggiornamento di pipewire-audio.
ssc_enabled() {
    case $ARC_SSC in
        yes)  return 0 ;;
        auto) pacman -Q pipewire-audio >/dev/null 2>&1 ;;
        *)    return 1 ;;
    esac
}

# pipewire-audio porta i file di sviluppo di libspa, bluez-libs gli header Bluetooth
ssc_deps() {
    pac -S --needed pipewire-audio bluez-libs
}

build_ssc() {
    local conf=/usr/share/arcbase/ssc.conf plugin=libspa-codec-bluez5-aptx.so
    mkdir -p "${conf%/*}"
    # da qui `arcbase-ssc rebuild` ricompila lo stesso sorgente dopo un aggiornamento di PipeWire
    cat > "$conf" <<CONF
# Arcbase Desktop — sorgente del plugin SSC (arcbase-ssc rebuild), da config/packages.conf
SSC_URL='$(pkg_url ssc)'
SSC_SHA256='${PKG_SHA256[ssc]}'
CONF
    arcbase-ssc build-here
    # lo slot aptx di Arch passa al plugin SSC (lo stesso fa l'hook a ogni aggiornamento)
    /usr/share/libalpm/scripts/arcbase-ssc-activate
    cmp -s "/usr/lib/ssc-codec/$plugin" "/usr/lib/spa-0.2/bluez5/$plugin" \
        || die "il plugin SSC non ha preso lo slot aptx di PipeWire"
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
if calamares_enabled; then
    step calamares-deps calamares_deps
    build calamares
fi
if ssc_enabled; then
    step ssc-deps ssc_deps
    build ssc
fi
step desktop-conf configure_desktop
step debian-layer debian_layer
step cleanup      cleanup

msg "Desktop '$ARC_DESKTOP' installato."
msg "Prossimo passo (fuori dal chroot): make image"
