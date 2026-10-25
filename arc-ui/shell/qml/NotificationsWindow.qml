// Notifiche a comparsa: in alto al centro, sotto l'orario della topbar.
// Sono una pila: la più recente davanti; delle altre spunta solo il bordo in
// basso (al massimo due), così il vetro non lascia vedere le schede dietro.
// Col mouse sopra la pila si apre in elenco e le notifiche non scadono.
// Clic = azione predefinita.
// La finestra ha dimensione fissa (niente ridimensionamenti mentre arrivano
// notifiche); mouse e sfocatura seguono le schede, anche durante le animazioni.
import QtQuick
import QtQuick.Window
import org.arcbase.core
import "."

Window {
    id: win

    readonly property bool hasItems: Notifications.count > 0 && Shell.overlay === ""
    property bool ready: false
    // Pila aperta (mouse sopra)
    readonly property bool expanded: stackHover.hovered && Notifications.count > 1
    readonly property int peek: 9          // quanto spuntano le schede dietro
    readonly property int spacing: 10
    readonly property int shown: 3         // schede visibili nella pila chiusa
    // Altezze delle schede per posizione, dalle schede stesse
    property var heights: []

    color: "transparent"
    width: 400
    height: 620
    visible: false

    Component.onCompleted: {
        Shell.configureLayer(win, "arc-notifications", Shell.LayerOverlay, Shell.AnchorTop,
                             -1, Shell.KeyboardNone, Theme.panelTop, 0, 0, 0);
        ready = true;
        visible = hasItems;
        Shell.setInputRegion(win, [{ x: 0, y: 0, width: 1, height: 1, radius: 0 }]);
    }
    onHasItemsChanged: if (ready) visible = hasItems
    onVisibleChanged: if (visible) settle()

    function heightAt(i) {
        return heights[i] !== undefined ? heights[i] : 84;
    }
    function setHeight(i, h) {
        if (heights[i] === h) return;
        const list = heights.slice();
        list[i] = h;
        heights = list;
    }
    // Posto di ogni scheda: y e altezza visibile
    function slotY(i) {
        if (!expanded) return i === 0 ? 0 : heightAt(0) + peek * (i - 1);
        let y = 0;
        for (let k = 0; k < i; ++k) y += heightAt(k) + spacing;
        return y;
    }
    function slotHeight(i) {
        return expanded || i === 0 ? heightAt(i) : peek;
    }
    readonly property real stackHeight: {
        const n = expanded ? Notifications.count : Math.min(Notifications.count, shown);
        return n === 0 ? 0 : slotY(n - 1) + slotHeight(n - 1);
    }

    // Mouse e sfocatura sulle schede visibili; durante le animazioni si
    // aggiornano a ogni fotogramma
    function updateRegions() {
        const rects = [];
        for (let i = 0; i < stack.count; ++i) {
            const slot = stack.itemAt(i);
            if (!slot || slot.opacity < 0.05) continue;
            const r = slot.region();
            if (r.height > 0.5) rects.push(r);
        }
        Shell.setBlur(win, rects);
        Shell.setInputRegion(win, rects.length > 0 ? rects : [{ x: 0, y: 0, width: 1, height: 1, radius: 0 }]);
    }
    function settle() {
        frames.restart();
    }
    onExpandedChanged: settle()
    onHeightsChanged: settle()
    Connections {
        target: Notifications
        function onCountChanged() { win.settle(); }
    }
    Timer {
        id: frames
        interval: 16
        repeat: true
        property int ticks: 0
        onRunningChanged: if (running) ticks = 0
        onTriggered: {
            win.updateRegions();
            if (++ticks > Math.ceil((Theme.slow + 80) / interval)) stop();
        }
    }

    // Zona del mouse: la pila (o l'elenco aperto)
    Item {
        width: parent.width
        height: win.stackHeight
        HoverHandler {
            id: stackHover
            // La pila non scade mentre ha il mouse sopra
            onHoveredChanged: {
                for (let i = 0; i < stack.count; ++i) {
                    const slot = stack.itemAt(i);
                    if (slot) Notifications.setHovered(slot.notificationId, hovered);
                }
            }
        }
    }

    Repeater {
        id: stack
        model: Notifications

        // Il posto ritaglia la scheda: dietro se ne vede solo il fondo
        delegate: Item {
            id: slot

            required property int index
            required property int notificationId
            required property string appName
            required property string icon
            required property string summary
            required property string body
            required property var actions
            required property int urgency

            readonly property bool behind: index > 0 && !win.expanded
            property real inset: behind ? win.width * 0.03 * Math.min(index, win.shown) : 0
            property bool entered: false

            z: -index
            width: win.width
            y: entered ? win.slotY(index) : -24
            height: win.slotHeight(index)
            opacity: !entered ? 0 : behind && index >= win.shown ? 0 : 1
            visible: opacity > 0
            clip: true

            Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on inset { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Theme.normal } }

            function region() {
                return { x: inset, y: y, width: width - 2 * inset, height: height,
                         radius: Math.min(Theme.rXl, height / 2) };
            }

            Component.onCompleted: {
                win.setHeight(index, content.implicitHeight);
                entered = true;
                win.settle();
            }
            onIndexChanged: win.setHeight(index, content.implicitHeight)

            GlassPanel {
                id: panel
                x: slot.inset
                width: parent.width - 2 * slot.inset
                // Dietro: alta quanto serve per arrotondare solo il fondo
                height: slot.behind ? 2 * Theme.rXl : content.implicitHeight
                Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                anchors.bottom: parent.bottom
                radius: Theme.rXl
                border.color: slot.urgency >= 2 ? Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.5) : Theme.materialBorder

                NotificationCard {
                    id: content
                    width: parent.width
                    height: implicitHeight
                    opacity: slot.behind ? 0 : 1
                    enabled: !slot.behind
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    appName: slot.appName
                    icon: slot.icon
                    summary: slot.summary
                    body: slot.body
                    actions: slot.actions
                    onImplicitHeightChanged: win.setHeight(slot.index, implicitHeight)
                    onHoveredChanged: Notifications.setHovered(slot.notificationId, hovered || stackHover.hovered)
                    onClicked: Notifications.invoke(slot.notificationId, "default")
                    onClosed: Notifications.dismiss(slot.notificationId)
                    onActionInvoked: key => Notifications.invoke(slot.notificationId, key)
                }
            }
        }
    }
}
