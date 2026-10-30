# Arcbase Desktop

**Un sistema operativo desktop costruito da zero con [Linux From Scratch](https://www.linuxfromscratch.org/)
che usa insieme due gestori di pacchetti: `pacman` di Arch Linux e `apt`/`dpkg` di Debian.**

```
$ arc install firefox vlc            # dai repository Arch (pacman)
$ arc install --deb gimp             # da Debian 13 "trixie" (apt)
$ sudo apt install libreoffice       # anche apt funziona "nativamente"
$ arc search obs                     # cerca in entrambi i mondi
$ arc upgrade                        # aggiorna tutto: Arch + Debian
```

---

## Indice

- [Come funziona](#come-funziona)
- [Requisiti](#requisiti)
- [Compilare Arcbase](#compilare-arcbase)
- [Configurazione](#configurazione)
- [Usare `arc`](#usare-arc)
- [Struttura del repository](#struttura-del-repository)
- [Test](#test)
- [Limiti noti](#limiti-noti)

## Come funziona

Due gestori di pacchetti **non possono** possedere gli stessi file: se pacman e dpkg
installassero entrambi `/usr/lib/libc.so.6`, il sistema si romperebbe al primo
aggiornamento. Arcbase risolve il problema dando a ciascuno un territorio separato
e un unico strumento, `arc`, per governarli:

```
┌───────────────────────────────────────────────────────────────────────────┐
│                         arc  (CLI unificata)                              │
│   install · remove · search · upgrade · run · export · deb2pkg · doctor   │
├──────────────────────────────────┬────────────────────────────────────────┤
│  HOST — gestito da pacman        │  LAYER DEBIAN — gestito da apt/dpkg    │
│                                  │  /var/lib/arcbase/debian               │
│  ┌────────────────────────────┐  │                                        │
│  │ pacchetti Arch (core,extra)│  │  root Debian completo (debootstrap),   │
│  │ KDE/GNOME/Xfce, Firefox,   │  │  eseguito con bubblewrap:              │
│  │ mesa, pipewire, firmware…  │  │   · apt/dpkg veri di Debian            │
│  └────────────────────────────┘  │   · nessun file tocca /usr dell'host   │
│  ┌────────────────────────────┐  │   · le app condividono /home, display, │
│  │ arcbase-base (virtuale)    │  │     audio, D-Bus, GPU                  │
│  │ = sistema LFS compilato da │  │                                        │
│  │   sorgente: glibc, gcc,    │  │  le app installate vengono "esportate":│
│  │   systemd, PAM, pacman…    │  │   /usr/local/bin/<app>  (wrapper)      │
│  └────────────────────────────┘  │   /usr/local/share/applications/…      │
│                                  │   → compaiono nel menu del desktop     │
├──────────────────────────────────┴────────────────────────────────────────┤
│           kernel Linux + systemd + GRUB (BIOS e UEFI), senza initramfs    │
└───────────────────────────────────────────────────────────────────────────┘
```

### 1. Il base LFS diventa un pacchetto pacman

Il sistema base (glibc, gcc, bash, systemd, Linux-PAM, openssl, python, perl, …) è
compilato da sorgente seguendo **LFS 12.3 (systemd)**, poi registrato in pacman come
pacchetto virtuale **`arcbase-base`** che non contiene file ma dichiara
`provides=(glibc=2.41 bash=5.2.37 … libc.so=6-64 libssl.so=3-64 …)`:

- i nomi Arch equivalenti vengono da [`config/arch-provides.map`](config/arch-provides.map);
- le *soname* (`libfoo.so=N-64`, il formato usato dai pacchetti Arch) vengono rilevate
  automaticamente da `/usr/lib`.

Così `pacman -S plasma-desktop` trova soddisfatte le dipendenze di base e scarica dai
repository Arch solo ciò che manca. `arcbase-base` è in `HoldPkg` e `arc` ne impedisce
la rimozione.

Per essere compatibile con i pacchetti Arch, il layout del filesystem segue quello di
Arch: `/usr/sbin → bin`, `/lib64 → usr/lib`. Gli hook ALPM che in Arch arrivano con il
pacchetto `systemd` (sysusers, tmpfiles, daemon-reload, udev, hwdb…) sono forniti da
Arcbase in [`rootfs/usr/share/libalpm/hooks`](rootfs/usr/share/libalpm/hooks).

### 2. Compatibilità ABI con i binari Arch

I pacchetti Arch sono compilati con le ultime glibc e libstdc++. Se il base LFS è più
vecchio, alcuni programmi non partirebbero (`version GLIBC_2.xx not found`). Per questo:

- **`arcbase-runtime-sync`** confronta glibc / gcc-libs del base con quelle di Arch e,
  se Arch è più recente, *adotta* il pacchetto Arch (lo toglie dai provides di
  `arcbase-base` e lo installa sopra i file LFS). Gira durante la build e ad ogni
  `arc upgrade` (disattivabile con `ARC_RUNTIME_SYNC=never`).
- un hook ALPM (**`arcbase-abi-check`**) controlla ogni binario installato da pacman e
  segnala librerie o simboli mancanti; `arc doctor --abi` fa la stessa verifica su
  tutto il sistema.

### 3. Il layer Debian

`apt` e `dpkg` sono quelli veri di Debian, ma lavorano su un root Debian separato
(`/var/lib/arcbase/debian`, creato con `debootstrap`):

- come **root** (installazioni) il layer è montato in lettura/scrittura con bubblewrap;
  `policy-rc.d` impedisce che i pacchetti avviino servizi;
- come **utente** (eseguire le app) il layer è montato in sola lettura e condivide con
  l'host `/home`, `/tmp`, Wayland/X11, PipeWire, D-Bus, `/dev` (GPU, audio), font,
  fuso orario, DNS e utenti;
- dopo ogni operazione apt, **le app installate dall'utente vengono esportate**:
  wrapper in `/usr/local/bin`, file `.desktop` (con suffisso "(Debian)") e icone in
  `/usr/local/share`. Un comando già presente sull'host non viene mai sovrascritto.
- sull'host `apt`, `apt-get`, `apt-cache`, `apt-mark`, `dpkg` e `dpkg-query` sono
  collegamenti ad `arc`, che li inoltra al layer: `sudo apt install ./pacchetto.deb`
  funziona come su Debian.

In alternativa, `arc deb2pkg file.deb` converte un `.deb` in un pacchetto pacman
nativo (in stile *debtap*), da installare direttamente sull'host.

### Modifiche rispetto a LFS

| Cosa | Perché |
|---|---|
| Linux-PAM (da BLFS) prima di shadow e systemd; systemd con `-D pam=enabled` | logind e i display manager richiedono `pam_systemd` |
| Configurazione PAM compatibile con `pambase` di Arch (`system-login`, …) | i pacchetti Arch (sddm, gdm, sudo…) includono quei file |
| systemd con `sysusers=true` e gruppi `render`/`sgx` | utenti di sistema dei pacchetti Arch; accesso alla GPU |
| gmp `--enable-fat`, libffi `--with-gcc-arch=x86-64` | l'immagine deve girare su qualunque CPU x86-64 |
| util-linux con `runuser` | serve agli script di build e a `arc deb2pkg` |
| `/usr/sbin → bin`, `/lib64 → usr/lib` | layout di Arch |
| GRUB compilato sia per i386-pc sia per x86_64-efi | immagine avviabile in BIOS e UEFI |
| Stadio 10: GnuPG, GPGME, libarchive, curl, **pacman**, bubblewrap, debootstrap | i due gestori di pacchetti, compilati da sorgente |

## Requisiti

- Host Linux **x86_64** con gli strumenti di sviluppo richiesti da LFS
  (`make check` li verifica tutti), più `curl`, `losetup`, `sfdisk`, `mkfs.ext4`,
  `mkfs.vfat`, `blkid`, `runuser`;
- una partizione vuota da almeno **60 GB** (sorgenti, compilazione, desktop);
- almeno 4 GB di RAM (8+ consigliati), connessione a Internet (anche durante il chroot:
  pacman e debootstrap scaricano i pacchetti);
- tempo: la compilazione del sistema base richiede **diverse ore** a seconda della CPU.

## Compilare Arcbase

```bash
git clone https://github.com/lori28167/arcbase-desktop.git
cd arcbase-desktop

# 1. partizione di destinazione (esempio: /dev/sdb1 — ATTENZIONE, viene formattata)
sudo mkfs.ext4 /dev/sdb1
sudo mkdir -p /mnt/lfs && sudo mount /dev/sdb1 /mnt/lfs

# 2. (facoltativo) personalizzazione
cp config/arcbase.conf config/local.conf   # e modifica solo ciò che serve

# 3. build completa
sudo make all
```

oppure uno stadio alla volta (ogni stadio è **riprendibile**: dopo un errore basta
rilanciarlo, i pacchetti già compilati vengono saltati):

| Comando | Cosa fa | Riferimento |
|---|---|---|
| `make check` | verifica i requisiti dell'host | LFS 2.2 |
| `sudo make prepare` | gerarchia di `$LFS`, utente `lfs` | LFS 4 |
| `sudo make download` | scarica ~100 sorgenti, verifica gli md5 LFS | LFS 3 |
| `sudo make toolchain` | cross-toolchain (come utente `lfs`) | LFS 5 |
| `sudo make temp-tools` | strumenti temporanei (come utente `lfs`) | LFS 6 |
| `sudo make chroot-tools` | entra nel chroot, strumenti aggiuntivi | LFS 7 |
| `sudo make base-system` | sistema base + Linux-PAM | LFS 8 |
| `sudo make merge-usr` | layout `/usr` compatibile con Arch | — |
| `sudo make config` | rete, locale, utenti, identità, overlay | LFS 9 |
| `sudo make kernel` | kernel + GRUB BIOS/UEFI | LFS 10 |
| `sudo make package-managers` | pacman, `arcbase-base`, portachiavi, layer apt | BLFS |
| `sudo make desktop` | desktop dai repository Arch, layer Debian | — |
| `sudo make image` | immagine disco avviabile in `out/` | — |
| `sudo make iso` | ISO live ibrida (BIOS + UEFI, CD/USB) in `out/` | — |
| `make iso-test` | avvia la ISO in QEMU (BIOS e UEFI) fino al login | — |
| `make install-test` | installa dalla ISO su un disco virtuale e lo riavvia | — |

I log di ogni pacchetto sono in `$LFS/sources/.arcbase-logs/`. `sudo make enter` apre
una shell nel chroot, `sudo make umount` smonta i file system virtuali.

### Avviare l'immagine

```bash
# QEMU con UEFI e accelerazione 3D
qemu-system-x86_64 -enable-kvm -m 4G -smp 4 -cpu host \
    -bios /usr/share/ovmf/OVMF.fd -device virtio-vga-gl -display gtk,gl=on \
    -drive file=out/arcbase-desktop-1.1-x86_64.img,format=raw,if=virtio

# chiavetta USB (cancella /dev/sdX!)
sudo dd if=out/arcbase-desktop-1.1-x86_64.img of=/dev/sdX bs=4M status=progress conv=fsync
```

### ISO live

`sudo make iso` (dopo gli stadi fino a `desktop`) crea
`out/arcbase-desktop-1.1-x86_64.iso`, avviabile da CD/DVD o, scritta con `dd`, da
chiavetta USB, sia in BIOS sia in UEFI. Il sistema è compresso in uno squashfs
(`/arcbase/rootfs.sfs`) e all'avvio diventa un overlay con le modifiche in RAM. È
l'unico caso in cui Arcbase usa un initramfs: uno minimale (bash, mount, blkid,
`switch_root` e [`live-init.sh`](rootfs/usr/lib/arcbase/live-init.sh)) che trova il
supporto tramite l'etichetta `ARCBASE_LIVE`. Servono sull'host `mksquashfs`
(squashfs-tools) e `xorriso`.

```bash
sudo make iso
make iso-test          # QEMU senza display: GRUB → kernel → systemd → login,
                       # con BIOS e (se c'è OVMF) UEFI; salva out/iso-test-*.ppm
qemu-system-x86_64 -enable-kvm -m 4G -smp 4 -cpu host \
    -cdrom out/arcbase-desktop-1.1-x86_64.iso
```

La voce di GRUB "shell di debug nell'initramfs" ferma l'avvio con la root live già
montata in `/new_root`.

### Installare su disco

Dalla sessione live l'icona **Installa Arcbase Desktop** (la prima della dock, e sulla
scrivania) apre l'**installer grafico**, [Calamares](https://calamares.io) con il
branding di Arcbase: lingua, fuso orario, tastiera, disco (cancella tutto, oppure
partizioni a mano), utente e nome del computer, riepilogo e installazione, con una
conferma prima di toccare il disco. Parte senza password (la sessione live è la sola
che può lanciarlo). Come funziona e come si personalizza: [`calamares/README.md`](calamares/README.md).

Calamares non è nei repository di Arch: lo stadio `desktop` lo compila dal sorgente
(`ARC_CALAMARES`, `auto` per i desktop `kde` e `arc`). Il sistema installato non ha
initramfs, quindi **la root può essere solo ext4** (niente btrfs/xfs/LVM/LUKS per `/`).

Se Calamares non è stato compilato (`ARC_CALAMARES=no`, o desktop GNOME/Xfce) resta
l'installer da terminale `sudo arcbase-install`, che si può usare comunque (è anche
quello provato in QEMU da `make install-test`). Chiede
disco, nome del computer, utente, password, fuso orario e tastiera (default `us`),
poi **cancella il disco scelto** e crea:

| Partizione | Dimensione | Uso |
|---|---|---|
| BIOS boot | 1 MiB | GRUB per BIOS |
| ESP (FAT32) | 512 MiB | GRUB per UEFI, montata su `/boot/efi` |
| root (ext4) | resto del disco | il sistema |

Il sistema viene copiato dallo squashfs della ISO (le modifiche fatte nella sessione
live non vengono copiate) e GRUB è installato sia per BIOS sia per UEFI. Per
un'installazione non interattiva:

```bash
sudo arcbase-install --disk /dev/sdX --yes --hostname pc --user mario \
    --fullname "Mario Rossi" --password '…' --timezone Europe/Rome --keymap it
```

Senza `--root-password` l'account root resta bloccato e si amministra con `sudo`.
`make install-test` prova tutto in QEMU: installa su un disco virtuale vuoto (BIOS e
UEFI), riavvia dal disco e verifica utente, nome host e stato di systemd.

Per installare su una partizione reale invece che su un'immagine, dopo aver copiato il
sistema si usa `arcbase-bootloader --disk /dev/sdX --root /dev/sdX3 --esp /dev/sdX2`
(senza `efibootmgr` GRUB viene installato nel percorso UEFI di fallback `\EFI\BOOT`).

### Kernel aggiornati (mirror)

Il kernel della build resta fisso, ma un server di casa può compilare, provare in QEMU
e pubblicare da solo l'ultimo kernel stabile (`linux-arcbase`) e l'ultimo LTS
(`linux-lts-arcbase`), avvisando su Telegram: vedi
[`tools/kernel-mirror`](tools/kernel-mirror/README.md). Sui PC Arcbase:

```bash
sudo arcbase-kernel-mirror enable http://<server>:8080
sudo pacman -S linux-arcbase linux-lts-arcbase
```

GRUB elenca tutti i kernel in `/boot` (lo rigenera `arcbase-grub-cfg` a ogni
aggiornamento); le opzioni di avvio sono in `/etc/arcbase/boot.conf`.

Credenziali iniziali: utente `arc` / password `arcbase` (anche per root).
**Cambiale al primo accesso** con `passwd`, oppure impostale prima della build in
`config/local.conf`.

## Configurazione

Tutte le opzioni sono in [`config/arcbase.conf`](config/arcbase.conf) e si
sovrascrivono in `config/local.conf` o come variabili d'ambiente. Le principali:

| Variabile | Default | Descrizione |
|---|---|---|
| `LFS` | `/mnt/lfs` | punto di montaggio della destinazione |
| `ARC_DESKTOP` | `kde` | `kde`, `arc` ([arc UI](arc-ui/README.md) su base KDE), `gnome`, `xfce` o `none` ([liste](config/desktop)) |
| `ARC_LOCALE` / `ARC_KEYMAP` / `ARC_TIMEZONE` | `it_IT.UTF-8` / `it` / `Europe/Rome` | lingua, tastiera, fuso |
| `ARC_USER`, `ARC_USER_PASSWORD`, `ARC_ROOT_PASSWORD` | `arc`, `arcbase`, `arcbase` | utente desktop |
| `ARC_ARCH_REPOS` | `core extra` | repository Arch abilitati |
| `ARC_DEBIAN_SUITE` | `trixie` | versione Debian del layer |
| `ARC_DEBIAN_INIT_AT_BUILD` | `yes` | crea il layer Debian già nell'immagine |
| `ARC_DEBIAN_PACKAGES` | *(vuoto)* | pacchetti Debian da preinstallare |
| `ARC_PREFER` | `arch` | chi vince in `arc install <nome>` se esiste in entrambi |
| `ARC_RUNTIME_SYNC` | `auto` | allineamento ABI di glibc/gcc-libs ad Arch |
| `ARC_CALAMARES` | `auto` | installer grafico Calamares nella ISO: `yes`, `no`, `auto` (sì con `kde`/`arc`) |
| `ARC_IMAGE_SIZE` | `32G` | dimensione dell'immagine disco |
| `ARC_JOBS` | numero di CPU | processi di compilazione paralleli |
| `LFS_TESTS` | `0` | `1` esegue le test suite di LFS (molto più lento) |

Le versioni dei sorgenti sono in [`config/packages.conf`](config/packages.conf) e la
configurazione del kernel in [`config/kernel/arcbase.config`](config/kernel/arcbase.config).

## Usare `arc`

```text
arc install [-a|--arch] [-d|--deb] [-y] <pkg|file.deb|file.pkg.tar.zst>...
arc remove  [-a|-d] [-y] <pkg>...      # l'origine viene rilevata da sola
arc update | upgrade [-y]              # Arch + layer Debian
arc search <termine>                   # risultati Arch e Debian
arc info <pkg> | list [-a|-d] | origin <pkg>
arc run <comando>                      # esegue un programma del layer Debian
arc shell                              # shell nel layer Debian
arc deb init|status|shell|reset        # gestione del layer
arc export [pkg] | unexport <pkg>      # app Debian nel menu/PATH
arc deb2pkg <file.deb>                 # .deb → pacchetto pacman nativo
arc doctor [--abi] | sync-runtime
```

Esempi:

```bash
arc origin glibc        # glibc: sistema base LFS (compilato da sorgente, arcbase-base)
arc origin firefox      # firefox: installato da Arch Linux (pacman)
arc origin gimp         # gimp: non installato, disponibile in Arch Linux
sudo arc install --deb gimp       # forza la versione Debian
gimp                              # wrapper esportato → arc run -- /usr/bin/gimp
sudo arc install ./google-chrome-stable_current_amd64.deb
arc list                          # [arch] firefox …   [debian] gimp …
```

`pacman` resta disponibile per tutto ciò che riguarda l'host (`pacman -Qo`, `-Qi`, …).

## Struttura del repository

```
Makefile                     orchestrazione degli stadi
config/
  arcbase.conf               configurazione della build
  packages.conf              sorgenti e versioni (LFS 12.3 + BLFS + pacman/apt)
  arch-provides.map          nomi Arch forniti dal base LFS
  kernel/arcbase.config      frammento di configurazione del kernel
  desktop/*.list             pacchetti di KDE, arc, GNOME, Xfce
scripts/
  lib/common.sh              motore di build (ricette, stamp, log, dry-run)
  00…05, 12                  stadi eseguiti sull'host
  chroot/06…11               stadi eseguiti nel chroot
rootfs/                      file installati nel sistema
  usr/bin/arc                CLI unificata (+ link apt, dpkg…)
  usr/lib/arcbase/           layer Debian ed esportazione delle app
  usr/bin/arcbase-*          mkbase, runtime-sync, abi-check, bootloader
  usr/share/libalpm/hooks/   hook ALPM (systemd, controllo ABI)
  etc/pam.d, etc/profile…    configurazione di sistema
arc-ui/                      desktop arc UI su base KDE (ARC_DESKTOP=arc, vedi arc-ui/README.md)
  shell/                     arc-shell: topbar, dock, widget, launcher, notifiche (Qt/QML)
  theme/                     Kvantum, decorazioni, SDDM, blocco schermo, Alt+Tab
calamares/                   installer grafico (Calamares) della ISO live, vedi calamares/README.md
  settings.conf, modules/    sequenza e configurazione dei moduli
  python/                    moduli scritti per Arcbase: arcbase_bootloader, arcbase_localize
  branding/arcbase/          aspetto: logo, slideshow, foglio di stile
  bin/, polkit/              lanciatore dalla sessione live (pkexec, senza password)
tests/                       test senza root né rete
```

## Test

```bash
make lint    # shellcheck su tutti gli script
make test    # suite:
             #  - test-recipes: ogni stadio ha tutte le ricette e i sorgenti (dry run)
             #  - test-build-engine: estrazione, errexit, stamp, log
             #  - test-arc: arc con pacman/bubblewrap/apt simulati (installazione
             #    mista, esportazione app, shim apt/dpkg, deb init, arcbase-mkbase,
             #    runtime-sync, abi-check)
             #  - test-kernel-mirror: strumenti del mirror dei kernel
             #  - test-arc-ui: temi generati, install.sh in una cartella di prova,
             #    sessione arc, controlli statici di QML e C++
             #  - test-calamares: configurazione dell'installer grafico, sequenza,
             #    helper di avvio, moduli Python con libcalamares simulato
```

La CI su GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) esegue
lint e test ad ogni push.

## Limiti noti

- **Solo x86_64.** Niente Secure Boot e niente initramfs: la root non può essere
  cifrata (LUKS) e i driver di avvio sono compilati nel kernel.
- **Kernel compilato da sorgente**: moduli esterni come i driver NVIDIA proprietari o
  i pacchetti `*-dkms` di Arch non sono supportati; con GPU NVIDIA si usa `nouveau`.
- **Versioni**: le ricette seguono LFS 12.3. Per aggiornare il base a un libro LFS più
  recente vanno aggiornate `config/packages.conf` e le ricette corrispondenti; fino ad
  allora la compatibilità con i binari Arch è garantita da `arcbase-runtime-sync`.
- Alcuni URL (pool Debian, portachiavi Arch) puntano a versioni precise che col tempo
  vengono rimosse dai mirror: in caso di errore di `make download` aggiorna la voce in
  `config/packages.conf`.
- Il layer Debian è pensato per **applicazioni**: i servizi di sistema (demoni systemd)
  dei pacchetti Debian non vengono avviati; per quelli usa i pacchetti Arch.
