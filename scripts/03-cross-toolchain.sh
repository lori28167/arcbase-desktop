#!/bin/bash
# =============================================================================
#  Stadio 03 — toolchain di cross-compilazione (LFS cap. 5)
#  Eseguito come utente 'lfs' (lo script si rilancia da solo se avviato da root).
# =============================================================================
STAGE=ch5
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
as_lfs_user

GCC_VER=$(pkg_ver gcc)
GLIBC_VER=$(pkg_ver glibc)

build_binutils_pass1() {
    mkdir -v build && cd build
    ../configure --prefix="$LFS/tools" \
                 --with-sysroot="$LFS" \
                 --target="$LFS_TGT"   \
                 --disable-nls         \
                 --enable-gprofng=no   \
                 --disable-werror      \
                 --enable-new-dtags    \
                 --enable-default-hash-style=gnu
    make
    make install
}

build_gcc_pass1() {
    extract_into mpfr mpfr
    extract_into gmp gmp
    extract_into mpc mpc
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    mkdir -v build && cd build
    ../configure --target="$LFS_TGT"            \
                 --prefix="$LFS/tools"          \
                 --with-glibc-version="$GLIBC_VER" \
                 --with-sysroot="$LFS"          \
                 --with-newlib                  \
                 --without-headers              \
                 --enable-default-pie           \
                 --enable-default-ssp           \
                 --disable-nls                  \
                 --disable-shared               \
                 --disable-multilib             \
                 --disable-threads              \
                 --disable-libatomic            \
                 --disable-libgomp              \
                 --disable-libquadmath          \
                 --disable-libssp               \
                 --disable-libvtv               \
                 --disable-libstdcxx            \
                 --enable-languages=c,c++
    make
    make install
    cd ..
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
        "$(dirname "$("$LFS_TGT-gcc" -print-libgcc-file-name)")/include/limits.h"
}

build_linux_headers() {
    make mrproper
    make headers
    find usr/include -type f ! -name '*.h' -delete
    cp -rv usr/include "$LFS/usr"
}

build_glibc_cross() {
    ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64"
    ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
    patch -Np1 -i "$(pkg_file patch-glibc-fhs)"
    mkdir -v build && cd build
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure --prefix=/usr                        \
                 --host="$LFS_TGT"                    \
                 --build="$(../scripts/config.guess)" \
                 --enable-kernel=5.4                  \
                 --with-headers="$LFS/usr/include"    \
                 --disable-nscd                       \
                 libc_cv_slibdir=/usr/lib
    make
    make DESTDIR="$LFS" install
    sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"
    # Verifica di sanità del cross-compilatore
    echo 'int main(){}' | "$LFS_TGT-gcc" -xc -
    readelf -l a.out | grep -q '/lib64/ld-linux-x86-64.so.2'
    rm -v a.out
}

build_gcc_libstdcxx() {
    mkdir -v build && cd build
    ../libstdc++-v3/configure          \
        --host="$LFS_TGT"              \
        --build="$(../config.guess)"   \
        --prefix=/usr                  \
        --disable-multilib             \
        --disable-nls                  \
        --disable-libstdcxx-pch        \
        --with-gxx-include-dir="/tools/$LFS_TGT/include/c++/$GCC_VER"
    make
    make DESTDIR="$LFS" install
    rm -v "$LFS"/usr/lib/lib{stdc++{,exp,fs},supc++}.la
}

build binutils pass1
build gcc      pass1
build linux    headers
build glibc    cross
build gcc      libstdcxx

msg "Toolchain di cross-compilazione completata"
