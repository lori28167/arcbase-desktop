#!/bin/bash
# =============================================================================
#  install.sh — installa il builder dei kernel Arcbase su un server
#  (VM Debian/Proxmox o Arch Linux). Va eseguito come root dalla cartella
#  tools/kernel-mirror del repository. Rieseguirlo aggiorna lo script e le
#  unità systemd senza toccare la configurazione.
# =============================================================================
set -o errexit -o nounset -o pipefail
cd "$(dirname "$0")"
[[ $EUID -eq 0 ]] || { echo "serve root: sudo $0" >&2; exit 1; }

echo "==> Dipendenze"
if command -v apt-get >/dev/null; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential bc bison flex libelf-dev libssl-dev cpio kmod zstd xz-utils \
        gnupg dirmngr curl ca-certificates git python3 libarchive-tools fakeroot sudo \
        qemu-system-x86 qemu-utils
elif command -v pacman >/dev/null; then
    pacman -S --needed --noconfirm base-devel bc cpio libelf openssl kmod zstd xz \
        gnupg curl git python libarchive fakeroot sudo qemu-base
else
    echo "distribuzione non supportata: installa a mano le dipendenze (vedi README)" >&2
    exit 1
fi

echo "==> Utente arcbuild"
if ! id arcbuild >/dev/null 2>&1; then
    useradd --system --create-home --home-dir /var/lib/arcbase-kbuild \
        --shell /usr/sbin/nologin --comment "Arcbase kernel builder" arcbuild
fi
getent group kvm >/dev/null && usermod -aG kvm arcbuild

echo "==> File"
install -m755 arcbase-kbuild arcbase-kbot /usr/local/bin/
install -m755 arcbase-kbuild-ctl /usr/local/sbin/
# Regola sudo per il bot: controllata con visudo prima di attivarla
install -m440 arcbase-kbuild.sudoers /etc/sudoers.d/arcbase-kbuild.new
if visudo -cqf /etc/sudoers.d/arcbase-kbuild.new; then
    mv -f /etc/sudoers.d/arcbase-kbuild.new /etc/sudoers.d/arcbase-kbuild
else
    rm -f /etc/sudoers.d/arcbase-kbuild.new
    echo "regola sudo non valida: comandi /build /stop /orario del bot disattivati" >&2
fi
if [[ ! -e /etc/arcbase-kbuild.conf ]]; then
    install -m644 kbuild.conf.example /etc/arcbase-kbuild.conf
    echo "  -> creato /etc/arcbase-kbuild.conf"
fi
if [[ ! -e /etc/arcbase-kbuild.env ]]; then
    install -m600 -o arcbuild -g arcbuild kbuild.env.example /etc/arcbase-kbuild.env
    echo "  -> creato /etc/arcbase-kbuild.env (token Telegram, permessi 600)"
fi
install -d -m755 -o arcbuild -g arcbuild /srv/arcbase-mirror
install -m644 arcbase-kbuild.service arcbase-kbuild-manual@.service arcbase-kbuild.timer \
    arcbase-kmirror-http.service arcbase-kbot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now arcbase-kmirror-http.service
systemctl enable --now arcbase-kbuild.timer
systemctl enable arcbase-kbot.service
systemctl restart arcbase-kbot.service   # riparte con lo script aggiornato

ip=$(hostname -I 2>/dev/null | awk '{print $1}')
cat <<EOF

==> Builder installato. Prossimi passi:
  1. Telegram: metti token e chat in /etc/arcbase-kbuild.env
     (sudo -u arcbuild nano /etc/arcbase-kbuild.env), poi
       sudo -u arcbuild arcbase-kbuild notify-test
       sudo systemctl restart arcbase-kbot     # comandi del bot: scrivigli /help
  2. Chiave di firma del repository:
       sudo -u arcbuild arcbase-kbuild key --generate
  3. VM di prova (scarica l'ultima ISO da GitHub, oppure --iso FILE):
       sudo -u arcbuild arcbase-kbuild setup-vm
  4. Prima build (poi ci pensa il timer ogni notte alle 03:30):
       sudo systemctl start arcbase-kbuild      # log: journalctl -fu arcbase-kbuild
  5. Su ogni PC Arcbase:
       sudo arcbase-kernel-mirror enable http://${ip:-<ip-del-server>}:8080
       sudo pacman -S linux-arcbase             # e/o linux-lts-arcbase
EOF
