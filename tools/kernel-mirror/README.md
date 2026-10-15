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
- copia lo script in `/usr/local/bin`;
- crea `/etc/arcbase-kbuild.conf` (impostazioni) e `/etc/arcbase-kbuild.env`
  (token del bot Telegram, permessi 600, leggibile solo da `arcbuild`);
- attiva:
  - `arcbase-kbuild.timer`;
  - `arcbase-kmirror-http.service`, che serve `/srv/arcbase-mirror` sulla porta
    8080.

Poi:

```bash
sudo -u arcbuild nano /etc/arcbase-kbuild.env        # token e chat del bot Telegram
sudo -u arcbuild arcbase-kbuild notify-test          # messaggio di prova
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

## Sui PC Arcbase

```bash
sudo arcbase-kernel-mirror enable http://<ip-del-server>:8080
sudo pacman -S linux-arcbase          # e/o linux-lts-arcbase
```

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
