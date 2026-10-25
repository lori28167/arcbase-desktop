// Velo dietro al centro di controllo e al centro notifiche: tutto lo schermo
// sfocato e un po' scurito, così resta in vista solo il pannello.
// È una superficie a parte nel livello Top, creata prima di topbar e dock
// (Main.qml): sta sopra le finestre ma sotto di loro, che restano nitide e
// cliccabili. Il pannello è nell'overlay, sopra a tutto. Resta sempre mappata
// (vuota e trasparente quando non serve) per non cambiare posto nella pila.
import QtQuick
import QtQuick.Window
import org.arcbase.core
import "."

Window {
    id: win

    readonly property bool active: Shell.overlay === "control" || Shell.overlay === "notifications"
    property bool ready: false

    color: "transparent"
    width: 1280
    height: 800
    visible: false

    Component.onCompleted: {
        Shell.configureLayer(win, "arc-veil", Shell.LayerTop,
                             Shell.AnchorTop | Shell.AnchorBottom | Shell.AnchorLeft | Shell.AnchorRight,
                             -1, Shell.KeyboardNone);
        ready = true;
        visible = true;
        update();
    }

    function update() {
        if (!ready) return;
        const full = [{ x: 0, y: 0, width: win.width, height: win.height, radius: 0 }];
        if (active) {
            clearTimer.stop();
            Shell.setBlur(win, full);
            Shell.setInputRegion(win, full);
        } else {
            // Niente clic intercettati; la sfocatura sparisce dopo il velo
            Shell.setInputRegion(win, [{ x: 0, y: 0, width: 1, height: 1, radius: 0 }]);
            clearTimer.restart();
        }
    }
    onActiveChanged: update()
    onWidthChanged: Qt.callLater(update)
    onHeightChanged: Qt.callLater(update)
    Timer {
        id: clearTimer
        interval: Theme.normal
        onTriggered: if (!win.active) Shell.setBlur(win, [])
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: win.active ? 0.7 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
    }
    // Un clic sul velo chiude il pannello
    MouseArea {
        anchors.fill: parent
        enabled: win.active
        onClicked: Shell.hideOverlay()
    }
}
