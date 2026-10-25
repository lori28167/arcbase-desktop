// Widget Orologio. Opzioni: analog (lancette), seconds.
// S: ora e giorno · M: saluto, ora, data · L: ora grande o quadrante grande
import QtQuick
import org.arcbase.core
import "."

Item {
    id: widget

    property string size: "m"
    property var options: ({})
    signal optionChanged(string key, var value)

    readonly property bool analog: options.analog === true
    readonly property bool seconds: options.seconds === true
    readonly property int hour: Clock.now.getHours()
    readonly property string greeting: hour < 5 ? "Buonanotte" : hour < 13 ? "Buongiorno" : hour < 18 ? "Buon pomeriggio" : "Buonasera"
    readonly property string time: seconds ? Qt.formatTime(Clock.now, "HH:mm:ss") : Clock.time
    readonly property string longDate: Clock.longDate.charAt(0).toUpperCase() + Clock.longDate.slice(1)

    // --- Digitale
    Column {
        visible: !widget.analog
        anchors.left: parent.left
        anchors.leftMargin: widget.size === "s" ? 20 : 26
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            visible: widget.size !== "s"
            text: widget.greeting + ", " + Shell.fullName.split(" ")[0]
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        Text {
            text: widget.time
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: widget.size === "s" ? (widget.seconds ? 34 : 46) : widget.size === "l" ? 96 : 64
            font.weight: Font.Light
            font.letterSpacing: widget.size === "s" ? -1 : -2
            font.features: ({ "tnum": 1 })
        }
        Text {
            text: widget.size === "s" ? Clock.shortDate : widget.longDate
            color: widget.size === "s" ? Theme.muted : Theme.text
            font.family: Theme.font
            font.pixelSize: widget.size === "l" ? 20 : 16
        }
    }

    // --- Analogico
    Item {
        visible: widget.analog
        anchors.fill: parent

        AnalogFace {
            id: face
            width: widget.size === "l" ? Math.min(parent.width, parent.height) - 110 : Math.min(parent.height - 36, 150)
            height: width
            x: widget.size === "m" ? 22 : (parent.width - width) / 2
            y: widget.size === "l" ? 30 : (parent.height - height) / 2
            showSeconds: widget.seconds
        }
        Column {
            visible: widget.size !== "s"
            x: widget.size === "m" ? face.x + face.width + 22 : (parent.width - width) / 2
            y: widget.size === "m" ? (parent.height - height) / 2 : face.y + face.height + 16
            spacing: 2
            Text {
                anchors.horizontalCenter: widget.size === "l" ? parent.horizontalCenter : undefined
                text: Clock.time
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 30
                font.weight: Font.Light
            }
            Text {
                anchors.horizontalCenter: widget.size === "l" ? parent.horizontalCenter : undefined
                text: widget.longDate
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: 14
            }
        }
    }

    component AnalogFace: Item {
        id: dial
        property bool showSeconds: false
        readonly property real h: Clock.now.getHours() % 12
        readonly property real m: Clock.now.getMinutes()
        readonly property real s: Clock.now.getSeconds()

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.surface2
            border.width: 1
            border.color: Theme.borderHi
        }
        // Tacche delle ore
        Repeater {
            model: 12
            Item {
                required property int index
                anchors.fill: parent
                rotation: index * 30
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: dial.height * 0.06
                    width: parent.index % 3 === 0 ? 3 : 2
                    height: dial.height * (parent.index % 3 === 0 ? 0.08 : 0.05)
                    radius: 1
                    color: parent.index % 3 === 0 ? Theme.text : Theme.sub
                }
            }
        }
        Hand { length: 0.27; thickness: 4; angle: (dial.h + dial.m / 60) * 30; color: Theme.text }
        Hand { length: 0.38; thickness: 3; angle: (dial.m + dial.s / 60) * 6; color: Theme.text }
        Hand { visible: dial.showSeconds; length: 0.42; thickness: 1.5; angle: dial.s * 6; color: "#f59e0b" }
        Rectangle {
            anchors.centerIn: parent
            width: 8; height: 8; radius: 4
            color: dial.showSeconds ? "#f59e0b" : Theme.text
        }

    }

    // Lancetta: ruota attorno al centro del quadrante
    component Hand: Item {
        id: hand
        property real length
        property real thickness
        property real angle
        property color color
        anchors.fill: parent
        rotation: angle
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 - parent.height * hand.length
            width: hand.thickness
            height: parent.height * hand.length + 6
            radius: width / 2
            color: hand.color
            antialiasing: true
        }
    }
}
