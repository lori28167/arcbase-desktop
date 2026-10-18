// Cursore orizzontale di arc UI (traccia vetrosa, riempimento bianco)
import QtQuick
import "."

Item {
    id: slider

    property real value: 0      // 0..1
    signal moved(real value)

    implicitWidth: 200
    implicitHeight: 28

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 8
        radius: 4
        color: Theme.surface3

        Rectangle {
            width: Math.max(height, track.width * Math.min(1, slider.value))
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }
    Rectangle {
        x: Math.min(1, slider.value) * (slider.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20; radius: 10
        color: Theme.accent
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.15)
        scale: area.pressed ? 1.12 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        preventStealing: true
        function update(mouseX) {
            slider.moved(Math.max(0, Math.min(1, mouseX / width)));
        }
        onPressed: mouse => update(mouse.x)
        onPositionChanged: mouse => { if (pressed) update(mouse.x); }
    }
    WheelHandler {
        onWheel: event => slider.moved(Math.max(0, Math.min(1, slider.value + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
