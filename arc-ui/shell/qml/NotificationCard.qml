// Contenuto di una notifica (.arc-toast): icona, app, ora, titolo, testo,
// azioni e pulsante di chiusura. Usato dai popup e dal centro notifiche.
import QtQuick
import "."

Item {
    id: card

    property string appName
    property string icon
    property string summary
    property string body
    property var actions: []
    property date time
    property bool showTime: false
    readonly property bool hovered: hover.containsMouse || closeButton.containsMouse

    signal clicked()
    signal closed()
    signal actionInvoked(string key)

    implicitHeight: column.height + 28

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: card.clicked()
    }

    AppIcon {
        id: appIcon
        x: 10
        y: 10
        width: 44
        height: 44
        url: card.icon
    }

    Column {
        id: column
        anchors { left: appIcon.right; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 36; topMargin: 14 }
        spacing: 3

        Row {
            width: parent.width
            spacing: 6
            Text {
                text: card.appName
                textFormat: Text.PlainText
                visible: text !== ""
                color: Theme.sub
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.6
            }
            Text {
                visible: card.showTime
                text: Qt.formatTime(card.time, "HH:mm")
                color: Theme.sub
                font.family: Theme.font
                font.pixelSize: 11
            }
        }
        Text {
            width: parent.width
            text: card.summary
            // Testo semplice (specifica freedesktop): con il formato automatico
            // "Mail da Mario <mario@x.it>" perderebbe l'indirizzo, preso per un tag
            textFormat: Text.PlainText
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: card.body
            visible: text !== ""
            textFormat: Text.StyledText
            color: Theme.muted
            linkColor: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
        Flow {
            width: parent.width
            spacing: 6
            topPadding: 6
            visible: card.actions && card.actions.length > 0
            Repeater {
                model: card.actions
                MouseArea {
                    id: action
                    required property var modelData
                    width: actionLabel.implicitWidth + 24
                    height: 28
                    hoverEnabled: true
                    onClicked: card.actionInvoked(modelData.key)
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: action.containsMouse ? Theme.surface3 : Theme.surface2
                        border.width: 1
                        border.color: Theme.border
                    }
                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: action.modelData.label
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    MouseArea {
        id: closeButton
        anchors { top: parent.top; right: parent.right; margins: 10 }
        width: 22
        height: 22
        hoverEnabled: true
        opacity: card.hovered ? 1 : 0
        onClicked: card.closed()
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Rectangle {
            anchors.fill: parent
            radius: 11
            color: closeButton.containsMouse ? Theme.surface4 : Theme.surface2
        }
        ArcIcon { anchors.centerIn: parent; width: 12; height: 12; strokeWidth: 2.4; name: "close"; color: Theme.text }
    }
}
