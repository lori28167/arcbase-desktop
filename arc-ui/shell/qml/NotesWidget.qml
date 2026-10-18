// Widget Note: un appunto sempre in vista, salvato da solo.
// Opzioni: text, tint (colore della striscia in alto).
import QtQuick
import org.arcbase.core
import "."

Item {
    id: widget

    property string size: "m"
    property var options: ({})
    signal optionChanged(string key, var value)

    // Testo dalle opzioni salvate, ma mai mentre si scrive
    onOptionsChanged: {
        const saved = options.text || "";
        if (!note.activeFocus && note.text !== saved) note.text = saved;
    }

    Rectangle {
        visible: (widget.options.tint || "") !== ""
        x: 22
        y: 14
        width: 36
        height: 4
        radius: 2
        color: widget.options.tint || "transparent"
    }

    Flickable {
        id: flick
        anchors { fill: parent; margins: 20; topMargin: 26 }
        contentHeight: note.paintedHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        TextEdit {
            id: note
            width: flick.width
            height: Math.max(flick.height, paintedHeight)
            color: Theme.text
            selectionColor: Theme.surface4
            font.family: Theme.font
            font.pixelSize: widget.size === "s" ? 13 : 15
            wrapMode: TextEdit.Wrap
            // Si salva un attimo dopo l'ultima modifica
            onTextChanged: if (activeFocus) saveTimer.restart()
            onActiveFocusChanged: if (!activeFocus && saveTimer.running) { saveTimer.stop(); widget.optionChanged("text", text); }

            Text {
                visible: note.text === "" && !note.activeFocus
                text: "Scrivi una nota…"
                color: Theme.sub
                font: note.font
            }
        }
    }
    Timer {
        id: saveTimer
        interval: 800
        onTriggered: widget.optionChanged("text", note.text)
    }
}
