#!/bin/bash
# =============================================================================
#  Test dell'installer grafico (calamares/) senza compilare Calamares: file di
#  configurazione, coerenza tra sequenza e moduli, script di installazione,
#  helper di avvio per root, moduli Python con un libcalamares finto.
#
#  La compilazione di Calamares e la prova grafica si fanno nella VM
#  (make desktop, make iso, make iso-test). Non richiede root né rete; serve
#  python3 con PyYAML (apt install python3-yaml).
#
#  Facoltativo: CALAMARES_SRC=<sorgente di Calamares 3.4.x> controlla anche le
#  configurazioni con gli schemi JSON del progetto (serve il modulo jsonschema).
# =============================================================================
set -o nounset -o pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
CAL=$REPO/calamares
T=$(mktemp -d)
trap '[[ -n ${KEEP:-} ]] || rm -rf "$T"' EXIT

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  \e[32m✔\e[0m %s\n' "$1"; }
ko()   { fail=$((fail + 1)); printf '  \e[31m✘\e[0m %s\n' "$1"; [[ -n ${2:-} ]] && printf '      %s\n' "$2"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else ko "$d"; fi; }
empty() { local d=$1; if [[ -z $2 ]]; then ok "$d"; else ko "$d" "$2"; fi; }   # ok se $2 è vuoto, altrimenti lo mostra
has()   { grep -qF -- "$2" "$1" 2>/dev/null; }
hasnt() { ! grep -qF -- "$2" "$1" 2>/dev/null; }
py()    { python3 -I "$@"; }

if ! py -c 'import yaml' 2>/dev/null; then
    echo "serve PyYAML (apt install python3-yaml): test di Calamares non eseguiti" >&2
    exit 1
fi

# --- Installazione in una cartella di prova ---------------------------------------
R=$T/root
echo "installazione (calamares/install.sh)"
"$CAL/install.sh" --live-user arc --timezone Europe/Rome "$R" >/dev/null 2>&1
check "installazione riuscita"                  test -f "$R/etc/calamares/settings.conf"
check "reinstallazione idempotente"             "$CAL/install.sh" --live-user arc --timezone Europe/Rome "$R"
check "nessun segnaposto @…@ rimasto"           bash -c '! grep -rEq "@(LIVE_USER|REGION|ZONE)@" "$0/etc/calamares"' "$R"
check "utente della live in removeuser.conf"    grep -qx 'username: arc' "$R/etc/calamares/modules/removeuser.conf"
check "home della live non copiata sul disco"   has "$R/etc/calamares/modules/unpackfs.conf" '"/home/arc/"'
check "fuso orario predefinito (Europe/Rome)"   bash -c 'grep -qx "region: \"Europe\"" "$0" && grep -qx "zone:   \"Rome\"" "$0"' "$R/etc/calamares/modules/locale.conf"

R2=$T/root2
"$CAL/install.sh" --live-user mario --timezone America/Argentina/Buenos_Aires "$R2" >/dev/null 2>&1
check "--live-user e --timezone rispettati"     bash -c 'grep -qx "username: mario" "$0/etc/calamares/modules/removeuser.conf" && grep -q "region: \"America\"" "$0/etc/calamares/modules/locale.conf" && grep -q "zone:   \"Argentina/Buenos_Aires\"" "$0/etc/calamares/modules/locale.conf"' "$R2"
"$CAL/install.sh" --timezone UTC "$T/root3" >"$T/utc.log" 2>&1
check "fuso senza regione: ripiego e avviso"    bash -c 'grep -q "region: \"Europe\"" "$0/etc/calamares/modules/locale.conf" && grep -q "uso Europe/Rome" "$1"' "$T/root3" "$T/utc.log"
check "senza destinazione: rifiutato"           bash -c '! "$0" >/dev/null 2>&1' "$CAL/install.sh"
check "destinazione /: rifiutata"               bash -c '! "$0" / >/dev/null 2>&1' "$CAL/install.sh"
check "utente della live strano: rifiutato"     bash -c '! "$0" --live-user "a b" "$1" >/dev/null 2>&1' "$CAL/install.sh" "$T/x"
check "utente root: rifiutato"                  bash -c '! "$0" --live-user root "$1" >/dev/null 2>&1' "$CAL/install.sh" "$T/x"
check "utente con ../ rifiutato"                bash -c '! "$0" --live-user "../x" "$1" >/dev/null 2>&1' "$CAL/install.sh" "$T/x"
check "lanciatore e helper eseguibili"          bash -c 'test -x "$0/usr/bin/arcbase-install-gui" && test -x "$0/usr/lib/arcbase/installer-root"' "$R"
check "moduli Python con module.desc e main.py" bash -c 'for m in arcbase_bootloader arcbase_localize; do test -f "$0/usr/lib/calamares/modules/$m/module.desc" && test -f "$0/usr/lib/calamares/modules/$m/main.py" || exit 1; done' "$R"
check "logo e immagine di benvenuto (SVG validi)" py -c 'import sys, xml.dom.minidom as m; [m.parse(f) for f in sys.argv[1:]]' \
                                                 "$R/usr/share/calamares/branding/arcbase/logo.svg" "$R/usr/share/calamares/branding/arcbase/welcome.svg"

echo "configurazione di Calamares"
check "YAML valido: settings e moduli"          py -c '
import sys, yaml
for f in sys.argv[1:]:
    d = yaml.safe_load(open(f))
    assert isinstance(d, dict), f
' "$R/etc/calamares/settings.conf" "$R"/etc/calamares/modules/*.conf "$R/usr/share/calamares/branding/arcbase/branding.desc"

# Sequenza, moduli e istanze: tutto ciò che settings.conf usa deve esistere
SEQ=$T/seq.txt
py - "$R/etc/calamares/settings.conf" > "$SEQ" <<'EOF'
import sys, yaml
s = yaml.safe_load(open(sys.argv[1]))
inst = {i["id"] for i in s.get("instances", [])}
for phase in s["sequence"]:
    for kind, mods in phase.items():
        for m in mods:
            print(kind, m)
for i in s.get("instances", []):
    print("instance", i["id"], i["module"], i.get("config", i["module"] + ".conf"))
print("branding", s["branding"])
EOF
# Moduli di Calamares che si compilano e quelli saltati (da 11-desktop.sh)
BUILT=$(bash -c 'source <(sed -n "/^CALAMARES_MODULES=(/,/)$/p" "$0"); echo "${CALAMARES_MODULES[*]}"' "$REPO/scripts/chroot/11-desktop.sh")
SKIPPED=$(bash -c 'source <(sed -n "/^CALAMARES_SKIP_MODULES=(/,/zfshostid)/p" "$0"); echo "${CALAMARES_SKIP_MODULES[*]}"' "$REPO/scripts/chroot/11-desktop.sh")
check "elenco dei moduli compilati letto"       test -n "$BUILT" -a -n "$SKIPPED"
INSTANCES=" $(awk '$1 == "instance" { printf "%s ", $2 }' "$SEQ")"
unknown=$(while read -r kind m _; do
    case $kind in
        show|exec)
            base=${m%%@*}
            if [[ $m == *@* ]]; then
                [[ $INSTANCES == *" ${m#*@} "* ]] || echo "istanza $m non dichiarata"
            elif [[ " $BUILT " != *" $base "* && ! -d $CAL/python/$base ]]; then
                echo "$m (né compilato né in calamares/python)"
            fi ;;
    esac
done < "$SEQ")
empty "ogni modulo della sequenza esiste"       "$unknown"
check "nessun modulo usato è tra i saltati"     bash -c 'for m in $0; do [[ " $1 " != *" $m "* ]] || exit 1; done' "$BUILT" "$SKIPPED"
check "i moduli standard sostituiti sono saltati" bash -c 'for m in bootloader localecfg displaymanager machineid initcpio initramfs; do [[ " $0 " == *" $m "* ]] || exit 1; done' "$SKIPPED"
missing=$(for m in $BUILT; do
    [[ $m == summary || $m == shellprocess ]] && continue   # summary non ha configurazione; shellprocess solo come istanza
    [[ -f $CAL/modules/$m.conf ]] || echo "$m.conf"
done)
empty "ogni modulo compilato ha la sua configurazione" "$missing"
missing=$(while read -r kind _ _ conf; do
    [[ $kind == instance ]] && { [[ -f $CAL/modules/$conf ]] || echo "$conf"; }
done < "$SEQ")
empty "ogni istanza ha il suo file"             "$missing"
check "branding: stessa cartella e componentName" bash -c '
b=$(awk "\$1==\"branding\"{print \$2}" "$0"); test -f "$1/usr/share/calamares/branding/$b/branding.desc" && grep -qx "componentName:  $b" "$1/usr/share/calamares/branding/$b/branding.desc"' "$SEQ" "$R"
check "branding: immagini indicate presenti"    bash -c 'd="$0/usr/share/calamares/branding/arcbase"; for f in $(sed -n "s/^    product\(Icon\|Logo\|Welcome\): *\"\(.*\)\"/\2/p" "$d/branding.desc") show.qml stylesheet.qss; do test -f "$d/$f" || exit 1; done' "$R"
check "branding: slideshow API 2 con Presentation" bash -c 'grep -q "^slideshowAPI:   2" "$0/branding.desc" && grep -q "Presentation" "$0/show.qml"' "$CAL/branding/arcbase"

# Ordine dei passi di installazione
order=$(py - "$R/etc/calamares/settings.conf" <<'EOF'
import sys, yaml
s = yaml.safe_load(open(sys.argv[1]))
ex = next(m for p in s["sequence"] for k, m in p.items() if k == "exec")
need = [("partition", "mount"), ("mount", "unpackfs"), ("unpackfs", "removeuser"),
        ("removeuser", "users"), ("unpackfs", "fstab"), ("unpackfs", "arcbase_localize"),
        ("unpackfs", "users"), ("unpackfs", "arcbase_bootloader"), ("users", "shellprocess@cleanup"),
        ("arcbase_bootloader", "umount"), ("shellprocess@cleanup", "preservefiles"),
        ("preservefiles", "umount")]
for a, b in need:
    if ex.index(a) >= ex.index(b):
        print("%s deve venire prima di %s" % (a, b))
if ex[-1] != "umount":
    print("umount deve essere l'ultimo")
EOF
)
empty "ordine dei passi (copia, utenti, boot, umount)" "$order"

# Cosa fa la configurazione per Arcbase
CONF=$R/etc/calamares/modules
check "root solo ext4 nelle partizioni automatiche" py -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert d["availableFileSystemTypes"] == ["ext4"] and d["defaultFileSystemType"] == "ext4"
assert d["lvm"]["enable"] is False and d["enableLuksAutomatedPartitioning"] is False
' "$CONF/partition.conf"
check "root solo ext4 anche a mano (con la chiave che Calamares legge)" py -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
r = d["directoryFilesystemRestrictions"]
# un elemento senza "directory" fa scartare in silenzio tutto l elenco
assert all("directory" in e and "allowedFilesystemTypes" in e for e in r)
assert {"directory": "/", "allowedFilesystemTypes": ["ext4"]} in r
' "$CONF/partition.conf"
check "ESP: 512 MiB su /boot/efi come arcbase-install" bash -c 'grep -q "mountPoint:         \"/boot/efi\"" "$0" && grep -q "recommendedSize:    512MiB" "$0"' "$CONF/partition.conf"
check "niente ibernazione (serve un initramfs)" bash -c '! grep -qE "^\s*- suspend" "$0"' "$CONF/partition.conf"
check "root bloccato: nessuna password di root" grep -qx 'setRootPassword: false' "$CONF/users.conf"
check "root bloccato dal passo finale"          has "$CONF/shellprocess_cleanup.conf" '"passwd -l root"'
check "utente amministratore (wheel/sudo)"      bash -c 'grep -qx "sudoersGroup:    wheel" "$0" && grep -q "name: wheel" "$0"' "$CONF/users.conf"
check "gruppi di sistema creati come di sistema" py -c '
import sys, yaml
g = yaml.safe_load(open(sys.argv[1]))["defaultGroups"]
by = {e["name"]: e for e in g if isinstance(e, dict)}
for n in ("wheel", "input", "render", "users"):
    assert by[n]["system"] is True and by[n]["must_exist"] is False, n
' "$CONF/users.conf"
check "nessun autologin"                        bash -c 'grep -qx "doAutologin:      false" "$0"' "$CONF/users.conf"
check "fstab di Calamares (swap e extra compresi)" py -c '
import sys, yaml
s = yaml.safe_load(open(sys.argv[1]))
ex = next(m for p in s["sequence"] for k, m in p.items() if k == "exec")
assert "fstab" in ex and "bootloader" not in ex
' "$R/etc/calamares/settings.conf"
live_mount=$(sed -n 's/^LIVE=\(.*\)$/\1/p' "$REPO/rootfs/usr/lib/arcbase/live-init.sh")
check "copia dalla squashfs montata da live-init.sh" has "$CONF/unpackfs.conf" "source: \"$live_mount/sfs\""
check "unpackfs: sorgente directory (bind), destinazione /" bash -c 'grep -q "sourcefs: \"ext4\"" "$0" && grep -q "destination: \"\"" "$0"' "$CONF/unpackfs.conf"
excl_ok=1
for f in /etc/calamares/ /usr/share/calamares/ /usr/lib/calamares/ /usr/bin/calamares /usr/bin/arcbase-install-gui \
         /usr/lib/arcbase/installer-root /usr/share/applications/arcbase-install.desktop \
         /usr/share/polkit-1/actions/org.arcbase.installer.policy; do
    has "$CONF/unpackfs.conf" "\"$f\"" || { excl_ok=0; echo "      manca l'esclusione di $f"; }
done
check "l'installer non finisce nel sistema installato" test $excl_ok -eq 1
check "welcome: 20 GB, root richiesto, niente rete" py -c '
import sys, yaml
r = yaml.safe_load(open(sys.argv[1]))["requirements"]
assert r["requiredStorage"] == 20 and "root" in r["required"] and "internet" not in r["check"]
' "$CONF/welcome.conf"
check "tastiera: niente keymap Debian, niente /etc/default/keyboard" bash -c 'grep -qx "convertedKeymapPath: \"\"" "$0" && grep -qx "writeEtcDefaultKeyboard: false" "$0"' "$CONF/keyboard.conf"
check "chroot utilizzabile: /dev /proc /sys /run, efivarfs" bash -c 'for p in /proc /sys /dev /run /sys/firmware/efi/efivars; do grep -q "mountPoint: $p\$" "$0" || exit 1; done' "$CONF/mount.conf"

# Facoltativo: gli schemi JSON del progetto (non sono nel repository: licenza GPL)
if [[ -n ${CALAMARES_SRC:-} ]] && py -c 'import jsonschema' 2>/dev/null; then
    bad=$(py - "$CALAMARES_SRC" "$CONF" <<'EOF'
import glob, os, sys, yaml
from jsonschema import validate, ValidationError
src, conf = sys.argv[1:3]
for f in sorted(glob.glob(conf + "/*.conf")):
    name = os.path.basename(f)[:-5]
    mod = "shellprocess" if name.startswith("shellprocess") else name
    schema_file = os.path.join(src, "src/modules", mod, mod + ".schema.yaml")
    if not os.path.exists(schema_file):
        continue          # moduli nostri (arcbase_*) e senza schema
    schema = yaml.safe_load(open(schema_file))
    data = yaml.safe_load(open(f))
    if mod == "partition":
        # lo schema di 3.4.3 elenca "mountpointFilesystemRestrictions", ma il codice
        # (PartitionViewStep.cpp) legge "directoryFilesystemRestrictions"
        data.pop("directoryFilesystemRestrictions", None)
    try:
        validate(data, schema)
    except ValidationError as e:
        print("%s: %s" % (os.path.basename(f), e.message))
EOF
)
    empty "schemi JSON di Calamares (CALAMARES_SRC)" "$bad"
else
    echo "  (schemi JSON di Calamares: saltati — CALAMARES_SRC e jsonschema non disponibili)"
fi

echo "lanciatore e helper per root"
LAUNCH=$R/usr/bin/arcbase-install-gui
HELPER=$R/usr/lib/arcbase/installer-root
# L'helper gira da root con pkexec, fuori dai test: se ne prova il controllo
# degli argomenti togliendo i controlli dell'ambiente (root, sessione live,
# socket Wayland) e sostituendo l'ultimo exec con la stampa dell'ambiente.
SANDBOX=$T/installer-root.sh
sed -e 's|^\[\[ \$EUID -eq 0 \]\] .*|true|' \
    -e 's|^\[\[ -d /run/arcbase-live/medium \]\] .*|true|' \
    -e 's|^    \[\[ -S .*|    true|' \
    -e 's|^exec env -i "\${env_list\[@\]}" /usr/bin/calamares|printf "%s\\n" "${env_list[@]}" /usr/bin/calamares|' \
    "$HELPER" > "$SANDBOX"
check "prova dell'helper: i controlli sono stati isolati" bash -c '[[ $(grep -c "^true$" "$0") -eq 2 ]] && grep -q "^    true$" "$0" && grep -q "^printf" "$0"' "$SANDBOX"
helper() { PKEXEC_UID=1000 bash "$SANDBOX" "$@" 2>&1; }
out=$(helper WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 LANG=it_IT.UTF-8 XDG_SESSION_TYPE=wayland)
check "Wayland: ambiente pulito e piattaforma"  bash -c 'grep -qx QT_QPA_PLATFORM=wayland <<<"$0" && grep -qx HOME=/root <<<"$0" && grep -qx QT_STYLE_OVERRIDE=Fusion <<<"$0" && grep -qx WAYLAND_DISPLAY=wayland-0 <<<"$0"' "$out"
check "avvia Calamares e nient'altro"           bash -c 'tail -n1 <<<"$0" | grep -qx /usr/bin/calamares' "$out"
out=$(helper -d DISPLAY=:0)
check "X11 con DISPLAY e opzione -d"            bash -c 'grep -qx QT_QPA_PLATFORM=xcb <<<"$0" && tail -n2 <<<"$0" | tr "\n" " " | grep -q "/usr/bin/calamares -d"' "$out"
for bad in 'WAYLAND_DISPLAY=../../etc/x' 'WAYLAND_DISPLAY=/tmp/sock' 'XDG_RUNTIME_DIR=/run/user/0' 'XDG_RUNTIME_DIR=/tmp' \
           'DISPLAY=;id' 'DISPLAY=$(id):0' 'LANG=it IT' 'XDG_SESSION_TYPE=tty' 'XAUTHORITY=/etc/shadow' 'XAUTHORITY=relativo' \
           'PATH=/tmp' 'LD_PRELOAD=/tmp/x.so' '--version' 'id' '-d;id'; do
    out=$(helper WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 "$bad"); rc=$?
    check "rifiuta «$bad»" bash -c '[[ $0 -ne 0 && $1 == *"installer-root:"* ]]' "$rc" "$out"
done
out=$(helper LANG=it_IT.UTF-8); rc=$?
check "senza schermo: rifiutato"                bash -c '[[ $0 -ne 0 && $1 == *"nessuno schermo"* ]]' "$rc" "$out"
out=$(PKEXEC_UID='' bash "$SANDBOX" WAYLAND_DISPLAY=wayland-0 2>&1); rc=$?
check "senza PKEXEC_UID: rifiutato"             bash -c '[[ $0 -ne 0 && $1 == *PKEXEC_UID* ]]' "$rc" "$out"
out=$(bash "$HELPER" DISPLAY=:0 2>&1); rc=$?
check "da non-root: rifiutato (originale)"      bash -c '[[ $0 -ne 0 && $1 == *"serve root"* ]]' "$rc" "$out"
out=$(bash "$LAUNCH" 2>&1); rc=$?
check "il lanciatore fuori dalla live: rifiutato" bash -c '[[ $0 -ne 0 && $1 == *"sessione live"* ]]' "$rc" "$out"
check "il lanciatore usa pkexec e l'helper"     bash -c 'grep -q "pkexec /usr/lib/arcbase/installer-root" "$0"' "$LAUNCH"
check "il lanciatore passa solo variabili d'ambiente note" bash -c 'grep -q "for v in WAYLAND_DISPLAY XDG_RUNTIME_DIR DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP LANG" "$0"' "$LAUNCH"

POLICY=$R/usr/share/polkit-1/actions/org.arcbase.installer.policy
check "polkit: XML ben formato"                 py -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$POLICY"
check "polkit: autorizza l'helper installato"   has "$POLICY" '<annotate key="org.freedesktop.policykit.exec.path">/usr/lib/arcbase/installer-root</annotate>'
check "polkit: solo la sessione attiva"         bash -c 'grep -q "<allow_active>yes" "$0" && grep -q "<allow_any>no" "$0" && grep -q "<allow_inactive>no" "$0"' "$POLICY"
DESK=$R/usr/share/applications/arcbase-install.desktop
check "lanciatore: Exec = lo script installato" grep -qx 'Exec=arcbase-install-gui' "$DESK"
shell_desktop=$(sed -n 's|.*installerDesktop = QStringLiteral("\(.*\)");|\1|p' "$REPO/arc-ui/shell/src/shell.cpp")
check "lanciatore: nome atteso dalla dock di arc UI" test "$shell_desktop" = /usr/share/applications/arcbase-install.desktop
check "lanciatore: lo stesso nome che toglie arcbase-install" has "$REPO/rootfs/usr/bin/arcbase-install" 'arcbase-install.desktop'

echo "arcbase-bootloader per Calamares"
out=$(bash "$REPO/rootfs/usr/bin/arcbase-bootloader" --no-fstab 2>&1); rc=$?
check "--no-fstab è un'opzione nota"            bash -c '[[ $0 -eq 2 && $1 == uso:* ]]' "$rc" "$out"
check "con --no-fstab non si scrive /etc/fstab" bash -c 'awk "/^if \(\( fstab \)\)/,/^fi/" "$0" | grep -q "> /etc/fstab"' "$REPO/rootfs/usr/bin/arcbase-bootloader"
check "il modulo lo chiama con --no-fstab"      has "$CAL/python/arcbase_bootloader/main.py" '"--no-fstab"'

echo "moduli Python (libcalamares simulato)"
check "sintassi dei moduli (ast)"               py -c '
import ast, sys
for f in sys.argv[1:]:
    ast.parse(open(f).read(), f)
' "$CAL"/python/*/main.py
check "module.desc: nome = cartella, interfaccia python" bash -c 'for d in "$0"/python/*/; do n=$(basename "$d"); grep -qx "name:       \"$n\"" "$d/module.desc" && grep -qx "interface:  \"python\"" "$d/module.desc" || exit 1; done' "$CAL"
if out=$(py "$REPO/tests/calamares_modules_test.py" 2>&1); then
    ok "prove dei moduli: $(tail -n3 <<<"$out" | head -n1)"
else
    ko "prove dei moduli" "$(tail -n 25 <<<"$out")"
fi

echo "compilazione e ISO"
PK=$REPO/config/packages.conf
check "calamares in packages.conf con SHA-256"  bash -c 'awk "\$1==\"calamares\" && \$4 ~ /^[0-9a-f]{64}\$/ {f=1} END{exit !f}" "$0"' "$PK"
check "sorgente dal repository ufficiale (Codeberg)" bash -c 'awk "\$1==\"calamares\"{print \$3}" "$0" | grep -q "^https://codeberg.org/Calamares/calamares/releases/download/v@V@/calamares-@V@.tar.gz\$"' "$PK"
D=$REPO/scripts/chroot/11-desktop.sh
check "build con Qt 6, Python (pybind11) e QML"  bash -c 'grep -q "DWITH_QT6=ON" "$0" && grep -q "DWITH_PYBIND11=ON" "$0" && grep -q "DWITH_PYTHON=ON" "$0" && grep -q "DWITH_QML=ON" "$0"' "$D"
check "build senza test, crash reporting e polkit-qt" bash -c 'for o in BUILD_TESTING BUILD_SCHEMA_TESTING BUILD_CRASH_REPORTING INSTALL_POLKIT INSTALL_CONFIG; do grep -q "D$o=OFF" "$0" || exit 1; done' "$D"
check "dopo l'installazione si verificano i moduli" has "$D" 'modulo $m non compilato'
check "dipendenze: kpmcore, rsync, yaml-cpp"    bash -c 'for p in kpmcore rsync yaml-cpp libpwquality; do grep -q "$p" "$0" || exit 1; done' "$D"
check "solo con ARC_CALAMARES (auto: kde e arc)" bash -c 'grep -q "if calamares_enabled; then" "$0" && grep -q "auto) \[\[ \$ARC_DESKTOP == kde || \$ARC_DESKTOP == arc \]\]" "$0"' "$D"
check "ARC_CALAMARES in arcbase.conf"           grep -qF ': "${ARC_CALAMARES=auto}"' "$REPO/config/arcbase.conf"
check "13-iso.sh configura Calamares nella live" bash -c 'grep -q "calamares/install.sh\" --live-user \"\$ARC_USER\" --timezone \"\$ARC_TIMEZONE\" \"\$STAGING\"" "$0"' "$REPO/scripts/13-iso.sh"
check "13-iso.sh: senza Calamares resta arcbase-install" has "$REPO/scripts/13-iso.sh" 'Exec=konsole -e sudo arcbase-install'

echo
echo "Risultato: $pass superati, $fail falliti"
(( fail == 0 ))
