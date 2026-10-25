// arc UI — scelta di uscita (ksmserver-logout-greeter: tasto di accensione,
// Ctrl+Alt+Canc). Segnali e proprietà sono quelli attesi dal greeter di KDE.
import QtQuick
import QtQuick.Shapes

Rectangle {
    id: root

    signal logoutRequested()
    signal haltRequested()
    signal suspendRequested(int spdMethod)
    signal rebootRequested()
    signal rebootRequested2(int opt)
    signal cancelRequested()
    signal lockScreenRequested()
    signal cancelSoftwareUpdateRequested()

    property bool canLogout: true
    property bool canReboot: true
    property bool canShutdown: true
    property bool canSuspend: false
    property bool canHibernate: false
    property var sdtype: 0
    property bool showAllOptions: true

    color: Qt.rgba(8 / 255, 6 / 255, 12 / 255, 0.55)
    focus: true
    Keys.onEscapePressed: root.cancelRequested()

    MouseArea {
        anchors.fill: parent
        onClicked: root.cancelRequested()
    }

    Rectangle {
        anchors.centerIn: parent
        width: buttons.width + 56
        height: buttons.height + 56
        radius: 28
        color: Qt.rgba(12 / 255, 10 / 255, 18 / 255, 0.80)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)

        MouseArea { anchors.fill: parent }

        Row {
            id: buttons
            anchors.centerIn: parent
            spacing: 18
            Choice { label: "Blocca"; glyph: "M7.5 11 V8 A4.5 4.5 0 0 1 16.5 8 V11 M5.5 11 H18.5 V20.5 H5.5 Z"; onClicked: root.lockScreenRequested() }
            Choice { label: "Sospendi"; visible: root.canSuspend; glyph: "M20 14.5 A8 8 0 1 1 9.5 4 A6.5 6.5 0 0 0 20 14.5 Z"; onClicked: root.suspendRequested(1) }
            Choice { label: "Esci"; visible: root.canLogout; glyph: "M10 4 H6 A2 2 0 0 0 4 6 V18 A2 2 0 0 0 6 20 H10 M15 8 L19 12 L15 16 M19 12 H9"; onClicked: root.logoutRequested() }
            Choice { label: "Riavvia"; visible: root.canReboot; glyph: "M19.5 12 A7.5 7.5 0 1 1 17.3 6.7 M17.6 2.8 V6.9 H13.5"; onClicked: root.rebootRequested() }
            Choice { label: "Spegni"; visible: root.canShutdown; glyph: "M12 3 V12 M7.05 8.05 A7 7 0 1 0 16.95 8.05"; danger: true; onClicked: root.haltRequested() }
        }
    }

    component Choice: MouseArea {
        id: choice
        property string label
        property string glyph
        property bool danger: false
        width: 84
        height: 104
        hoverEnabled: true

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72; height: 72; radius: 36
            color: choice.containsMouse
                   ? (choice.danger ? Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.24) : Qt.rgba(1, 1, 1, 0.16))
                   : Qt.rgba(1, 1, 1, 0.07)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
            scale: choice.pressed ? 0.95 : 1

            Item {
                anchors.centerIn: parent
                width: 28; height: 28
                layer.enabled: true
                layer.samples: 4
                Shape {
                    width: 24; height: 24
                    scale: 28 / 24
                    transformOrigin: Item.TopLeft
                    ShapePath {
                        strokeColor: Qt.rgba(1, 1, 1, 0.95)
                        strokeWidth: 1.8
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: choice.glyph }
                    }
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: choice.label
            color: Qt.rgba(1, 1, 1, 0.75)
            font.family: "Google Sans Flex"
            font.pixelSize: 13
        }
    }
}
