# Installer grafico (Calamares)

La ISO live installa Arcbase Desktop con [Calamares](https://calamares.io), con il
branding di Arcbase. È un sostituto grafico di `arcbase-install` (che resta, da
terminale, ed è quello provato in QEMU da `make install-test`).

```
Benvenuto → Località → Tastiera → Partizioni → Utente → Riepilogo ─┐ conferma
                                                                   ▼
 partition → mount → unpackfs → removeuser → fstab → locale → keyboard
   → arcbase_localize → users → arcbase_bootloader → cleanup → preservefiles → umount
                                                                   ▼
                                                              Fine (riavvia)
```

## Come si arriva alla ISO

| Passo | Dove | Cosa |
|---|---|---|
| download | `config/packages.conf` | sorgente `calamares` dal repository ufficiale (Codeberg), con lo **SHA-256** fissato: `02-download.sh` e la build rifiutano un file diverso |
| compilazione | `scripts/chroot/11-desktop.sh` (`ARC_CALAMARES`) | dopo le librerie Qt/KDE di Arch (`kpmcore`, `yaml-cpp`, `rsync`…); solo i moduli usati, Qt 6, Python con pybind11 incluso nel sorgente |
| verifica | stesso script | si ferma se un modulo (es. `partition` senza kpmcore) è stato saltato da CMake in silenzio |
| configurazione | `scripts/13-iso.sh` → `calamares/install.sh` | solo nella squashfs della live, mai in `$LFS` |

`ARC_CALAMARES=auto` (default) lo compila con i desktop `kde` e `arc`; `yes` lo forza,
`no` lo esclude e la ISO usa il lanciatore di `arcbase-install` da terminale.

Calamares non è nei repository di Arch (solo AUR) e il suo sviluppo è passato da GitHub
a Codeberg: la versione è in `config/packages.conf`. Passando a una nuova versione
vanno ricontrollati i nomi dei moduli (`CALAMARES_MODULES` e `CALAMARES_SKIP_MODULES`
in `11-desktop.sh`) e le configurazioni (vedi "Controllare le configurazioni").

## Cosa è diverso da un'installazione Calamares standard

Arcbase non è una distribuzione Arch/Debian e il sistema installato **non ha
initramfs**. Per questo:

- **Il bootloader non è il modulo `bootloader` di Calamares** (si aspetta
  `grub-mkconfig` e un initramfs): `arcbase_bootloader` (`python/`) chiama
  `arcbase-bootloader`, lo stesso strumento di `arcbase-install` e delle immagini
  (GRUB per BIOS o UEFI, `root=PARTUUID=…`, menu di `arcbase-grub-cfg`). Ricava root,
  ESP e disco da ciò che il modulo `partition` lascia in Global Storage. In UEFI scrive
  anche il percorso di ripiego `\EFI\BOOT\BOOTX64.EFI`. L'`/etc/fstab` resta quello di
  Calamares (swap e partizioni extra comprese): `arcbase-bootloader --no-fstab`.
- **La root può essere solo ext4**: xfs e btrfs sono moduli del kernel, LVM e LUKS
  richiedono un initramfs. `partition.conf` offre solo ext4 (anche a mano:
  `directoryFilesystemRestrictions`), niente cifratura, LVM né ibernazione, e il modulo
  `arcbase_bootloader` rifiuta una root diversa con un messaggio chiaro.
- **Le locale si generano con `localedef`**, non con `locale-gen` (in LFS non c'è):
  `arcbase_localize` (`python/`) ne genera nel sistema installato la lingua scelta se la
  ISO non l'ha, scrive `/etc/locale.conf` e il layout di tastiera di KDE
  (`/etc/xdg/kxkbrc`). Se una locale non si riesce a generare ripiega su `C.UTF-8`.
- **La copia usa la squashfs già montata dalla live** (`/run/arcbase-live/sfs`, come
  fa `arcbase-install`): le modifiche fatte durante la sessione live non finiscono sul
  disco. Si escludono la home dell'utente live e l'installer stesso.
- **Utente come in `arcbase-install`**: l'utente della live (`ARC_USER`) viene tolto
  (`removeuser`) prima di creare il nuovo; il nuovo è amministratore (gruppo `wheel`) e
  l'account root resta **bloccato** (`passwd -l root`; la root della live ha una
  password nota). Per questo `users.conf` non chiede una password di root.
- **Il log dell'installazione** resta in `/var/log/Calamares.log` (`preservefiles`).

## Avvio dalla sessione live

L'icona **Installa Arcbase Desktop** (`arcbase-install.desktop`: la dock di arc UI
la mette per prima) esegue `arcbase-install-gui`:

1. controlla di essere nella live (altrimenti rifiuta) e raccoglie poche variabili
   d'ambiente (`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `DISPLAY`, `XAUTHORITY`, …);
2. chiede a polkit di eseguire `/usr/lib/arcbase/installer-root` come root. Il criterio
   (`polkit/org.arcbase.installer.policy`) lo permette senza password a chi ha la
   sessione attiva: **solo nella live**, il file non esiste nel sistema installato;
3. `installer-root` **verifica ogni variabile** (arrivano da un processo non fidato:
   socket Wayland che esiste davvero in `/run/user/<uid>`, `XAUTHORITY` dell'utente…),
   non accetta nient'altro e avvia `/usr/bin/calamares` con un ambiente pulito, stile
   Fusion (così non dipende dalla configurazione di KDE dell'utente, che root non legge).

Da terminale: `arcbase-install-gui -d` avvia Calamares in modalità debug; il log è in
`/root/.cache/calamares/session.log`.

## File

```
settings.conf              sequenza dei moduli
modules/*.conf             configurazione dei moduli (segnaposto @LIVE_USER@, @REGION@, @ZONE@)
python/arcbase_*/          moduli scritti per Arcbase: module.desc + main.py
branding/arcbase/          branding.desc (nome e versione dall'os-release), slideshow, stile
bin/arcbase-install-gui    lanciatore (utente) → pkexec
bin/installer-root         helper per root (controlla gli argomenti, avvia Calamares)
polkit/                    criterio polkit (solo live)
arcbase-install.desktop    lanciatore nel menu, sulla scrivania e nella dock
install.sh                 installa tutto in una cartella (la squashfs della live)
```

`install.sh [--live-user NOME] [--timezone ZONA] DESTDIR` sostituisce i segnaposto con
valori controllati e rifiuta `/`: l'installer non va installato nel sistema in uso.

## Provarlo

```bash
sudo make desktop      # compila Calamares (ARC_CALAMARES) e il resto
sudo make iso
make iso-run           # avvia la ISO in QEMU con una finestra; poi l'icona dell'installer
```

Va provato con un disco virtuale vuoto, in BIOS e in UEFI (con OVMF). Se qualcosa non
va guarda `/root/.cache/calamares/session.log` nella live e `/var/log/Calamares.log`
sul sistema installato.

### Controllare le configurazioni

`make test` esegue `tests/test-calamares.sh`: coerenza tra sequenza e moduli, ordine dei
passi, script di installazione, helper di avvio (argomenti validi e non), moduli Python
con un `libcalamares` simulato. Non compila né avvia Calamares. Per controllare le
configurazioni anche contro gli schemi JSON del progetto:

```bash
curl -LO https://codeberg.org/Calamares/calamares/releases/download/v3.4.3/calamares-3.4.3.tar.gz
tar xf calamares-3.4.3.tar.gz
CALAMARES_SRC=$PWD/calamares-3.4.3 tests/test-calamares.sh      # serve python3-jsonschema
```

(Lo schema di `partition` in 3.4.3 elenca `mountpointFilesystemRestrictions` mentre il
codice legge `directoryFilesystemRestrictions`: il test lo tiene in conto.)

## Limiti

- Solo ext4 per la root, niente cifratura del disco (vedi sopra).
- In BIOS Calamares crea una tabella MBR con un'unica partizione root; su un disco GPT
  già esistente serve una partizione "BIOS boot" (flag `bios_grub`) per installare GRUB.
- Le slide e le stringhe dei moduli `arcbase_*` sono in italiano/inglese: le traduzioni
  di Calamares coprono le sue pagine, non questi testi.
