#!/bin/bash
# =============================================================================
#  Verifica statica degli stadi di build (ARCBASE_DRY_RUN=1): ogni pacchetto
#  deve avere la propria ricetta build_<nome> e una voce in packages.conf, e
#  ogni passo la sua funzione. Nessuna compilazione, nessun root richiesto.
# =============================================================================
set -o nounset -o pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

fail=0 total=0
for s in 03-cross-toolchain.sh 04-temp-tools.sh chroot/06-chroot-tools.sh \
         chroot/07-base-system.sh chroot/08-system-config.sh chroot/09-kernel-boot.sh \
         chroot/10-package-managers.sh chroot/11-desktop.sh; do
    if out=$(ARCBASE_DRY_RUN=1 LFS="$T" "$REPO/scripts/$s" 2>&1); then
        n=$(grep -cE '^(build|step) ' <<<"$out")
        total=$((total + n))
        printf '  \e[32m✔\e[0m %-32s %3d ricette/passi\n' "$s" "$n"
    else
        fail=$((fail + 1))
        printf '  \e[31m✘\e[0m %s\n%s\n' "$s" "$(tail -n 3 <<<"$out" | sed 's/^/      /')"
    fi
done

# Ogni voce di arch-provides.map deve puntare a un sorgente esistente
while read -r name src; do
    [[ -z ${name:-} || $name == \#* || $src == @ARCBASE@ ]] && continue
    if ! grep -qE "^${src}[[:space:]]" "$REPO/config/packages.conf"; then
        printf '  \e[31m✘\e[0m arch-provides.map: %s -> %s non esiste in packages.conf\n' "$name" "$src"
        fail=$((fail + 1))
    fi
done < "$REPO/config/arch-provides.map"

echo
echo "Ricette verificate: $total, stadi falliti: $fail"
(( fail == 0 ))
