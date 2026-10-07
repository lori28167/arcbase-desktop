#!/bin/bash
# =============================================================================
#  Stadio 04 — strumenti temporanei cross-compilati (LFS cap. 6)
#  Eseguito come utente 'lfs'.
# =============================================================================
STAGE=ch6
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
as_lfs_user

# configure standard per la cross-compilazione: std_configure <config.guess> [opzioni]
std_configure() {
    local guess=$1; shift
    ./configure --prefix=/usr --host="$LFS_TGT" --build="$($guess)" "$@"
}

build_m4() {
    std_configure build-aux/config.guess
    make
    make DESTDIR="$LFS" install
}

build_ncurses() {
    mkdir build
    pushd build
        ../configure AWK=gawk
        make -C include
        make -C progs tic
    popd
    ./configure --prefix=/usr                \
                --host="$LFS_TGT"            \
                --build="$(./config.guess)"  \
                --mandir=/usr/share/man      \
                --with-manpage-format=normal \
                --with-shared                \
                --without-normal             \
                --with-cxx-shared            \
                --without-debug              \
                --without-ada                \
                --disable-stripping          \
                AWK=gawk
    make
    make DESTDIR="$LFS" TIC_PATH="$(pwd)/build/progs/tic" install
    ln -sv libncursesw.so "$LFS/usr/lib/libncurses.so"
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$LFS/usr/include/curses.h"
}

build_bash() {
    ./configure --prefix=/usr                      \
                --build="$(sh support/config.guess)" \
                --host="$LFS_TGT"                  \
                --without-bash-malloc
    make
    make DESTDIR="$LFS" install
    ln -sfv bash "$LFS/bin/sh"
}

build_coreutils() {
    std_configure build-aux/config.guess \
        --enable-install-program=hostname \
        --enable-no-install-program=kill,uptime
    make
    make DESTDIR="$LFS" install
    mv -v "$LFS/usr/bin/chroot" "$LFS/usr/sbin"
    mkdir -pv "$LFS/usr/share/man/man8"
    mv -v "$LFS/usr/share/man/man1/chroot.1" "$LFS/usr/share/man/man8/chroot.8"
    sed -i 's/"1"/"8"/' "$LFS/usr/share/man/man8/chroot.8"
}

build_diffutils() {
    std_configure ./build-aux/config.guess
    make
    make DESTDIR="$LFS" install
}

build_file() {
    mkdir build
    pushd build
        ../configure --disable-bzlib      \
                     --disable-libseccomp \
                     --disable-xzlib      \
                     --disable-zlib
        make
    popd
    std_configure ./config.guess
    make FILE_COMPILE="$(pwd)/build/src/file"
    make DESTDIR="$LFS" install
    rm -v "$LFS/usr/lib/libmagic.la"
}

build_findutils() {
    std_configure build-aux/config.guess --localstatedir=/var/lib/locate
    make
    make DESTDIR="$LFS" install
}

build_gawk() {
    sed -i 's/extras//' Makefile.in
    std_configure build-aux/config.guess
    make
    make DESTDIR="$LFS" install
}

build_grep() {
    std_configure ./build-aux/config.guess
    make
    make DESTDIR="$LFS" install
}

build_gzip() {
    ./configure --prefix=/usr --host="$LFS_TGT"
    make
    make DESTDIR="$LFS" install
}

build_make() {
    std_configure build-aux/config.guess --without-guile
    make
    make DESTDIR="$LFS" install
}

build_patch() {
    std_configure build-aux/config.guess
    make
    make DESTDIR="$LFS" install
}

build_sed() {
    std_configure ./build-aux/config.guess
    make
    make DESTDIR="$LFS" install
}

build_tar() {
    std_configure build-aux/config.guess
    make
    make DESTDIR="$LFS" install
}

build_xz() {
    std_configure build-aux/config.guess \
        --disable-static \
        --docdir="/usr/share/doc/xz-$(pkg_ver xz)"
    make
    make DESTDIR="$LFS" install
    rm -v "$LFS/usr/lib/liblzma.la"
}

build_binutils_pass2() {
    sed '6031s/$add_dir//' -i ltmain.sh
    mkdir -v build && cd build
    ../configure                   \
        --prefix=/usr              \
        --build="$(../config.guess)" \
        --host="$LFS_TGT"          \
        --disable-nls              \
        --enable-shared            \
        --enable-gprofng=no        \
        --disable-werror           \
        --enable-64-bit-bfd        \
        --enable-new-dtags         \
        --enable-default-hash-style=gnu
    make
    make DESTDIR="$LFS" install
    rm -v "$LFS"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}

build_gcc_pass2() {
    extract_into mpfr mpfr
    extract_into gmp gmp
    extract_into mpc mpc
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    sed '/thread_header =/s/@.*@/gthr-posix.h/' \
        -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
    mkdir -v build && cd build
    ../configure                                       \
        --build="$(../config.guess)"                   \
        --host="$LFS_TGT"                              \
        --target="$LFS_TGT"                            \
        LDFLAGS_FOR_TARGET="-L$PWD/$LFS_TGT/libgcc"    \
        --prefix=/usr                                  \
        --with-build-sysroot="$LFS"                    \
        --enable-default-pie                           \
        --enable-default-ssp                           \
        --disable-nls                                  \
        --disable-multilib                             \
        --disable-libatomic                            \
        --disable-libgomp                              \
        --disable-libquadmath                          \
        --disable-libsanitizer                         \
        --disable-libssp                               \
        --disable-libvtv                               \
        --enable-languages=c,c++
    make
    make DESTDIR="$LFS" install
    ln -sv gcc "$LFS/usr/bin/cc"
}

for p in m4 ncurses bash coreutils diffutils file findutils gawk grep gzip make patch sed tar xz; do
    build "$p"
done
build binutils pass2
build gcc      pass2

msg "Strumenti temporanei completati. Prossimo passo: make chroot-tools (come root)"
