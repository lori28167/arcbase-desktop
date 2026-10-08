#!/bin/bash
# =============================================================================
#  Test di 'arc' e degli strumenti arcbase-* senza un sistema Arcbase reale.
#
#  pacman, bubblewrap (e quindi apt/dpkg nel layer) e vercmp sono sostituiti da
#  mock che registrano le chiamate e simulano i database: si verificano la
#  scelta del backend, l'installazione mista Arch+Debian, l'esportazione delle
#  app Debian (wrapper, .desktop, icone), lo shim apt/dpkg, arcbase-mkbase e
#  arcbase-runtime-sync. Non richiede root né rete.
# =============================================================================
set -o nounset -o pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap '[[ -n ${KEEP:-} ]] || rm -rf "$T"' EXIT

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  \e[32m✔\e[0m %s\n' "$1"; }
ko()   { fail=$((fail + 1)); printf '  \e[31m✘\e[0m %s\n' "$1"; [[ -n ${2:-} ]] && printf '      %s\n' "$2"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else ko "$d"; fi; }
has()   { grep -qF -- "$2" "$1" 2>/dev/null; }
hasnt() { ! grep -qF -- "$2" "$1" 2>/dev/null; }

# --- Ambiente simulato -------------------------------------------------------------
L=$T/debian            # layer Debian
mkdir -p "$T/bin" "$T/state/exports" "$T/local" "$T/pkgfiles" \
         "$L/var/lib/dpkg/info" "$L/var/lib/apt" \
         "$L/usr/bin" "$L/usr/share/applications" "$L/usr/share/icons/hicolor/48x48/apps"
printf 'suite=trixie\n' > "$L/.arcbase-layer"
cat > "$L/var/lib/dpkg/status" <<'EOF'
Package: base-files
Status: install ok installed
Version: 13

Package: bash
Status: install ok installed
Version: 5.2

EOF
: > "$L/var/lib/apt/extended_states"
printf 'base-files\nbash\n' > "$T/state/debian-baseline.list"

printf 'firefox\nvlc\nglibc\ngcc-libs\n' > "$T/arch-available"
printf 'firefox\n' > "$T/arch-installed"
printf 'glibc\nzlib\n' > "$T/arch-provided"
printf 'foo\nlibfoo\nfakels\n' > "$T/deb-available"
echo '2.99+r1-1' > "$T/arch-version-glibc"
echo '14.2.0-1'  > "$T/arch-version-gcc-libs"

# Pacchetto Debian "foo": un eseguibile, un .desktop, un'icona
printf '#!/bin/sh\necho foo\n' > "$L/usr/bin/foo"; chmod +x "$L/usr/bin/foo"
echo PNG > "$L/usr/share/icons/hicolor/48x48/apps/foo.png"
cat > "$L/usr/share/applications/foo.desktop" <<'EOF'
[Desktop Entry]
Name=Foo
Name[it]=Pippo
Exec=foo %U
TryExec=foo
Icon=foo
DBusActivatable=true
Type=Application
Actions=new;

[Desktop Action new]
Name=New Window
Exec=foo --new
EOF
printf '/usr/bin/foo\n/usr/share/applications/foo.desktop\n/usr/share/icons/hicolor/48x48/apps/foo.png\n' > "$T/pkgfiles/foo"
# Pacchetto "fakels": fornisce /usr/bin/ls, che esiste già sull'host
printf '#!/bin/sh\n' > "$L/usr/bin/ls"; chmod +x "$L/usr/bin/ls"
printf '#!/bin/sh\n' > "$L/usr/bin/fakels-tool"; chmod +x "$L/usr/bin/fakels-tool"
printf '/usr/bin/ls\n/usr/bin/fakels-tool\n' > "$T/pkgfiles/fakels"
: > "$T/pkgfiles/libfoo"

# --- Mock --------------------------------------------------------------------------
cat > "$T/bin/pacman" <<'EOF'
#!/bin/bash
D=$(cd "$(dirname "$0")/.." && pwd)
echo "$*" >> "$D/pacman.log"
op=$1; shift
pkg=${*: -1}
case $op in
    -S)   [[ -e $D/pacman-fail ]] && exit 1; exit 0 ;;
    -Si)  grep -qx -- "$pkg" "$D/arch-available" || exit 1
          printf 'Name            : %s\n' "$pkg"
          [[ -f $D/arch-version-$pkg ]] && printf 'Version         : %s\n' "$(cat "$D/arch-version-$pkg")"
          exit 0 ;;
    -Sg)  exit 1 ;;
    -Qq|-Q|-Qi) grep -qx -- "$pkg" "$D/arch-installed" ;;
    -T)   grep -qx -- "$pkg" "$D/arch-provided" ;;
    -Qe)  sed 's/$/ 1.0-1/' "$D/arch-installed" ;;
    -Ss)  grep -- "$pkg" "$D/arch-available" | sed 's|^|extra/|' ;;
    *)    exit 0 ;;
esac
EOF
cat > "$T/bin/bwrap" <<'EOF'
#!/bin/bash
# Mock di bubblewrap: ignora le opzioni e simula apt/dpkg nel layer
D=$(cd "$(dirname "$0")/.." && pwd)
L=$D/debian
mode=user
echo "$*" >> "$D/bwrap-args.log"
while [[ $# -gt 0 && $1 != -- ]]; do
    [[ $1 == --bind && ${3:-} == / ]] && mode=root
    shift
done
shift
echo "[$mode] $*" >> "$D/bwrap.log"
cmd=$1; shift
install_pkg() {
    printf 'Package: %s\nStatus: install ok installed\nVersion: 1.0\n\n' "$1" >> "$L/var/lib/dpkg/status"
    cp "$D/pkgfiles/$1" "$L/var/lib/dpkg/info/$1.list" 2>/dev/null || :
}
remove_pkg() {
    awk -v p="$1" 'BEGIN{RS=""; ORS="\n\n"} $0 !~ ("Package: " p "\n") {print}' \
        "$L/var/lib/dpkg/status" > "$L/status.new" && mv "$L/status.new" "$L/var/lib/dpkg/status"
    rm -f "$L/var/lib/dpkg/info/$1.list"
}
case $cmd in
    apt-cache)
        sub=$1; shift
        [[ ${1:-} == --no-all-versions ]] && shift
        case $sub in
            show)   grep -qx -- "$1" "$D/deb-available" && { echo "Package: $1"; exit 0; }; exit 100 ;;
            search) grep -- "$1" "$D/deb-available" | sed 's/$/ - pacchetto di prova/' ;;
        esac ;;
    apt-get|apt)
        sub=$1; shift
        for a; do
            [[ $a == -* ]] && continue
            p=${a##*/}; p=${p%%_*}; p=${p%.deb}
            case $sub in
                install) install_pkg "$p" ;;
                remove)  remove_pkg "$p" ;;
            esac
        done ;;
esac
exit 0
EOF
cat > "$T/bin/vercmp" <<'EOF'
#!/bin/bash
[[ $1 == "$2" ]] && { echo 0; exit; }
[[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1) == "$2" ]] && echo 1 || echo -1
EOF
chmod +x "$T/bin/"*
ln -s "$REPO/rootfs/usr/bin/arc" "$T/bin/arc"
for s in apt-get dpkg; do ln -s "$REPO/rootfs/usr/bin/arc" "$T/bin/$s"; done

export PATH="$T/bin:$REPO/rootfs/usr/bin:$PATH"
export ARC_CONF=/nonexistent ARC_LIBDIR="$REPO/rootfs/usr/lib/arcbase"
export ARC_STATEDIR="$T/state" ARC_DEBIAN_ROOT="$L" ARC_EXPORT_PREFIX="$T/local"
export ARC_PACMAN="$T/bin/pacman" ARC_BWRAP="$T/bin/bwrap" ARC_ROOT_BACKEND=bwrap
export ARC_ASSUME_ROOT=1 ARC_PREFER=arch
# Comandi "dell'host": quelli veri più una directory controllata dai test
mkdir -p "$T/hostbin"
export ARC_HOST_BIN_DIRS="$T/hostbin /usr/bin /bin"

# --- Test --------------------------------------------------------------------------
echo "arc: risoluzione dell'origine"
out=$(arc origin firefox vlc foo glibc nonexiste 2>&1)
check "firefox installato da Arch"          grep -q 'firefox: installato da Arch' <<<"$out"
check "vlc disponibile in Arch"             grep -q 'vlc: non installato, disponibile in Arch' <<<"$out"
check "foo disponibile in Debian"           grep -q 'foo: non installato, disponibile in Debian' <<<"$out"
check "glibc fornito dal base LFS"          grep -q 'glibc: sistema base LFS' <<<"$out"
check "pacchetto inesistente"               grep -q 'nonexiste: non trovato' <<<"$out"

echo "arc install: pacchetti misti Arch + Debian"
arc install -y vlc foo >/dev/null 2>&1
check "pacman -S chiamato per vlc"          has "$T/pacman.log" "-S --needed --noconfirm -- vlc"
check "apt-get install chiamato per foo"    has "$T/bwrap.log" "[root] apt-get install -y foo"
check "foo non passato a pacman"            hasnt "$T/pacman.log" "-- vlc foo"

echo "esportazione delle app Debian"
W=$T/local/bin/foo
D=$T/local/share/applications/arcbase-deb-foo.desktop
check "wrapper creato"                      test -x "$W"
check "wrapper marcato da arc"              has "$W" "# arcbase-export: foo"
check "wrapper usa arc run"                 has "$W" 'exec /usr/bin/arc run -- /usr/bin/foo "$@"'
check ".desktop esportato"                  test -f "$D"
check "Exec riscritto"                      has "$D" "Exec=/usr/bin/arc run -- foo %U"
check "Exec delle azioni riscritto"         has "$D" "Exec=/usr/bin/arc run -- foo --new"
check "nome con suffisso (Debian)"          has "$D" "Name=Foo (Debian)"
check "nome localizzato con suffisso"       has "$D" "Name[it]=Pippo (Debian)"
check "nome delle azioni invariato"         has "$D" "Name=New Window"
check "TryExec rimosso"                     hasnt "$D" "TryExec"
check "DBusActivatable rimosso"             hasnt "$D" "DBusActivatable"
check "icona copiata"                       test -f "$T/local/share/icons/hicolor/48x48/apps/foo.png"
check "registro delle esportazioni"         test -s "$T/state/exports/foo.list"

echo "comandi dell'host mai sovrascritti"
arc install -y --deb fakels >/dev/null 2>&1
check "ls dell'host non esportato"          test ! -e "$T/local/bin/ls"
check "fakels-tool esportato"               test -x "$T/local/bin/fakels-tool"

echo "arc list / search"
out=$(arc list 2>&1)
check "list mostra firefox [arch]"          grep -q 'arch.*firefox' <<<"$out"
check "list mostra foo [debian]"            grep -q 'debian.*foo 1.0' <<<"$out"
check "list esclude il bootstrap Debian"    bash -c '! grep -q "bash 5.2" <<<"$0"' "$out"
out=$(arc search fire 2>&1)
check "search interroga Arch"               grep -q 'extra/firefox' <<<"$out"
out=$(arc search foo 2>&1)
check "search interroga Debian"             grep -q 'foo - pacchetto di prova' <<<"$out"

echo "arc unexport / export"
arc unexport foo >/dev/null 2>&1
check "unexport rimuove il wrapper"         test ! -e "$W"
check "unexport rimuove il .desktop"        test ! -e "$D"
arc export >/dev/null 2>&1
check "sync rispetta l'esclusione"          test ! -e "$W"
arc export foo >/dev/null 2>&1
check "export forzato ricrea il wrapper"    test -x "$W"

echo "arc remove"
arc remove -y foo vlc >/dev/null 2>&1
check "apt-get remove per foo"              has "$T/bwrap.log" "[root] apt-get remove --autoremove -y foo"
check "pacman -Rs non chiamato per foo"     hasnt "$T/pacman.log" "-Rs --noconfirm -- foo"
check "esportazioni di foo rimosse"         test ! -e "$W"
arc remove -y arcbase-base >/dev/null 2>&1
check "arcbase-base protetto"               test $? -ne 0
printf 'vlc\n' >> "$T/arch-installed"
arc remove -y vlc >/dev/null 2>&1
check "pacman -Rs per vlc"                  has "$T/pacman.log" "-Rs --noconfirm -- vlc"

echo "pacchetti del sistema base"
printf 'glibc\n' >> "$T/arch-available"
: > "$T/pacman.log"
out=$(arc install -y glibc 2>&1)
check "install di un pacchetto del base: saltato" grep -q 'già fornito dal sistema base' <<<"$out"
check "pacman -S non chiamato per glibc"    hasnt "$T/pacman.log" "-S --needed --noconfirm -- glibc"
arc remove -y glibc >/dev/null 2>&1
check "remove di un pacchetto del base => errore" test $? -ne 0

echo "errori"
arc install -y nonexiste >/dev/null 2>&1
check "pacchetto inesistente => errore"     test $? -ne 0
ARC_DEBIAN_ROOT=$T/vuoto arc install -y --deb foo >/dev/null 2>&1
check "layer assente => errore"             test $? -ne 0

echo "shim apt-get / dpkg"
apt-get install -y libfoo >/dev/null 2>&1
check "apt-get inoltrato al layer (root)"   has "$T/bwrap.log" "[root] apt-get install -y libfoo"
deb=$T/bar_2.0_amd64.deb; echo x > "$deb"
dpkg -i "$deb" >/dev/null 2>&1
check ".deb locale copiato nel layer"       test -f "$L/var/cache/arcbase-local/bar_2.0_amd64.deb"
check "dpkg riceve il percorso nel layer"   has "$T/bwrap.log" "[root] dpkg -i /var/cache/arcbase-local/bar_2.0_amd64.deb"
ARC_ASSUME_ROOT=0 apt-get moo >/dev/null 2>&1 || :
if [[ $EUID -ne 0 ]]; then
    check "utente normale => esecuzione utente" has "$T/bwrap.log" "[user] apt-get moo"
fi

echo "arcbase-mkbase"
mkdir -p "$T/etc"
printf 'glibc=2.41\ngcc-libs=14.2.0\nzlib=1.3.1\nlibz.so=1-64\n# commento\n' > "$T/provides.list"
printf 'gcc-libs\n' > "$T/adopted.list"
out=$(ARC_BASE_PROVIDES=$T/provides.list ARC_ADOPTED=$T/adopted.list "$REPO/rootfs/usr/bin/arcbase-mkbase" --print)
check "pkgname arcbase-base"                grep -q '^pkgname = arcbase-base' <<<"$out"
check "provides glibc"                      grep -q '^provides = glibc=2.41' <<<"$out"
check "provides soname"                     grep -q '^provides = libz.so=1-64' <<<"$out"
check "pacchetti adottati esclusi"          bash -c '! grep -q gcc-libs <<<"$0"' "$out"
check "commenti ignorati"                   bash -c '! grep -q commento <<<"$0"' "$out"

echo "arcbase-runtime-sync --check"
: > "$T/adopted.list"
out=$(ARC_BASE_PROVIDES=$T/provides.list ARC_ADOPTED=$T/adopted.list \
      ARC_RUNTIME_SYNC_PKGS="glibc gcc-libs" arcbase-runtime-sync --check)
check "glibc più recente in Arch => adottato"  grep -qw glibc <<<"$out"
check "gcc-libs uguale => non adottato"         bash -c '! grep -qw gcc-libs <<<"$0"' "$out"

echo "arcbase-runtime-sync: adozione transazionale"
cat > "$T/bin/arcbase-mkbase" <<'EOF2'
#!/bin/bash
D=$(cd "$(dirname "$0")/.." && pwd)
echo "mkbase adopted=[$(paste -sd, "$ARC_ADOPTED" 2>/dev/null)]" >> "$D/mkbase.log"
EOF2
chmod +x "$T/bin/arcbase-mkbase"
: > "$T/adopted.list"; : > "$T/mkbase.log"; touch "$T/pacman-fail"
ARC_BASE_PROVIDES=$T/provides.list ARC_ADOPTED=$T/adopted.list ARC_RUNTIME_SYNC_PKGS=glibc \
    arcbase-runtime-sync --noconfirm >/dev/null 2>&1
check "pacman fallito => errore"                test $? -ne 0
check "adopted.list invariata"                  test ! -s "$T/adopted.list"
check "arcbase-base senza glibc, poi ripristinato" \
    bash -c '[[ $(sed -n 1p "$1") == "mkbase adopted=[glibc]" && $(sed -n 2p "$1") == "mkbase adopted=[]" ]]' _ "$T/mkbase.log"
rm -f "$T/pacman-fail"
ARC_BASE_PROVIDES=$T/provides.list ARC_ADOPTED=$T/adopted.list ARC_RUNTIME_SYNC_PKGS=glibc \
    arcbase-runtime-sync --noconfirm >/dev/null 2>&1
check "pacman riuscito => glibc adottata"       grep -qx glibc "$T/adopted.list"
rm -f "$T/bin/arcbase-mkbase"

echo "arcbase-abi-check"
out=$(printf 'usr/bin/ls\nusr/share/doc/nulla\n' | arcbase-abi-check --report)
check "binari dell'host senza problemi"     test $? -eq 0 -a -z "$out"

echo "layer con migliaia di pacchetti (pipefail + grep -q)"
cp "$L/var/lib/dpkg/status" "$T/status.bak"
printf 'Package: aaa-primo\nStatus: install ok installed\nVersion: 1\n\n' >> "$L/var/lib/dpkg/status"
awk 'BEGIN { for (i = 0; i < 30000; i++) printf "Package: zz-pkg%05d\nStatus: install ok installed\nVersion: 1\n\n", i }' \
    >> "$L/var/lib/dpkg/status"
out=$(arc origin aaa-primo 2>&1)
check "pacchetto trovato nonostante SIGPIPE"    grep -q 'installato nel layer Debian' <<<"$out"
cp "$T/status.bak" "$L/var/lib/dpkg/status"

echo "esportazioni: aggiornamento, conflitti, link assoluti"
arc install -y --deb foo >/dev/null 2>&1
check "foo riesportato"                         test -x "$T/local/bin/foo"
# aggiornamento del pacchetto: nuovo eseguibile e lista dpkg più recente
printf '#!/bin/sh\n' > "$L/usr/bin/foo-new"; chmod +x "$L/usr/bin/foo-new"
echo /usr/bin/foo-new >> "$T/pkgfiles/foo"
cp "$T/pkgfiles/foo" "$L/var/lib/dpkg/info/foo.list"
touch -d '1 hour ago' "$T/state/exports/foo.list"
arc export >/dev/null 2>&1
check "dopo l'upgrade il nuovo comando è esportato" test -x "$T/local/bin/foo-new"
# pacman installa un comando "foo" sull'host
printf '#!/bin/sh\n' > "$T/hostbin/foo"
arc export >/dev/null 2>&1
check "il wrapper che nasconde l'host è rimosso" test ! -e "$T/local/bin/foo"
check "gli altri comandi del pacchetto restano"  test -x "$T/local/bin/foo-new"
rm -f "$T/hostbin/foo"
# due pacchetti con lo stesso comando
printf '/usr/bin/fakels-tool\n' > "$T/pkgfiles/dup"; echo dup >> "$T/deb-available"
arc install -y --deb dup >/dev/null 2>&1
check "il wrapper resta del primo pacchetto"    has "$T/local/bin/fakels-tool" "# arcbase-export: fakels "
arc remove -y dup >/dev/null 2>&1
check "rimuovere il secondo non lo cancella"     test -x "$T/local/bin/fakels-tool"
# link simbolico assoluto dentro il layer
mkdir -p "$L/usr/share/code/bin"
printf '#!/bin/sh\n' > "$L/usr/share/code/bin/code"; chmod +x "$L/usr/share/code/bin/code"
ln -s /usr/share/code/bin/code "$L/usr/bin/code"
printf '/usr/bin/code\n' > "$T/pkgfiles/code"; echo code >> "$T/deb-available"
arc install -y --deb code >/dev/null 2>&1
check "link assoluto risolto nel layer"         test -x "$T/local/bin/code"

echo "pacchetto Debian con il nome di un componente del base"
echo vim >> "$T/arch-provided"; echo vim >> "$T/deb-available"; : > "$T/pkgfiles/vim"
arc install -y --deb vim >/dev/null 2>&1
check "origin: vim nel layer Debian"            grep -q 'installato nel layer Debian' <<<"$(arc origin vim)"
arc remove -y vim >/dev/null 2>&1
check "remove senza --deb lo rimuove da Debian" has "$T/bwrap.log" "[root] apt-get remove --autoremove -y vim"

echo "bubblewrap: punti di montaggio nel layer in sola lettura"
rm -f "$L/etc/machine-id"; : > "$T/bwrap-args.log"
arc run true >/dev/null 2>&1
check "nessun bind su /etc/machine-id mancante" hasnt "$T/bwrap-args.log" "/etc/machine-id"
mkdir -p "$L/etc"; : > "$L/etc/machine-id"; : > "$T/bwrap-args.log"
arc run true >/dev/null 2>&1
check "bind su /etc/machine-id se esiste"       has "$T/bwrap-args.log" "--ro-bind /etc/machine-id /etc/machine-id"

echo "arc deb init (debootstrap simulato)"
cat > "$T/bin/debootstrap" <<'EOF'
#!/bin/bash
D=$(cd "$(dirname "$0")/.." && pwd)
echo "$*" > "$D/debootstrap.args"
r=${*: -2:1}
mkdir -p "$r"/{etc/apt/sources.list.d,etc/default,usr/sbin,var/lib/dpkg,var/lib/apt}
echo 'deb http://old main' > "$r/etc/apt/sources.list"
printf '# it_IT.UTF-8 UTF-8\n# en_US.UTF-8 UTF-8\n' > "$r/etc/locale.gen"
printf 'Package: apt\nStatus: install ok installed\nVersion: 3.0\n\n' > "$r/var/lib/dpkg/status"
EOF
chmod +x "$T/bin/debootstrap"
echo key > "$T/keyring.gpg"
N=$T/nuovo
ARC_DEBIAN_ROOT=$N ARC_DEBIAN_KEYRING=$T/keyring.gpg ARC_LOCALE=it_IT.UTF-8 \
    ARC_DEBIAN_SUITE=trixie arc deb init >/dev/null 2>&1
check "debootstrap minbase/amd64"           has "$T/debootstrap.args" "--arch=amd64 --variant=minbase"
check "debootstrap con keyring"             has "$T/debootstrap.args" "--keyring=$T/keyring.gpg"
check "layer marcato come pronto"           test -f "$N/.arcbase-layer"
check "sources.list legacy rimosso"         test ! -e "$N/etc/apt/sources.list"
check "sorgenti deb822 con security"        has "$N/etc/apt/sources.list.d/debian.sources" "Suites: trixie-security"
check "sorgenti con updates"                has "$N/etc/apt/sources.list.d/debian.sources" "Suites: trixie trixie-updates"
check "policy-rc.d blocca i servizi"        has "$N/usr/sbin/policy-rc.d" "exit 101"
check "locale abilitata"                    has "$N/etc/locale.gen" "it_IT.UTF-8 UTF-8"
check "locale-gen eseguito nel layer"       has "$T/bwrap.log" "[root] locale-gen"
check "baseline registrata"                 has "$T/state/debian-baseline.list" "apt"
check "punto di montaggio dei font"         test -d "$N/usr/local/share/fonts"
check "machine-id creato come punto di montaggio" test -e "$N/etc/machine-id"

echo
echo "Risultato: $pass superati, $fail falliti"
(( fail == 0 ))
