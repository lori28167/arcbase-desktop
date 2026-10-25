// Indicatore a schermo (volume, luminosità, Wi‑Fi...): pillola vetrosa sopra
// la dock, sparisce da sola. Lo chiedono i servizi di KDE tramite Osd (C++).
import QtQuick
import QtQuick.Window
import org.arcbase.core
import "."

Window {
    id: win

    property string icon: "volume"
    property int value: 0
    property string text: ""
    property bool ready: false

    color: "transparent"
    width: 320
    height: 60
    visible: false

    Component.onCompleted: {
        Shell.configureLayer(win, "arc-osd", Shell.LayerOverlay, Shell.AnchorBottom, -1, Shell.KeyboardNone,
                             0, 0, Theme.dockHeight + 2 * Theme.gap + 24, 0);
        ready = true;
    }

    function show(icon, value, text) {
        win.icon = icon;
        win.value = value;
        win.text = text;
        if (ready && !visible) {
            visible = true;
            Qt.callLater(() => Shell.setBlur(win, [{ x: 0, y: 0, width: pill.width, height: pill.height, radius: pill.radius }]));
        }
        pill.opacity = 1;
        hideTimer.restart();
    }

    Connections {
        target: Osd
        function onShown(icon, value, text) { win.show(icon, value, text); }
    }
    Timer {
        id: hideTimer
        interval: 1600
        onTriggered: pill.opacity = 0
    }

    GlassPanel {
        id: pill
        anchors.fill: parent
        radius: height / 2
        opacity: 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.normal }
        }
        onOpacityChanged: if (opacity === 0) win.visible = false

        ArcIcon {
            id: glyph
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22
            name: win.icon
            color: Theme.text
        }
        // Barra (0..100) oppure testo
        Rectangle {
            visible: win.value >= 0
            anchors { left: glyph.right; leftMargin: 16; right: percent.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
            height: 8
            radius: 4
            color: Theme.surface3
            Rectangle {
                width: Math.max(height, parent.width * Math.min(100, win.value) / 100)
                height: parent.height
                radius: parent.radius
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: Theme.fast } }
            }
        }
        Text {
            id: percent
            visible: win.value >= 0
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            horizontalAlignment: Text.AlignRight
            text: win.value
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 13
            font.features: ({ "tnum": 1 })
        }
        Text {
            visible: win.value < 0
            anchors { left: glyph.right; leftMargin: 14; right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            text: win.text
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.Medium
        }
    }
}
