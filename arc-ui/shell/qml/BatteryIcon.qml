// Batteria orizzontale come nel mockup: contorno, polo e livello di carica
import QtQuick
import "."

Item {
    id: battery

    property int level: 100
    property bool charging: false
    property color color: "white"

    implicitWidth: 26
    implicitHeight: 14

    Rectangle {
        id: body
        width: parent.width - 3
        height: parent.height
        radius: 4
        color: "transparent"
        border.width: 1.6
        border.color: battery.color

        Rectangle {
            x: 3
            y: 3
            height: parent.height - 6
            width: Math.max(2, (parent.width - 6) * Math.min(100, battery.level) / 100)
            radius: 1.5
            color: battery.level <= 15 && !battery.charging ? Theme.red : battery.color
        }
    }
    Rectangle {
        anchors.left: body.right
        anchors.leftMargin: 1
        anchors.verticalCenter: body.verticalCenter
        width: 2
        height: 5
        radius: 1
        color: battery.color
    }
}
