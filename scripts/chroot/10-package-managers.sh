#!/bin/bash
# =============================================================================
#  Stadio 10 (nel chroot) — i due gestori di pacchetti
#
#  1. Dipendenze di pacman (da BLFS): certificati CA, libgpg-error, libgcrypt,
#     libassuan, libksba, npth, GnuPG, GPGME, libarchive, curl, wget, fakeroot
#  2. pacman (compilato da sorgente) + portachiavi Arch + /etc/pacman.conf
#  3. Registrazione del base LFS come pacchetto virtuale "arcbase-base"
#  4. bubblewrap, debootstrap e portachiavi Debian per il layer apt/dpkg
#  5. Configurazione di arc (/etc/arcbase/arc.conf)
# =============================================================================
STAGE=pkgmgr
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
in_chroot || die "questo script va eseguito nel chroot (make package-managers)"

doc() { printf '/usr/share/doc/%s-%s\n' "$1" "$(pkg_ver "$1")"; }

autotools() {
    ./configure --prefix=/usr --disable-static "$@"
    make
    make install
}

# --- 1. Dipendenze ----------------------------------------------------------------
build_cacert() {
    # Bundle Mozilla temporaneo: verrà sostituito dal pacchetto Arch
    # ca-certificates (p11-kit, update-ca-trust) nello stadio 11.
    install -vDm644 cacert-*.pem /etc/ssl/certs/ca-certificates.crt
    ln -sfv certs/ca-certificates.crt /etc/ssl/cert.pem
}

build_libgpg_error() { autotools; }
build_libgcrypt()    { autotools; }
# libassuan resta alla 3.0.0 come in Arch: dalla 3.0.1 la versione dei simboli
# è LIBASSUAN_2.0 e i binari Arch (es. gpgme 2.x) richiedono LIBASSUAN_1.0.
build_libassuan() {
    autotools
    # Se c'era una versione più recente (es. 3.0.2), ldconfig farebbe puntare
    # libassuan.so.9 al file con numero maggiore: si tiene solo quello installato.
    local lib
    lib=$(readlink /usr/lib/libassuan.so)
    find /usr/lib -maxdepth 1 -name 'libassuan.so.9.*' ! -name "$lib" -delete
    ln -sfn "$lib" /usr/lib/libassuan.so.9
}
build_libksba()      { autotools; }
build_npth()         { autotools; }

build_gnupg() {
    mkdir build && cd build
    ../configure --prefix=/usr           \
                 --localstatedir=/var    \
                 --sysconfdir=/etc       \
                 --docdir="$(doc gnupg)"
    make
    make install
}

build_gpgme() {
    mkdir build && cd build
    # Solo la libreria C (serve a pacman): i binding C++/Qt li forniscono i
    # pacchetti Arch (gpgmepp, qgpgme), che altrimenti troverebbero file in conflitto.
    ../configure --prefix=/usr --disable-static --disable-gpg-test \
                 --disable-languages
    make
    # Si controlla il database e non "pacman -Q": se gpgme o le sue dipendenze
    # sono appena cambiate, pacman stesso potrebbe non avviarsi.
    if compgen -G '/var/lib/pacman/local/gpgme-[0-9]*' >/dev/null; then
        # gpgme già adottato da Arch (2.x, libgpgme.so.45): si installa solo la
        # libreria 1.x usata da pacman, senza toccare i file del pacchetto Arch.
        make DESTDIR="$PWD/dest" install
        cp -av dest/usr/lib/libgpgme.so.11* /usr/lib/
    else
        make install
    fi
}

build_libarchive() { autotools; }

# --enable-versioned-symbols: le librerie Arch (libproxy, ...) si collegano a
# curl_easy_*@CURL_OPENSSL_4; senza i simboli versionati il link fallisce.
# Non si adotta il curl di Arch: richiede OPENSSL_3.5.0, l'OpenSSL di LFS è 3.4.
build_curl() {
    autotools --with-openssl                \
              --enable-versioned-symbols    \
              --without-libpsl              \
              --enable-threaded-resolver    \
              --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt
}

build_wget() {
    ./configure --prefix=/usr --sysconfdir=/etc --with-ssl=openssl
    make
    make install
}

build_fakeroot() {
    [[ -x configure ]] || ./bootstrap
    ./configure --prefix=/usr                  \
                --libdir=/usr/lib/libfakeroot  \
                --disable-static               \
                --with-ipc=sysv
    make
    make install
    install -dm755 /etc/ld.so.conf.d
    echo /usr/lib/libfakeroot > /etc/ld.so.conf.d/fakeroot.conf
    ldconfig
}

# --- 2. pacman ----------------------------------------------------------------------
build_pacman() {
    meson setup build                     \
        --prefix=/usr                     \
        --sysconfdir=/etc                 \
        --localstatedir=/var              \
        --buildtype=release               \
        -D doc=disabled                   \
        -D doxygen=disabled               \
        -D scriptlet-shell=/usr/bin/bash  \
        -D ldconfig=/usr/bin/ldconfig     \
        -D crypto=openssl                 \
        -D gpgme=enabled                  \
        -D curl=enabled                   \
        -D i18n=true
    meson compile -C build
    meson install -C build
    install -dm755 /var/lib/pacman /var/cache/pacman/pkg /etc/pacman.d/hooks
}

configure_pacman() {
    # Utente usato da pacman 7 per scaricare i pacchetti in sandbox
    getent group alpm >/dev/null || groupadd -r alpm
    id alpm >/dev/null 2>&1 || \
        useradd -r -g alpm -d / -s /usr/bin/nologin -c "Arch Linux Package Management" alpm

    local repo
    {
        cat <<EOF
#
# Arcbase Desktop — /etc/pacman.conf
#
# pacman gestisce il sistema host. Il base compilato da sorgente (LFS) è
# registrato come pacchetto virtuale "arcbase-base" (vedi arcbase-mkbase):
# non può essere rimosso e fornisce i pacchetti Arch equivalenti.
# Il software Debian si gestisce con apt nel layer Debian (vedi 'arc').
#
[options]
HoldPkg      = pacman glibc arcbase-base
Architecture = auto
Color
CheckSpace
VerbosePkgLists
ParallelDownloads = 5
DownloadUser = alpm
SigLevel          = Required DatabaseOptional
LocalFileSigLevel = Optional

EOF
        for repo in $ARC_ARCH_REPOS; do
            printf '[%s]\nInclude = /etc/pacman.d/mirrorlist\n\n' "$repo"
        done
        cat <<'EOF'
# Repository locale facoltativo per pacchetti propri (es. da 'arc deb2pkg'):
#[arcbase-local]
#SigLevel = Optional TrustAll
#Server = file:///var/cache/arcbase/repo
EOF
    } > /etc/pacman.conf
    cat > /etc/pacman.d/mirrorlist <<EOF
# Arcbase Desktop — mirror dei repository Arch Linux
Server = $ARC_ARCH_MIRROR
EOF
}

# --- 3. arcbase-base -------------------------------------------------------------
generate_provides() {
    local out=/usr/share/arcbase/base-provides.list name src ver f so
    mkdir -p "${out%/*}"
    {
        echo "# Componenti del sistema base Arcbase compilati da sorgente (LFS $LFS_BOOK_VERSION)"
        echo "# Generato dallo stadio 10: <nome-arch>=<versione> e <soname>=<N>-64"
        while read -r name src; do
            [[ -z ${name:-} || $name == \#* ]] && continue
            if [[ $src == @ARCBASE@ ]]; then ver=$ARC_VERSION; else ver=$(pkg_ver "$src"); fi
            printf '%s=%s\n' "$name" "$ver"
        done < "$ARCBASE_DIR/config/arch-provides.map"
        # Soname delle librerie di sistema, nel formato usato dai pacchetti Arch
        for f in /usr/lib/lib*.so.*; do
            [[ -f $f && ! -L $f ]] || continue
            so=$(readelf -d "$f" 2>/dev/null | sed -n 's/.*Library soname: \[\(.*\)\]/\1/p')
            [[ $so == *.so.* ]] || continue
            printf '%s.so=%s-64\n' "${so%%.so.*}" "${so#*.so.}"
        done | sort -u
    } > "$out"
}

register_base() {
    arcbase-mkbase
}

keyrings() {
    pacman-key --init
    # Il pacchetto archlinux-keyring esegue "pacman-key --populate archlinux"
    pacman -U --noconfirm "$(pkg_file archlinux-keyring)"
    gpgconf --homedir /etc/pacman.d/gnupg --kill all || :
}

sync_repos() {
    [[ -n $ARC_ARCH_REPOS ]] || return 0
    pacman -Sy || echo "ATTENZIONE: impossibile sincronizzare i repository Arch (rete?)"
}

# --- 4. Layer Debian ----------------------------------------------------------------
build_bubblewrap() {
    meson setup build --prefix=/usr --buildtype=release -D man=disabled -D selinux=disabled
    meson compile -C build
    meson install -C build
}

build_debootstrap() {
    make install DESTDIR=/
}

build_debian_archive_keyring() {
    mkdir deb data
    bsdtar -xf debian-archive-keyring_*.deb -C deb
    bsdtar -xf deb/data.tar.* -C data
    install -vdm755 /usr/share/keyrings
    install -vm644 data/usr/share/keyrings/*.gpg /usr/share/keyrings/
}

# --- 5. Configurazione di arc ----------------------------------------------------------
configure_arc() {
    install -dm755 /etc/arcbase /var/lib/arcbase/exports
    cat > /etc/arcbase/arc.conf <<EOF
# Arcbase Desktop — configurazione di 'arc'
# Ordine di risoluzione per 'arc install <nome>': arch | debian
ARC_PREFER=$ARC_PREFER

# Layer Debian
ARC_DEBIAN_ROOT=/var/lib/arcbase/debian
ARC_DEBIAN_SUITE=$ARC_DEBIAN_SUITE
ARC_DEBIAN_MIRROR=$ARC_DEBIAN_MIRROR
ARC_DEBIAN_SECURITY_MIRROR=$ARC_DEBIAN_SECURITY_MIRROR
ARC_DEBIAN_COMPONENTS="$ARC_DEBIAN_COMPONENTS"
ARC_DEBIAN_KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg
ARC_LOCALE=$ARC_LOCALE

# Esporta automaticamente le app Debian installate (menu + PATH)
ARC_AUTO_EXPORT=yes
ARC_EXPORT_PREFIX=/usr/local

# Allineamento delle librerie runtime ai repository Arch: auto | never
ARC_RUNTIME_SYNC=$ARC_RUNTIME_SYNC
ARC_RUNTIME_SYNC_PKGS="$ARC_RUNTIME_SYNC_PKGS"
EOF
    install_overlay
}

for p in cacert libgpg-error libgcrypt libassuan libksba npth gnupg gpgme \
         libarchive curl wget fakeroot pacman; do
    build "$p"
done
step pacman-conf   configure_pacman
step provides      generate_provides
step arcbase-base  register_base
step keyrings      keyrings
for p in bubblewrap debootstrap debian-archive-keyring; do
    build "$p"
done
step arc-conf      configure_arc
step sync-repos    sync_repos

msg "pacman e apt (layer Debian) pronti."
msg "Prossimo passo: make desktop"
