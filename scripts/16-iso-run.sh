#!/bin/bash
# =============================================================================
#  Stadio 16 — avvia la ISO live in QEMU con una finestra (macOS e Linux)
#
#  Per guardare e usare il desktop (14-iso-test.sh invece gira senza schermo).
#  Non richiede root e non usa common.sh, così funziona anche su macOS.
#
#  Uso: 16-iso-run.sh [--iso FILE] [--disk FILE[:GB]] [--uefi] [--snapshot]
#    --iso FILE      ISO da avviare (default: out/arcbase-desktop-<versione>-x86_64.iso,
#                    oppure le parti .part1/.part2 scaricate da GitHub in out/*/)
#    --disk FILE     disco virtuale qcow2 (creato se manca, 20 GB o :GB) per
#                    installare o per i test che devono sopravvivere al riavvio
#    --uefi          avvio UEFI invece di BIOS (serve edk2 di QEMU)
#    --snapshot      i dischi non vengono scritti (le modifiche si perdono)
#  Variabili: ARC_RUN_MEM (4G), ARC_RUN_SMP (4), ARC_RUN_DISPLAY (cocoa|gtk|sdl|vnc=:0)
#  Dall'host: ssh -p 2222 utente@localhost  |  schermata: out/iso-run.mon (monitor QEMU)
# =============================================================================
set -o errexit -o nounset -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
OUT=${ARC_OUT_DIR:-$REPO/out}
VERSION=$(sed -n 's/^ARC_VERSION=//p' "$REPO/config/arcbase.conf" | head -n1)
MEM=${ARC_RUN_MEM:-4G}
SMP=${ARC_RUN_SMP:-4}

msg()  { printf '==> %s\n' "$*"; }
warn() { printf '==> ATTENZIONE: %s\n' "$*" >&2; }
die()  { printf '==> ERRORE: %s\n' "$*" >&2; exit 1; }

iso=''
disk=''
uefi=0
snapshot=0
while (($#)); do
    case $1 in
        --iso) iso=${2:?--iso richiede un file}; shift ;;
        --disk) disk=${2:?--disk richiede un file}; shift ;;
        --uefi) uefi=1 ;;
        --snapshot) snapshot=1 ;;
        -h|--help) sed -n '3,19p' "$0"; exit 0 ;;
        *) die "argomento sconosciuto: $1" ;;
    esac
    shift
done

command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 non trovato (macOS: brew install qemu)"
mkdir -p "$OUT"

# --- ISO: file indicato, quella costruita qui, oppure le parti di GitHub ----------
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
if [[ -z $iso ]]; then
    iso=$OUT/arcbase-desktop-$VERSION-x86_64.iso
    if [[ ! -f $iso ]]; then
        part1=''
        for f in "$OUT"/*/arcbase-desktop-*-x86_64.iso.part1; do [[ -f $f ]] && part1=$f; done
        [[ -n $part1 ]] || die "nessuna ISO: 'sudo make iso', oppure scaricare le parti della release in $OUT/<cartella>/"
        dir=$(dirname "$part1")
        iso=${part1%.part1}
        if [[ ! -f $iso ]]; then
            msg "Unisco le parti in $iso"
            cat "$dir"/"$(basename "$iso")".part* > "$iso.tmp"
            if [[ -f $dir/SHA256SUMS ]]; then
                want=$(awk -v f="$(basename "$iso")" '$2 == f || $2 == "*" f { print $1 }' "$dir/SHA256SUMS")
                got=$(sha256 "$iso.tmp" | awk '{ print $1 }')
                if [[ -z $want ]]; then
                    warn "SHA256SUMS non elenca $(basename "$iso"): checksum non verificato"
                elif [[ $want != "$got" ]]; then
                    rm -f "$iso.tmp"; die "checksum errato per $(basename "$iso")"
                else
                    msg "Checksum SHA-256 verificato"
                fi
            fi
            mv "$iso.tmp" "$iso"
        fi
    fi
fi
[[ -f $iso ]] || die "ISO non trovata: $iso"

# --- Accelerazione e schermo -----------------------------------------------------
os=$(uname -s)
arch=$(uname -m)
accel=(-machine q35 -cpu max -accel "tcg,thread=multi,tb-size=512")
if [[ $os == Linux && -r /dev/kvm && -w /dev/kvm ]]; then
    accel=(-machine "q35,accel=kvm" -cpu host)
elif [[ $os == Darwin && $arch == x86_64 ]]; then
    accel=(-machine "q35,accel=hvf" -cpu host)
else
    warn "nessuna accelerazione hardware: emulazione (TCG), l'avvio di KDE richiede alcuni minuti"
fi

display=${ARC_RUN_DISPLAY:-}
if [[ -z $display ]]; then
    [[ $os == Darwin ]] && display=cocoa || display=gtk
fi
case $display in
    vnc=*) display_args=(-vnc "${display#vnc=}") ;;
    *) display_args=(-display "$display") ;;
esac

# --- Firmware UEFI (facoltativo) -----------------------------------------------------
fw=()
if ((uefi)); then
    code=''
    for f in /opt/homebrew/share/qemu/edk2-x86_64-code.fd /usr/local/share/qemu/edk2-x86_64-code.fd \
             /usr/share/qemu/edk2-x86_64-code.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd \
             /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
        [[ -f $f ]] && { code=$f; break; }
    done
    [[ -n $code ]] || die "firmware UEFI (edk2/OVMF) non trovato: avviare senza --uefi"
    fw=(-drive "if=pflash,format=raw,readonly=on,file=$code")
fi

# --- Disco virtuale (facoltativo) ---------------------------------------------------
disk_args=()
if [[ -n $disk ]]; then
    size=20
    if [[ $disk == *:* ]]; then size=${disk##*:}; disk=${disk%:*}; fi
    command -v qemu-img >/dev/null || die "qemu-img non trovato"
    [[ -f $disk ]] || { msg "Creo il disco $disk (${size} GB)"; qemu-img create -f qcow2 "$disk" "${size}G" >/dev/null; }
    disk_args=(-drive "file=$disk,if=virtio,format=qcow2")
fi
snap=()
((snapshot)) && snap=(-snapshot)

mon=$OUT/iso-run.mon
log=$OUT/iso-run.log
rm -f "$mon" "$log"

msg "Avvio $(basename "$iso") — ${MEM} di RAM, ${SMP} CPU, schermo: $display"
msg "ssh: -p 2222 utente@localhost  |  monitor QEMU: $mon  |  seriale: $log"
# ${arr[@]+"${arr[@]}"}: la bash 3.2 di macOS non accetta array vuoti con set -u
exec qemu-system-x86_64 "${accel[@]}" -smp "$SMP" -m "$MEM" ${fw[@]+"${fw[@]}"} \
    -cdrom "$iso" -boot d ${disk_args[@]+"${disk_args[@]}"} ${snap[@]+"${snap[@]}"} \
    -device virtio-vga "${display_args[@]}" \
    -device qemu-xhci -device usb-tablet -device usb-kbd \
    -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 \
    -serial "file:$log" -monitor "unix:$mon,server,nowait"
