# arc UI — il desktop di Arcbase

`ARC_DESKTOP=arc` installa un desktop con il design di [arc UI](https://arcbase.org/ui)
(pannelli di vetro, topbar fluttuante, dock) sopra la base di KDE, **senza nessun
elemento grafico di Plasma**:

- **KWin** resta compositor Wayland e window manager, e i servizi KDE senza
  interfaccia restano attivi: rete, audio, bluetooth, energia, schermi, blocco
  dello schermo, portali, polkit;
- **plasmashell non parte**: al suo posto c'è **arc-shell**, una shell Qt/QML
  scritta da zero;
- le app KDE (Dolphin, Konsole, Kate, Impostazioni…) usano lo stile Kvantum
  **ArcGlass** e lo schema colori **ArcUI**;
- le finestre hanno la decorazione **arc** (`decoration/`, plugin KDecoration3):
  barra del titolo di vetro sfocato, nome dell'app a sinistra, pulsanti tondi
  scuri a destra (riduci, ingrandisci, chiudi), angoli arrotondati (quelli in
  basso li taglia KWin), bordo di vetro e ombra;
- le icone delle app del sistema sono le **arc icons** (`icons/generate.py`),
  disegnate in stile macOS ma originali: file, store, installer, foto,
  documenti, archivi, impostazioni, terminale, cestino, cattura, informazioni,
  calcolatrice, editor, monitor di sistema, Launchpad. Le altre app prendono
  **WhiteSur** (GPL-3.0, scaricato a versione fissa con checksum in
  `11-desktop.sh`), poi Papirus.

Tutti i pannelli usano lo stesso materiale: vetro scuro sfocato da KWin
(`Theme.material`, `GlassPanel.qml`).

| Parte | Cosa fa |
|---|---|
| Topbar | logo (Launchpad), ora e data (centro notifiche), stato (centro di controllo); con un'app ingrandita si attacca ai bordi e mostra nome e pulsanti della finestra |
| Dock | app fissate e aperte, ingrandimento a onda, rimbalzo all'avvio, menu col tasto destro, Launchpad, Cestino; con un'app ingrandita si nasconde e torna dal bordo in basso |
| Launchpad | la topbar si trasforma nella barra di ricerca; app a pagine come nei vecchi macOS; cartelle 2×2 come widget (app avviabili dal riquadro), create trascinando un'app su un'altra; riordino col trascinamento; nome della cartella modificabile |
| Ricerca | stile Spotlight con KRunner: app, file (Baloo), impostazioni, calcoli, conversioni, finestre, documenti recenti, comandi |
| Centro di controllo | Wi‑Fi (con elenco reti), Bluetooth, Non disturbare, luce notturna, modalità aereo, cattura; luminosità e volume; musica; batteria; sessione |
| Centro notifiche | storico, Non disturbare, Cancella tutto |
| Notifiche | server `org.freedesktop.Notifications`, azioni, pausa col mouse |
| OSD | volume, luminosità, Wi‑Fi… dai tasti (servizio `org.kde.osdService`) |
| Scrivania | widget Orologio, Calendario, Meteo, Musica, Sistema, Note in S/M/L; modifica, spostamento, aggiunta; menu col tasto destro; scelta dello sfondo |
| Stato di sistema | a eventi, senza controlli continui: UPower (batteria), NetworkManager (rete), BlueZ (Bluetooth), PipeWire `pactl subscribe` (volume) |
| Login e blocco | tema SDDM `arc`, schermata di blocco e di uscita arc |

```
┌──────────────────────────────────────────────────────────────────────┐
│ ARC                     16:02   gio 13 ott                ⬡  ◔  ᯤ  ▭ │  topbar
└──────────────────────────────────────────────────────────────────────┘
┌──────────────┐
│ Buongiorno   │   widget (layer Bottom: le finestre li coprono)
│ 16:02        │
└──────────────┘
┌──────────────┐
│ Ottobre 2026 │
└──────────────┘
               ┌──────────────────────────────────┐
               │  ▣   ▣   ▣   ▣   ▣   ▣  │  ⊞     │  dock
               └──────────────────────────────────┘
```

## Come si avvia

1. SDDM (tema `arc`) avvia la sessione `arc` → `/usr/bin/startarc`.
2. `startarc` esporta `ARC_SESSION=1` e lancia `startplasma-wayland`: la sessione
   KDE normale, che copia l'ambiente nel gestore utente di systemd.
3. `plasma-plasmashell.service` ha una `ExecCondition` che con `ARC_SESSION=1`
   lo salta; `arc-shell.service` (in `plasma-workspace.target`) parte al suo posto.
4. La sessione Plasma resta disponibile e funziona come prima: lì è arc-shell
   a non partire.

## Struttura

```
shell/                 arc-shell (C++ + QML, compilata da 11-desktop.sh con CMake)
  src/shell.*          stato di sistema (batteria, rete, Wi‑Fi, Bluetooth, volume,
                       luminosità), layer-shell, sfocatura di KWin, sfondi, widget,
                       sessione, D-Bus org.arcbase.Shell
  src/applications.*   elenco delle app (KService) e avvio (KIO)
  src/notifications.*  server org.freedesktop.Notifications e storico
  src/media.*          lettore attivo via MPRIS
  src/osd.*            org.kde.osdService (indicatore di volume e luminosità)
  src/search.*         ricerca del Launchpad con KRunner
  qml/                 Theme.qml (token), GlassPanel (materiale), TopBar, Dock,
                       Launchpad, ControlCenter, NotificationCenter, Osd,
                       DesktopWindow + *Widget.qml, WallpaperPicker
decoration/            decorazione delle finestre per KWin (C++, KDecoration3)
icons/generate.py      arc icons (stile macOS, sopra WhiteSur per le altre app)
session/               startarc, sessione Wayland, unità systemd, file .desktop
theme/
  generate.py          genera Kvantum ArcGlass e decorazioni Aurorae dai token
  ArcUI.colors         schema colori KDE
  sddm/                schermata di accesso
  lookandfeel/         schermata di blocco e di uscita (org.arcbase.arcui)
  tabbox/              selettore delle finestre Alt+Tab
config/                impostazioni predefinite (/etc/xdg, /etc/skel)
wallpaper/             Dolomiti (da ArcBase/assets/dolomiti-hero.jpg)
install.sh             installa tutto tranne il binario (anche in una cartella di prova)
preview/               anteprima interattiva senza KDE (run.sh, mock, runner)
```

## Personalizzare

- **Token grafici**: `shell/qml/Theme.qml` (shell) e le costanti in cima a
  `theme/generate.py` (app e finestre), entrambi presi da `ArcBase/ui/arc-ui.css`.
- **Icone**: ogni arc icon è una funzione in `icons/generate.py`: squircle
  continuo con ombra, oggetti con gradienti, luci e ombre (feGaussianBlur, Qt
  6.7+); un'icona vale per più nomi (quelli dei file .desktop). La versione di WhiteSur è in
  `config/arcbase.conf` (`ARC_ICON_THEME_URL`, `ARC_ICON_THEME_SHA256`).
- **Finestre**: misure e colori in `decoration/arcdecoration.h` (`Metrics`) e in
  cima a `arcdecoration.cpp`; l'anteprima li copia in `preview/SampleWindow.qml`.
- **Sfondo e app nella dock**: `/etc/xdg/arcbase/arc-shell.conf`, o per un solo
  utente `~/.config/arcbase/arc-shell.conf` (lo sfondo si cambia anche dal menu
  della scrivania; i widget si salvano lì in `[Widgets] layout`):

  ```ini
  [Shell]
  wallpaper=/percorso/immagine.jpg
  dock=org.kde.dolphin.desktop, firefox.desktop, org.kde.konsole.desktop
  ```

- **Scorciatoie**: Meta apre il launcher (`kwinrc`), anche Alt+F1 e Meta+Spazio
  (`org.arcbase.launcher.desktop`). Da terminale:

  ```bash
  dbus-send --session --type=method_call --dest=org.arcbase.Shell /Shell org.arcbase.Shell.toggleLauncher
  ```

## Provare le modifiche

Anteprima interattiva, anche su macOS (`brew install qt cmake`): carica i veri
QML della shell, simula le parti in C++ e KDE e si ricarica a ogni salvataggio.

```bash
arc-ui/preview/run.sh             # desktop: clic su dock, launcher, centro di controllo
arc-ui/preview/run.sh sddm        # schermata di accesso
arc-ui/preview/run.sh --shots     # salva le schermate in arc-ui/preview/.out
arc-ui/preview/run.sh --anim      # fotogrammi: finestra che va a tutto schermo
arc-ui/preview/run.sh --anim-launchpad  # fotogrammi: topbar che diventa ricerca
```

Ctrl+Spazio fa da tasto Meta. Un pannello accanto simula notifiche, batteria e
rete. Le icone delle app sono segnaposto e la sfocatura imita quella di KWin.

```bash
make test                         # include tests/test-arc-ui.sh
arc-ui/install.sh /tmp/arc-root   # installa i temi in una cartella, senza root
```

Su un sistema Arcbase (o Arch con KDE) si può ricompilare e riavviare solo la shell:

```bash
cmake -S arc-ui/shell -B /tmp/arc-shell -DCMAKE_INSTALL_PREFIX=/usr
cmake --build /tmp/arc-shell && sudo cmake --install /tmp/arc-shell
systemctl --user restart arc-shell
```

## Privacy

Il widget Meteo contatta `geocoding-api.open-meteo.com` e `api.open-meteo.com`
(senza account né chiave) solo se è sulla scrivania, ogni 30 minuti. Nient'altro
nella shell usa la rete.

## Limiti attuali

- La decorazione delle finestre è compilata e verificata contro le intestazioni
  di KDecoration3, ma va provata dentro KWin (VM).
- La dock mostra le finestre aperte tramite `libtaskmanager` di KDE; se manca,
  mostra solo le app fissate. Le app non si fissano ancora dal menu della dock.
- Overview e Present Windows di KWin sono disattivati perché hanno la grafica di Plasma.
- Il Bluetooth si accende e si spegne con `bluetoothctl`; l'abbinamento dei
  dispositivi è nelle Impostazioni.
