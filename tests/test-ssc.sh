#!/bin/bash
# =============================================================================
#  Test dell'integrazione del codec SSC (Galaxy Buds): voce in packages.conf,
#  ricetta dello stadio desktop, hook pacman, script di attivazione e comando
#  arcbase-ssc, tutti in una cartella di prova (nessun PipeWire vero).
#
#  La compilazione del plugin sul sistema Arcbase e la prova con le cuffie si
#  fanno nella ISO (make desktop, make iso). Non richiede root né rete; la
#  prova di `arcbase-ssc rebuild` usa un finto sorgente e serve meson, ninja e gcc.
# =============================================================================
set -o nounset -o pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
SSC=$REPO/rootfs/usr/bin/arcbase-ssc
ACT=$REPO/rootfs/usr/share/libalpm/scripts/arcbase-ssc-activate
HOOK=$REPO/rootfs/usr/share/libalpm/hooks/95-arcbase-ssc.hook
DESKTOP=$REPO/scripts/chroot/11-desktop.sh
T=$(mktemp -d)
trap '[[ -n ${KEEP:-} ]] || rm -rf "$T"' EXIT

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  \e[32m✔\e[0m %s\n' "$1"; }
ko()   { fail=$((fail + 1)); printf '  \e[31m✘\e[0m %s\n' "$1"; [[ -n ${2:-} ]] && printf '      %s\n' "$2"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else ko "$d"; fi; }
has()   { grep -qF -- "$2" "$1" 2>/dev/null; }
same()  { cmp -s "$1" "$2"; }

# --- Sorgente e ricetta -------------------------------------------------------------
echo "sorgente e ricetta"
read -r _ ver url sha < <(grep -E '^ssc[[:space:]]' "$REPO/config/packages.conf")
check "ssc in packages.conf: commit di 40 cifre esadecimali" bash -c '[[ $1 =~ ^[0-9a-f]{40}$ ]]' _ "$ver"
check "ssc in packages.conf: SHA-256 di 64 cifre"             bash -c '[[ $1 =~ ^[0-9a-f]{64}$ ]]' _ "$sha"
check "ssc: sorgente dal repository ufficiale, versione nell'URL" bash -c '[[ $1 == https://github.com/lori28167/SamsungScalableCodec-linux/archive/@V@.tar.gz ]]' _ "$url"
check "ARC_SSC in arcbase.conf (auto)"                       has "$REPO/config/arcbase.conf" ': "${ARC_SSC=auto}"'
check "ricetta build_ssc nello stadio desktop"               has "$DESKTOP" 'build_ssc() {'
check "lo stadio compila ssc solo con ARC_SSC"               bash -c 'grep -A3 "^if ssc_enabled" "$0" | grep -q "build ssc"' "$DESKTOP"
check "la ricetta scrive il sorgente per arcbase-ssc rebuild" has "$DESKTOP" '/usr/share/arcbase/ssc.conf'
check "la ricetta verifica che lo slot aptx sia preso"       has "$DESKTOP" 'non ha preso lo slot aptx'
check "pacchetti di build: pipewire-audio e bluez-libs"      has "$DESKTOP" 'pac -S --needed pipewire-audio bluez-libs'

# --- Hook pacman ------------------------------------------------------------------------
echo "hook pacman"
check "hook: dopo pipewire-audio (Install e Upgrade)"        bash -c 'grep -q "^Target = pipewire-audio" "$0" && grep -q "^Operation = Upgrade" "$0" && grep -q "^Operation = Install" "$0"' "$HOOK"
check "hook: PostTransaction"                                has "$HOOK" 'When = PostTransaction'
check "hook: esegue lo script di attivazione"                bash -c 'grep -q "^Exec = /usr/share/libalpm/scripts/arcbase-ssc-activate" "$0"' "$HOOK"
check "script di attivazione eseguibile"                     test -x "$ACT"
check "arcbase-ssc eseguibile"                               test -x "$SSC"

# --- Attivazione dopo un aggiornamento di pipewire-audio -----------------------------------
echo "attivazione (arcbase-ssc-activate)"
setup() {   # setup <cartella> <versione di PipeWire> <versione per cui è compilato il plugin>
    local d=$1
    rm -rf "$d"; mkdir -p "$d/ssc" "$d/spa" "$d/etc"
    printf 'Name: libpipewire-0.3\nVersion: %s\n' "$2" > "$d/pw.pc"
    printf 'plugin-ssc\n' > "$d/ssc/libspa-codec-bluez5-aptx.so"
    [[ -n ${3:-} ]] && printf '%s\n' "$3" > "$d/ssc/built-for"
    printf 'aptx-di-arch\n' > "$d/spa/libspa-codec-bluez5-aptx.so"
    return 0
}
act() {     # act <cartella>
    local d=$1
    SSC_DIR=$d/ssc SPA_DIR=$d/spa PW_PC=$d/pw.pc SSC_DISABLED=$d/etc/ssc.disabled "$ACT"
}
A=$T/a
setup "$A" 1.6.10 1.6.10
out=$(act "$A" 2>&1); rc=$?
check "stessa versione: esce senza errori"                   test $rc -eq 0
check "lo slot aptx prende il plugin SSC"                    same "$A/ssc/libspa-codec-bluez5-aptx.so" "$A/spa/libspa-codec-bluez5-aptx.so"
check "il plugin aptx di Arch viene conservato"              bash -c '[[ $(cat "$0") == aptx-di-arch ]]' "$A/ssc/aptx-arch.so"
check "nessun file temporaneo rimasto"                       bash -c '[[ $(find "$0" -type f | wc -l) -eq 1 ]]' "$A/spa"
check "avvisa di riavviare WirePlumber"                      bash -c 'grep -q wireplumber <<< "$0"' "$out"
act "$A" >/dev/null 2>&1
check "seconda esecuzione: idempotente (backup intatto)"     bash -c '[[ $(cat "$0") == aptx-di-arch ]]' "$A/ssc/aptx-arch.so"
# pacman aggiorna pipewire-audio: rimette il suo plugin, l'hook ripristina il nostro
printf 'aptx-di-arch-2\n' > "$A/spa/libspa-codec-bluez5-aptx.so"
act "$A" >/dev/null 2>&1
check "dopo l'aggiornamento il plugin SSC torna al suo posto" same "$A/ssc/libspa-codec-bluez5-aptx.so" "$A/spa/libspa-codec-bluez5-aptx.so"
check "il backup è quello della versione nuova"              bash -c '[[ $(cat "$0") == aptx-di-arch-2 ]]' "$A/ssc/aptx-arch.so"

B=$T/b
setup "$B" 1.7.0 1.6.10
out=$(act "$B" 2>&1); rc=$?
check "PipeWire diverso da quello del plugin: non lo attiva"  bash -c '[[ $(cat "$0") == aptx-di-arch ]]' "$B/spa/libspa-codec-bluez5-aptx.so"
check "...ma non è un errore (non blocca pacman)"             test $rc -eq 0
check "...e dice come ricompilarlo"                          bash -c 'grep -q "arcbase-ssc rebuild" <<< "$0"' "$out"
setup "$B" 1.6.10 ""
act "$B" >/dev/null 2>&1
check "senza built-for non attiva il plugin"                 bash -c '[[ $(cat "$0") == aptx-di-arch ]]' "$B/spa/libspa-codec-bluez5-aptx.so"
setup "$B" 1.6.10 1.6.10
touch "$B/etc/ssc.disabled"
act "$B" >/dev/null 2>&1
check "disattivato dall'utente: non attiva il plugin"        bash -c '[[ $(cat "$0") == aptx-di-arch ]]' "$B/spa/libspa-codec-bluez5-aptx.so"
setup "$B" 1.6.10 1.6.10
rm -f "$B/ssc/libspa-codec-bluez5-aptx.so"
check "plugin non installato: esce senza errori"             act "$B"
setup "$B" 1.6.10 1.6.10
rm -rf "$B/spa"
check "PipeWire senza cartella dei plugin: esce senza errori" act "$B"

# --- arcbase-ssc ---------------------------------------------------------------------------------
echo "arcbase-ssc"
ssc() {     # ssc <cartella> <argomenti>   (come root finto, sempre nella cartella di prova)
    local d=$1; shift
    ARC_ASSUME_ROOT=1 SSC_DIR=$d/ssc SPA_DIR=$d/spa PW_PC=$d/pw.pc SSC_DISABLED=$d/etc/ssc.disabled \
        SSC_ACTIVATE=$ACT SSC_CONF=$d/ssc.conf SSC_LICENSE_DIR=$d/lic "$SSC" "$@"
}
C=$T/c
setup "$C" 1.6.10 1.6.10
rm -f "$C/ssc/libspa-codec-bluez5-aptx.so"
out=$(ssc "$C" status)
check "status senza plugin: dice che non è installato"       bash -c '[[ $0 == *"non installato"* ]]' "$out"
setup "$C" 1.6.10 1.6.10
out=$(ssc "$C" status)
check "status: plugin non ancora attivo"                     bash -c '[[ $0 == *"non attivo: lo slot aptx è quello di Arch"* ]]' "$out"
ssc "$C" enable >/dev/null 2>&1
out=$(ssc "$C" status)
check "enable attiva il plugin"                              same "$C/ssc/libspa-codec-bluez5-aptx.so" "$C/spa/libspa-codec-bluez5-aptx.so"
check "status: attivo"                                       bash -c '[[ $0 == *"attivo (al posto di aptx)"* ]]' "$out"
ssc "$C" disable >/dev/null 2>&1
check "disable rimette il plugin aptx di Arch"               bash -c '[[ $(cat "$0") == aptx-di-arch ]]' "$C/spa/libspa-codec-bluez5-aptx.so"
check "disable lascia il segno (nessuna riattivazione)"      test -e "$C/etc/ssc.disabled"
act "$C" >/dev/null 2>&1
check "dopo disable l'hook non riattiva il plugin"           bash -c '[[ $(cat "$0") == aptx-di-arch ]]' "$C/spa/libspa-codec-bluez5-aptx.so"
out=$(ssc "$C" status)
check "status: disattivato"                                  bash -c '[[ $0 == *disattivato* ]]' "$out"
ssc "$C" enable >/dev/null 2>&1
check "enable toglie il segno e riattiva"                    bash -c '[[ ! -e $0/etc/ssc.disabled ]] && cmp -s $0/ssc/libspa-codec-bluez5-aptx.so $0/spa/libspa-codec-bluez5-aptx.so' "$C"
setup "$C" 1.7.0 1.6.10
out=$(ssc "$C" status)
check "status: PipeWire cambiato, serve rebuild"             bash -c '[[ $0 == *"compilato per PipeWire 1.6.10, installato 1.7.0 (arcbase-ssc rebuild)"* ]]' "$out"
if [[ $EUID -ne 0 ]]; then
    out=$(SSC_DIR=$C/ssc SPA_DIR=$C/spa PW_PC=$C/pw.pc "$SSC" enable 2>&1); rc=$?
    check "senza root: enable si rifiuta"                    bash -c '[[ $1 -ne 0 && $0 == *"serve root"* ]]' "$out" "$rc"
fi
"$SSC" bogus >/dev/null 2>&1; rc=$?
check "comando sconosciuto: errore d'uso (2)"                test $rc -eq 2
check "aiuto"                                                bash -c '"$0" help | grep -q "arcbase-ssc rebuild"' "$SSC"
check "disable senza backup reinstalla pipewire-audio"       has "$SSC" 'pacman -S --noconfirm pipewire-audio'

# --- rebuild con un finto sorgente (meson, ninja e gcc veri) ------------------------------------
echo "arcbase-ssc rebuild (sorgente finto)"
if command -v meson >/dev/null && command -v ninja >/dev/null && command -v gcc >/dev/null; then
    F=$T/fake/ssc-fake
    mkdir -p "$F/src" "$F/third_party/celt" "$F/third_party/pipewire-bluez5"
    printf 'int ssc_fake(void) { return 7; }\n' > "$F/src/ssc.c"
    printf 'GPL\n' > "$F/LICENSE"; printf 'BSD\n' > "$F/third_party/celt/COPYING.opus"
    printf 'MIT\n' > "$F/third_party/pipewire-bluez5/COPYING.pipewire"
    printf 'int main(void) { return 0; }\n' > "$F/t.c"
    cat > "$F/meson.build" <<'MESON'
project('fake', 'c')
shared_library('spa-codec-bluez5-aptx', 'src/ssc.c', name_prefix: 'lib')
test('fake', executable('t', 't.c'))
MESON
    tar -C "$T/fake" -czf "$T/fake.tar.gz" ssc-fake
    sum=$(sha256sum "$T/fake.tar.gz" | cut -d' ' -f1)
    D=$T/d
    setup "$D" 1.6.10 ""
    rm -f "$D/ssc/libspa-codec-bluez5-aptx.so" "$D/ssc/built-for"
    printf "SSC_URL='file://%s'\nSSC_SHA256='%s'\n" "$T/fake.tar.gz" "$sum" > "$D/ssc.conf"
    out=$(ssc "$D" rebuild 2>&1); rc=$?
    check "rebuild: compila, prova e installa" test $rc -eq 0 -a -f "$D/ssc/libspa-codec-bluez5-aptx.so"
    [[ $rc -ne 0 ]] && printf '%s\n' "$out" | tail -n 8 | sed 's/^/      /'
    check "rebuild: registra la versione di PipeWire"        bash -c '[[ $(cat "$0") == 1.6.10 ]]' "$D/ssc/built-for"
    check "rebuild: installa le licenze"                     test -f "$D/lic/LICENSE" -a -f "$D/lic/COPYING.opus" -a -f "$D/lic/COPYING.pipewire"
    check "rebuild: attiva il plugin nello slot aptx"        same "$D/ssc/libspa-codec-bluez5-aptx.so" "$D/spa/libspa-codec-bluez5-aptx.so"
    # sorgente alterato: SHA-256 diverso, non si compila e non si tocca niente
    setup "$D" 1.6.10 ""
    rm -f "$D/ssc/libspa-codec-bluez5-aptx.so" "$D/ssc/built-for"
    printf "SSC_URL='file://%s'\nSSC_SHA256='%064d'\n" "$T/fake.tar.gz" 0 > "$D/ssc.conf"
    out=$(ssc "$D" rebuild 2>&1); rc=$?
    check "rebuild: SHA-256 errato, rifiutato"               bash -c '[[ $1 -ne 0 && $0 == *"SHA-256 errato"* ]]' "$out" "$rc"
    check "rebuild rifiutato: nessun plugin installato"      test ! -e "$D/ssc/libspa-codec-bluez5-aptx.so"
    check "rebuild rifiutato: lo slot aptx resta di Arch"    bash -c '[[ $(cat "$0") == aptx-di-arch ]]' "$D/spa/libspa-codec-bluez5-aptx.so"
    printf 'SSC_URL=\n' > "$D/ssc.conf"
    out=$(ssc "$D" rebuild 2>&1); rc=$?
    check "rebuild: configurazione incompleta, rifiutata"    bash -c '[[ $1 -ne 0 && $0 == *incompleto* ]]' "$out" "$rc"
else
    echo "  (meson, ninja o gcc non trovati: prova di rebuild saltata)"
fi

echo
echo "Risultato: $pass superati, $fail falliti"
[[ $fail -eq 0 ]]
