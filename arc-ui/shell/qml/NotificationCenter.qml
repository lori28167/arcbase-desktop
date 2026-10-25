// Centro notifiche (clic su ora e data), in alto al centro sotto l'orario:
// a sinistra il calendario del mese, a destra lo storico delle notifiche
// raggruppato per app. Ogni gruppo è una pila (la più recente davanti, le
// altre spuntano sotto); un clic sulla pila la apre. "Non disturbare" e
// "Cancella tutto" in alto.
import QtQuick
import org.arcbase.core
import "."

Item {
    id: root

    property real maxHeight: 600
    readonly property var history: Notifications.history
    // Rettangoli da sfocare (OverlayWindow): i due pannelli
    readonly property var blurRects: [
        { x: calendar.x, y: calendar.y, width: calendar.width, height: calendar.height, radius: calendar.radius, corners: calendar.corners },
        { x: notes.x, y: notes.y, width: notes.width, height: notes.height, radius: notes.radius, corners: notes.corners }
    ]

    width: 372 * 2 + 8
    height: Math.min(maxHeight, 520)

    opacity: 0
    Component.onCompleted: { opacity = 1; regroup(); }
    Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

    // Gruppi per app: [{ app, items: [riga...] }], dal più recente
    property var groups: []
    property string open: ""      // gruppo aperto
    function regroup() {
        const map = {};
        const list = [];
        for (let i = 0; i < history.count; ++i) {
            const n = history.get(i);
            const key = n.appName || "Sistema";
            if (!map[key]) {
                map[key] = { app: key, items: [] };
                list.push(map[key]);
            }
            map[key].items.push(n);
        }
        groups = list;
    }
    Connections {
        target: root.history
        function onCountChanged() { root.regroup(); }
    }

    // ======================================================== calendario
    GlassPanel {
        id: calendar
        width: 372
        height: parent.height
        radius: Theme.outer(26, 10)
        // Gruppo calendario | notifiche: piccoli gli angoli che si guardano
        readonly property bool leftSide: x === 0
        readonly property var corners: Theme.groupCorners(radius, true, !leftSide, true, leftSide)
        topLeftRadius: corners[0]; topRightRadius: corners[1]; bottomRightRadius: corners[2]; bottomLeftRadius: corners[3]
        MouseArea { anchors.fill: parent }

        property date shown: new Date(Clock.now.getFullYear(), Clock.now.getMonth(), 1)
        readonly property int year: shown.getFullYear()
        readonly property int month: shown.getMonth()
        readonly property int offset: (new Date(year, month, 1).getDay() + 6) % 7
        readonly property int days: new Date(year, month + 1, 0).getDate()
        function isToday(d) {
            const t = Clock.now;
            return d === t.getDate() && month === t.getMonth() && year === t.getFullYear();
        }

        Column {
            x: 22
            y: 22
            width: parent.width - 44
            spacing: 18

            // Oggi, grande
            Column {
                spacing: 2
                Text {
                    text: Qt.locale().dayName(Clock.now.getDay(), Locale.LongFormat).toUpperCase()
                    color: "#f87171"
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
                Text {
                    text: Clock.now.getDate() + " " + Qt.locale().standaloneMonthName(Clock.now.getMonth(), Locale.LongFormat)
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                }
            }

            // Mese con frecce
            Item {
                width: parent.width
                height: 28
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const name = Qt.locale().standaloneMonthName(calendar.month, Locale.LongFormat);
                        return name.charAt(0).toUpperCase() + name.slice(1) + " " + calendar.year;
                    }
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Arrow { icon: "chevron-left"; onClicked: calendar.shown = new Date(calendar.year, calendar.month - 1, 1) }
                    Arrow { icon: "chevron-right"; onClicked: calendar.shown = new Date(calendar.year, calendar.month + 1, 1) }
                }
            }

            Grid {
                id: grid
                columns: 7
                width: parent.width
                readonly property real cell: width / 7
                Repeater {
                    model: ["L", "M", "M", "G", "V", "S", "D"]
                    Text {
                        required property string modelData
                        width: grid.cell
                        height: 26
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.sub
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
                Repeater {
                    model: calendar.offset + calendar.days
                    Item {
                        required property int index
                        readonly property int day: index - calendar.offset + 1
                        width: grid.cell
                        height: 40
                        Rectangle {
                            anchors.centerIn: parent
                            width: 34; height: 34; radius: 17
                            color: "white"
                            visible: parent.day > 0 && calendar.isToday(parent.day)
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: parent.day > 0
                            text: parent.day
                            color: calendar.isToday(parent.day) ? Theme.accentText : Theme.text
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: calendar.isToday(parent.day) ? Font.Bold : Font.Normal
                        }
                    }
                }
            }
        }

        // In fondo: apre il calendario completo
        MouseArea {
            id: openCalendar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: calendar.radius - 25 }
            height: 50
            hoverEnabled: true
            onClicked: Shell.run("merkuro-calendar", [])
            Rectangle {
                anchors.fill: parent
                radius: 25
                color: openCalendar.containsMouse ? Theme.surface3 : Theme.surface2
                border.width: 1
                border.color: Theme.border
            }
            Text {
                anchors.centerIn: parent
                text: "Apri Calendario"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    // ======================================================== notifiche
    GlassPanel {
        id: notes
        x: calendar.width + 8
        width: 372
        height: parent.height
        radius: Theme.outer(26, 10)
        // Gruppo calendario | notifiche: piccoli gli angoli che si guardano
        readonly property bool leftSide: x === 0
        readonly property var corners: Theme.groupCorners(radius, true, !leftSide, true, leftSide)
        topLeftRadius: corners[0]; topRightRadius: corners[1]; bottomRightRadius: corners[2]; bottomLeftRadius: corners[3]
        clip: true
        MouseArea { anchors.fill: parent }

        Item {
            id: heading
            x: 22
            y: 18
            width: parent.width - 44
            height: 40
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: "Notifiche"; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                Text {
                    text: root.history.count === 0 ? "Nessuna notifica"
                        : root.history.count === 1 ? "1 notifica" : root.history.count + " notifiche"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                // Non disturbare
                MouseArea {
                    id: dnd
                    width: 34; height: 34
                    hoverEnabled: true
                    onClicked: Notifications.doNotDisturb = !Notifications.doNotDisturb
                    Rectangle {
                        anchors.fill: parent
                        radius: 17
                        color: Notifications.doNotDisturb ? Theme.accent : dnd.containsMouse ? Theme.surface3 : Theme.surface2
                        ArcIcon { anchors.centerIn: parent; width: 16; height: 16; name: "moon-small"; color: Notifications.doNotDisturb ? Theme.accentText : Theme.text }
                    }
                }
                MouseArea {
                    id: clearAll
                    visible: root.history.count > 0
                    width: clearLabel.implicitWidth + 24
                    height: 34
                    hoverEnabled: true
                    onClicked: root.history.clearAll()
                    Rectangle {
                        anchors.fill: parent
                        radius: 17
                        color: clearAll.containsMouse ? Theme.surface3 : Theme.surface2
                    }
                    Text {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: "Cancella"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }
            }
        }

        Column {
            visible: root.history.count === 0
            anchors.centerIn: parent
            spacing: 10
            ArcIcon { anchors.horizontalCenter: parent.horizontalCenter; width: 34; height: 34; name: "bell"; color: Theme.sub; strokeWidth: 1.4 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Notifications.doNotDisturb ? "Non disturbare è attivo" : "Tutto in ordine"
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: 14
            }
        }

        Flickable {
            anchors { top: heading.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
            contentHeight: groupList.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: groupList
                width: parent.width
                spacing: 12
                Repeater {
                    model: root.groups
                    // Un gruppo: pila chiusa o elenco aperto
                    Item {
                        id: group
                        required property var modelData
                        readonly property bool expanded: root.open === modelData.app || modelData.items.length === 1
                        readonly property int peeks: expanded ? 0 : Math.min(2, modelData.items.length - 1)
                        width: groupList.width
                        height: cards.height + peeks * 8

                        // Schede dietro (solo il bordo in basso)
                        Repeater {
                            model: group.peeks
                            Rectangle {
                                required property int index
                                z: -1 - index
                                x: 10 * (index + 1)
                                width: group.width - 20 * (index + 1)
                                y: cards.height - height + 8 * (index + 1)
                                height: 40
                                radius: 22
                                color: Theme.surface1
                                border.width: 1
                                border.color: Theme.border
                            }
                        }
                        Column {
                            id: cards
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: group.expanded ? group.modelData.items : group.modelData.items.slice(0, 1)
                                Rectangle {
                                    id: entry
                                    required property var modelData
                                    radius: Theme.inner(notes.radius, 10)
                                    width: cards.width
                                    height: card.implicitHeight
                                    color: card.hovered ? Theme.surface3 : Theme.surface2
                                    border.width: 1
                                    border.color: Theme.border
                                    NotificationCard {
                                        id: card
                                        anchors.fill: parent
                                        appName: entry.modelData.appName
                                        icon: entry.modelData.icon
                                        summary: entry.modelData.summary
                                        body: entry.modelData.body
                                        time: entry.modelData.time
                                        showTime: true
                                        // Pila chiusa: il clic la apre
                                        onClicked: {
                                            if (!group.expanded) root.open = group.modelData.app;
                                            else root.history.dismiss(entry.modelData.notificationId);
                                        }
                                        onClosed: root.history.dismiss(entry.modelData.notificationId)
                                    }
                                }
                            }
                        }
                        // Pila aperta: "Mostra meno"
                        Text {
                            visible: root.open === group.modelData.app && group.modelData.items.length > 1
                            anchors { right: parent.right; bottom: parent.top; rightMargin: 12; bottomMargin: -2 }
                            text: "Mostra meno"
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: 11
                            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.open = "" }
                        }
                    }
                }
            }
        }
    }

    component Arrow: MouseArea {
        id: arrow
        property string icon
        width: 30; height: 30
        hoverEnabled: true
        Rectangle { anchors.fill: parent; radius: 15; color: arrow.containsMouse ? Theme.surface3 : "transparent" }
        ArcIcon { anchors.centerIn: parent; width: 14; height: 14; strokeWidth: 2.2; name: arrow.icon; color: Theme.text }
    }
}
