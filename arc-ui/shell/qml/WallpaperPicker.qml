// Scelta dello sfondo (menu della scrivania): miniature delle immagini di
// arc, dei pacchetti di sfondi di sistema e di Immagini/Sfondi
import QtQuick
import org.arcbase.core
import "."

Item {
    id: picker

    readonly property var images: Shell.wallpapers()

    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: Theme.normal } }

    GlassPanel {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.dockHeight + 2 * Theme.gap
        width: Math.min(parent.width - 96, 940)
        height: 300

        MouseArea { anchors.fill: parent }

        Text {
            x: 22
            y: 18
            text: "Sfondo della scrivania"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 22
            y: 21
            text: "Aggiungi immagini in Immagini/Sfondi"
            color: Theme.sub
            font.family: Theme.font
            font.pixelSize: 12
        }

        ListView {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18; top: parent.top; topMargin: 58 }
            orientation: ListView.Horizontal
            spacing: 14
            clip: true
            model: picker.images
            boundsBehavior: Flickable.StopAtBounds

            delegate: MouseArea {
                id: thumb
                required property var modelData
                readonly property bool current: Shell.wallpaper === modelData.url
                width: 300
                height: ListView.view.height
                hoverEnabled: true
                onClicked: Shell.wallpaper = modelData.url

                Rectangle {
                    id: frame
                    width: parent.width
                    height: parent.height - 28
                    radius: Theme.rLg
                    color: Theme.surface2
                    border.width: thumb.current ? 3 : 1
                    border.color: thumb.current ? Theme.accent : thumb.containsMouse ? Theme.borderHi : Theme.border
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: thumb.current ? 3 : 1
                        source: thumb.modelData.url
                        sourceSize.width: 600
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
                Text {
                    anchors.top: frame.bottom
                    anchors.topMargin: 8
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: thumb.modelData.name
                    elide: Text.ElideRight
                    color: thumb.current ? Theme.text : Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
        }
    }
}
