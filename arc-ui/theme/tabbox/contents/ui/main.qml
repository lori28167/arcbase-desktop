// arc UI — selettore delle finestre di KWin (Alt+Tab): icone grandi su una
// barra vetrosa, titolo della finestra scelta sotto
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWin

KWin.TabBoxSwitcher {
    id: tabBox

    Window {
        id: dialog

        visible: tabBox.visible
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint
        color: "transparent"
        width: Math.min(panel.implicitWidth, tabBox.screenGeometry.width - 80)
        height: panel.implicitHeight
        x: tabBox.screenGeometry.x + (tabBox.screenGeometry.width - width) / 2
        y: tabBox.screenGeometry.y + (tabBox.screenGeometry.height - height) / 2

        Rectangle {
            id: panel
            anchors.fill: parent
            implicitWidth: list.contentWidth + 40
            implicitHeight: 96 + 24 + title.implicitHeight + 28
            radius: 28
            color: Qt.rgba(12 / 255, 10 / 255, 18 / 255, 0.86)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.16)

            ListView {
                id: list
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 20 }
                height: 96
                orientation: ListView.Horizontal
                spacing: 8
                model: tabBox.model
                currentIndex: tabBox.currentIndex
                highlightMoveDuration: 120
                clip: true

                highlight: Rectangle {
                    radius: 20
                    color: Qt.rgba(1, 1, 1, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                }

                delegate: Item {
                    required property int index
                    required property var model
                    width: 96
                    height: 96

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 64
                        height: 64
                        source: model.icon
                        opacity: model.minimized ? 0.55 : 1
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            tabBox.currentIndex = index;
                            tabBox.model.activate(index);
                        }
                    }
                }
            }

            Text {
                id: title
                anchors { top: list.bottom; topMargin: 14; left: parent.left; right: parent.right; leftMargin: 24; rightMargin: 24 }
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: list.currentItem ? list.currentItem.model.caption : ""
                color: Qt.rgba(1, 1, 1, 0.95)
                font.family: "Google Sans Flex"
                font.pixelSize: 14
                font.weight: Font.Medium
            }
        }
    }
}
