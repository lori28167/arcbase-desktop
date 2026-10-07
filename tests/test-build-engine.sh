#!/bin/bash
# =============================================================================
#  Test del motore di build (scripts/lib/common.sh) senza compilare nulla:
#  registro dei sorgenti, estrazione, esecuzione delle ricette con errexit,
#  stamp per la ripresa, log e fallimenti.
# =============================================================================
set -o nounset -o pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0 fail=0
ok() { pass=$((pass + 1)); printf '  \e[32m✔\e[0m %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf '  \e[31m✘\e[0m %s\n' "$1"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else ko "$d"; fi; }

# Copia dell'albero con un packages.conf di prova
mkdir -p "$T/tree" "$T/lfs/sources"
cp -a "$REPO/config" "$REPO/scripts" "$T/tree/"
cat > "$T/tree/config/packages.conf" <<'EOF'
# prova
hello   1.2.3  https://example.org/hello-@V@.tar.gz
broken  0.1    https://example.org/broken-@V@.tar.gz
cert    2025   https://example.org/cert-@V@.pem?download=1
EOF
mkdir -p "$T/src/hello-1.2.3" "$T/src/broken-0.1"
echo 'ciao' > "$T/src/hello-1.2.3/README"
echo 'x' > "$T/src/broken-0.1/README"
tar -C "$T/src" -czf "$T/lfs/sources/hello-1.2.3.tar.gz" hello-1.2.3
tar -C "$T/src" -czf "$T/lfs/sources/broken-0.1.tar.gz" broken-0.1
echo PEM > "$T/lfs/sources/cert-2025.pem"

cat > "$T/tree/scripts/stage-test.sh" <<'EOF'
#!/bin/bash
STAGE=test
source "$(dirname "$0")/lib/common.sh"
build_hello() {
    test -f README
    echo "$(pkg_ver hello) $(cat README)" > "$LFS/hello.out"
}
build_broken() {
    false                       # deve interrompere la ricetta...
    touch "$LFS/broken.reached" # ...e questa riga non deve essere eseguita
}
build_cert() { cp cert-*.pem "$LFS/cert.out"; }
case ${1:-} in
    hello)  build hello ;;
    broken) build broken ;;
    cert)   build cert ;;
    url)    pkg_url hello; pkg_file cert ;;
esac
EOF
chmod +x "$T/tree/scripts/stage-test.sh"
run() { LFS=$T/lfs "$T/tree/scripts/stage-test.sh" "$@"; }

echo "registro dei sorgenti"
out=$(run url)
check "@V@ sostituito nell'URL"         grep -qx 'https://example.org/hello-1.2.3.tar.gz' <<<"$out"
check "query string esclusa dal file"   grep -qx "$T/lfs/sources/cert-2025.pem" <<<"$out"

echo "build riuscita"
run hello >/dev/null 2>&1
check "ricetta eseguita nella directory del sorgente" grep -qx '1.2.3 ciao' "$T/lfs/hello.out"
check "stamp creato"                    test -f "$T/lfs/sources/.arcbase-stamps/test-hello.done"
check "log creato"                      test -s "$T/lfs/sources/.arcbase-logs/test-hello.log"
check "directory di build ripulita"     test ! -e "$T/lfs/sources/build"
rm "$T/lfs/hello.out"
run hello >/dev/null 2>&1
check "pacchetto completato non ricompilato" test ! -e "$T/lfs/hello.out"

echo "file non-tarball"
run cert >/dev/null 2>&1
check "file copiato e ricetta eseguita" grep -qx PEM "$T/lfs/cert.out"

echo "build fallita"
run broken >/dev/null 2>&1
check "uscita con errore"               test $? -ne 0
check "errexit attivo nella ricetta"    test ! -e "$T/lfs/broken.reached"
check "nessuno stamp per il fallimento" test ! -e "$T/lfs/sources/.arcbase-stamps/test-broken.done"

echo
echo "Risultato: $pass superati, $fail falliti"
(( fail == 0 ))
