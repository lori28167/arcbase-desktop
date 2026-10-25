// Menu contestuale di arc UI (stesso materiale dei pannelli).
// items: [{ text, icon, action: function, danger, separator }]
import QtQuick
import "."

GlassPanel {
    id: menu

    property var items: []
    signal done()

    width: 230
    height: column.height + 12
    radius: Theme.rLg
    visible: false
    opacity: visible ? 1 : 0
    scale: visible ? 1 : 0.96
    transformOrigin: Item.Top

    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }

    // Apre il menu nel punto (x, y) del genitore, dentro i suoi bordi
    function popup(px, py, list) {
        items = list;
        x = Math.max(8, Math.min(px, parent.width - width - 8));
        y = Math.max(8, Math.min(py, parent.height - height - 8));
        visible = true;
    }
    function close() {
        visible = false;
        done();
    }

    // Il clic dentro il menu non arriva a ciò che c'è sotto
    MouseArea { anchors.fill: parent }

    Column {
        id: column
        x: 6
        y: 6
        width: parent.width - 12

        Repeater {
            model: menu.items

            Item {
                id: entry
                required property var modelData
                width: column.width
                height: modelData.separator ? 9 : 34

                Rectangle {
                    visible: entry.modelData.separator === true
                    anchors.verticalCenter: parent.verticalCenter
                    x: 8
                    width: parent.width - 16
                    height: 1
                    color: Theme.border
                }
                MouseArea {
                    id: area
                    visible: entry.modelData.separator !== true
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        menu.close();
                        if (entry.modelData.action) entry.modelData.action();
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.inner(Theme.rLg, 6)
                        color: area.containsMouse ? (entry.modelData.danger ? Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.22) : Theme.surface3) : "transparent"
                    }
                    ArcIcon {
                        id: entryIcon
                        visible: !!entry.modelData.icon
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 17; height: 17
                        name: entry.modelData.icon || ""
                        color: entry.modelData.danger ? "#fca5a5" : Theme.text
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: entryIcon.visible ? 37 : 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.text || ""
                        color: entry.modelData.danger ? "#fca5a5" : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
