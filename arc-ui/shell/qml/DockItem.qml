// Posto di un'icona nella dock. Il posto ha dimensione fissa (la dock calcola
// l'onda su queste posizioni); l'icona visibile si ingrandisce e si sposta
// con zoom e shift dati dalla dock, rimbalza all'avvio, mostra il puntino se
// l'app è aperta e l'etichetta al passaggio del mouse.
import QtQuick
import "."

Item {
    id: item

    property string iconName
    property string glyph
    property string label
    property bool running: false
    property bool active: false
    // Dalla dock
    property real zoom: 1
    property real shift: 0

    readonly property bool isDockSlot: true
    readonly property alias hovered: area.containsMouse

    signal activated()
    signal middleClicked()
    signal contextMenu(real x, real y)

    width: Theme.dockIcon
    height: Theme.dockIcon

    function bounce() {
        bounceAnimation.restart();
    }

    property real lift: 0
    SequentialAnimation {
        id: bounceAnimation
        loops: 2
        NumberAnimation { target: item; property: "lift"; to: 22; duration: 210; easing.type: Easing.OutQuad }
        NumberAnimation { target: item; property: "lift"; to: 0; duration: 210; easing.type: Easing.InQuad }
    }

    Item {
        id: visual
        width: Theme.dockIcon
        height: Theme.dockIcon
        transform: [
            Scale {
                origin.x: Theme.dockIcon / 2
                origin.y: Theme.dockIcon
                xScale: item.zoom
                yScale: item.zoom
            },
            Translate {
                x: item.shift
                y: -item.lift
            }
        ]

        AppIcon {
            anchors.fill: parent
            name: item.iconName
            glyph: item.glyph
            pressedOpacity: area.pressed ? 0.75 : 1
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) {
                    item.middleClicked();
                } else if (mouse.button === Qt.RightButton) {
                    const p = item.mapToItem(null, item.width / 2 + item.shift, -Theme.dockIcon * (item.zoom - 1));
                    item.contextMenu(p.x, p.y);
                } else {
                    item.activated();
                }
            }
        }
    }

    // Puntino dell'app aperta (lungo se è quella attiva)
    Rectangle {
        x: item.width / 2 - width / 2 + item.shift
        anchors.top: parent.bottom
        anchors.topMargin: (Theme.dockPadding - height) / 2
        width: item.active ? 10 : 4
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, item.active ? 0.95 : 0.65)
        visible: item.running
        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
    }

    // Etichetta sopra l'icona ingrandita (.arc-dock-item[data-tip])
    GlassPanel {
        x: item.width / 2 - width / 2 + item.shift
        y: -Theme.dockIcon * (item.zoom - 1) - height - 14 - item.lift
        width: tip.implicitWidth + 24
        height: 30
        radius: 10
        opacity: item.hovered && item.label !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }

        Text {
            id: tip
            anchors.centerIn: parent
            text: item.label
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }
}
