// arc UI — schermata di blocco (kscreenlocker_greet)
// Il greeter di KDE fornisce "authenticator" (PAM); qui solo la grafica arc.
import QtQuick

Rectangle {
    id: root

    // Interfaccia attesa dal greeter di KDE
    property bool viewVisible: true
    property bool debug: false
    property string notification: ""
    property bool suspendToRamSupported: false
    property bool suspendToDiskSupported: false
    signal suspendToRam()
    signal suspendToDisk()
    signal clearPassword()

    color: "#0f0d14"

    readonly property color text: Qt.rgba(1, 1, 1, 0.95)
    readonly property color sub: Qt.rgba(1, 1, 1, 0.35)
    readonly property string userName: typeof kscreenlocker_userName !== "undefined" ? kscreenlocker_userName : ""
    property date now: new Date()
    property bool busy: false

    onClearPassword: password.text = ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    function unlock() {
        if (password.text === "" || busy) {
            return;
        }
        busy = true;
        status.text = "";
        const secret = password.text;
        password.text = "";
        authenticator.respond(secret);
    }

    Connections {
        target: authenticator
        function onSucceeded() {
            Qt.quit();
        }
        function onFailed() {
            root.busy = false;
            status.text = "Password errata";
            shake.restart();
            restart.restart();
        }
        function onPromptForSecretChanged() {
            root.busy = false;
            password.forceActiveFocus();
        }
    }
    // Nuovo tentativo dopo un errore
    Timer {
        id: restart
        interval: 600
        onTriggered: authenticator.startAuthenticating()
    }

    Image {
        anchors.fill: parent
        source: "file:///usr/share/arcbase/arc-ui/wallpaper/dolomiti.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.38) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.66) }
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.18
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "HH:mm")
            color: root.text
            font.family: "Google Sans Flex"
            font.pixelSize: 112
            font.weight: Font.Light
            font.letterSpacing: -4
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                const s = Qt.locale().toString(root.now, "dddd d MMMM");
                return s.charAt(0).toUpperCase() + s.slice(1);
            }
            color: root.text
            font.family: "Google Sans Flex"
            font.pixelSize: 22
        }
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.56
        width: 360
        height: 128
        radius: 28
        color: Qt.rgba(12 / 255, 10 / 255, 18 / 255, 0.62)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        transform: Translate { id: offset }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: offset; property: "x"; to: -12; duration: 50 }
            NumberAnimation { target: offset; property: "x"; to: 10; duration: 70 }
            NumberAnimation { target: offset; property: "x"; to: -6; duration: 70 }
            NumberAnimation { target: offset; property: "x"; to: 0; duration: 60 }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 20
            text: root.userName
            color: root.text
            font.family: "Google Sans Flex"
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 22 }
            height: 48
            radius: 24
            color: Qt.rgba(0, 0, 0, 0.28)
            border.width: 1
            border.color: password.activeFocus ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.12)

            TextInput {
                id: password
                anchors { left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20; verticalCenter: parent.verticalCenter }
                echoMode: TextInput.Password
                passwordCharacter: "•"
                color: root.text
                font.family: "Google Sans Flex"
                font.pixelSize: 16
                clip: true
                focus: true
                onAccepted: root.unlock()
                Keys.onEscapePressed: text = ""
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: password.text === ""
                    text: root.busy ? "Verifica…" : "Password per sbloccare"
                    color: root.sub
                    font: password.font
                }
            }
        }
    }

    Text {
        id: status
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: card.bottom
        anchors.topMargin: 14
        color: "#fca5a5"
        font.family: "Google Sans Flex"
        font.pixelSize: 13
    }

    Component.onCompleted: {
        password.forceActiveFocus();
        authenticator.startAuthenticating();
    }
}
