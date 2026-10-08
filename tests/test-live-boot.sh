#!/bin/bash
# =============================================================================
#  Test di avvio dell'initramfs live (richiede root, loop device, xorriso,
#  mksquashfs, cpio): esegue davvero /init dell'initramfs come PID 1 in un
#  namespace isolato, su una mini-ISO con etichetta ARCBASE_LIVE che contiene
#  arcbase/rootfs.sfs e arcbase/live/. Il finto "systemd" del rootfs scrive un
#  rapporto su un secondo disco (etichetta ARCREPORT) che il test poi legge.
#
#  Verifica: ricerca del supporto per etichetta, mount della squashfs, overlay
#  scrivibile in RAM, copia della sessione live, switch_root, /run con il
#  supporto ancora montato (necessario a Calamares).
# =============================================================================
set -o nounset -o pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
skip() { echo "test di avvio live saltato: $*"; exit 0; }
[[ $EUID -eq 0 ]] || skip "serve root (sudo $0)"
for fs in squashfs overlay devtmpfs; do
    grep -qw "$fs" /proc/filesystems || skip "il kernel non supporta $fs"
done
for t in xorriso mksquashfs cpio losetup unshare switch_root mkfs.ext4 blkid; do
    command -v "$t" >/dev/null || skip "$t non installato"
done
losetup -f >/dev/null 2>&1 || skip "loop device non disponibili"

T=$(mktemp -d)
LOOPS=()
cleanup() {
    local l
    for l in "${LOOPS[@]}"; do losetup -d "$l" 2>/dev/null; done
    [[ -n ${SHOW_REPORT:-} ]] && cat "$T/report-mnt/report.txt" 2>/dev/null; umount "$T/report-mnt" 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT

pass=0 fail=0
check() { local d=$1; shift; if "$@"; then pass=$((pass + 1)); printf '  \e[32m✔\e[0m %s\n' "$d"; else fail=$((fail + 1)); printf '  \e[31m✘\e[0m %s\n' "$d"; fi; }

echo "preparazione"
ARC_LIVE_INIT="$REPO/rootfs/usr/lib/arcbase/live-init" \
    "$REPO/rootfs/usr/bin/arcbase-mkinitramfs-live" "$T/initramfs.img" >/dev/null
mkdir "$T/initrd" && (cd "$T/initrd" && gzip -dc "$T/initramfs.img" | cpio -id --quiet)

# Rootfs di prova: gli stessi binari dell'initramfs + un finto systemd
mkdir "$T/rootfs"
cp -a "$T/initrd/." "$T/rootfs/"
rm -f "$T/rootfs/init"
mkdir -p "$T/rootfs/usr/lib/systemd" "$T/rootfs/etc" "$T/rootfs/report"
echo "squashfs" > "$T/rootfs/etc/origine"
cat > "$T/rootfs/usr/lib/systemd/systemd" <<'EOF'
#!/bin/bash
export PATH=/usr/bin
mount "$(blkid -L ARCREPORT)" /report || exit 1
{
    echo "pid=$$"
    # (solo builtin di bash: il rootfs di prova contiene i binari dell'initramfs)
    while read -r _ mp fs _; do [[ $mp == / ]] && rootfs=$fs; done < /proc/mounts
    echo "root=${rootfs:-?}"
    mountpoint -q /run/arcbase/medium && echo "medium=montato"
    [[ -f /run/arcbase/medium/arcbase/rootfs.sfs ]] && echo "sfs=visibile"
    [[ -f /etc/live-marker ]] && echo "live=copiato"
    echo "origine=$(cat /etc/origine)"
    { : > /scrivibile; } 2>/dev/null && echo "root=scrivibile"
    [[ -e /dev/null && -d /proc/1 && -d /sys/kernel ]] && echo "vfs=ok"
    echo "fine=ok"
} > /report/report.txt
umount /report
EOF
chmod +x "$T/rootfs/usr/lib/systemd/systemd"
mkdir -p "$T/iso/arcbase/live/etc"
echo "live" > "$T/iso/arcbase/live/etc/live-marker"
mksquashfs "$T/rootfs" "$T/iso/arcbase/rootfs.sfs" -noappend -no-progress -comp zstd >/dev/null 2>&1 \
    || mksquashfs "$T/rootfs" "$T/iso/arcbase/rootfs.sfs" -noappend -no-progress >/dev/null
if grep -qw iso9660 /proc/filesystems; then
    xorriso -as mkisofs -quiet -V ARCBASE_LIVE -o "$T/live.iso" "$T/iso" 2>/dev/null
else
    # Kernel di test senza iso9660 (quello di Arcbase lo ha built-in): stesso
    # contenuto ed etichetta su ext4; l'init monta con rilevamento automatico.
    echo "  (kernel senza iso9660: supporto di prova in ext4)"
    truncate -s 64M "$T/live.iso"
    mkfs.ext4 -q -L ARCBASE_LIVE -d "$T/iso" "$T/live.iso"
fi
truncate -s 16M "$T/report.img"
mkfs.ext4 -q -L ARCREPORT "$T/report.img"
LOOPS+=("$(losetup -f --show -r "$T/live.iso")")
LOOPS+=("$(losetup -f --show "$T/report.img")")

echo "avvio dell'initramfs (PID 1 in un namespace)"
# Timeout breve: senza supporto l'init aprirebbe una shell di emergenza
timeout -s KILL 60 unshare --mount --pid --fork --propagation private \
    chroot "$T/initrd" /init </dev/null >"$T/console.log" 2>&1
mkdir "$T/report-mnt"
mount -o ro "${LOOPS[1]}" "$T/report-mnt"
R="$T/report-mnt/report.txt"
if [[ ! -f $R ]]; then
    echo "  nessun rapporto: l'avvio non è arrivato a systemd"
    sed 's/^/    | /' "$T/console.log" | tail -n 20
fi
has() { grep -qx "$1" "$R" 2>/dev/null; }
check "systemd avviato come PID 1"              has "pid=1"
check "root = overlay (squashfs + tmpfs)"       has "root=overlay"
check "root scrivibile (in RAM)"                has "root=scrivibile"
check "sistema letto dalla squashfs"            has "origine=squashfs"
check "sessione live copiata nel root"          has "live=copiato"
check "supporto montato in /run/arcbase/medium" has "medium=montato"
check "squashfs visibile per Calamares"         has "sfs=visibile"
check "/dev, /proc e /sys spostati nel nuovo root" has "vfs=ok"
check "avvio completato"                        has "fine=ok"

echo
echo "Risultato: $pass superati, $fail falliti"
(( fail == 0 ))
