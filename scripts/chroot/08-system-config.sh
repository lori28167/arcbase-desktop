#!/bin/bash
# =============================================================================
#  Stadio 08 (nel chroot) — configurazione del sistema (LFS cap. 9)
#  + identità di Arcbase Desktop, overlay del rootfs, utenti.
# =============================================================================
STAGE=ch9
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
in_chroot || die "questo script va eseguito nel chroot (make config)"

identity() {
    cat > /usr/lib/os-release <<EOF
NAME="$ARC_NAME"
PRETTY_NAME="$ARC_NAME $ARC_VERSION ($ARC_CODENAME)"
ID=$ARC_ID
ID_LIKE="arch debian"
VERSION="$ARC_VERSION ($ARC_CODENAME)"
VERSION_ID=$ARC_VERSION
VERSION_CODENAME=$ARC_CODENAME
BUILD_ID=lfs-$LFS_BOOK_VERSION
ANSI_COLOR="38;2;23;147;209"
HOME_URL="$ARC_HOME_URL"
DOCUMENTATION_URL="$ARC_HOME_URL#readme"
BUG_REPORT_URL="$ARC_HOME_URL/issues"
LOGO=distributor-logo
EOF
    ln -sfv ../usr/lib/os-release /etc/os-release
    cat > /etc/lsb-release <<EOF
DISTRIB_ID="$ARC_NAME"
DISTRIB_RELEASE="$ARC_VERSION"
DISTRIB_CODENAME="$ARC_CODENAME"
DISTRIB_DESCRIPTION="$ARC_NAME $ARC_VERSION"
EOF
    echo "$ARC_VERSION" > /etc/arcbase-release
    # Requisito LFS: /etc/lfs-release
    echo "$LFS_BOOK_VERSION-systemd" > /etc/lfs-release
}

network() {
    echo "$ARC_HOSTNAME" > /etc/hostname
    cat > /etc/hosts <<EOF
# Arcbase Desktop — /etc/hosts
127.0.0.1  localhost
127.0.1.1  $ARC_HOSTNAME
::1        localhost ip6-localhost ip6-loopback
EOF
    # Rete di base con systemd-networkd (il desktop passerà a NetworkManager)
    mkdir -p /etc/systemd/network
    cat > /etc/systemd/network/20-wired.network <<"EOF"
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF
}

locale_console() {
    cat > /etc/locale.conf <<EOF
LANG=$ARC_LOCALE
EOF
    cat > /etc/vconsole.conf <<EOF
KEYMAP=$ARC_KEYMAP
FONT=$ARC_CONSOLE_FONT
EOF
    ln -sfv "/usr/share/zoneinfo/$ARC_TIMEZONE" /etc/localtime
    # Non cancellare lo schermo al login (LFS 9.10)
    mkdir -pv /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/noclear.conf <<"EOF"
[Service]
TTYVTDisallocate=no
EOF
}

overlay() {
    install_overlay
    mkdir -p /var/lib/arcbase /usr/share/arcbase /etc/arcbase
}

users() {
    echo "root:$ARC_ROOT_PASSWORD" | chpasswd
    if ! id "$ARC_USER" >/dev/null 2>&1; then
        useradd -m -c "$ARC_USER_FULLNAME" -G wheel,audio,video,input,render,users "$ARC_USER"
    fi
    echo "$ARC_USER:$ARC_USER_PASSWORD" | chpasswd
    # L'installer Calamares rimuove questo utente dal sistema installato
    echo "$ARC_USER" > /etc/arcbase/build-user
}

services() {
    systemctl enable systemd-networkd systemd-resolved systemd-timesyncd
}

step identity identity
step network  network
step locale   locale_console
step overlay  overlay
step users    users
step services services

msg "Configurazione completata. Prossimo passo: make kernel"
