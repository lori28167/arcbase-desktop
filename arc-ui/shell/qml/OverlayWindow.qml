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
        if (mode === "launcher" || mode === "wallpaper") {
            Shell.setBlur(win, [{ x: 0, y: 0, width: win.width, height: win.height, radius: 0 }]);
        } else if (panelLoader.item) {
            const p = panelLoader.item;
            Shell.setBlur(win, [{ x: panelLoader.x, y: panelLoader.y, width: p.width, height: p.height, radius: p.radius }]);
        } else {
            Shell.setBlur(win, []);
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

        // Velo dietro la scelta dello sfondo (il Launchpad ha il suo)
        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
            visible: win.mode === "wallpaper"
        }
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

        Loader {
            anchors.fill: parent
            active: win.mode === "wallpaper"
            focus: active
            sourceComponent: WallpaperPicker {}
        }

        // Pannelli sotto la topbar, a destra
        Loader {
            id: panelLoader
            x: parent.width - width - Theme.edge
            y: Theme.panelTop
            active: win.mode === "control" || win.mode === "notifications"
            focus: active
            sourceComponent: win.mode === "control" ? controlComponent : notificationsComponent
            onLoaded: Qt.callLater(win.updateBlur)
            onHeightChanged: Qt.callLater(win.updateBlur)
            onWidthChanged: Qt.callLater(win.updateBlur)
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
