#!/bin/bash
# =============================================================================
#  Test del mirror dei kernel senza compilare un kernel vero:
#   - arcbase-grub-cfg: elenco dei kernel, predefinito, lettura del vecchio
#     grub.cfg, modalità --hook
#   - arcbase-kbuild: pacchetto (con un finto albero del kernel), database del
#     repository letto da pacman, pulizia delle versioni vecchie, firma,
#     confronto con releases.json di kernel.org
#  Non richiede root né rete; i controlli con pacman si saltano se manca.
# =============================================================================
set -o nounset -o pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
KBUILD=$REPO/tools/kernel-mirror/arcbase-kbuild
GRUBCFG=$REPO/rootfs/usr/bin/arcbase-grub-cfg
T=$(mktemp -d)
trap '[[ -n ${KEEP:-} ]] || rm -rf "$T"' EXIT

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  \e[32m✔\e[0m %s\n' "$1"; }
ko()   { fail=$((fail + 1)); printf '  \e[31m✘\e[0m %s\n' "$1"; [[ -n ${2:-} ]] && printf '      %s\n' "$2"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else ko "$d"; fi; }
has()   { grep -qF -- "$2" "$1" 2>/dev/null; }

# --- arcbase-grub-cfg ----------------------------------------------------------------
echo "arcbase-grub-cfg"
B=$T/boot
mkdir -p "$B/grub"
touch "$B/vmlinuz-6.13.4-arcbase" "$B/vmlinuz-7.2.11-arcbase" "$B/vmlinuz-6.18.57-arcbase-lts" "$B/vmlinuz-7.2.9-arcbase"
# grub.cfg come lo scriveva arcbase-bootloader prima di arcbase-grub-cfg
cat > "$B/grub/grub.cfg" <<'EOF'
search --no-floppy --fs-uuid --set=root 1111-UUID
menuentry "Arcbase Desktop" {
    linux /boot/vmlinuz-6.13.4-arcbase root=PARTUUID=2222-PART ro rootwait quiet console=ttyS0
}
menuentry "Arcbase Desktop (modalità testo, ripristino)" {
    linux /boot/vmlinuz-6.13.4-arcbase root=PARTUUID=2222-PART ro rootwait systemd.unit=multi-user.target
}
EOF
G() { ARC_BOOT_DIR=$B ARC_BOOT_CONF=$T/boot.conf "$GRUBCFG" "$@"; }
G > "$T/g.out" 2>&1
check "eseguito senza boot.conf (legge il vecchio grub.cfg)" has "$T/g.out" "avvio predefinito 7.2.11-arcbase (4 kernel)"
first=$(grep -m1 '^ *linux ' "$B/grub/grub.cfg")
check "predefinito: il kernel più recente"     grep -q '/boot/vmlinuz-7.2.11-arcbase root=PARTUUID=2222-PART ro rootwait quiet console=ttyS0$' <<<"$first"
check "UUID della root conservato"             has "$B/grub/grub.cfg" "--set=root 1111-UUID"
check "sottomenu con gli altri kernel"         has "$B/grub/grub.cfg" 'submenu "Altri kernel"'
check "kernel LTS nel sottomenu"               has "$B/grub/grub.cfg" "vmlinuz-6.18.57-arcbase-lts root="
check "kernel LFS originale nel sottomenu"     has "$B/grub/grub.cfg" "vmlinuz-6.13.4-arcbase root="
check "nessun file temporaneo rimasto"         test -z "$(find "$B/grub" -name '.grub.cfg.*')"

printf 'ROOT_UUID=AAAA\nROOT_PARTUUID=BBBB\nCMDLINE=quiet\\ splash\nDEFAULT_KERNEL=*-lts\n' > "$T/boot.conf"
G > /dev/null 2>&1
first=$(grep -m1 '^ *linux ' "$B/grub/grub.cfg")
check "boot.conf: DEFAULT_KERNEL=*-lts"        grep -q 'vmlinuz-6.18.57-arcbase-lts root=PARTUUID=BBBB ro rootwait quiet splash$' <<<"$first"
check "boot.conf: UUID"                        has "$B/grub/grub.cfg" "--set=root AAAA"
rm -f "$T/boot.conf" "$B/grub/grub.cfg"
G --hook > "$T/g.out" 2>&1
check "--hook senza configurazione: esce con 0" test $? -eq 0
check "--hook senza configurazione: non scrive grub.cfg" test ! -e "$B/grub/grub.cfg"
G > /dev/null 2>&1
check "senza --hook e senza configurazione: errore" test $? -ne 0

# --- arcbase-kbuild: pacchetto ----------------------------------------------------------
echo "arcbase-kbuild: pacchetto"
export KB_CONF=$T/none.conf KB_WORKDIR=$T/work KB_REPO_DIR=$T/mirror KB_SRC=$REPO KB_KEEP=3
K=$T/ksrc
mkdir -p "$K/arch/x86/boot"
echo bzimage > "$K/arch/x86/boot/bzImage"; echo map > "$K/System.map"; echo 'CONFIG_X=y' > "$K/.config"
# finto Makefile del kernel: modules_install crea un modulo e modules.dep
cat > "$K/Makefile" <<'EOF'
modules_install:
	mkdir -p $(INSTALL_MOD_PATH)/lib/modules/$(KREL)/kernel
	echo ko > $(INSTALL_MOD_PATH)/lib/modules/$(KREL)/kernel/test.ko
	echo 'kernel/test.ko:' > $(INSTALL_MOD_PATH)/lib/modules/$(KREL)/modules.dep
	ln -sf /tmp $(INSTALL_MOD_PATH)/lib/modules/$(KREL)/build
EOF
mkpkg() {  # mkpkg <flavor> <ver> <rel>
    local name=linux-arcbase krel=$2-arcbase
    [[ $1 == lts ]] && name=linux-lts-arcbase krel=$2-arcbase-lts
    mkdir -p "$KB_REPO_DIR/arcbase-kernel/x86_64"
    KREL=$krel fakeroot -- "$KBUILD" _package "$1" "$2" "$3" cafe "$K" "$krel" "$T/pkgdir" \
        "$KB_REPO_DIR/arcbase-kernel/x86_64/$name-$2-$3-x86_64.pkg.tar.zst"
}
if command -v fakeroot >/dev/null && command -v bsdtar >/dev/null; then
    mkpkg stable 7.2.9 1 > "$T/p.out" 2>&1
    P=$KB_REPO_DIR/arcbase-kernel/x86_64/linux-arcbase-7.2.9-1-x86_64.pkg.tar.zst
    check "pacchetto creato"                      test -s "$P"
    bsdtar -tvf "$P" > "$T/list" 2>/dev/null
    check "kernel in /boot"                       has "$T/list" "boot/vmlinuz-7.2.9-arcbase"
    check "moduli in /usr/lib/modules"            has "$T/list" "usr/lib/modules/7.2.9-arcbase/kernel/test.ko"
    check "file del pacchetto di root"            bash -c '! grep -v " root  *root " "$0" | grep -q .' "$T/list"
    check "link build/source rimossi"             bash -c '! grep -q "modules/7.2.9-arcbase/build" "$0"' "$T/list"
    check ".PKGINFO, .MTREE e .INSTALL presenti"  bash -c 'grep -q " .PKGINFO$" "$0" && grep -q " .MTREE$" "$0" && grep -q " .INSTALL$" "$0"' "$T/list"
    bsdtar -xOf "$P" .PKGINFO > "$T/pkginfo"
    check "versione 7.2.9-1"                      has "$T/pkginfo" "pkgver = 7.2.9-1"
    check "hash della configurazione registrato"  has "$T/pkginfo" "xdata = arcbaseconf=cafe"
    mkpkg stable 7.2.10 1 >/dev/null 2>&1; mkpkg stable 7.2.11 1 >/dev/null 2>&1; mkpkg stable 7.2.11 2 >/dev/null 2>&1
    mkpkg lts 6.18.57 1 >/dev/null 2>&1

    echo "arcbase-kbuild: repository"
    "$KBUILD" key --generate > "$T/key.out" 2>&1
    check "chiave di firma creata e pubblicata"   test -s "$KB_REPO_DIR/arcbase-kernel/arcbase-kernel.asc"
    for f in "$KB_REPO_DIR"/arcbase-kernel/x86_64/*.pkg.tar.zst; do
        gpg --homedir "$KB_WORKDIR/signing" --batch -q --detach-sign --no-armor -o "$f.sig" "$f" 2>/dev/null
    done
    "$KBUILD" repo > "$T/repo.out" 2>&1
    D=$KB_REPO_DIR/arcbase-kernel/x86_64
    check "versione più vecchia oltre KB_KEEP rimossa" test ! -e "$D/linux-arcbase-7.2.9-1-x86_64.pkg.tar.zst"
    check "versioni recenti conservate"           test -e "$D/linux-arcbase-7.2.10-1-x86_64.pkg.tar.zst"
    check "database e link creati"                test -L "$D/arcbase-kernel.db" -a -s "$D/arcbase-kernel.db.tar.gz"
    check "database firmato"                      gpg --homedir "$KB_WORKDIR/signing" --batch -q --verify "$D/arcbase-kernel.db.sig" "$D/arcbase-kernel.db" 2>/dev/null
    bsdtar -xOf "$D/arcbase-kernel.db" > "$T/db" 2>/dev/null
    check "solo l'ultima versione nel database"   bash -c 'grep -qx "7.2.11-2" "$0" && ! grep -qx "7.2.11-1" "$0"' "$T/db"
    check "firma del pacchetto nel database"      has "$T/db" "%PGPSIG%"
    check "linux-lts-arcbase nel database"        has "$T/db" "linux-lts-arcbase-6.18.57-1-x86_64.pkg.tar.zst"

    if command -v pacman >/dev/null; then
        mkdir -p "$T/pacdb"
        cat > "$T/pacman.conf" <<EOF
[options]
Architecture = x86_64
SigLevel = Never
[arcbase-kernel]
Server = file://$KB_REPO_DIR/arcbase-kernel/\$arch
EOF
        PAC=(pacman --config "$T/pacman.conf" --dbpath "$T/pacdb" --noconfirm)
        fakeroot -- "${PAC[@]}" -Sy > "$T/sy.out" 2>&1
        "${PAC[@]}" -Si linux-arcbase > "$T/si.out" 2>&1
        check "pacman legge il repository"        has "$T/si.out" "7.2.11-2"
        "${PAC[@]}" -Si linux-lts-arcbase > "$T/si.out" 2>&1
        check "pacman vede linux-lts-arcbase"     has "$T/si.out" "6.18.57-1"
        fakeroot -- "${PAC[@]}" -Fy > /dev/null 2>&1
        "${PAC[@]}" -Fl linux-arcbase > "$T/fl.out" 2>&1
        check "database dei file (pacman -F)"     has "$T/fl.out" "boot/vmlinuz-7.2.11-arcbase"
        "${PAC[@]}" -Qip "$D/linux-arcbase-7.2.11-2-x86_64.pkg.tar.zst" > "$T/qip.out" 2>&1
        check "pacman -Qip legge il pacchetto"    has "$T/qip.out" "Kernel Linux 7.2.11"
        mkdir -p "$T/root/var/lib/pacman"
        fakeroot -- pacman --config "$T/pacman.conf" --root "$T/root" --dbpath "$T/root/var/lib/pacman" \
            --noconfirm --noscriptlet --nodeps -U "$D/linux-arcbase-7.2.11-2-x86_64.pkg.tar.zst" > "$T/u.out" 2>&1
        check "pacman -U installa kernel e moduli" test -s "$T/root/boot/vmlinuz-7.2.11-arcbase" \
            -a -s "$T/root/usr/lib/modules/7.2.11-arcbase/kernel/test.ko"
        LANG=C "${PAC[@]}" --root "$T/root" --dbpath "$T/root/var/lib/pacman" -Qkk linux-arcbase > "$T/qkk.out" 2>&1
        # fuori da fakeroot i file risultano dell'utente: si ignorano solo UID/GID
        check "pacman -Qkk: file conformi a .MTREE" bash -c '! grep "^warning: linux-arcbase:" "$0" | grep -v "(UID mismatch)\|(GID mismatch)" | grep -q . && grep -q "total files" "$0"' "$T/qkk.out"
    else
        echo "  (pacman non disponibile: controlli con pacman saltati)"
    fi

    echo "arcbase-kbuild: versioni"
    cat > "$T/releases.json" <<'EOF'
{"releases": [
 {"moniker": "mainline", "version": "7.3-rc7", "iseol": false, "source": "x", "pgp": null},
 {"moniker": "stable", "version": "7.2.12", "iseol": false, "source": "https://e/linux-7.2.12.tar.xz", "pgp": "https://e/linux-7.2.12.tar.sign"},
 {"moniker": "longterm", "version": "6.18.57", "iseol": false, "source": "https://e/a.tar.xz", "pgp": "https://e/a.tar.sign"},
 {"moniker": "longterm", "version": "6.12.113", "iseol": false, "source": "https://e/b.tar.xz", "pgp": "https://e/b.tar.sign"}
]}
EOF
    KB_RELEASES_URL=file://$T/releases.json "$KBUILD" check > "$T/check.out" 2>&1
    check "stable: nuova versione rilevata"      grep -qE 'linux-arcbase +7.2.11-2 +7.2.12 +da aggiornare' "$T/check.out"
    check "lts: longterm più recente, config cambiata" grep -qE 'linux-lts-arcbase +6.18.57-1 +6.18.57 +config cambiata' "$T/check.out"
else
    echo "  (fakeroot o bsdtar non disponibili: test del pacchetto saltati)"
fi

echo
echo "Risultato: $pass superati, $fail falliti"
(( fail == 0 ))
