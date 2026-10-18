// Centro notifiche (clic su ora e data): storico delle notifiche, "Non
// disturbare" e "Cancella tutto"
import QtQuick
import org.arcbase.core
import "."

GlassPanel {
    id: panel

    property real maxHeight: 600

    width: 380
    height: Math.min(maxHeight, heading.height + 32 + (history.count > 0 ? list.contentHeight + 12 : empty.height))

    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

    readonly property var history: Notifications.history

    // Il clic nel pannello non lo chiude
    MouseArea { anchors.fill: parent }

    Column {
        id: heading
        x: 18
        y: 16
        width: parent.width - 36
        spacing: 12

        Item {
            width: parent.width
            height: 40
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: {
                        const s = Clock.longDate;
                        return s.charAt(0).toUpperCase() + s.slice(1);
                    }
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
                Text {
                    text: panel.history.count === 0 ? "Nessuna notifica"
                        : panel.history.count === 1 ? "1 notifica" : panel.history.count + " notifiche"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            MouseArea {
                id: clearAll
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: panel.history.count > 0
                width: clearLabel.implicitWidth + 24
                height: 30
                hoverEnabled: true
                onClicked: panel.history.clearAll()
                Rectangle {
                    anchors.fill: parent
                    radius: 15
                    color: clearAll.containsMouse ? Theme.surface3 : Theme.surface2
                    border.width: 1
                    border.color: Theme.border
                }
                Text {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: "Cancella tutto"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
        }

        // Non disturbare
        MouseArea {
            id: dnd
            width: parent.width
            height: 48
            hoverEnabled: true
            onClicked: Notifications.doNotDisturb = !Notifications.doNotDisturb
            Rectangle {
                anchors.fill: parent
                radius: Theme.rMd
                color: dnd.containsMouse ? Theme.surface2 : Theme.surface1
                border.width: 1
                border.color: Theme.border
            }
            Rectangle {
                id: bubble
                x: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 15
                color: Notifications.doNotDisturb ? Theme.accent : Theme.surface3
                ArcIcon { anchors.centerIn: parent; width: 16; height: 16; name: "moon-small"; color: Notifications.doNotDisturb ? Theme.accentText : Theme.text }
            }
            Column {
                anchors { left: bubble.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                Text { text: "Non disturbare"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text {
                    text: Notifications.doNotDisturb ? "Le notifiche arrivano solo qui" : "Disattivato"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }
        }
    }

    Column {
        id: empty
        visible: panel.history.count === 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: heading.bottom
        topPadding: 28
        bottomPadding: 34
        spacing: 10
        ArcIcon { anchors.horizontalCenter: parent.horizontalCenter; width: 34; height: 34; name: "bell"; color: Theme.sub; strokeWidth: 1.4 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Tutto in ordine"
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 14
        }
    }

    ListView {
        id: list
        visible: panel.history.count > 0
        anchors { top: heading.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 12 }
        model: panel.history
        spacing: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: Theme.normal; easing.type: Easing.OutCubic }
        }

        delegate: Rectangle {
            id: entry
            required property int notificationId
            required property string appName
            required property string icon
            required property string summary
            required property string body
            required property var time

            width: ListView.view.width
            height: card.implicitHeight
            radius: Theme.rLg
            color: card.hovered ? Theme.surface2 : Theme.surface1
            border.width: 1
            border.color: Theme.border

            NotificationCard {
                id: card
                anchors.fill: parent
                appName: entry.appName
                icon: entry.icon
                summary: entry.summary
                body: entry.body
                time: entry.time
                showTime: true
                onClicked: panel.history.dismiss(entry.notificationId)
                onClosed: panel.history.dismiss(entry.notificationId)
            }
        }
    }
}
