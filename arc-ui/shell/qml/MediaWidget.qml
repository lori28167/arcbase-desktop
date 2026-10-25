// Widget Musica (MPRIS): copertina, titolo, artista e comandi.
// S: copertina con play · M: copertina e testo affiancati · L: copertina grande
import QtQuick
import org.arcbase.core
import "."

Item {
    id: widget

    property string size: "m"
    property var options: ({})
    signal optionChanged(string key, var value)

    // --- Niente in riproduzione
    Column {
        visible: !Media.available
        anchors.centerIn: parent
        spacing: 10
        ArcIcon { anchors.horizontalCenter: parent.horizontalCenter; width: 30; height: 30; name: "music"; color: Theme.sub; strokeWidth: 1.5 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Niente in riproduzione"
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 13
        }
    }

    Item {
        visible: Media.available
        anchors.fill: parent
        anchors.margins: 16

        // Copertina
        Rectangle {
            id: art
            width: widget.size === "s" ? parent.width : widget.size === "m" ? parent.height : parent.width
            height: widget.size === "l" ? parent.height - 112 : width
            radius: Theme.inner(Theme.widgetRadius, 16)
            color: Theme.surface3
            clip: true
            Image {
                anchors.fill: parent
                source: Media.artUrl
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
                asynchronous: true
            }
            ArcIcon { anchors.centerIn: parent; width: 34; height: 34; name: "music"; color: Theme.sub; visible: Media.artUrl === "" }

            // S: play sopra la copertina
            Control {
                visible: widget.size === "s"
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                icon: Media.playing ? "pause" : "play"
                big: true
                onClicked: Media.playPause()
            }
        }

        Column {
            visible: widget.size !== "s"
            x: widget.size === "m" ? art.width + 16 : 0
            y: widget.size === "m" ? 4 : art.height + 14
            width: widget.size === "m" ? parent.width - art.width - 16 : parent.width
            spacing: 2
            Text { width: parent.width; text: Media.title || Media.player; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { width: parent.width; text: Media.artist || Media.player; elide: Text.ElideRight; color: Theme.muted; font.family: Theme.font; font.pixelSize: 13 }
        }
        Row {
            visible: widget.size !== "s"
            x: widget.size === "m" ? art.width + 10 : (parent.width - width) / 2
            anchors.bottom: parent.bottom
            spacing: 6
            Control { icon: "previous"; enabled: Media.canGoPrevious; onClicked: Media.previous() }
            Control { icon: Media.playing ? "pause" : "play"; big: true; onClicked: Media.playPause() }
            Control { icon: "next"; enabled: Media.canGoNext; onClicked: Media.next() }
        }
    }

    component Control: MouseArea {
        id: control
        property string icon
        property bool big: false
        width: big ? 44 : 36
        height: width
        hoverEnabled: true
        opacity: enabled ? 1 : 0.35
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: control.big ? Theme.accent : control.containsMouse ? Theme.surface3 : "transparent"
            scale: control.pressed ? 0.92 : 1
        }
        ArcIcon {
            anchors.centerIn: parent
            width: control.big ? 18 : 18; height: width
            name: control.icon
            filled: true
            color: control.big ? Theme.accentText : Theme.text
        }
    }
}
