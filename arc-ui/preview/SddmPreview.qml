// Anteprima del tema SDDM: oggetti finti al posto di quelli del greeter.
// La password è sempre "errata", per provare l'animazione di errore.
import QtQuick

Window {
    id: root
    width: 1440
    height: 900
    visible: true
    color: "black"

    QtObject {
        id: sddm
        signal loginFailed()
        signal loginSucceeded()
        property bool canSuspend: true
        property bool canReboot: true
        property bool canPowerOff: true
        function login(user, password, session) { console.log("login", user, session); loginFailed(); }
        function suspend() {}
        function reboot() {}
        function powerOff() {}
    }
    QtObject {
        id: config
        property string background: wallpaperPath
        property string font: "Inter"
    }
    ListModel {
        id: userModel
        property string lastUser: "arc"
        ListElement { name: "arc"; realName: "Arcbase User" }
    }
    ListModel {
        id: sessionModel
        property int lastIndex: 0
        ListElement { name: "Plasma (Wayland)"; file: "plasma.desktop" }
        ListElement { name: "arc"; file: "arc.desktop" }
    }

    Loader {
        id: loader
        anchors.fill: parent
        source: sddmUrl
        onStatusChanged: if (status === Loader.Error) Qt.exit(1)
    }
    Timer {
        interval: 1500
        running: shots
        onTriggered: loader.grabToImage(r => {
            r.saveToFile(outDir + "/sddm.png");
            console.log("salvato sddm, sessione scelta:", loader.item.sessionIndex);
            Qt.quit();
        })
    }
}
