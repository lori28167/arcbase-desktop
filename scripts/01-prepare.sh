#!/bin/bash
# =============================================================================
#  Stadio 01 — preparazione di $LFS (LFS cap. 2.7, 4.2, 4.3)
#
#  La partizione di destinazione deve essere già creata, formattata e montata
#  su $LFS (default /mnt/lfs). Per fare la build in una semplice directory,
#  esportare ARC_ALLOW_UNMOUNTED=1.
# =============================================================================
STAGE=prepare
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
require_root

[[ -n $LFS && $LFS != / ]] || die "LFS non valido: '$LFS'"
mkdir -p "$LFS"
if ! mountpoint -q "$LFS" && [[ ${ARC_ALLOW_UNMOUNTED:-0} != 1 ]]; then
    die "$LFS non è un punto di montaggio. Montare la partizione di destinazione oppure esportare ARC_ALLOW_UNMOUNTED=1"
fi

msg "Creazione della gerarchia minima in $LFS"
mkdir -pv "$LFS"/{etc,var,tools} "$LFS"/usr/{bin,lib,sbin}
for d in bin lib sbin; do
    [[ -e $LFS/$d ]] || ln -sv "usr/$d" "$LFS/$d"
done
mkdir -pv "$LFS/lib64"

msg "Directory dei sorgenti"
mkdir -pv "$SRC_DIR" "$STAMP_DIR" "$LOG_DIR"
chmod -v a+wt "$SRC_DIR" "$STAMP_DIR" "$LOG_DIR"

msg "Utente di build 'lfs'"
if ! getent group lfs >/dev/null; then groupadd lfs; fi
if ! id lfs >/dev/null 2>&1; then
    useradd -s /bin/bash -g lfs -m -k /dev/null lfs
fi
# Una sola volta: dopo il passaggio a root (05-chroot.sh) rifarlo
# restituirebbe /usr, /etc e /var all'utente lfs.
if ! is_done prepare-owner && ! is_done chroot-owner; then
    chown -v lfs "$LFS"/{usr{,/*},var,etc,tools,lib64}
    for d in bin lib sbin; do chown -h lfs "$LFS/$d"; done
    mark_done prepare-owner
fi

msg "Copia dell'albero Arcbase in $LFS/arcbase"
sync_tree

msg "Preparazione completata. Prossimo passo: make download"
