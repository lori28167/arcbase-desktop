// Copione del trailer (run.sh --trailer): guida la shell vera nell'anteprima
// scena per scena, con titoli e didascalie sopra, mentre il runner registra i
// fotogrammi. Poi trailer.sh monta il video.
import QtQuick
import QtQuick.Effects
import org.arcbase.core
import org.kde.taskmanager
import "../shell/qml"

Item {
    id: trailer

    required property var shell     // Main.qml della shell
    signal finished()

    anchors.fill: parent
    z: 1000

    // --- Titoli a tutto schermo (apertura e chiusura) ----------------------------
    Rectangle {
        id: card
        anchors.fill: parent
        color: "#0b0910"
        opacity: 1
        Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.InOutCubic } }

        Column {
            anchors.centerIn: parent
            spacing: 22
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "../shell/qml/assets/arc-wordmark-light.svg"
                sourceSize.height: 96
                height: 96
                fillMode: Image.PreserveAspectFit
                scale: card.opacity > 0.5 ? 1 : 0.94
                Behavior on scale { NumberAnimation { duration: 1400; easing.type: Easing.OutCubic } }
            }
            Text {
                id: cardTitle
                anchors.horizontalCenter: parent.horizontalCenter
                color: "white"
                font.family: Theme.font
                font.pixelSize: 44
                font.weight: Font.DemiBold
            }
            Text {
                id: cardSub
                anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(1, 1, 1, 0.6)
                font.family: Theme.font
                font.pixelSize: 22
            }
        }
    }

    // --- Didascalia in basso al centro, sopra la dock ---------------------------
    Item {
        id: caption
        property string text
        x: (parent.width - width) / 2
        y: parent.height - Theme.dockHeight - Theme.gap - height - 28
        width: label.implicitWidth + 44
        height: 62
        opacity: text !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 350 } }
        GlassPanel {
            anchors.fill: parent
            radius: 31
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: caption.text
            color: "white"
            font.family: Theme.font
            font.pixelSize: 24
            font.weight: Font.DemiBold
        }
    }

    function say(text) {
        if (caption.text === text) return;
        caption.text = "";
        Qt.callLater(() => caption.text = text);
    }
    function launchpad() {
        return trailer.shell.overlay.launchpad;
    }

    // Notifiche finte per la scena delle notifiche
    property var toasts: [["Telegram", "telegram", "Giulia", "Ci vediamo alle 18 in piazza?"],
                          ["Firefox", "firefox", "Download completato", "arcbase-desktop.iso (2,1 GB)"],
                          ["Calendario", "office-calendar", "Riunione tra 10 minuti", "Revisione del progetto Arc"],
                          ["Discover", "plasmadiscover", "Aggiornamenti disponibili", "12 pacchetti possono essere aggiornati."],
                          ["Spectacle", "org.kde.spectacle", "Schermata salvata", "Immagini/Schermata 17-30.png"]]
    property int toast: 0
    Timer {
        id: toastTimer
        interval: 420
        repeat: true
        onTriggered: {
            const e = trailer.toasts[trailer.toast];
            Notifications.push(e[0], e[1], e[2], e[3], 1);
            if (++trailer.toast >= trailer.toasts.length) stop();
        }
    }
    // Scrittura lettera per lettera nella ricerca
    property string typing
    property int typed: 0
    Timer {
        id: typeTimer
        interval: 160
        repeat: true
        onTriggered: {
            trailer.typed++;
            const pad = trailer.launchpad();
            if (pad) pad.setQuery(trailer.typing.substring(0, trailer.typed));
            if (trailer.typed >= trailer.typing.length) stop();
        }
    }
    function type(text) {
        typing = text;
        typed = 0;
        typeTimer.restart();
    }

    function clearNotifications() {
        while (Notifications.count > 0) Notifications.remove(0);
    }

    // --- Copione: [secondi dall'inizio, azione] -----------------------------------
    readonly property var script: [
        [0.0, () => { cardTitle.text = "Arcbase Desktop"; cardSub.text = "Il desktop, ripensato in vetro."; }],
        [3.2, () => { card.opacity = 0; }],
        [4.6, () => say("Vetro scuro, ovunque")],
        [7.4, () => { say("La barra diventa ricerca"); Shell.toggleLauncher(); }],
        [10.6, () => { say("Cartelle grandi come widget"); const p = launchpad(); if (p) p.folderId = "folder-internet"; }],
        [13.4, () => { const p = launchpad(); if (p) p.folderId = ""; }],
        [14.2, () => { say("Cerca app, file e calcoli"); type("12*4"); }],
        [17.6, () => { say(""); Shell.hideOverlay(); }],
        [18.8, () => { say("Finestre di sistema, in vetro"); WindowState.active = true; WindowState.visible = true; }],
        [22.4, () => { say("A tutto schermo, la barra si trasforma"); WindowState.maximized = true; }],
        [26.0, () => { WindowState.maximized = false; }],
        [27.4, () => { say(""); WindowState.visible = false; }],
        [28.4, () => { say("Centro di controllo"); Shell.showControlCenter(); }],
        [31.8, () => { Shell.hideOverlay(); clearNotifications(); }],
        [32.6, () => { say("Notifiche in pila, sotto l'orario"); trailer.toast = 0; toastTimer.restart(); }],
        [37.2, () => { say("Tutto in un posto"); Shell.showNotifications(); }],
        [40.4, () => { say(""); Shell.hideOverlay(); }],
        [41.2, () => { cardTitle.text = "Arcbase Desktop"; cardSub.text = "Basato su KDE · arc UI"; card.opacity = 1; }],
        [45.0, () => trailer.finished()]
    ]
    property int next: 0
    property real t0: 0
    Timer {
        id: clock
        interval: 20
        repeat: true
        onTriggered: {
            const t = (Date.now() - trailer.t0) / 1000;
            while (trailer.next < trailer.script.length && trailer.script[trailer.next][0] <= t) {
                trailer.script[trailer.next][1]();
                trailer.next++;
            }
            if (trailer.next >= trailer.script.length) stop();
        }
    }
    function start() {
        clearNotifications();
        WindowState.visible = false;
        WindowState.maximized = false;
        Shell.overlay = "";
        next = 0;
        t0 = Date.now();
        clock.start();
    }
}
