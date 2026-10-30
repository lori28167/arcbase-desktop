/* Arcbase Desktop — presentazione mostrata mentre si copia il sistema.
 * Slide di Calamares (API 2): una dopo l'altra ogni 12 secondi. */
import QtQuick
import calamares.slideshow 1.0;

Presentation {
    id: presentation

    Timer {
        interval: 12000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    component Card: Rectangle {
        property string title
        property string body
        anchors.fill: parent
        color: "#0f0d14"

        Column {
            anchors.centerIn: parent
            width: parent.width * 0.78
            spacing: 18
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64; height: 5; radius: 2.5
                color: "#8c52ff"
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: title
                color: "#ffffff"
                font.family: "Google Sans Flex"
                font.pixelSize: 30
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: body
                color: Qt.rgba(1, 1, 1, 0.7)
                font.family: "Google Sans Flex"
                font.pixelSize: 17
                lineHeight: 1.25
            }
        }
    }

    Slide {
        Card {
            title: qsTr("Benvenuto in Arcbase Desktop")
            body: qsTr("Un sistema costruito da zero con Linux From Scratch: ogni componente è compilato da sorgente.")
        }
    }
    Slide {
        Card {
            title: qsTr("Due mondi di pacchetti")
            body: qsTr("arc install firefox installa dai repository di Arch Linux (pacman);\narc install --deb gimp da Debian (apt). Un solo comando per entrambi.")
        }
    }
    Slide {
        Card {
            title: qsTr("Kernel sempre aggiornati")
            body: qsTr("Oltre al kernel dell'installazione puoi avere l'ultimo stabile e l'ultimo LTS, provati in una macchina virtuale prima della pubblicazione.")
        }
    }
    Slide {
        Card {
            title: qsTr("Quasi fatto")
            body: qsTr("Stiamo copiando il sistema sul disco e installando l'avvio. Ci vuole qualche minuto: non spegnere il computer.")
        }
    }
}
