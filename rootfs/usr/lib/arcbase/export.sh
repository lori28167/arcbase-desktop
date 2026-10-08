# shellcheck shell=bash
# =============================================================================
#  arc — esportazione delle applicazioni Debian sull'host
#
#  Per ogni pacchetto Debian installato dall'utente:
#    * gli eseguibili in /usr/bin e /usr/games diventano wrapper in
#      $ARC_EXPORT_PREFIX/bin che chiamano `arc run`;
#    * i file .desktop vengono copiati in $ARC_EXPORT_PREFIX/share/applications
#      con Exec= riscritto e il suffisso " (Debian)" nel nome;
#    * le icone (tema hicolor e pixmaps) vengono copiate in
#      $ARC_EXPORT_PREFIX/share.
#  Ogni file creato è annotato in $ARC_STATEDIR/exports/<pacchetto>.list, così
#  la rimozione è esatta. I comandi già presenti sull'host non vengono mai
#  sovrascritti: l'host (pacman) ha sempre la precedenza.
# =============================================================================

ARC_EXPORT_MARK="# arcbase-export"

_exp_dir()   { printf '%s/exports\n' "$ARC_STATEDIR"; }
_exp_bin()   { printf '%s/bin\n' "$ARC_EXPORT_PREFIX"; }
_exp_apps()  { printf '%s/share/applications\n' "$ARC_EXPORT_PREFIX"; }
_exp_share() { printf '%s/share\n' "$ARC_EXPORT_PREFIX"; }

# Pacchetti attualmente esportati
export_current() {
    local f
    for f in "$(_exp_dir)"/*.list; do
        [[ -e $f ]] || continue
        f=${f##*/}
        printf '%s\n' "${f%.list}"
    done | sort -u
}

# Pacchetti che dovrebbero essere esportati:
#   (installati dall'utente ∪ forzati con `arc export`) − esclusi con `arc unexport`
export_desired() {
    local force=$ARC_STATEDIR/export-force.list
    local deny=$ARC_STATEDIR/export-deny.list
    {
        deb_user_pkgs
        if [[ -r $force ]]; then
            comm -12 <(sort -u "$force") <(deb_installed_pkgs)
        fi
    } | sort -u | if [[ -r $deny ]]; then comm -23 - <(sort -u "$deny"); else cat; fi
}

# Directory dei comandi dell'host (gestite da pacman): hanno sempre la precedenza
: "${ARC_HOST_BIN_DIRS:=/usr/bin /usr/sbin /bin /sbin}"

# Un comando con questo nome esiste già sull'host?
_host_has_cmd() {
    local name=$1 d
    for d in $ARC_HOST_BIN_DIRS; do
        [[ -e $d/$name ]] && return 0
    done
    return 1
}

# Il percorso di destinazione è già occupato (da un file dell'host o
# dall'esportazione di un altro pacchetto)? Le esportazioni non si
# sovrascrivono mai a vicenda: ogni file ha un solo proprietario.
_dest_taken() { [[ -e $1 || -L $1 ]]; }

# Risolve un percorso del layer seguendo i link simbolici *dentro* il layer
# (un link assoluto come /usr/bin/x -> /etc/alternatives/x va interpretato
# rispetto al root Debian, non a quello dell'host). Stampa il percorso host.
_layer_path() {
    local p=$1 t i
    for (( i = 0; i < 16; i++ )); do
        [[ -L $ARC_DEBIAN_ROOT$p ]] || break
        t=$(readlink "$ARC_DEBIAN_ROOT$p")
        if [[ $t == /* ]]; then p=$t; else p="${p%/*}/$t"; fi
    done
    printf '%s%s\n' "$ARC_DEBIAN_ROOT" "$p"
}

_write_bin_wrapper() {
    local pkg=$1 path=$2 dest=$3
    mkdir -p "${dest%/*}"
    cat > "$dest" <<EOF
#!/bin/sh
$ARC_EXPORT_MARK: $pkg (Debian $ARC_DEBIAN_SUITE)
exec /usr/bin/arc run -- $path "\$@"
EOF
    chmod 755 "$dest"
}

# Riscrive un .desktop del layer per l'host
_rewrite_desktop() {
    local src=$1 dest=$2 icon=${3:-}
    awk -v pfx="/usr/bin/arc run -- " -v icon="$icon" '
        /^\[/                       { main = ($0 == "[Desktop Entry]"); print; next }
        /^Exec=/                    { sub(/^Exec=/, "Exec=" pfx); print; next }
        /^TryExec=/                 { next }
        /^DBusActivatable=/         { next }
        main && /^Icon=/ && icon != "" { print "Icon=" icon; next }
        main && /^Name(\[[^]]*\])?=/ { print $0 " (Debian)"; next }
        { print }
    ' "$src" > "$dest"
    chmod 644 "$dest"
}

# Copia le icone di nome $1 dal layer; stampa i file creati
_export_icons() {
    local name=$1 r=$ARC_DEBIAN_ROOT f rel dest
    [[ -n $name ]] || return 0
    while IFS= read -r f; do
        rel=${f#"$r"/usr/share/}
        dest="$(_exp_share)/$rel"
        _dest_taken "$dest" && continue
        install -Dm644 "$f" "$dest"
        printf '%s\n' "$dest"
    done < <(find "$r/usr/share/icons/hicolor" "$r/usr/share/pixmaps" \
                  \( -name "$name.png" -o -name "$name.svg" -o -name "$name.svgz" -o -name "$name.xpm" \) \
                  -type f 2>/dev/null)
}

export_pkg() {
    local pkg=$1 r=$ARC_DEBIAN_ROOT rec tmp f name dest icon newicon real
    local edir
    edir=$(_exp_dir)
    mkdir -p "$edir"
    rec="$edir/$pkg.list"
    tmp=$(mktemp)
    while IFS= read -r f; do
        case $f in
            /usr/bin/*|/usr/games/*|/bin/*)
                real=$(_layer_path "$f")
                [[ -f $real && -x $real ]] || continue
                name=${f##*/}
                dest="$(_exp_bin)/$name"
                if _host_has_cmd "$name"; then
                    info "$name esiste già sull'host: non esportato (usa 'arc run $name')"
                    continue
                fi
                if _dest_taken "$dest"; then
                    info "$name è già esportato da un altro pacchetto: salto"
                    continue
                fi
                _write_bin_wrapper "$pkg" "$f" "$dest"
                printf '%s\n' "$dest" >> "$tmp"
                ;;
            /usr/share/applications/*.desktop)
                real=$(_layer_path "$f")
                [[ -f $real ]] || continue
                dest="$(_exp_apps)/arcbase-deb-${f##*/}"
                _dest_taken "$dest" && continue
                mkdir -p "${dest%/*}"
                icon=$(sed -n 's/^Icon=//p' "$real" | head -n1)
                newicon=
                if [[ $icon == /* ]]; then
                    icon=$(_layer_path "$icon")
                    newicon="$(_exp_share)/pixmaps/arcbase-deb-${icon##*/}"
                    if [[ -f $icon ]] && ! _dest_taken "$newicon"; then
                        install -Dm644 "$icon" "$newicon"
                        printf '%s\n' "$newicon" >> "$tmp"
                    elif [[ ! -f $icon ]]; then
                        newicon=
                    fi
                else
                    _export_icons "$icon" >> "$tmp"
                fi
                _rewrite_desktop "$real" "$dest" "$newicon"
                printf '%s\n' "$dest" >> "$tmp"
                ;;
        esac
    done < <(deb_pkg_files "$pkg")
    sort -u "$tmp" > "$rec"
    rm -f "$tmp"
    if [[ -s $rec ]]; then
        info "esportato $pkg ($(wc -l < "$rec") file)"
    fi
}

unexport_pkg() {
    local pkg=$1 rec f
    rec="$(_exp_dir)/$pkg.list"
    [[ -f $rec ]] || return 0
    while IFS= read -r f; do
        # Rimuove solo file creati da arc (wrapper marcati o dentro il prefisso)
        [[ $f == "$ARC_EXPORT_PREFIX"/* ]] || continue
        rm -f -- "$f"
    done < "$rec"
    rm -f "$rec"
    info "rimosse le esportazioni di $pkg"
}

export_refresh_caches() {
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q "$(_exp_apps)" 2>/dev/null || :
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1 && [[ -d $(_exp_share)/icons/hicolor ]]; then
        gtk-update-icon-cache -q -t -f "$(_exp_share)/icons/hicolor" 2>/dev/null || :
    fi
}

# Un'esportazione è da rifare se il pacchetto è stato aggiornato dopo
# l'esportazione (il suo elenco dpkg è più recente) o se uno dei suoi wrapper
# ora nasconde un comando installato sull'host da pacman.
_export_stale() {
    local pkg=$1 rec info f
    rec="$(_exp_dir)/$pkg.list"
    info=$ARC_DEBIAN_ROOT/var/lib/dpkg/info
    for f in "$info/$pkg.list" "$info/$pkg:$(deb_arch).list"; do
        [[ -e $f && $f -nt $rec ]] && return 0
    done
    while IFS= read -r f; do
        [[ $f == "$(_exp_bin)"/* ]] && _host_has_cmd "${f##*/}" && return 0
    done < "$rec"
    return 1
}

# Allinea le esportazioni ai pacchetti installati nel layer
export_sync() {
    local p changed=0
    deb_ready || return 0
    local -a current desired
    mapfile -t current < <(export_current)
    mapfile -t desired < <(export_desired)
    # rimossi o esclusi
    while IFS= read -r p; do
        [[ -n $p ]] || continue
        unexport_pkg "$p"; changed=1
    done < <(comm -23 <(printf '%s\n' "${current[@]}" | sed '/^$/d') <(printf '%s\n' "${desired[@]}" | sed '/^$/d'))
    # aggiornati o in conflitto con l'host
    while IFS= read -r p; do
        [[ -n $p ]] || continue
        if _export_stale "$p"; then
            unexport_pkg "$p"; export_pkg "$p"; changed=1
        fi
    done < <(comm -12 <(printf '%s\n' "${current[@]}" | sed '/^$/d') <(printf '%s\n' "${desired[@]}" | sed '/^$/d'))
    # nuovi
    while IFS= read -r p; do
        [[ -n $p ]] || continue
        export_pkg "$p"; changed=1
    done < <(comm -13 <(printf '%s\n' "${current[@]}" | sed '/^$/d') <(printf '%s\n' "${desired[@]}" | sed '/^$/d'))
    if (( changed )); then export_refresh_caches; fi
}

_list_add()    { mkdir -p "${1%/*}"; { cat "$1" 2>/dev/null; printf '%s\n' "$2"; } | sort -u > "$1.new" && mv "$1.new" "$1"; }
_list_remove() { [[ -f $1 ]] || return 0; grep -vxF -- "$2" "$1" > "$1.new" || :; mv "$1.new" "$1"; }

# `arc export <pkg>`: forza l'esportazione (anche di pacchetti di base)
export_force() {
    local p
    for p; do
        deb_installed "$p" || die "$p non è installato nel layer Debian"
        _list_add "$ARC_STATEDIR/export-force.list" "$p"
        _list_remove "$ARC_STATEDIR/export-deny.list" "$p"
        unexport_pkg "$p"
        export_pkg "$p"
    done
    export_refresh_caches
}

# `arc unexport <pkg>`: rimuove e non riesporta più
export_deny() {
    local p
    for p; do
        _list_add "$ARC_STATEDIR/export-deny.list" "$p"
        _list_remove "$ARC_STATEDIR/export-force.list" "$p"
        unexport_pkg "$p"
    done
    export_refresh_caches
}
