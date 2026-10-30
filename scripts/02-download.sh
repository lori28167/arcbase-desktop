#!/bin/bash
# =============================================================================
#  Stadio 02 — download dei sorgenti (LFS cap. 3) + componenti Arcbase
#
#  Per ogni voce di config/packages.conf scarica l'URL primario; in caso di
#  errore prova il mirror completo LFS ($LFS_SOURCES_MIRROR). I file presenti
#  nel file md5sums ufficiale del libro LFS vengono verificati, e così quelli
#  con uno SHA-256 in packages.conf.
# =============================================================================
STAGE=download
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

mkdir -p "$SRC_DIR"

fetch() {  # fetch <url> <destinazione>
    local url=$1 out=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 20 -o "$out.part" "$url"
    else
        wget -q --tries=3 -O "$out.part" "$url"
    fi && mv "$out.part" "$out"
}

failed=()
for name in "${!PKG_URL[@]}"; do
    url=${PKG_URL[$name]}
    out=$(pkg_file "$name")
    [[ -s $out ]] && continue
    info "$name → ${out##*/}"
    if ! fetch "$url" "$out"; then
        warn "URL primario non raggiungibile, provo il mirror LFS"
        if ! fetch "$LFS_SOURCES_MIRROR/${out##*/}" "$out"; then
            rm -f "$out.part"
            failed+=("$name")
        fi
    fi
done

msg "Verifica md5 (lista ufficiale LFS $LFS_BOOK_VERSION)"
md5list="$SRC_DIR/md5sums.lfs"
if [[ -s $md5list ]] || fetch "$LFS_BOOK_URL/md5sums" "$md5list"; then
    checked=0 bad=0
    while read -r sum file; do
        [[ -f $SRC_DIR/$file ]] || continue
        checked=$((checked + 1))
        if [[ $(md5sum "$SRC_DIR/$file" | cut -d' ' -f1) != "$sum" ]]; then
            warn "md5 errato: $file (rimosso, rilanciare make download)"
            rm -f "$SRC_DIR/$file"
            bad=$((bad + 1))
        fi
    done < "$md5list"
    info "$checked file verificati, $bad errati"
    (( bad == 0 )) || die "alcuni sorgenti sono corrotti"
else
    warn "impossibile scaricare md5sums: verifica saltata"
fi

# SHA-256 dei sorgenti che lo dichiarano in packages.conf (il quarto campo)
bad=0
for name in "${!PKG_SHA256[@]}"; do
    [[ -n ${PKG_SHA256[$name]} && -f $(pkg_file "$name") ]] || continue
    if ! verify_source "$name"; then
        warn "SHA-256 errato: $(pkg_file "$name") (rimosso, rilanciare make download)"
        rm -f "$(pkg_file "$name")"
        bad=$((bad + 1))
    fi
done
(( bad == 0 )) || die "alcuni sorgenti non corrispondono allo SHA-256 di packages.conf"

if (( ${#failed[@]} > 0 )); then
    die "download falliti: ${failed[*]} — aggiornare gli URL in config/packages.conf"
fi
chmod a+r "$SRC_DIR"/* 2>/dev/null || :
msg "Tutti i sorgenti sono in $SRC_DIR"
