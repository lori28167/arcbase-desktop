#!/bin/bash
# =============================================================================
#  Stadio 15 — test dell'installer in QEMU (non richiede root)
#
#  Per ogni modalità (BIOS e, se c'è OVMF, UEFI):
#    1. avvia la ISO con un disco virtuale vuoto e, dalla console seriale,
#       esegue arcbase-install su /dev/vda (cambiando anche utente e nome host)
#    2. spegne, riavvia dal disco e accede con il nuovo utente
#    3. verifica nome host, utente, root ext4 e stato di systemd, e salva una
#       schermata dello schermo virtuale (out/install-test-*.ppm)
#
#  Uso: 15-install-test.sh [bios|uefi]...      (default: tutti quelli disponibili)
#  Variabili: ARC_INSTALL_TEST_TIMEOUT (secondi per ogni attesa, default 900)
# =============================================================================
STAGE=install-test
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

ISO="$ARC_OUT_DIR/arcbase-desktop-$ARC_VERSION-x86_64.iso"
TIMEOUT=${ARC_INSTALL_TEST_TIMEOUT:-900}

[[ -f $ISO ]] || die "$ISO non trovata: eseguire prima 'sudo make iso'"
for t in qemu-system-x86_64 qemu-img python3; do
    command -v "$t" >/dev/null || die "$t non trovato sull'host"
done

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

modes=("$@")
if (( ${#modes[@]} == 0 )); then
    modes=(bios)
    if find_ovmf >/dev/null; then modes+=(uefi); else warn "OVMF non trovato: salto il test UEFI"; fi
fi

# Socket e script in /tmp; il disco virtuale (fino a ~10 GB scritti) in out/,
# perché /tmp è spesso un tmpfs in RAM
T=$(mktemp -d)
DISK="$ARC_OUT_DIR/install-test-disk.qcow2"
QPID=''
cleanup() {
    [[ -n $QPID ]] && kill "$QPID" 2>/dev/null
    rm -rf "$T" "$DISK"
}
trap cleanup EXIT

# Pilota la console seriale (socket unix di QEMU) come "expect": argomenti
#   expect:<regex>  send:<testo>  timeout:<secondi>  print:<regex con un gruppo>
cat > "$T/serial.py" <<'EOF'
import re, socket, sys, time
sock_path, log_path, steps = sys.argv[1], sys.argv[2], sys.argv[3:]
for _ in range(300):
    try:
        s = socket.socket(socket.AF_UNIX); s.connect(sock_path); break
    except OSError:
        time.sleep(0.2)
else:
    sys.exit("socket seriale non disponibile")
s.settimeout(1)
log, buf, timeout = open(log_path, 'ab'), b'', 900
def wait(pattern):
    global buf
    rx, end = re.compile(pattern.encode()), time.time() + timeout
    while time.time() < end:
        m = rx.search(buf)
        if m:
            buf = buf[m.end():]
            return m
        try:
            data = s.recv(65536)
            if not data:
                sys.exit(f"console chiusa aspettando: {pattern}")
            log.write(data); log.flush(); buf += data
        except socket.timeout:
            pass
    sys.exit(f"timeout aspettando: {pattern}")
for st in steps:
    kind, _, arg = st.partition(':')
    if kind == 'timeout':
        timeout = int(arg)
    elif kind == 'expect':
        wait(arg)
    elif kind == 'print':
        print(wait(arg).group(1).decode(errors='replace').strip())
    elif kind == 'send':
        time.sleep(0.5); s.sendall(arg.encode() + b'\r')
EOF

monitor() {  # monitor <comando>
    python3 - "$T/mon.sock" "$1" <<'EOF'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
time.sleep(0.3); s.recv(65536)
s.sendall((sys.argv[2] + "\n").encode()); time.sleep(1); s.close()
EOF
}

# qemu_start <log> <opzioni...>: QEMU senza display, seriale su socket
qemu_start() {
    local log=$1; shift
    rm -f "$T/serial.sock" "$T/mon.sock"
    qemu-system-x86_64 "${accel[@]}" -smp 4 -m 4G "${fw[@]}" "$@" \
        -device virtio-vga -display none \
        -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
        -chardev "socket,id=s0,path=$T/serial.sock,server=on,wait=off,logfile=$log" \
        -serial chardev:s0 -monitor "unix:$T/mon.sock,server,nowait" -no-reboot &
    QPID=$!
}
qemu_stop() {
    [[ -n $QPID ]] || return 0
    kill "$QPID" 2>/dev/null || :
    wait "$QPID" 2>/dev/null || :   # il codice d'uscita di QEMU non conta
    QPID=''
}

SER=(python3 "$T/serial.py" "$T/serial.sock")
INSTALL_CMD="arcbase-install --disk /dev/vda --yes --hostname arctest --user tester \
--fullname 'Test User' --password test123 --root-password test123 --timezone Europe/Rome \
--cmdline 'quiet console=ttyS0,115200 console=tty0'; echo INSTALL_RC=\$?"
CHECK_CMD='systemctl is-system-running --wait >/dev/null; echo "CHECK $(hostname) $(id -un) $(findmnt -no FSTYPE /) $(systemctl is-system-running)"; systemctl --failed --no-legend --plain | sed "s/^/FAILED /"; echo CHECK_END'

failed=0
for mode in "${modes[@]}"; do
    fw=()
    case $mode in
        bios) ;;
        uefi)
            code=$(find_ovmf) || die "OVMF non trovato"
            vars="${code/CODE/VARS}"
            [[ -f $vars ]] || die "OVMF_VARS non trovato accanto a $code"
            cp "$vars" "$T/vars.fd"
            fw=(-drive "if=pflash,format=raw,readonly=on,file=$code"
                -drive "if=pflash,format=raw,file=$T/vars.fd")
            ;;
        *) die "modalità sconosciuta: $mode (bios|uefi)" ;;
    esac
    log_inst="$ARC_OUT_DIR/install-test-$mode-install.log"
    log_boot="$ARC_OUT_DIR/install-test-$mode-boot.log"
    shot="$ARC_OUT_DIR/install-test-$mode.ppm"
    rm -f "$log_inst" "$log_boot" "$shot"
    qemu-img create -q -f qcow2 "$DISK" 25G

    msg "[$mode] installazione dalla ISO su un disco vuoto — log: $log_inst"
    qemu_start "$log_inst" -cdrom "$ISO" -boot d \
        -drive "file=$DISK,format=qcow2,if=virtio"
    if rc=$("${SER[@]}" "$T/serial-inst.raw" "timeout:$TIMEOUT" \
            'expect:login: ?$' 'send:root' 'expect:[Pp]assword: ?' 'send:arcbase' \
            'timeout:120' 'send:echo READY_$((40+2))' 'expect:READY_42' \
            "timeout:$TIMEOUT" "send:$INSTALL_CMD" 'print:INSTALL_RC=([0-9]+)\r?\n'); then
        info "arcbase-install terminato con codice $rc"
    else
        rc=x
    fi
    if [[ $rc != 0 ]]; then
        printf '  %s✘ installazione fallita%s\n' "$_R" "$_0"
        tail -n 30 "$log_inst" >&2 || :
        qemu_stop; failed=$((failed + 1)); continue
    fi
    info "✔ installazione completata, spegnimento"
    "${SER[@]}" "$T/serial-inst.raw" 'timeout:120' 'send:poweroff' 'expect:reboot: Power down|Power down' || :
    for _ in $(seq 60); do kill -0 "$QPID" 2>/dev/null || break; sleep 1; done
    qemu_stop

    msg "[$mode] avvio dal disco installato — log: $log_boot"
    qemu_start "$log_boot" -boot c -drive "file=$DISK,format=qcow2,if=virtio"
    if out=$("${SER[@]}" "$T/serial-boot.raw" "timeout:$TIMEOUT" \
             'expect:arctest login: ?$' 'send:tester' 'expect:[Pp]assword: ?' 'send:test123' \
             'timeout:300' "send:$CHECK_CMD" 'print:(CHECK [a-z0-9-]+ [a-z0-9_-]+ [a-z0-9]+ [a-z]+)\r?\n' 'print:([\s\S]*?)CHECK_END'); then
        check=$(head -n1 <<<"$out")
        info "$check"
        grep '^FAILED' <<<"$out" | sed 's/^/      /' || :
        read -r _ h u fs state <<<"$check"
        if [[ $h == arctest && $u == tester && $fs == ext4 && $state =~ ^(running|degraded)$ ]]; then
            info "✔ sistema installato avviato: utente, nome host e root corretti"
        else
            printf '  %s✘ verifica fallita: %s%s\n' "$_R" "$check" "$_0"
            failed=$((failed + 1))
        fi
        info "attendo 20s per il display manager, poi salvo la schermata"
        sleep 20
        monitor "screendump $shot" && info "schermata: $shot"
    else
        printf '  %s✘ il sistema installato non arriva al login%s\n' "$_R" "$_0"
        tail -n 30 "$log_boot" >&2 || :
        failed=$((failed + 1))
    fi
    qemu_stop
done

(( failed == 0 )) || die "test dell'installer falliti: $failed/${#modes[@]}"
msg "Installazione e avvio dal disco riusciti (${modes[*]})"
