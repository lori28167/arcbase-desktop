// Widget Calendario. Opzioni: sundayFirst.
// S: giorno della settimana e numero grande · M: mese · L: giorno + mese grande
import QtQuick
import org.arcbase.core
import "."

Item {
    id: widget

    property string size: "m"
    property var options: ({})
    signal optionChanged(string key, var value)

    readonly property date today: Clock.now
    readonly property int year: today.getFullYear()
    readonly property int month: today.getMonth()
    readonly property int firstDay: options.sundayFirst === true ? 0 : 1
    // Giorni vuoti prima del primo del mese
    readonly property int offset: (new Date(year, month, 1).getDay() - firstDay + 7) % 7
    readonly property int days: new Date(year, month + 1, 0).getDate()
    readonly property int rows: Math.ceil((offset + days) / 7)
    readonly property string monthName: {
        const name = Qt.locale().standaloneMonthName(month, Locale.LongFormat);
        return name.charAt(0).toUpperCase() + name.slice(1);
    }
    readonly property string weekday: Qt.locale().dayName(today.getDay(), Locale.LongFormat)

    // --- S: foglio del giorno
    Column {
        visible: widget.size === "s"
        anchors.centerIn: parent
        spacing: -4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: widget.weekday.toUpperCase()
            color: "#f87171"
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Bold
            font.letterSpacing: 1
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: widget.today.getDate()
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 78
            font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: widget.monthName
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 14
        }
    }

    // --- M e L: mese
    Item {
        visible: widget.size !== "s"
        anchors.fill: parent

        Row {
            id: header
            x: 22
            y: 16
            spacing: 10
            Text {
                visible: widget.size === "l"
                text: widget.today.getDate()
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 44
                font.weight: Font.Light
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    visible: widget.size === "l"
                    text: widget.weekday.charAt(0).toUpperCase() + widget.weekday.slice(1)
                    color: "#f87171"
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    text: widget.monthName + " " + widget.year
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
            }
        }

        Grid {
            id: grid
            anchors { left: parent.left; right: parent.right; top: header.bottom; margins: 16; topMargin: widget.size === "l" ? 14 : 8 }
            columns: 7
            readonly property real cellWidth: width / 7
            readonly property real cellHeight: (widget.height - header.y - header.height - anchors.topMargin - 14) / (widget.rows + 1)

            Repeater {
                model: 7
                Text {
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Qt.locale().dayName((index + widget.firstDay) % 7, Locale.NarrowFormat).toUpperCase()
                    color: Theme.sub
                    font.family: Theme.font
                    font.pixelSize: widget.size === "l" ? 12 : 11
                    font.weight: Font.DemiBold
                }
            }
            Repeater {
                model: widget.rows * 7
                Item {
                    id: cell
                    required property int index
                    readonly property int day: index - widget.offset + 1
                    readonly property bool isToday: day === widget.today.getDate()
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - 2
                        height: width
                        radius: width / 2
                        color: Theme.accent
                        visible: cell.isToday
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: cell.day >= 1 && cell.day <= widget.days
                        text: cell.day
                        color: cell.isToday ? Theme.accentText : Theme.text
                        font.family: Theme.font
                        font.pixelSize: widget.size === "l" ? 15 : 12
                        font.weight: cell.isToday ? Font.DemiBold : Font.Normal
                        font.features: ({ "tnum": 1 })
                    }
                }
            }
        }
    }
}
