// Notifiche a comparsa: in alto a destra sotto la topbar, le più recenti in
// cima. Clic = azione predefinita, mouse sopra = non scadono. Nascoste mentre
// è aperto un pannello nello stesso angolo.
import QtQuick
import QtQuick.Window
import org.arcbase.core
import "."

Window {
    id: win

    readonly property bool hasItems: Notifications.count > 0 && Shell.overlay === ""
    property bool ready: false

    color: "transparent"
    width: 380
    height: Math.max(1, list.contentHeight)
    visible: false

    Component.onCompleted: {
        Shell.configureLayer(win, "arc-notifications", Shell.LayerOverlay, Shell.AnchorTop | Shell.AnchorRight,
                             -1, Shell.KeyboardNone, Theme.panelTop, Theme.edge, 0, 0);
        ready = true;
        visible = hasItems;
    }
    onHasItemsChanged: if (ready) visible = hasItems

    function updateBlur() {
        const rects = [];
        for (let i = 0; i < list.count; ++i) {
            const item = list.itemAtIndex(i);
            if (item) rects.push({ x: item.x, y: item.y - list.contentY, width: item.width, height: item.height, radius: item.radius });
        }
        Shell.setBlur(win, rects);
    }
    onHeightChanged: Qt.callLater(updateBlur)
    onVisibleChanged: if (visible) Qt.callLater(updateBlur)

    ListView {
        id: list
        anchors.fill: parent
        model: Notifications
        spacing: 10
        interactive: false
        onCountChanged: Qt.callLater(win.updateBlur)

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal }
            NumberAnimation { property: "x"; from: 32; to: 0; duration: Theme.slow; easing.type: Easing.OutBack }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: Theme.normal; easing.type: Easing.OutCubic }
        }

        delegate: GlassPanel {
            id: popup

            required property int notificationId
            required property string appName
            required property string icon
            required property string summary
            required property string body
            required property var actions
            required property int urgency

            width: ListView.view.width
            height: content.implicitHeight
            radius: Theme.rXl
            border.color: urgency >= 2 ? Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.5) : Theme.materialBorder
            onHeightChanged: Qt.callLater(win.updateBlur)

            NotificationCard {
                id: content
                anchors.fill: parent
                appName: popup.appName
                icon: popup.icon
                summary: popup.summary
                body: popup.body
                actions: popup.actions
                onHoveredChanged: Notifications.setHovered(popup.notificationId, hovered)
                onClicked: Notifications.invoke(popup.notificationId, "default")
                onClosed: Notifications.dismiss(popup.notificationId)
                onActionInvoked: key => Notifications.invoke(popup.notificationId, key)
            }
        }
    }
}
