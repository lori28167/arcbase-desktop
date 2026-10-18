// arc UI — schermata di accesso (SDDM, Qt 6)
// Sfondo Dolomiti, ora grande, card vetrosa con utente e password.
// Accede sempre alla sessione "arc".
import QtQuick

Rectangle {
    id: root

    width: 1920
    height: 1080
    color: "#0f0d14"

    readonly property color text: Qt.rgba(1, 1, 1, 0.95)
    readonly property color muted: Qt.rgba(1, 1, 1, 0.58)
    readonly property color sub: Qt.rgba(1, 1, 1, 0.35)
    readonly property string font: config.font || "Inter"

    property var users: []
    property int userIndex: 0
    property int sessionIndex: sessionModel.lastIndex
    property date now: new Date()

    readonly property var user: users.length > 0 ? users[Math.min(userIndex, users.length - 1)] : ({ name: "", realName: "" })

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // Raccolta di utenti e sessioni dai modelli di SDDM
    Repeater {
        model: userModel
        delegate: Item {
            Component.onCompleted: {
                const name = model.name || "";
                root.users = root.users.concat([{ name: name, realName: model.realName || name }]);
                if (name === userModel.lastUser) {
                    root.userIndex = root.users.length - 1;
                }
            }
        }
    }
    Repeater {
        model: sessionModel
        delegate: Item {
            Component.onCompleted: {
                const file = String(model.file || "");
                if (model.name === "arc" || file === "arc.desktop" || file.endsWith("/arc.desktop")) {
                    root.sessionIndex = index;
                }
            }
        }
    }

    function login() {
        if (root.user.name === "") {
            return;
        }
        status.text = "";
        busy = true;
        sddm.login(root.user.name, password.text, root.sessionIndex);
    }
    property bool busy: false

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false;
            password.text = "";
            status.text = "Password errata";
            shake.restart();
            password.forceActiveFocus();
        }
        function onLoginSucceeded() {
            status.text = "";
        }
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        source: config.background || ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.58) }
        }
    }

    // --- Logo in alto a sinistra
    Image {
        x: 40
        y: 36
        height: 22
        width: height * 1232 / 424
        source: "arc-wordmark-light.svg"
        sourceSize.height: 66
    }

    // --- Ora e data
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.16
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "HH:mm")
            color: root.text
            font.family: root.font
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
            font.family: root.font
            font.pixelSize: 22
        }
    }

    // --- Card di accesso (.arc-card / .login-left-panel)
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.52
        width: 380
        height: content.height + 56
        radius: 28
        color: Qt.rgba(12 / 255, 10 / 255, 18 / 255, 0.62)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        transform: Translate { id: shakeOffset }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: shakeOffset; property: "x"; to: -12; duration: 50 }
            NumberAnimation { target: shakeOffset; property: "x"; to: 10; duration: 70 }
            NumberAnimation { target: shakeOffset; property: "x"; to: -6; duration: 70 }
            NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 60 }
        }

        Column {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28 }
            spacing: 16

            // Utente (frecce se ce n'è più di uno)
            Item {
                width: parent.width
                height: 112

                Rectangle {
                    id: avatar
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 76; height: 76; radius: 38
                    color: Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.22)
                    Text {
                        anchors.centerIn: parent
                        text: root.user.realName.charAt(0).toUpperCase()
                        color: root.text
                        font.family: root.font
                        font.pixelSize: 32
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: root.user.realName
                    color: root.text
                    font.family: root.font
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                }
                ArcIcon {
                    visible: root.users.length > 1
                    anchors.verticalCenter: avatar.verticalCenter
                    anchors.left: parent.left
                    width: 22; height: 22
                    name: "chevron-left"
                    color: root.muted
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.userIndex = (root.userIndex + root.users.length - 1) % root.users.length }
                }
                ArcIcon {
                    visible: root.users.length > 1
                    anchors.verticalCenter: avatar.verticalCenter
                    anchors.right: parent.right
                    width: 22; height: 22
                    name: "chevron-right"
                    color: root.muted
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.userIndex = (root.userIndex + 1) % root.users.length }
                }
            }

            // Password (.arc-input)
            Rectangle {
                width: parent.width
                height: 50
                radius: 25
                color: Qt.rgba(0, 0, 0, 0.28)
                border.width: 1
                border.color: password.activeFocus ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.12)

                TextInput {
                    id: password
                    anchors { left: parent.left; right: go.left; leftMargin: 20; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    color: root.text
                    font.family: root.font
                    font.pixelSize: 16
                    clip: true
                    focus: true
                    enabled: !root.busy
                    onAccepted: root.login()
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: password.text === ""
                        text: "Password"
                        color: root.sub
                        font: password.font
                    }
                }
                Rectangle {
                    id: go
                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 38; height: 38; radius: 19
                    color: goArea.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.9)
                    ArcIcon { anchors.centerIn: parent; width: 18; height: 18; name: "arrow-right"; color: "#0f0d14"; strokeWidth: 2.2 }
                    MouseArea { id: goArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.login() }
                }
            }

            Text {
                id: status
                width: parent.width
                height: text === "" ? 0 : implicitHeight
                horizontalAlignment: Text.AlignHCenter
                color: "#fca5a5"
                font.family: root.font
                font.pixelSize: 13
            }
        }
    }

    // --- Energia in basso a destra
    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: 32 }
        spacing: 12
        PowerButton { icon: "moon"; visible: sddm.canSuspend; onClicked: sddm.suspend() }
        PowerButton { icon: "restart"; visible: sddm.canReboot; onClicked: sddm.reboot() }
        PowerButton { icon: "power"; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
    }

    component PowerButton: MouseArea {
        id: button
        property string icon
        width: 48; height: 48
        hoverEnabled: true
        Rectangle {
            anchors.fill: parent
            radius: 24
            color: button.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(12 / 255, 10 / 255, 18 / 255, 0.5)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
        }
        ArcIcon { anchors.centerIn: parent; width: 20; height: 20; name: button.icon; color: root.text }
    }

    Component.onCompleted: password.forceActiveFocus()
}
