#!/bin/bash
# =============================================================================
#  Stadio 14 — test di avvio della ISO live in QEMU (non richiede root)
#
#  Avvia la ISO senza display, una volta con BIOS (SeaBIOS) e una con UEFI
#  (OVMF, se installato), e segue la console seriale: il test passa quando
#  GRUB, kernel, initramfs live e systemd arrivano al prompt di login.
#  Al termine salva una schermata dello schermo virtuale (out/iso-test-*.ppm)
#  per controllare il desktop grafico.
#
#  Uso: 14-iso-test.sh [bios|uefi]...      (default: tutti quelli disponibili)
#  Variabili: ARC_ISO_TEST_TIMEOUT (secondi, default 600), ARC_ISO_TEST_MEM (4G)
# =============================================================================
STAGE=iso-test
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

ISO="$ARC_OUT_DIR/arcbase-desktop-$ARC_VERSION-x86_64.iso"
TIMEOUT=${ARC_ISO_TEST_TIMEOUT:-600}
MEM=${ARC_ISO_TEST_MEM:-4G}

[[ -f $ISO ]] || die "$ISO non trovata: eseguire prima 'sudo make iso'"
command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 non trovato sull'host"

accel=(-machine q35 -cpu max)
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    accel=(-machine "q35,accel=kvm" -cpu host)
else
    warn "/dev/kvm non accessibile: emulazione TCG (molto più lenta)"
fi

find_ovmf() {
    local f
    for f in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE_4M.fd \
             /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
             /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/qemu/edk2-x86_64-code.fd; do
        [[ -f $f ]] && { printf '%s\n' "$f"; return 0; }
    done
    return 1
}
ovmf_vars_for() {
    local code=$1 v
    for v in "${code/CODE/VARS}" "${code%/*}/OVMF_VARS.fd" /usr/share/qemu/edk2-i386-vars.fd; do
        [[ -f $v ]] && { printf '%s\n' "$v"; return 0; }
    done
    return 1
}

modes=("$@")
if (( ${#modes[@]} == 0 )); then
    modes=(bios)
    if find_ovmf >/dev/null; then modes+=(uefi); else warn "OVMF non trovato: salto il test UEFI (pacchetto edk2-ovmf / ovmf)"; fi
fi

T=$(mktemp -d)
QPID=''
cleanup() {
    [[ -n $QPID ]] && kill "$QPID" 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT

# expect <log> <regex> <secondi>: attende una riga della seriale
expect() {
    local log=$1 re=$2 limit=$3 start=$SECONDS
    while (( SECONDS - start < limit )); do
        grep -qaE "$re" "$log" 2>/dev/null && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 2
    done
    return 1
}

monitor() {  # monitor <comando>: comando al monitor QEMU (socket unix)
    python3 - "$T/mon.sock" "$1" <<'EOF'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
time.sleep(0.3); s.recv(65536)
s.sendall((sys.argv[2] + "\n").encode()); time.sleep(1); s.close()
EOF
}

failed=0
for mode in "${modes[@]}"; do
    log="$ARC_OUT_DIR/iso-test-$mode.log"
    shot="$ARC_OUT_DIR/iso-test-$mode.ppm"
    rm -f "$log" "$shot"
    fw=()
    case $mode in
        bios) ;;
        uefi)
            code=$(find_ovmf) || die "OVMF non trovato"
            vars=$(ovmf_vars_for "$code") || die "OVMF_VARS non trovato accanto a $code"
            cp "$vars" "$T/vars.fd"
            fw=(-drive "if=pflash,format=raw,readonly=on,file=$code"
                -drive "if=pflash,format=raw,file=$T/vars.fd")
            ;;
        *) die "modalità sconosciuta: $mode (bios|uefi)" ;;
    esac

    msg "Avvio della ISO in QEMU ($mode), timeout ${TIMEOUT}s — log: $log"
    qemu-system-x86_64 "${accel[@]}" -smp 4 -m "$MEM" "${fw[@]}" \
        -cdrom "$ISO" -boot d \
        -device virtio-vga -display none \
        -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
        -serial "file:$log" -monitor "unix:$T/mon.sock,server,nowait" \
        -no-reboot &
    QPID=$!

    ok=1
    check() {  # check <descrizione> <regex> <secondi>
        (( ok )) || return 0
        if expect "$log" "$2" "$3"; then
            info "✔ $1"
        else
            printf '  %s✘ %s%s\n' "$_R" "$1" "$_0"
            ok=0
        fi
    }
    # La voce predefinita usa "quiet": kernel e systemd non scrivono sulla
    # seriale finché serial-getty non mostra il prompt.
    check "menu di GRUB"                                'Arcbase Desktop .*\(live\)' 120
    check "kernel + initramfs live + systemd → login" 'login:'                      "$TIMEOUT"

    if (( ok )); then
        info "unità fallite durante l'avvio:"
        grep -aE 'FAILED|Failed to start' "$log" | sed 's/^/      /' || echo "      nessuna"
        info "attendo 30s per il display manager, poi salvo la schermata"
        sleep 30
        monitor "screendump $shot" && info "schermata: $shot"
    else
        failed=$((failed + 1))
        warn "ultime righe della seriale ($mode):"
        tail -n 25 "$log" >&2 || :
    fi
    kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
    QPID=''
done

(( failed == 0 )) || die "test di avvio falliti: $failed/${#modes[@]}"
msg "La ISO si avvia correttamente (${modes[*]})"
