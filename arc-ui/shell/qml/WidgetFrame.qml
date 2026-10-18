// Cornice di un widget sulla scrivania: materiale di arc UI, contenuto in base
// al tipo e, in modifica, i comandi (rimuovi, contenuto, S/M/L) e il
// trascinamento sulla griglia. Una pressione lunga entra in modifica.
import QtQuick
import org.arcbase.core
import "."

GlassPanel {
    id: frame

    property string wid
    property string kind
    property string size: "m"
    property var options: ({})
    property bool editing: false
    property bool dragging: dragArea.drag.active

    signal removeRequested()
    signal sizeRequested(string size)
    signal settingsRequested()
    signal dropped(real x, real y)
    signal editRequested()
    signal optionChanged(string key, var value)

    radius: Theme.widgetRadius
    z: dragging ? 10 : 0
    scale: dragging ? 1.04 : 1
    Behavior on scale { NumberAnimation { duration: Theme.fast } }

    // Tremolio leggero in modifica
    rotation: 0
    SequentialAnimation on rotation {
        running: frame.editing && !frame.dragging
        loops: Animation.Infinite
        NumberAnimation { to: 0.5; duration: 140; easing.type: Easing.InOutSine }
        NumberAnimation { to: -0.5; duration: 140; easing.type: Easing.InOutSine }
        onStopped: frame.rotation = 0
    }

    // Pressione lunga sul widget = modifica (sotto al contenuto: pulsanti e
    // campi del widget restano cliccabili)
    MouseArea {
        anchors.fill: parent
        enabled: !frame.editing
        pressAndHoldInterval: 600
        onPressAndHold: frame.editRequested()
    }

    Loader {
        id: content
        anchors.fill: parent
        source: {
            switch (frame.kind) {
            case "clock": return "ClockWidget.qml";
            case "calendar": return "CalendarWidget.qml";
            case "media": return "MediaWidget.qml";
            case "system": return "SystemWidget.qml";
            case "notes": return "NotesWidget.qml";
            case "weather": return "WeatherWidget.qml";
            }
            return "";
        }
        onLoaded: {
            item.size = Qt.binding(() => frame.size);
            item.options = Qt.binding(() => frame.options);
            if (item.optionChanged) item.optionChanged.connect(frame.optionChanged);
        }
        // In modifica il contenuto non riceve clic
        enabled: !frame.editing
    }

    // In modifica: trascina sulla griglia
    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: frame.editing
        drag.target: frame
        drag.threshold: 4
        property bool moved: false
        property real lastX: 0
        property real lastY: 0
        onPressed: moved = false
        onPositionChanged: {
            if (drag.active) {
                moved = true;
                lastX = frame.x;
                lastY = frame.y;
            }
        }
        onReleased: if (moved) frame.dropped(lastX, lastY)
    }

    // --- Comandi di modifica
    MouseArea {
        id: removeButton
        visible: frame.editing
        x: -9
        y: -9
        width: 26; height: 26
        onClicked: frame.removeRequested()
        Rectangle {
            anchors.fill: parent
            radius: 13
            color: "#3a3446"
            border.width: 1
            border.color: Theme.borderHi
            ArcIcon { anchors.centerIn: parent; width: 13; height: 13; strokeWidth: 2.6; name: "minus"; color: Theme.text }
        }
    }
    MouseArea {
        id: settingsButton
        visible: frame.editing
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        width: 30; height: 30
        onClicked: frame.settingsRequested()
        Rectangle {
            anchors.fill: parent
            radius: 15
            color: Theme.surface3
            border.width: 1
            border.color: Theme.border
            ArcIcon { anchors.centerIn: parent; width: 15; height: 15; name: "pencil"; color: Theme.text }
        }
    }
    // Dimensioni (sotto il bordo inferiore)
    GlassPanel {
        visible: frame.editing && !frame.dragging
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.bottom
        width: sizes.width + 8
        height: 32
        radius: 16

        Row {
            id: sizes
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: [["s", "S"], ["m", "M"], ["l", "L"]]
                MouseArea {
                    id: chip
                    required property var modelData
                    width: 34; height: 24
                    hoverEnabled: true
                    onClicked: frame.sizeRequested(modelData[0])
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: frame.size === chip.modelData[0] ? Theme.accent : chip.containsMouse ? Theme.surface3 : "transparent"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: chip.modelData[1]
                        color: frame.size === chip.modelData[0] ? Theme.accentText : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
