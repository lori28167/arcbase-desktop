#!/bin/bash
# =============================================================================
#  Stadio 07 (nel chroot) — sistema base (LFS cap. 8, variante systemd)
#
#  Differenze rispetto a LFS, necessarie per un desktop e per la convivenza
#  con i pacchetti Arch:
#   * Linux-PAM (da BLFS) compilato prima di shadow e systemd: logind e i
#     display manager (sddm/gdm/lightdm) richiedono pam_systemd;
#   * shadow e systemd compilati con supporto PAM; util-linux con runuser;
#   * systemd con systemd-sysusers abilitato (usato dagli hook ALPM per creare
#     gli utenti di sistema richiesti dai pacchetti Arch);
#   * gmp con --enable-fat e libffi senza -march=native: l'immagine deve
#     funzionare su qualunque CPU x86-64, non solo su quella di build.
# =============================================================================
STAGE=ch8
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
in_chroot || die "questo script va eseguito nel chroot (make base-system)"

GCC_VER=$(pkg_ver gcc)
PERL_MM=$(ver_mm perl)

doc() { printf '/usr/share/doc/%s-%s\n' "$1" "$(pkg_ver "$1")"; }

# pip_install <nome-modulo>: installazione di moduli Python (LFS 8.52+)
pip_install() {
    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
    pip3 install --no-index --no-user --find-links dist "$1"
}

build_man_pages() {
    rm -v man3/crypt*
    make -R GIT=false prefix=/usr install
}

build_iana_etc() {
    cp services protocols /etc
}

build_glibc() {
    patch -Np1 -i "$(pkg_file patch-glibc-fhs)"
    mkdir -v build && cd build
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure --prefix=/usr                   \
                 --disable-werror                \
                 --enable-kernel=5.4             \
                 --enable-stack-protector=strong \
                 --disable-nscd                  \
                 libc_cv_slibdir=/usr/lib
    make
    run_tests make check
    touch /etc/ld.so.conf
    sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
    make install
    sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd

    # Locale: C.UTF-8 + quella di sistema + quelle extra
    local l
    localedef -i C -f UTF-8 C.UTF-8
    for l in $ARC_LOCALE $ARC_EXTRA_LOCALES; do
        localedef -i "${l%%.*}" -f UTF-8 "$l" || echo "locale $l non generata"
    done

    cat > /etc/nsswitch.conf <<"EOF"
# Arcbase Desktop — /etc/nsswitch.conf
passwd: files systemd
group: files systemd
shadow: files systemd

hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
networks: files

protocols: files
services: files
ethers: files
rpc: files
EOF

    # Fusi orari
    tar -xf "$(pkg_file tzdata)"
    local ZONEINFO=/usr/share/zoneinfo tz
    mkdir -pv $ZONEINFO/{posix,right}
    for tz in etcetera southamerica northamerica europe africa antarctica \
              asia australasia backward; do
        zic -L /dev/null   -d $ZONEINFO       "$tz"
        zic -L /dev/null   -d $ZONEINFO/posix "$tz"
        zic -L leapseconds -d $ZONEINFO/right "$tz"
    done
    cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
    zic -d $ZONEINFO -p America/New_York
    ln -sfv "/usr/share/zoneinfo/$ARC_TIMEZONE" /etc/localtime

    cat > /etc/ld.so.conf <<"EOF"
# Arcbase Desktop — /etc/ld.so.conf
/usr/local/lib
/opt/lib
include /etc/ld.so.conf.d/*.conf
EOF
    mkdir -pv /etc/ld.so.conf.d
}

build_zlib() {
    ./configure --prefix=/usr
    make
    make install
    rm -fv /usr/lib/libz.a
}

build_bzip2() {
    patch -Np1 -i "$(pkg_file patch-bzip2-docs)"
    sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
    sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
    make -f Makefile-libbz2_so
    make clean
    make
    make PREFIX=/usr install
    cp -av libbz2.so.* /usr/lib
    ln -sfv "libbz2.so.$(pkg_ver bzip2)" /usr/lib/libbz2.so
    cp -v bzip2-shared /usr/bin/bzip2
    local i
    for i in /usr/bin/{bzcat,bunzip2}; do ln -sfv bzip2 "$i"; done
    rm -fv /usr/lib/libbz2.a
}

build_xz() {
    ./configure --prefix=/usr --disable-static --docdir="$(doc xz)"
    make
    make install
}

build_lz4() {
    make BUILD_STATIC=no PREFIX=/usr
    make BUILD_STATIC=no PREFIX=/usr install
}

build_zstd() {
    make prefix=/usr
    make prefix=/usr install
    rm -v /usr/lib/libzstd.a
}

build_file() {
    ./configure --prefix=/usr
    make
    make install
}

build_readline() {
    sed -i '/MV.*old/d' Makefile.in
    sed -i '/{OLDSUFF}/c:' support/shlib-install
    sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
    ./configure --prefix=/usr --disable-static --with-curses --docdir="$(doc readline)"
    make SHLIB_LIBS="-lncursesw"
    make install
}

build_m4() {
    ./configure --prefix=/usr
    make
    make install
}

build_bc() {
    CC=gcc ./configure --prefix=/usr -G -O3 -r
    make
    make install
}

build_flex() {
    ./configure --prefix=/usr --docdir="$(doc flex)" --disable-static
    make
    make install
    ln -sfv flex   /usr/bin/lex
    ln -sfv flex.1 /usr/share/man/man1/lex.1
}

build_tcl() {
    local SRCDIR d v
    SRCDIR=$(pwd)
    cd unix
    ./configure --prefix=/usr --mandir=/usr/share/man --disable-rpath
    make
    sed -e "s|$SRCDIR/unix|/usr/lib|" -e "s|$SRCDIR|/usr/include|" -i tclConfig.sh
    for d in pkgs/tdbc[0-9]*; do
        v=${d#pkgs/}
        sed -e "s|$SRCDIR/unix/pkgs/$v|/usr/lib/$v|"   \
            -e "s|$SRCDIR/pkgs/$v/generic|/usr/include|" \
            -e "s|$SRCDIR/pkgs/$v/library|/usr/lib/tcl8.6|" \
            -e "s|$SRCDIR/pkgs/$v|/usr/include|"       \
            -i "$d/tdbcConfig.sh"
    done
    for d in pkgs/itcl[0-9]*; do
        v=${d#pkgs/}
        sed -e "s|$SRCDIR/unix/pkgs/$v|/usr/lib/$v|"   \
            -e "s|$SRCDIR/pkgs/$v/generic|/usr/include|" \
            -e "s|$SRCDIR/pkgs/$v|/usr/include|"       \
            -i "$d/itclConfig.sh"
    done
    make install
    chmod -v u+w /usr/lib/libtcl8.6.so
    make install-private-headers
    ln -sfv tclsh8.6 /usr/bin/tclsh
    mv /usr/share/man/man3/{Thread,Tcl_Thread}.3
}

build_expect() {
    local v
    v=$(pkg_ver expect)
    patch -Np1 -i "$(pkg_file patch-expect-gcc14)"
    ./configure --prefix=/usr           \
                --with-tcl=/usr/lib     \
                --enable-shared         \
                --disable-rpath         \
                --mandir=/usr/share/man \
                --with-tclinclude=/usr/include
    make
    make install
    ln -svf "expect$v/libexpect$v.so" /usr/lib
}

build_dejagnu() {
    mkdir -v build && cd build
    ../configure --prefix=/usr
    make install
}

build_pkgconf() {
    ./configure --prefix=/usr --disable-static --docdir="$(doc pkgconf)"
    make
    make install
    ln -sfv pkgconf   /usr/bin/pkg-config
    ln -sfv pkgconf.1 /usr/share/man/man1/pkg-config.1
}

build_binutils() {
    mkdir -v build && cd build
    ../configure --prefix=/usr       \
                 --sysconfdir=/etc   \
                 --enable-ld=default \
                 --enable-plugins    \
                 --enable-shared     \
                 --disable-werror    \
                 --enable-64-bit-bfd \
                 --enable-new-dtags  \
                 --with-system-zlib  \
                 --enable-default-hash-style=gnu
    make tooldir=/usr
    run_tests make -k check
    make tooldir=/usr install
    rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a \
            /usr/share/doc/gprofng/
}

build_gmp() {
    # --enable-fat: librerie con dispatch a runtime per tutte le CPU x86-64
    ./configure --prefix=/usr    \
                --enable-cxx     \
                --enable-fat     \
                --disable-static \
                --docdir="$(doc gmp)"
    make
    run_tests make check
    make install
}

build_mpfr() {
    ./configure --prefix=/usr --disable-static --enable-thread-safe --docdir="$(doc mpfr)"
    make
    make install
}

build_mpc() {
    ./configure --prefix=/usr --disable-static --docdir="$(doc mpc)"
    make
    make install
}

build_attr() {
    ./configure --prefix=/usr --disable-static --sysconfdir=/etc --docdir="$(doc attr)"
    make
    make install
}

build_acl() {
    ./configure --prefix=/usr --disable-static --docdir="$(doc acl)"
    make
    make install
}

build_libcap() {
    sed -i '/install -m.*STA/d' libcap/Makefile
    make prefix=/usr lib=lib
    make prefix=/usr lib=lib install
}

build_libxcrypt() {
    ./configure --prefix=/usr                \
                --enable-hashes=strong,glibc \
                --enable-obsolete-api=no     \
                --disable-static             \
                --disable-failure-tokens
    make
    make install
}

build_gcc() {
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    mkdir -v build && cd build
    ../configure --prefix=/usr            \
                 LD=ld                    \
                 --enable-languages=c,c++ \
                 --enable-default-pie     \
                 --enable-default-ssp     \
                 --enable-host-pie        \
                 --disable-multilib       \
                 --disable-bootstrap      \
                 --disable-fixincludes    \
                 --with-system-zlib
    make
    run_tests make -k check
    make install
    local triplet
    triplet=$(gcc -dumpmachine)
    chown -v -R root:root "/usr/lib/gcc/$triplet/$GCC_VER"/include{,-fixed}
    ln -sfvr /usr/bin/cpp /usr/lib
    ln -sfv gcc.1 /usr/share/man/man1/cc.1
    ln -sfv "../../libexec/gcc/$triplet/$GCC_VER/liblto_plugin.so" /usr/lib/bfd-plugins/
    # Verifiche di sanità (LFS 8.29)
    echo 'int main(){}' > dummy.c
    cc dummy.c -v -Wl,--verbose &> dummy.log
    readelf -l a.out | grep -q ': /lib64/ld-linux-x86-64.so.2'
    grep -q 'crt1.o succeeded' dummy.log
    rm -v dummy.c a.out dummy.log
    mkdir -pv /usr/share/gdb/auto-load/usr/lib
    local py
    for py in /usr/lib/*gdb.py; do
        [[ -e $py ]] && mv -v "$py" /usr/share/gdb/auto-load/usr/lib
    done
}

build_ncurses() {
    local so
    ./configure --prefix=/usr           \
                --mandir=/usr/share/man \
                --with-shared           \
                --without-debug         \
                --without-normal        \
                --with-cxx-shared       \
                --enable-pc-files       \
                --with-pkg-config-libdir=/usr/lib/pkgconfig
    make
    make DESTDIR="$PWD/dest" install
    so=$(basename "$(find dest/usr/lib -maxdepth 1 -name 'libncursesw.so.*.*' -type f | head -n1)")
    install -vm755 "dest/usr/lib/$so" /usr/lib
    rm -v "dest/usr/lib/$so"
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
    cp -av dest/* /
    local lib
    for lib in ncurses form panel menu; do
        ln -sfv "lib${lib}w.so" "/usr/lib/lib${lib}.so"
        ln -sfv "${lib}w.pc"    "/usr/lib/pkgconfig/${lib}.pc"
    done
    ln -sfv libncursesw.so /usr/lib/libcurses.so
}

build_sed() {
    ./configure --prefix=/usr
    make
    make install
}

build_psmisc() {
    ./configure --prefix=/usr
    make
    make install
}

build_gettext() {
    ./configure --prefix=/usr --disable-static --docdir="$(doc gettext)"
    make
    make install
    chmod -v 0755 /usr/lib/preloadable_libintl.so
}

build_bison() {
    ./configure --prefix=/usr --docdir="$(doc bison)"
    make
    make install
}

build_grep() {
    sed -i "s/echo/#echo/" src/egrep.sh
    ./configure --prefix=/usr
    make
    make install
}

build_bash() {
    ./configure --prefix=/usr             \
                --without-bash-malloc     \
                --with-installed-readline \
                --docdir="$(doc bash)"
    make
    make install
}

build_libtool() {
    ./configure --prefix=/usr
    make
    make install
    rm -fv /usr/lib/libltdl.a
}

build_gdbm() {
    ./configure --prefix=/usr --disable-static --enable-libgdbm-compat
    make
    make install
}

build_gperf() {
    ./configure --prefix=/usr --docdir="$(doc gperf)"
    make
    make install
}

build_expat() {
    ./configure --prefix=/usr --disable-static --docdir="$(doc expat)"
    make
    make install
}

build_inetutils() {
    sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
    ./configure --prefix=/usr        \
                --bindir=/usr/bin    \
                --localstatedir=/var \
                --disable-logger     \
                --disable-whois      \
                --disable-rcp        \
                --disable-rexec      \
                --disable-rlogin     \
                --disable-rsh        \
                --disable-servers
    make
    make install
    mv -v /usr/{,s}bin/ifconfig
}

build_less() {
    ./configure --prefix=/usr --sysconfdir=/etc
    make
    make install
}

build_perl() {
    export BUILD_ZLIB=False BUILD_BZIP2=0
    sh Configure -des                                         \
        -D prefix=/usr                                        \
        -D vendorprefix=/usr                                  \
        -D privlib="/usr/lib/perl5/$PERL_MM/core_perl"        \
        -D archlib="/usr/lib/perl5/$PERL_MM/core_perl"        \
        -D sitelib="/usr/lib/perl5/$PERL_MM/site_perl"        \
        -D sitearch="/usr/lib/perl5/$PERL_MM/site_perl"       \
        -D vendorlib="/usr/lib/perl5/$PERL_MM/vendor_perl"    \
        -D vendorarch="/usr/lib/perl5/$PERL_MM/vendor_perl"   \
        -D man1dir=/usr/share/man/man1                        \
        -D man3dir=/usr/share/man/man3                        \
        -D pager="/usr/bin/less -isR"                         \
        -D useshrplib                                         \
        -D usethreads
    make
    make install
    unset BUILD_ZLIB BUILD_BZIP2
}

build_xml_parser() {
    perl Makefile.PL
    make
    make install
}

build_intltool() {
    sed -i 's:\\\${:\\\$\\{:' intltool-update.in
    ./configure --prefix=/usr
    make
    make install
}

build_autoconf() {
    ./configure --prefix=/usr
    make
    make install
}

build_automake() {
    ./configure --prefix=/usr --docdir="$(doc automake)"
    make
    make install
}

build_openssl() {
    ./config --prefix=/usr         \
             --openssldir=/etc/ssl \
             --libdir=lib          \
             shared                \
             zlib-dynamic
    make
    sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
    make MANSUFFIX=ssl install
    mv -v /usr/share/doc/openssl "$(doc openssl)"
}

build_elfutils() {
    ./configure --prefix=/usr --disable-debuginfod --enable-libdebuginfod=dummy
    make
    make -C libelf install
    install -vm644 config/libelf.pc /usr/lib/pkgconfig
    rm /usr/lib/libelf.a
}

build_libffi() {
    # x86-64 generico invece di -march=native (immagine portabile)
    ./configure --prefix=/usr --disable-static --with-gcc-arch=x86-64
    make
    make install
}

build_python() {
    ./configure --prefix=/usr          \
                --enable-shared        \
                --with-system-expat    \
                --enable-optimizations \
                --without-static-libpython
    make
    make install
    cat > /etc/pip.conf <<"EOF"
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF
}

build_flit_core()  { pip_install flit_core; }
build_wheel()      { pip_install wheel; }
build_setuptools() { pip_install setuptools; }

build_ninja() {
    python3 configure.py --bootstrap --verbose
    install -vm755 ninja /usr/bin/
    install -vDm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
    install -vDm644 misc/zsh-completion  /usr/share/zsh/site-functions/_ninja
}

build_meson() {
    pip_install meson
    install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
    install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
}

build_linux_pam() {
    # BLFS: Linux-PAM (prima di shadow e systemd)
    mkdir -v build && cd build
    meson setup .. --prefix=/usr --buildtype=release \
        -D docs=disabled \
        -D docdir="$(doc linux-pam)"
    ninja
    ninja install
    chmod -v 4755 /usr/sbin/unix_chkpwd
    # Configurazione PAM in stile Arch (system-auth, system-login, ...):
    # va installata subito, perché shadow la usa già durante l'installazione.
    install -vdm755 /etc/pam.d
    install -vm644 "$ARCBASE_DIR"/rootfs/etc/pam.d/* /etc/pam.d/
    install -vm644 "$ARCBASE_DIR/rootfs/etc/shells" /etc/shells
}

build_shadow() {
    sed -i 's/groups$(EXEEXT) //' src/Makefile.in
    find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
    find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
    find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
    sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
        -e 's:/var/spool/mail:/var/mail:'                   \
        -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
        -i etc/login.defs
    touch /usr/bin/passwd
    ./configure --sysconfdir=/etc   \
                --disable-static    \
                --with-{b,yes}crypt \
                --without-libbsd    \
                --with-libpam       \
                --with-group-name-max-length=32
    make
    make exec_prefix=/usr pamddir= install
    make -C man install-man
    # Con PAM queste opzioni sono gestite dai moduli (BLFS: Shadow + PAM)
    local opt
    for opt in FAIL_DELAY FAILLOG_ENAB LASTLOG_ENAB MAIL_CHECK_ENAB \
               OBSCURE_CHECKS_ENAB PORTTIME_CHECKS_ENAB QUOTAS_ENAB \
               CONSOLE MOTD_FILE FTMP_FILE NOLOGINS_FILE ENV_HZ PASS_MIN_LEN \
               SU_WHEEL_ONLY PASS_CHANGE_TRIES PASS_ALWAYS_WARN \
               CHFN_AUTH ENCRYPT_METHOD ENVIRON_FILE; do
        sed -i "s/^${opt}/# &/" /etc/login.defs
    done
    pwconv
    grpconv
    mkdir -p /etc/default
    useradd -D --gid 999
    sed -i '/MAIL/s/yes/no/' /etc/default/useradd
}

build_kmod() {
    mkdir -p build && cd build
    meson setup --prefix=/usr .. --sbindir=/usr/sbin --buildtype=release -D manpages=false
    ninja
    ninja install
}

build_coreutils() {
    patch -Np1 -i "$(pkg_file patch-coreutils-i18n)"
    autoreconf -fv
    automake -af
    FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr --enable-no-install-program=kill,uptime
    make
    make install
    mv -v /usr/bin/chroot /usr/sbin
    mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
    sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
}

build_check() {
    ./configure --prefix=/usr --disable-static
    make
    make docdir="$(doc check)" install
}

build_diffutils() {
    ./configure --prefix=/usr
    make
    make install
}

build_gawk() {
    sed -i 's/extras//' Makefile.in
    ./configure --prefix=/usr
    make
    rm -f "/usr/bin/gawk-$(pkg_ver gawk)"
    make install
    ln -sfv gawk.1 /usr/share/man/man1/awk.1
}

build_findutils() {
    ./configure --prefix=/usr --localstatedir=/var/lib/locate
    make
    make install
}

build_groff() {
    PAGE=A4 ./configure --prefix=/usr
    make
    make install
}

build_grub() {
    # GRUB per BIOS (i386-pc); la variante EFI è compilata nello stadio 09
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    echo depends bli part_gpt > grub-core/extra_deps.lst
    ./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu --disable-werror
    make
    make install
    mkdir -p /usr/share/bash-completion/completions
    mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions
}

build_gzip() {
    ./configure --prefix=/usr
    make
    make install
}

build_iproute2() {
    sed -i /ARPD/d Makefile
    rm -fv man/man8/arpd.8
    make NETNS_RUN_DIR=/run/netns
    make SBINDIR=/usr/sbin install
}

build_kbd() {
    patch -Np1 -i "$(pkg_file patch-kbd-backspace)"
    sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
    sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
    ./configure --prefix=/usr --disable-vlock
    make
    make install
}

build_libpipeline() {
    ./configure --prefix=/usr
    make
    make install
}

build_make() {
    ./configure --prefix=/usr
    make
    make install
}

build_patch() {
    ./configure --prefix=/usr
    make
    make install
}

build_tar() {
    FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
    make
    make install
}

build_texinfo() {
    ./configure --prefix=/usr
    make
    make install
}

build_vim() {
    echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
    ./configure --prefix=/usr
    make
    make install
    ln -sfv vim /usr/bin/vi
    local L
    for L in /usr/share/man/{,*/}man1/vim.1; do
        [[ -e $L ]] || continue
        ln -sfv vim.1 "$(dirname "$L")/vi.1"
    done
    cat > /etc/vimrc <<"EOF"
" Arcbase Desktop — /etc/vimrc
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1
set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif
EOF
}

build_markupsafe() { pip_install Markupsafe; }
build_jinja2()     { pip_install Jinja2; }

build_systemd() {
    mkdir -p build && cd build
    meson setup ..                \
        --prefix=/usr             \
        --buildtype=release       \
        -D default-dnssec=no      \
        -D firstboot=false        \
        -D install-tests=false    \
        -D ldconfig=false         \
        -D sysusers=true          \
        -D rpmmacrosdir=no        \
        -D homed=disabled         \
        -D userdb=false           \
        -D man=disabled           \
        -D mode=release           \
        -D pam=enabled            \
        -D pamconfdir=/etc/pam.d  \
        -D dev-kvm-mode=0660      \
        -D nobody-group=nogroup   \
        -D sysupdate=disabled     \
        -D ukify=disabled         \
        -D docdir="$(doc systemd)"
    ninja
    ninja install
    tar -xf "$(pkg_file systemd-man)" --no-same-owner --strip-components=1 -C /usr/share/man
    systemd-machine-id-setup
    systemctl preset-all
}

build_dbus() {
    mkdir build && cd build
    meson setup --prefix=/usr --buildtype=release --wrap-mode=nofallback ..
    ninja
    ninja install
    ln -sfv /etc/machine-id /var/lib/dbus
}

build_man_db() {
    ./configure --prefix=/usr                         \
                --docdir="$(doc man-db)"              \
                --sysconfdir=/etc                     \
                --disable-setuid                      \
                --enable-cache-owner=bin              \
                --with-browser=/usr/bin/lynx          \
                --with-vgrind=/usr/bin/vgrind         \
                --with-grap=/usr/bin/grap
    make
    make install
}

build_procps_ng() {
    ./configure --prefix=/usr              \
                --docdir="$(doc procps-ng)" \
                --disable-static           \
                --disable-kill             \
                --enable-watch8bit         \
                --with-systemd
    make src_w_LDADD='$(LDADD) -lsystemd'
    make install
}

build_util_linux() {
    # A differenza di LFS si compilano runuser e setpriv (c'è PAM)
    ./configure --bindir=/usr/bin     \
                --libdir=/usr/lib     \
                --runstatedir=/run    \
                --sbindir=/usr/sbin   \
                --disable-chfn-chsh   \
                --disable-login       \
                --disable-nologin     \
                --disable-su          \
                --disable-pylibmount  \
                --disable-liblastlog2 \
                --disable-static      \
                --without-python      \
                ADJTIME_PATH=/var/lib/hwclock/adjtime \
                --docdir="$(doc util-linux)"
    make
    make install
}

build_e2fsprogs() {
    mkdir -v build && cd build
    ../configure --prefix=/usr       \
                 --sysconfdir=/etc   \
                 --enable-elf-shlibs \
                 --disable-libblkid  \
                 --disable-libuuid   \
                 --disable-uuidd     \
                 --disable-fsck
    make
    make install
    rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
}

final_cleanup() {
    rm -rf /tmp/{*,.[!.]*}
    find /usr/lib /usr/libexec -name '*.la' -delete
    find /usr -depth -name "$LFS_TGT*" -print0 | xargs -0 -r rm -rf
}

# --- Ordine di compilazione (LFS 8.3–8.81 + PAM) --------------------------------
PACKAGES=(
    man-pages iana-etc glibc zlib bzip2 xz lz4 zstd file readline m4 bc flex
    tcl expect dejagnu pkgconf binutils gmp mpfr mpc attr acl libcap libxcrypt
    gcc ncurses sed psmisc gettext bison grep bash libtool gdbm gperf expat
    inetutils less perl xml-parser intltool autoconf automake openssl elfutils
    libffi python flit-core wheel setuptools ninja meson
    linux-pam shadow
    kmod coreutils check diffutils gawk findutils groff grub gzip iproute2 kbd
    libpipeline make patch tar texinfo vim markupsafe jinja2 systemd dbus
    man-db procps-ng util-linux e2fsprogs
)
for p in "${PACKAGES[@]}"; do
    build "$p"
done
step cleanup final_cleanup

msg "Sistema base completato."
msg "Prossimo passo: make merge-usr && make config"
