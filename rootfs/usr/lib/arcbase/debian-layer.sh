# shellcheck shell=bash
# =============================================================================
#  arc — gestione del layer Debian
#
#  Il layer è un root Debian completo (debootstrap) in $ARC_DEBIAN_ROOT,
#  gestito dal vero apt/dpkg di Debian. Viene eseguito:
#    * come root (apt, dpkg) con bubblewrap in lettura/scrittura, oppure con
#      chroot se siamo già dentro un chroot (build dell'immagine);
#    * come utente (applicazioni) con bubblewrap in sola lettura, condividendo
#      /home, /tmp, il display (X11/Wayland), D-Bus, PipeWire e /dev.
#  In questo modo le librerie Debian non toccano mai /usr dell'host gestito
#  da pacman: i due gestori non possono entrare in conflitto sui file.
# =============================================================================

deb_ready() { [[ -f $ARC_DEBIAN_ROOT/.arcbase-layer ]]; }

deb_require() {
    deb_ready || die "il layer Debian non è inizializzato: esegui 'sudo arc deb init'"
}

# Architettura Debian corrispondente a quella dell'host
deb_arch() {
    case $(uname -m) in
        x86_64)  echo amd64 ;;
        aarch64) echo arm64 ;;
        i?86)    echo i386 ;;
        *)       uname -m ;;
    esac
}

# Vero se il processo corrente è in un chroot (bubblewrap non funziona lì)
in_chroot() {
    local a b
    a=$(stat -Lc %d:%i / 2>/dev/null) || return 1
    b=$(stat -Lc %d:%i /proc/1/root/. 2>/dev/null) || return 1
    [[ $a != "$b" ]]
}

_deb_env() {
    printf '%s\n' \
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        "HOME=/root" "TERM=${TERM:-xterm}" "LANG=C.UTF-8" \
        "DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-}" \
        "APT_LISTCHANGES_FRONTEND=none"
}

# Esegue un comando come root dentro il layer (lettura/scrittura)
deb_root_exec() {
    local backend=${ARC_ROOT_BACKEND:-auto}
    if [[ $backend == auto ]]; then
        if in_chroot || ! command -v "$BWRAP" >/dev/null 2>&1; then
            backend=chroot
        else
            backend=bwrap
        fi
    fi
    local -a env
    mapfile -t env < <(_deb_env)
    if [[ $backend == chroot ]]; then
        _deb_chroot_exec "${env[@]}" -- "$@"
        return
    fi
    local resolv
    resolv=$(readlink -f /etc/resolv.conf 2>/dev/null || :)
    env -i "${env[@]}" "$BWRAP" \
        --bind "$ARC_DEBIAN_ROOT" / \
        --dev /dev --proc /proc --ro-bind /sys /sys \
        --tmpfs /tmp --tmpfs /run \
        ${resolv:+--ro-bind-try "$resolv" /etc/resolv.conf} \
        --die-with-parent \
        -- "$@"
}

# Backend chroot: monta i file system virtuali, esegue e smonta
_deb_chroot_exec() {
    local r=$ARC_DEBIAN_ROOT rc m
    local -a env=() mounted=()
    while [[ $1 != -- ]]; do env+=("$1"); shift; done
    shift
    for m in proc sys dev dev/pts; do mkdir -p "$r/$m"; done
    if ! mountpoint -q "$r/proc"; then mount -t proc proc "$r/proc" && mounted+=(proc); fi
    if ! mountpoint -q "$r/sys";  then mount -t sysfs sysfs "$r/sys" && mounted+=(sys); fi
    if ! mountpoint -q "$r/dev";  then mount --bind /dev "$r/dev" && mounted+=(dev); fi
    if ! mountpoint -q "$r/dev/pts"; then mount --bind /dev/pts "$r/dev/pts" && mounted+=(dev/pts); fi
    cp -L /etc/resolv.conf "$r/etc/resolv.conf" 2>/dev/null || :
    env -i "${env[@]}" chroot "$r" "$@"
    rc=$?
    for (( m = ${#mounted[@]} - 1; m >= 0; m-- )); do
        umount "$r/${mounted[m]}" 2>/dev/null || umount -l "$r/${mounted[m]}"
    done
    return $rc
}

# Esegue un comando come utente corrente nel layer (sola lettura): usato per
# lanciare le applicazioni Debian e per le interrogazioni (apt-cache, ...).
deb_user_exec() {
    local r=$ARC_DEBIAN_ROOT resolv dir
    local -a a=(
        --ro-bind "$r" /
        --dev-bind /dev /dev
        --proc /proc
        --ro-bind /sys /sys
        --bind /tmp /tmp
        --tmpfs /run
        --ro-bind-try /run/dbus /run/dbus
        --ro-bind-try /run/systemd/resolve /run/systemd/resolve
        --bind-try /run/media /run/media
        --setenv ARCBASE_LAYER debian
        --setenv debian_chroot arcbase-debian
        --die-with-parent
    )
    # Il layer è montato in sola lettura: bwrap non può creare i punti di
    # montaggio, quindi si monta solo dove la destinazione esiste già.
    _ubind() {  # _ubind <opzione> <sorgente> <destinazione>
        [[ -e $2 && -e $r$3 ]] && a+=("$1" "$2" "$3")
        return 0
    }
    resolv=$(readlink -f /etc/resolv.conf 2>/dev/null || :)
    [[ -n $resolv ]] && _ubind --ro-bind "$resolv" /etc/resolv.conf
    _ubind --ro-bind /etc/passwd /etc/passwd
    _ubind --ro-bind /etc/group /etc/group
    _ubind --ro-bind /etc/hosts /etc/hosts
    _ubind --ro-bind /etc/hostname /etc/hostname
    _ubind --ro-bind /etc/machine-id /etc/machine-id
    _ubind --bind /var/tmp /var/tmp
    _ubind --bind /home /home
    _ubind --bind /media /media
    _ubind --bind /mnt /mnt
    _ubind --ro-bind /usr/share/fonts /usr/local/share/fonts
    if [[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR ]]; then
        a+=(--bind "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR")
    fi
    if [[ -n ${HOME:-} && -d $HOME && $HOME != /home/* ]]; then
        _ubind --bind "$HOME" "$HOME"
    fi
    # Fuso orario dell'host (/etc/localtime è un link simbolico)
    if [[ -L /etc/localtime ]]; then
        a+=(--setenv TZ "$(readlink /etc/localtime | sed 's|^.*zoneinfo/||')")
    fi
    # Directory di lavoro: solo se esiste anche dentro il layer
    dir=$PWD
    case $dir in
        /home/*|/tmp/*|/tmp|/media/*|/mnt/*|/run/media/*|"${HOME:-/nonexistent}"*) ;;
        *) dir=${HOME:-/} ;;
    esac
    # La home fuori da /home è montata solo se esiste un punto di montaggio
    if [[ -n ${HOME:-} && $HOME != /home/* && $dir == "$HOME"* && ! -e $r$HOME ]]; then
        dir=/
    fi
    a+=(--chdir "$dir")
    "$BWRAP" "${a[@]}" -- "$@"
}

# Interrogazioni: root o utente a seconda di chi chiama
deb_exec() {
    if [[ $EUID -eq 0 ]]; then deb_root_exec "$@"; else deb_user_exec "$@"; fi
}

# --- Lettura diretta del database dpkg (nessun processo nel layer) ------------

deb_installed_pkgs() {
    local status=$ARC_DEBIAN_ROOT/var/lib/dpkg/status
    [[ -r $status ]] || return 0
    awk '
        /^Package:/ { p = $2 }
        /^Status:/  { s = $0 }
        /^$/        { if (p != "" && s ~ / installed$/) print p; p = ""; s = "" }
        END         { if (p != "" && s ~ / installed$/) print p }
    ' "$status" | sort -u
}

deb_auto_pkgs() {
    local ext=$ARC_DEBIAN_ROOT/var/lib/apt/extended_states
    [[ -r $ext ]] || return 0
    awk '
        /^Package:/        { p = $2 }
        /^Auto-Installed:/ { if ($2 == 1) print p }
    ' "$ext" | sort -u
}

# Pacchetti installati manualmente (= non come dipendenza)
deb_manual_pkgs() {
    comm -23 <(deb_installed_pkgs) <(deb_auto_pkgs)
}

# Pacchetti installati dall'utente (esclusi quelli del bootstrap iniziale)
deb_user_pkgs() {
    local base=$ARC_STATEDIR/debian-baseline.list
    if [[ -r $base ]]; then
        comm -23 <(deb_manual_pkgs) <(sort -u "$base")
    else
        deb_manual_pkgs
    fi
}

deb_installed() {
    # Niente "grep -q": con pipefail, l'uscita anticipata di grep fa ricevere
    # SIGPIPE ai comandi a monte e la pipeline risulterebbe fallita.
    deb_installed_pkgs | grep -xF -- "$1" >/dev/null
}

deb_pkg_version() {
    awk -v pkg="$1" '
        /^Package:/ { p = $2 }
        /^Version:/ { if (p == pkg) { print $2; exit } }
    ' "$ARC_DEBIAN_ROOT/var/lib/dpkg/status"
}

# Elenco dei file di un pacchetto installato nel layer
deb_pkg_files() {
    local info=$ARC_DEBIAN_ROOT/var/lib/dpkg/info
    cat "$info/$1.list" "$info/$1:$(deb_arch).list" 2>/dev/null || :
}

# --- Creazione del layer ---------------------------------------------------------

layer_init() {
    local r=$ARC_DEBIAN_ROOT suite=$ARC_DEBIAN_SUITE lang
    if deb_ready; then
        msg "Il layer Debian è già inizializzato in $r"
        return 0
    fi
    command -v debootstrap >/dev/null 2>&1 || die "debootstrap non trovato"
    [[ -r $ARC_DEBIAN_KEYRING ]] || die "keyring Debian mancante: $ARC_DEBIAN_KEYRING"
    [[ -n $r && $r != / ]] || die "ARC_DEBIAN_ROOT non valido: '$r'"

    msg "Creazione del layer Debian '$suite' in $r"
    mkdir -p "$r" "$ARC_STATEDIR"
    ARC_SHIM_DISABLE=1 debootstrap \
        --arch="$(deb_arch)" \
        --variant=minbase \
        --keyring="$ARC_DEBIAN_KEYRING" \
        --include="$ARC_DEBIAN_INCLUDE" \
        "$suite" "$r" "$ARC_DEBIAN_MIRROR" \
        || die "debootstrap fallito (il log è in $r/debootstrap/debootstrap.log)"

    info "configurazione di apt"
    rm -f "$r/etc/apt/sources.list"
    mkdir -p "$r/etc/apt/sources.list.d"
    {
        printf 'Types: deb\nURIs: %s\n' "$ARC_DEBIAN_MIRROR"
        if [[ $suite == sid || $suite == unstable ]]; then
            printf 'Suites: %s\n' "$suite"
        else
            printf 'Suites: %s %s-updates\n' "$suite" "$suite"
        fi
        printf 'Components: %s\n' "$ARC_DEBIAN_COMPONENTS"
        printf 'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg\n'
        if [[ $suite != sid && $suite != unstable ]]; then
            printf '\nTypes: deb\nURIs: %s\n' "$ARC_DEBIAN_SECURITY_MIRROR"
            printf 'Suites: %s-security\n' "$suite"
            printf 'Components: %s\n' "$ARC_DEBIAN_COMPONENTS"
            printf 'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg\n'
        fi
    } > "$r/etc/apt/sources.list.d/debian.sources"
    if [[ ! -e $r/usr/share/keyrings/debian-archive-keyring.gpg ]]; then
        install -Dm644 "$ARC_DEBIAN_KEYRING" "$r/usr/share/keyrings/debian-archive-keyring.gpg"
    fi

    info "nessun servizio viene avviato dentro il layer"
    cat > "$r/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
# Arcbase Desktop: i servizi non vengono mai avviati nel layer Debian
exit 101
EOF
    chmod 755 "$r/usr/sbin/policy-rc.d"

    # /etc/resolv.conf viene montato a runtime: deve essere un file regolare
    rm -f "$r/etc/resolv.conf"
    cp -L /etc/resolv.conf "$r/etc/resolv.conf" 2>/dev/null || : > "$r/etc/resolv.conf"
    # Punti di montaggio usati da deb_user_exec (il layer è in sola lettura)
    mkdir -p "$r/usr/local/share/fonts" "$r/media" "$r/mnt" "$r/home" "$r/var/tmp" "$r/root"
    local f
    for f in machine-id hosts hostname passwd group; do
        [[ -e $r/etc/$f ]] || : > "$r/etc/$f"
    done

    lang=${ARC_LOCALE:-${LANG:-C.UTF-8}}
    if [[ $lang != C.* && $lang != C && $lang != POSIX && -f $r/etc/locale.gen ]]; then
        info "locale $lang"
        if grep -q "^# *$lang " "$r/etc/locale.gen"; then
            sed -i "s/^# *\($lang \)/\1/" "$r/etc/locale.gen"
        else
            echo "$lang UTF-8" >> "$r/etc/locale.gen"
        fi
        deb_root_exec locale-gen || warn "locale-gen fallito"
        echo "LANG=$lang" > "$r/etc/default/locale"
    fi

    info "aggiornamento degli indici"
    deb_root_exec apt-get update || warn "apt-get update fallito"

    deb_manual_pkgs > "$ARC_STATEDIR/debian-baseline.list"
    printf 'suite=%s\ncreated=%s\n' "$suite" "$(date -u +%FT%TZ)" > "$r/.arcbase-layer"
    msg "Layer Debian pronto: usa 'arc install --deb <pacchetto>' oppure 'apt install'"
}

layer_status() {
    local r=$ARC_DEBIAN_ROOT
    if ! deb_ready; then
        echo "Layer Debian: non inizializzato (sudo arc deb init)"
        return 1
    fi
    echo "Layer Debian:     $r"
    sed 's/^/  /' "$r/.arcbase-layer"
    echo "Pacchetti:        $(deb_installed_pkgs | wc -l) installati, $(deb_user_pkgs | wc -l) dell'utente"
    echo "App esportate:    $(find "$ARC_STATEDIR/exports" -name '*.list' 2>/dev/null | wc -l) pacchetti"
    echo "Spazio occupato:  $(du -sh "$r" 2>/dev/null | cut -f1)"
}

layer_reset() {
    local r=$ARC_DEBIAN_ROOT p
    deb_ready || die "nessun layer Debian da rimuovere"
    [[ -n $r && $r != / && -f $r/.arcbase-layer ]] || die "percorso del layer non valido: $r"
    for p in $(export_current); do unexport_pkg "$p"; done
    export_refresh_caches
    rm -rf --one-file-system "$r"
    rm -f "$ARC_STATEDIR/debian-baseline.list"
    msg "Layer Debian rimosso"
}
