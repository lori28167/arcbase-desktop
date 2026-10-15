# Mirror dei kernel Arcbase

Un server di casa (per esempio una VM sul Beelink con Proxmox) compila da solo i
kernel nuovi, li prova e li pubblica come repository pacman `[arcbase-kernel]`:

| Pacchetto | Kernel | Versione (`uname -r`) |
|---|---|---|
| `linux-arcbase` | ultimo **stabile** di kernel.org | `7.2.11-arcbase` |
| `linux-lts-arcbase` | ultimo **longterm** (LTS) | `6.18.57-arcbase-lts` |

I due pacchetti possono stare insieme sullo stesso PC: GRUB avvia il kernel più
recente e mette gli altri in **Altri kernel**. Il kernel originale della build LFS
resta sempre disponibile come riserva.

## Come funziona

Ogni notte alle 03:30 il timer `arcbase-kbuild.timer` esegue `arcbase-kbuild run`,
che per ciascun pacchetto:

1. legge `releases.json` di kernel.org e lo confronta con l'ultima versione
   pubblicata. Ricompila anche se è cambiata `config/kernel/arcbase.config` su
   GitHub (con pkgrel+1);
2. scarica i sorgenti in `/srv/arcbase-mirror/sources/` e **verifica la firma GPG**:
   solo le chiavi di Linus Torvalds, Greg Kroah-Hartman e Sasha Levin, con impronte
   fissate nello script;
3. compila con `defconfig` + `arcbase.config` e controlla le opzioni di
   `config/kernel/required-options`;
4. crea il pacchetto pacman (kernel in `/boot`, moduli in `/usr/lib/modules`);
5. **lo prova in QEMU**:
   - lo installa con `pacman -U` in una copia usa e getta della VM Arcbase;
   - verifica che GRUB punti al nuovo kernel e riavvia;
   - controlla:
     - che sia in uso il kernel nuovo;
     - che systemd sia `running` e nessuna unità sia fallita;
     - che i moduli siano caricati;
     - che ci sia una scheda audio e la rete;
     - che `dmesg` non contenga Oops/BUG/WARNING;
6. se la prova passa lo firma, lo pubblica e aggiorna il database. Tiene le ultime 3
   versioni, scaricabili con `pacman -U` per tornare indietro;
7. ti scrive su **Telegram**:
   - ✅ pubblicato, con i risultati della prova e la schermata della VM;
   - oppure ❌ con il motivo del fallimento e il log in allegato.

   Una versione fallita non viene ritentata ogni notte: aspetta la versione
   successiva, una modifica della configurazione o `arcbase-kbuild run --force`.

## Installazione sul server

Consigliata una VM Debian 13 su Proxmox:
- 4 o più core, 8 GB di RAM, 60 GB di disco;
- CPU di tipo **host**, così QEMU dentro la VM può usare KVM (virtualizzazione
  annidata).

Funziona anche su Arch Linux.

```bash
git clone https://github.com/lori28167/arcbase-desktop.git
cd arcbase-desktop/tools/kernel-mirror
sudo ./install.sh
```

`install.sh`:
- installa le dipendenze;
- crea l'utente di sistema `arcbuild`;
- copia `arcbase-kbuild` e il bot `arcbase-kbot` in `/usr/local/bin`, e l'helper
  `arcbase-kbuild-ctl` in `/usr/local/sbin`;
- aggiunge la regola sudo per il bot (`/etc/sudoers.d/arcbase-kbuild`, controllata
  con `visudo`);
- crea `/etc/arcbase-kbuild.conf` (impostazioni) e `/etc/arcbase-kbuild.env`
  (token del bot Telegram, permessi 600, leggibile solo da `arcbuild`);
- attiva:
  - `arcbase-kbuild.timer`;
  - `arcbase-kmirror-http.service`, che serve `/srv/arcbase-mirror` sulla porta
    8080;
  - `arcbase-kbot.service`, il bot Telegram.

Per aggiornare il builder: `git pull` e di nuovo `sudo ./install.sh`. Il solo
`git pull` non basta, perché i programmi installati sono copie. La
configurazione esistente non viene toccata.

Poi:

```bash
sudo -u arcbuild nano /etc/arcbase-kbuild.env        # token e chat del bot Telegram
sudo -u arcbuild arcbase-kbuild notify-test          # messaggio di prova
sudo systemctl restart arcbase-kbot                  # attiva i comandi del bot
sudo -u arcbuild arcbase-kbuild key --generate       # chiave di firma del repository
sudo -u arcbuild arcbase-kbuild setup-vm             # VM di prova (ISO >= 1.1 da GitHub, o --iso FILE)
sudo systemctl start arcbase-kbuild                  # prima build; log: journalctl -fu arcbase-kbuild
```

Per creare il bot: su Telegram scrivi a **@BotFather** → `/newbot` e copia il
token. Poi manda un messaggio al bot e apri
`https://api.telegram.org/bot<TOKEN>/getUpdates`, dove trovi l'id della chat
(`"chat":{"id":...}`).

Altri comandi:
- `arcbase-kbuild check`: versioni pubblicate e versioni su kernel.org;
- `arcbase-kbuild run lts --force`: ricompila subito;
- `arcbase-kbuild repo`: rigenera il database.

## Comandi del bot Telegram

Il bot risponde **solo alla chat configurata** in `KB_TELEGRAM_CHAT`; i messaggi
da altre chat vengono ignorati e registrati nel log (`journalctl -u arcbase-kbot`).
I comandi compaiono anche nel menu `/` di Telegram.

| Comando | Cosa fa |
|---|---|
| `/status` | build in corso (da quanto, a che punto), kernel pubblicati e versioni su kernel.org, versioni fallite, prossima build automatica |
| `/build` | compila subito i kernel con una versione nuova |
| `/build lts` · `/build stable` | solo un kernel |
| `/build lts force` | ricompila anche se è già aggiornato (pkgrel+1) |
| `/stop` | ferma la build in corso; la versione non viene segnata come fallita |
| `/orario` | mostra l'orario della build notturna |
| `/orario 04:00` · `/orario off` · `/orario on` | sposta, sospende o riattiva la build notturna |
| `/log` | ultime righe del log della build |

Il bot gira come `arcbuild`, senza privilegi. Per avviare/fermare le build e
cambiare il timer usa `sudo arcbase-kbuild-ctl`, l'unico comando permesso dalla
regola sudo, che accetta solo argomenti validi:
- `build all|stable|lts[-force]`;
- `stop`;
- `schedule HH:MM|off|on`.

L'orario scelto con `/orario` è un drop-in di systemd in
`/etc/systemd/system/arcbase-kbuild.timer.d/orario.conf`.

## Pubblicazione per tutti gli utenti (GitHub Releases)

Con `KB_PUBLISH=github` in `/etc/arcbase-kbuild.conf`, dopo ogni build riuscita il
repository viene copiato anche negli asset della release `x86_64` di
[`lori28167/arcbase-kernel`](https://github.com/lori28167/arcbase-kernel). Da lì
pacman lo legge direttamente, e Arcbase lo ha già configurato come
`[arcbase-kernel]`.

Serve un token GitHub **fine-grained**, da mettere in `/etc/arcbase-kbuild.env` come
`KB_GITHUB_TOKEN`:
1. github.com → Settings → Developer settings → Fine-grained tokens;
2. **Repository access:** solo `arcbase-kernel`;
3. **Permissions:** Contents → **Read and write**, nient'altro.

`arcbase-kbuild publish` sincronizza a mano: carica solo i file cambiati e
toglie le versioni vecchie. Se una pubblicazione fallisce, ricevi ❌ su Telegram
e viene ritentata alla build successiva.

La chiave di firma va indicata in `config/arcbase.conf` (`ARC_KERNEL_KEY_FPR`,
l'impronta mostrata da `arcbase-kbuild key`): le ISO costruite dopo si fidano
solo dei pacchetti firmati da quella chiave.

## Sui PC Arcbase

Arcbase ha già `[arcbase-kernel]` attivo (repository pubblico su GitHub) e
`linux-arcbase` installato. Per usare invece un mirror di casa:

```bash
sudo arcbase-kernel-mirror enable http://<ip-del-server>:8080
sudo pacman -S linux-arcbase          # e/o linux-lts-arcbase
```

Per tornare al repository pubblico: `sudo arcbase-kernel-mirror enable`, senza
URL.

`enable`:
- scarica la chiave pubblica del mirror e ne mostra l'impronta, da confrontare con
  `arcbase-kbuild key` sul server;
- la aggiunge a pacman;
- aggiunge `[arcbase-kernel]` a `/etc/pacman.conf`.

Da quel momento i kernel si aggiornano con il normale `sudo arc upgrade` /
`pacman -Syu`. Dopo ogni installazione o rimozione, l'hook di pacman rigenera il menu
di GRUB con `arcbase-grub-cfg`. Le impostazioni sono in `/etc/arcbase/boot.conf`:
- opzioni del kernel;
- `DEFAULT_KERNEL='*-lts'` per avviare di default l'LTS.
