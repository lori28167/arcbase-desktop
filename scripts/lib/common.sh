# shellcheck shell=bash
# =============================================================================
#  Arcbase Desktop — funzioni condivise dagli script di build
#
#  Ogni stadio definisce STAGE e una funzione build_<pacchetto>[_<variante>]
#  per ogni pacchetto, poi chiama `build <pacchetto> [variante]`. La funzione
#  `build` estrae il sorgente, entra nella directory, esegue la ricetta con
#  `set -e` in una subshell (log in $LOG_DIR) e scrive uno "stamp" così che un
#  build interrotto riparta dal pacchetto fallito.
# =============================================================================
set -o errexit -o nounset -o pipefail
umask 022

ARCBASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ARCBASE_DIR

# shellcheck source=../../config/arcbase.conf
source "$ARCBASE_DIR/config/arcbase.conf"
if [[ -f $ARCBASE_DIR/config/local.conf ]]; then
    # shellcheck disable=SC1091
    source "$ARCBASE_DIR/config/local.conf"
fi

SRC_DIR="$LFS/sources"
BUILD_DIR="$SRC_DIR/build"
STAMP_DIR="$SRC_DIR/.arcbase-stamps"
LOG_DIR="$SRC_DIR/.arcbase-logs"
STAGE=${STAGE:-generic}

# --- Output -------------------------------------------------------------------
if [[ -t 1 ]]; then
    _B=$'\e[1m' _G=$'\e[32m' _Y=$'\e[33m' _R=$'\e[31m' _C=$'\e[36m' _0=$'\e[0m'
else
    _B='' _G='' _Y='' _R='' _C='' _0=''
fi
msg()  { printf '%s==>%s %s%s%s\n' "$_G" "$_0" "$_B" "$*" "$_0"; }
info() { printf '  %s->%s %s\n' "$_C" "$_0" "$*"; }
warn() { printf '%s==> ATTENZIONE:%s %s\n' "$_Y" "$_0" "$*" >&2; }
die()  { printf '%s==> ERRORE:%s %s\n' "$_R" "$_0" "$*" >&2; exit 1; }

require_root() { [[ $EUID -eq 0 ]] || die "questo stadio va eseguito come root"; }

in_chroot() { [[ ${ARCBASE_IN_CHROOT:-0} == 1 || ${ARCBASE_DRY_RUN:-0} == 1 ]]; }

# --- Registro dei sorgenti (config/packages.conf) ------------------------------
declare -gA PKG_VER=() PKG_URL=()
load_packages() {
    local name ver url
    while read -r name ver url; do
        [[ -z ${name:-} || $name == \#* ]] && continue
        PKG_VER[$name]=$ver
        PKG_URL[$name]=${url//@V@/$ver}
    done < "$ARCBASE_DIR/config/packages.conf"
}
load_packages

pkg_ver() {
    [[ -n ${PKG_VER[$1]:-} ]] || die "pacchetto sconosciuto in packages.conf: $1"
    printf '%s\n' "${PKG_VER[$1]}"
}
pkg_url() {
    [[ -n ${PKG_URL[$1]:-} ]] || die "pacchetto sconosciuto in packages.conf: $1"
    printf '%s\n' "${PKG_URL[$1]}"
}
# Percorso locale del file sorgente (basename dell'URL dentro $SRC_DIR)
pkg_file() {
    local url
    url=$(pkg_url "$1")
    url=${url%%\?*}
    printf '%s/%s\n' "$SRC_DIR" "${url##*/}"
}
# major.minor di una versione (es. 5.40.1 -> 5.40)
ver_mm() { local v; v=$(pkg_ver "$1"); printf '%s\n' "${v%.*}"; }

# Estrae un tarball secondario nella directory corrente e lo rinomina
# (es. mpfr/gmp/mpc dentro l'albero di gcc).
extract_into() {
    local pkg=$1 dest=$2 file top
    file=$(pkg_file "$pkg")
    # (|| : evita che SIGPIPE di tar con pipefail interrompa la ricetta)
    top=$(tar -tf "$file" | head -n1 | cut -d/ -f1) || :
    tar -xf "$file"
    mv -v "$top" "$dest"
}

# Esegue la test suite solo se LFS_TESTS=1; i fallimenti non bloccano la build.
run_tests() {
    [[ ${LFS_TESTS:-0} == 1 ]] || return 0
    "$@" || warn "test falliti per $* (ignorati, controllare il log)"
}

# --- Motore di build -------------------------------------------------------------
stamp_file() { printf '%s/%s.done\n' "$STAMP_DIR" "$1"; }
is_done()    { [[ -e $(stamp_file "$1") ]]; }
mark_done()  { mkdir -p "$STAMP_DIR"; touch "$(stamp_file "$1")"; }

# build <pacchetto> [variante]
build() {
    local pkg=$1 variant=${2:-} id fn tarball dir log rc
    id="${STAGE}-${pkg}${variant:+-$variant}"
    if is_done "$id"; then
        info "$id già completato, salto"
        return 0
    fi
    fn="build_${pkg//[-.+]/_}${variant:+_$variant}"
    declare -F "$fn" >/dev/null || die "ricetta mancante: $fn"
    tarball=$(pkg_file "$pkg")
    [[ -f $tarball ]] || die "sorgente mancante: $tarball (eseguire 'make download')"

    msg "[$STAGE] $pkg $(pkg_ver "$pkg")${variant:+ ($variant)}"
    mkdir -p "$LOG_DIR"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    case $tarball in
        *.tar.*|*.tgz) tar -xf "$tarball" -C "$BUILD_DIR" ;;
        *) cp "$tarball" "$BUILD_DIR/" ;;
    esac
    # Directory principale del sorgente (tzdata non ne ha una)
    dir=$(find "$BUILD_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1) || :
    [[ -n $dir ]] || dir=$BUILD_DIR

    log="$LOG_DIR/$id.log"
    set +o errexit
    if [[ ${LFS_VERBOSE:-0} == 1 ]]; then
        ( set -o errexit -o pipefail; cd "$dir"; set -x; "$fn" ) 2>&1 | tee "$log"
        rc=${PIPESTATUS[0]}
    else
        ( set -o errexit -o pipefail; cd "$dir"; set -x; "$fn" ) > "$log" 2>&1
        rc=$?
    fi
    set -o errexit
    if [[ $rc -ne 0 ]]; then
        tail -n 30 "$log" >&2
        die "compilazione fallita: $id (log completo: $log)"
    fi
    rm -rf "$BUILD_DIR"
    mark_done "$id"
}

# Esegue un passo non legato a un sorgente (configurazione, pulizia...) una
# sola volta: step <id> <funzione>
step() {
    local id="${STAGE}-$1" fn=$2 log rc
    if is_done "$id"; then
        info "$id già completato, salto"
        return 0
    fi
    msg "[$STAGE] $1"
    mkdir -p "$LOG_DIR"
    log="$LOG_DIR/$id.log"
    set +o errexit
    ( set -o errexit -o pipefail; cd /; set -x; "$fn" ) > "$log" 2>&1
    rc=$?
    set -o errexit
    if [[ $rc -ne 0 ]]; then
        tail -n 30 "$log" >&2
        die "passo fallito: $id (log completo: $log)"
    fi
    mark_done "$id"
}

# Rilancia lo script corrente come utente 'lfs' con l'ambiente pulito
# descritto in LFS cap. 4.4 (usato dagli stadi 03 e 04).
as_lfs_user() {
    [[ ${ARCBASE_DRY_RUN:-0} == 1 ]] && return 0
    if [[ $(id -un) == lfs ]]; then
        set +h
        return 0
    fi
    require_root
    sync_tree
    exec runuser -u lfs -- env -i \
        HOME=/home/lfs TERM="${TERM:-xterm}" LC_ALL=POSIX \
        LFS="$LFS" LFS_TGT="$LFS_TGT" \
        PATH="$LFS/tools/bin:/usr/bin:/bin" \
        CONFIG_SITE="$LFS/usr/share/config.site" \
        MAKEFLAGS="$MAKEFLAGS" LFS_TESTS="$LFS_TESTS" LFS_VERBOSE="$LFS_VERBOSE" \
        /bin/bash --noprofile --norc "$LFS/arcbase/scripts/$(basename "$0")"
}

# Copia rootfs/ (arc, hook ALPM, PAM, profile...) dentro / — solo nel chroot
install_overlay() {
    in_chroot || die "install_overlay va eseguito nel chroot"
    cp -a --no-preserve=ownership "$ARCBASE_DIR/rootfs/." /
    chmod 755 /usr/bin/arc /usr/bin/arcbase-* /usr/share/libalpm/scripts/*
}

# Copia l'albero di build (config, script, rootfs) dentro $LFS/arcbase, così
# che sia raggiungibile dall'utente lfs e dall'interno del chroot.
sync_tree() {
    [[ -n $LFS ]] || return 0
    local dest="$LFS/arcbase"
    [[ $ARCBASE_DIR == "$dest" ]] && return 0
    mkdir -p "$dest"
    rm -rf "$dest/config" "$dest/scripts" "$dest/rootfs"
    cp -a "$ARCBASE_DIR/config" "$ARCBASE_DIR/scripts" "$ARCBASE_DIR/rootfs" "$dest/"
    chmod -R a+rX "$dest"
}

# --- Dry run --------------------------------------------------------------------
# ARCBASE_DRY_RUN=1: gli stadi non compilano nulla, ma verificano che ogni
# pacchetto abbia la sua ricetta e una voce in packages.conf (tests/).
if [[ ${ARCBASE_DRY_RUN:-0} == 1 ]]; then
    build() {
        local fn="build_${1//[-.+]/_}${2:+_$2}"
        declare -F "$fn" >/dev/null || die "ricetta mancante: $fn"
        pkg_file "$1" >/dev/null
        printf 'build %s %s\n' "$1" "$(pkg_ver "$1")"
    }
    step() {
        declare -F "$2" >/dev/null || die "funzione mancante per il passo $1: $2"
        printf 'step %s\n' "$1"
    }
fi
