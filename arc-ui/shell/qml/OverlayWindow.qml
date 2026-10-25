// Livello a tutto schermo sopra tutto: Launchpad, centro di controllo, centro
// notifiche, scelta dello sfondo. Esc o un clic fuori dal pannello chiudono.
// Alla chiusura il contenuto sfuma prima di nascondere la finestra.
import QtQuick
import QtQuick.Window
import org.arcbase.core
import "."

Window {
    id: win

    // Modalità mostrata: resta quella vecchia durante l'animazione di chiusura
    property string mode: ""
    property bool closing: false
    property bool ready: false
    // Il Launchpad aperto (per l'anteprima e i test)
    readonly property var launchpad: launcherLoader.item

    color: "transparent"
    width: 1280
    height: 800
    visible: false

    Component.onCompleted: {
        Shell.configureLayer(win, "arc-overlay", Shell.LayerOverlay,
                             Shell.AnchorTop | Shell.AnchorBottom | Shell.AnchorLeft | Shell.AnchorRight,
                             -1, Shell.KeyboardExclusive);
        ready = true;
        sync();
    }

    function sync() {
        if (!ready) return;
        if (Shell.overlay !== "") {
            closeTimer.stop();
            closing = false;
            mode = Shell.overlay;
            visible = true;
        } else if (visible) {
            closing = true;
            closeTimer.restart();
        }
        Qt.callLater(updateBlur);
    }
    Connections {
        target: Shell
        function onOverlayChanged() { win.sync(); }
    }
    Timer {
        id: closeTimer
        // Il Launchpad chiude più piano: la barra di ricerca torna topbar
        interval: win.mode === "launcher" ? Theme.slow + 40 : Theme.normal
        onTriggered: {
            win.visible = false;
            win.closing = false;
            win.mode = "";
        }
    }

    function updateBlur() {
        const full = [{ x: 0, y: 0, width: win.width, height: win.height, radius: 0 }];
        if (mode === "launcher") {
            Shell.setBlur(win, full);
            Shell.setInputRegion(win, full);
        } else if (panelLoader.item) {
            const p = panelLoader.item;
            // Pannelli fatti di più parti (centro di controllo, centro
            // notifiche) dicono quali rettangoli sfocare
            const rects = p.blurRects ? p.blurRects : [{ x: 0, y: 0, width: p.width, height: p.height, radius: p.radius }];
            const placed = rects.map(r => ({ x: panelLoader.x + r.x, y: panelLoader.y + r.y, width: r.width, height: r.height, radius: r.radius, corners: r.corners }));
            Shell.setBlur(win, placed);
            // Fuori dal pannello i clic vanno al velo (VeilWindow, lo chiude)
            // o a topbar e dock, che restano sopra al velo
            Shell.setInputRegion(win, placed);
        } else {
            Shell.setBlur(win, []);
            Shell.setInputRegion(win, full);
        }
    }
    onWidthChanged: Qt.callLater(updateBlur)
    onHeightChanged: Qt.callLater(updateBlur)

    Item {
        id: root
        anchors.fill: parent
        focus: true
        opacity: win.closing && win.mode !== "launcher" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.normal - 40; easing.type: Easing.OutCubic } }
        Keys.onEscapePressed: Shell.hideOverlay()

        MouseArea {
            anchors.fill: parent
            onClicked: Shell.hideOverlay()
        }


        Loader {
            id: launcherLoader
            anchors.fill: parent
            active: win.mode === "launcher"
            focus: active
            sourceComponent: Launchpad { closing: win.closing }
        }


        // Pannelli sotto la topbar: centro di controllo a destra, centro
        // notifiche al centro sotto l'orario (dove compaiono le notifiche)
        Loader {
            id: panelLoader
            x: win.mode === "notifications" ? Math.round((parent.width - width) / 2) : parent.width - width - Theme.edge
            y: Theme.panelTop
            active: win.mode === "control" || win.mode === "notifications"
            focus: active
            sourceComponent: win.mode === "control" ? controlComponent : notificationsComponent
            onLoaded: Qt.callLater(win.updateBlur)
            onHeightChanged: Qt.callLater(win.updateBlur)
            onWidthChanged: Qt.callLater(win.updateBlur)
            Connections {
                target: panelLoader.item
                ignoreUnknownSignals: true
                function onBlurRectsChanged() { Qt.callLater(win.updateBlur); }
            }
        }
        Component {
            id: controlComponent
            ControlCenter {}
        }
        Component {
            id: notificationsComponent
            NotificationCenter {
                maxHeight: win.height - Theme.panelTop - Theme.dockHeight - 3 * Theme.gap
            }
        }
    }
}
