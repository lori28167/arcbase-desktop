/* Arcbase Desktop — presentazione mostrata durante l'installazione */
import QtQuick
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function nextSlide() { presentation.goToNextSlide(); }

    Timer {
        id: advanceTimer
        interval: 8000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 20
            text: "<h2>Benvenuto in Arcbase Desktop</h2>" +
                  "Un sistema compilato da sorgente con Linux From Scratch, " +
                  "che unisce i pacchetti di Arch Linux e di Debian."
        }
    }
    Slide {
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 20
            text: "<h2>Un solo comando: arc</h2>" +
                  "<tt>arc install firefox</tt> — dai repository Arch<br/>" +
                  "<tt>arc install --deb gimp</tt> — da Debian<br/>" +
                  "<tt>arc upgrade</tt> — aggiorna tutto"
        }
    }
    Slide {
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 20
            text: "<h2>Anche apt funziona</h2>" +
                  "<tt>sudo apt install ./pacchetto.deb</tt><br/>" +
                  "Le app Debian compaiono nel menu, accanto a quelle di Arch."
        }
    }

    function onActivate() { presentation.currentSlide = 0; }
    function onLeave() { }
}
