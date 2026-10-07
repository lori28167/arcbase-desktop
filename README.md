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

I log di ogni pacchetto sono in `$LFS/sources/.arcbase-logs/`. `sudo make enter` apre
una shell nel chroot, `sudo make umount` smonta i file system virtuali.

### Avviare l'immagine

```bash
# QEMU con UEFI e accelerazione 3D
qemu-system-x86_64 -enable-kvm -m 4G -smp 4 -cpu host \
    -bios /usr/share/ovmf/OVMF.fd -device virtio-vga-gl -display gtk,gl=on \
    -drive file=out/arcbase-desktop-1.0-x86_64.img,format=raw,if=virtio

# chiavetta USB (cancella /dev/sdX!)
sudo dd if=out/arcbase-desktop-1.0-x86_64.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Per installare su una partizione reale invece che su un'immagine, dopo aver copiato il
sistema si usa `arcbase-bootloader --disk /dev/sdX --root /dev/sdX3 --esp /dev/sdX2`.

Credenziali iniziali: utente `arc` / password `arcbase` (anche per root).
**Cambiale al primo accesso** con `passwd`, oppure impostale prima della build in
`config/local.conf`.

## Configurazione

Tutte le opzioni sono in [`config/arcbase.conf`](config/arcbase.conf) e si
sovrascrivono in `config/local.conf` o come variabili d'ambiente. Le principali:

| Variabile | Default | Descrizione |
|---|---|---|
| `LFS` | `/mnt/lfs` | punto di montaggio della destinazione |
| `ARC_DESKTOP` | `kde` | `kde`, `gnome`, `xfce` o `none` ([liste](config/desktop)) |
| `ARC_LOCALE` / `ARC_KEYMAP` / `ARC_TIMEZONE` | `it_IT.UTF-8` / `it` / `Europe/Rome` | lingua, tastiera, fuso |
| `ARC_USER`, `ARC_USER_PASSWORD`, `ARC_ROOT_PASSWORD` | `arc`, `arcbase`, `arcbase` | utente desktop |
| `ARC_ARCH_REPOS` | `core extra` | repository Arch abilitati |
| `ARC_DEBIAN_SUITE` | `trixie` | versione Debian del layer |
| `ARC_DEBIAN_INIT_AT_BUILD` | `yes` | crea il layer Debian già nell'immagine |
| `ARC_DEBIAN_PACKAGES` | *(vuoto)* | pacchetti Debian da preinstallare |
| `ARC_PREFER` | `arch` | chi vince in `arc install <nome>` se esiste in entrambi |
| `ARC_RUNTIME_SYNC` | `auto` | allineamento ABI di glibc/gcc-libs ad Arch |
| `ARC_IMAGE_SIZE` | `32G` | dimensione dell'immagine disco |
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
  desktop/*.list             pacchetti di KDE, GNOME, Xfce
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
tests/                       test senza root né rete
```

## Test

```bash
make lint    # shellcheck su tutti gli script
make test    # 3 suite:
             #  - test-recipes: ogni stadio ha tutte le ricette e i sorgenti (dry run)
             #  - test-build-engine: estrazione, errexit, stamp, log
             #  - test-arc: arc con pacman/bubblewrap/apt simulati (installazione
             #    mista, esportazione app, shim apt/dpkg, deb init, arcbase-mkbase,
             #    runtime-sync, abi-check)
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
