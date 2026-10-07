#!/bin/bash
# =============================================================================
#  Stadio 00 — verifica dei requisiti del sistema host (LFS cap. 2.2)
# =============================================================================
STAGE=host-check
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

errors=0
ok()   { printf '  %-12s %-10s OK\n' "$1" "$2"; }
bad()  { printf '  %-12s %s\n' "$1" "${_R}ERRORE${_0}: $2"; errors=$((errors + 1)); }

# ver_check <nome> <comando> <versione-minima>
ver_check() {
    local name=$1 cmd=$2 min=$3 v
    if ! command -v "$cmd" >/dev/null 2>&1; then
        bad "$name" "$cmd non trovato"
        return
    fi
    v=$("$cmd" --version 2>&1 | grep -E -o '[0-9]+\.[0-9.]+[a-z]*' | head -n1) || :
    if printf '%s\n' "$min" "$v" | sort --version-sort --check >/dev/null 2>&1; then
        ok "$name" "$v"
    else
        bad "$name" "versione $v, richiesta >= $min"
    fi
}

msg "Verifica dei requisiti dell'host"
ver_check Coreutils sort      8.1
ver_check Bash      bash      3.2
ver_check Binutils  ld        2.13.1
ver_check Bison     bison     2.7
ver_check Diffutils diff      2.8.1
ver_check Findutils find      4.2.31
ver_check Gawk      gawk      4.0.1
ver_check GCC       gcc       5.2
ver_check "GCC(C++)" g++      5.2
ver_check Grep      grep      2.5.1a
ver_check Gzip      gzip      1.3.12
ver_check M4        m4        1.4.10
ver_check Make      make      4.0
ver_check Patch     patch     2.5.4
ver_check Perl      perl      5.8.8
ver_check Python    python3   3.4
ver_check Sed       sed       4.1.5
ver_check Tar       tar       1.22
ver_check Texinfo   texi2any  5.0
ver_check Xz        xz        5.0.0

# Kernel >= 5.4
kver=$(uname -r | grep -E -o '^[0-9.]+')
if printf '%s\n' 5.4 "$kver" | sort --version-sort --check >/dev/null 2>&1; then
    ok Kernel "$kver"
else
    bad Kernel "versione $kver, richiesta >= 5.4"
fi

# Alias richiesti da LFS
# check_cond <nome> <messaggio-errore> <comando...>
check_cond() {
    local name=$1 err=$2; shift 2
    if "$@" >/dev/null 2>&1; then ok "$name" ""; else bad "$name" "$err"; fi
}
sh_is_bash() { [[ $(readlink -f "$(command -v sh)") == */bash ]]; }
check_cond "sh->bash" "/bin/sh deve puntare a bash" sh_is_bash
check_cond yacc "yacc mancante (bison)" command -v yacc
check_cond awk  "awk mancante (gawk)"   command -v awk

# Compilatore funzionante
tmp=$(mktemp -d)
echo 'int main(){}' > "$tmp/t.c"
if g++ -x c++ "$tmp/t.c" -o "$tmp/t" 2>/dev/null; then ok "g++ build" ""; else bad "g++" "non riesce a compilare"; fi
rm -rf "$tmp"

# Strumenti aggiuntivi usati da Arcbase
msg "Strumenti aggiuntivi (download e immagine disco)"
for t in curl losetup sfdisk mkfs.ext4 mkfs.vfat blkid runuser; do
    check_cond "$t" "non trovato" command -v "$t"
done
check_cond arch "Arcbase supporta solo x86_64" test "$(uname -m)" = x86_64

nproc_v=$(nproc)
mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
info "CPU: $nproc_v core, RAM: $((mem_kb / 1024)) MiB"
(( mem_kb >= 4000000 )) || warn "con meno di 4 GiB di RAM la compilazione di gcc/glibc può fallire"

if (( errors > 0 )); then
    die "$errors requisiti mancanti: installarli prima di continuare"
fi
msg "Host pronto per la build di $ARC_NAME"
