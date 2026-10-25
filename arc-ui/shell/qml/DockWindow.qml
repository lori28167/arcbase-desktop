// Dock in basso al centro: app fissate e aperte, poi Launchpad e Cestino.
// Ingrandimento "a onda" come su macOS: le icone vicine al puntatore crescono
// e spostano le altre; lo zoom si calcola sulle posizioni fisse dei posti,
// così l'onda è stabile. La finestra è più alta della dock per ingrandimento,
// etichette e menu; riceve il mouse solo sulla dock.
import QtQuick
import QtQuick.Window
import org.arcbase.core
import "."

Window {
    id: win

    readonly property real base: Theme.dockIcon
    readonly property real step: Theme.dockIcon + Theme.dockSpacing
    readonly property int headroom: 150
    readonly property real maxExtra: base * (Theme.dockZoom - 1) * Theme.dockZoomRange * 1.2

    // App ingrandita: la dock scivola via e lascia lo spazio alla finestra
    // (niente zona riservata); torna portando il puntatore sul bordo in basso
    readonly property bool autoHide: ActiveWindow.maximized
    property bool revealed: false
    readonly property bool hidden: autoHide && !revealed && !menu.visible
    readonly property real bottomInset: autoHide ? Theme.gap : 0
    // Entrata e uscita: la dock sale dal bordo con un leggero rimbalzo e scende
    // accelerando; anche all'avvio della sessione entra dal basso
    readonly property real offscreen: Theme.dockHeight + Theme.gap + 12
    property bool entered: false
    property real slide: !entered || hidden ? offscreen : 0
    Behavior on slide {
        NumberAnimation {
            duration: win.slide < win.offscreen / 2 ? Theme.normal : Theme.slow
            easing.type: win.hidden || !win.entered ? Easing.InCubic : Easing.OutBack
            easing.overshoot: 1.1
        }
    }
    Timer { interval: 250; running: win.ready && !win.entered; onTriggered: win.entered = true }
    property bool ready: false
    onAutoHideChanged: {
        revealed = false;
        updateLayer();
    }
    onHiddenChanged: Qt.callLater(updateRegions)
    onSlideChanged: updateRegions()
    function updateLayer() {
        if (!ready) return;
        // Nascosta: niente margine, il bordo dello schermo fa da "maniglia"
        if (autoHide) Shell.updateLayer(win, 0, 0, 0, 0, 0);
        else Shell.updateLayer(win, Theme.dockHeight + Theme.gap, 0, 0, Theme.gap, 0);
    }

    // Puntatore in coordinate della riga (-1 = fuori) e intensità dell'onda.
    // HoverHandler sull'antenato di tutto: vede il puntatore anche sopra le icone.
    readonly property bool inBand: tracker.hovered && !menu.visible
        && tracker.point.position.y >= win.height - win.bottomInset - Theme.dockHeight - base * (Theme.dockZoom - 1)
        && tracker.point.position.x >= row.x - Theme.dockPadding - maxExtra / 2
        && tracker.point.position.x <= row.x + row.width + Theme.dockPadding + maxExtra / 2
    readonly property real pointerX: inBand ? zone.mapToItem(row, tracker.point.position.x, 0).x : -1
    property real wave: inBand ? 1 : 0
    Behavior on wave { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // Centri dei posti (icone e separatore), aggiornati quando la riga cambia
    property var centers: []
    function updateCenters() {
        const list = [];
        for (let i = 0; i < row.children.length; ++i) {
            const c = row.children[i];
            if (c.visible && c.isDockSlot === true) list.push(c.x + c.width / 2);
        }
        centers = list;
    }

    function zoomAt(center) {
        if (pointerX < 0) return 1;
        const d = Math.abs(pointerX - center) / step;
        if (d >= Theme.dockZoomRange) return 1;
        return 1 + wave * (Theme.dockZoom - 1) * (Math.cos(Math.PI * d / Theme.dockZoomRange) + 1) / 2;
    }
    function extraBefore(center) {
        let sum = 0;
        for (const c of centers) {
            if (c < center - 0.5) sum += base * (zoomAt(c) - 1);
        }
        return sum;
    }
    readonly property real totalExtra: {
        let sum = 0;
        for (const c of centers) sum += base * (zoomAt(c) - 1);
        return sum;
    }
    function shiftFor(center) {
        return extraBefore(center) + base * (zoomAt(center) - 1) / 2 - totalExtra / 2;
    }

    color: "transparent"
    width: row.width + 2 * Theme.dockPadding + maxExtra + 2 * 40
    height: Theme.dockHeight + headroom
    visible: false

    Component.onCompleted: {
        Shell.configureLayer(win, "arc-dock", Shell.LayerTop, Shell.AnchorBottom,
                             Theme.dockHeight + Theme.gap, Shell.KeyboardNone,
                             0, 0, Theme.gap, 0);
        ready = true;
        updateLayer();
        visible = true;
    }

    function updateRegions() {
        if (slide >= offscreen - 0.5) {
            Shell.setBlur(win, []);
            Shell.setInputRegion(win, [{ x: 0, y: win.height - 4, width: win.width, height: 4, radius: 0 }]);
            return;
        }
        // La sfocatura segue la dock mentre entra o esce
        const rect = { x: dock.x, y: dock.y + slide, width: dock.width, height: dock.height, radius: dock.radius };
        Shell.setBlur(win, [rect]);
        // Sopra la dock: le icone ingrandite e, se aperto, il menu
        const lift = base * (Theme.dockZoom - 1) + 10;
        const input = [{ x: dock.x, y: dock.y - lift, width: dock.width, height: dock.height + lift, radius: 0 }];
        if (menu.visible) input.push({ x: menu.x, y: menu.y, width: menu.width, height: menu.height, radius: 0 });
        Shell.setInputRegion(win, input);
    }
    onWidthChanged: Qt.callLater(updateRegions)
    onVisibleChanged: if (visible) Qt.callLater(updateRegions)

    // Bordo in basso: con la dock nascosta il puntatore qui la fa tornare
    Item {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 4
        HoverHandler {
            id: edgeHover
            onHoveredChanged: if (hovered && win.autoHide) win.revealed = true
        }
    }
    Timer {
        interval: 700
        running: win.autoHide && win.revealed && !tracker.hovered && !edgeHover.hovered && !menu.visible
        onTriggered: win.revealed = false
    }

    Item {
        id: zone
        anchors.fill: parent
        transform: Translate { y: win.slide }
        opacity: 1 - 0.4 * win.slide / win.offscreen
        HoverHandler { id: tracker }

        // --- La dock (si allarga con l'onda)
        GlassPanel {
            id: dock
            anchors.bottom: parent.bottom
            anchors.bottomMargin: win.bottomInset
            x: (win.width - width) / 2
            width: row.width + 2 * Theme.dockPadding + win.totalExtra
            height: Theme.dockHeight
            radius: Theme.dockRadius
            onWidthChanged: Qt.callLater(win.updateRegions)
        }

        // --- Le icone, su posti fissi
        Row {
            id: row
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.dockPadding + win.bottomInset
            spacing: Theme.dockSpacing
            onPositioningComplete: win.updateCenters()
            onWidthChanged: win.updateCenters()

            Repeater {
                model: provider.item ? provider.item.model : null

                DockItem {
                    id: app
                    required property var model
                    required property int index

                    readonly property bool isLauncher: model.IsLauncher === true
                    iconName: Shell.iconForApp(model.AppId || "")
                    label: model.AppName || model.display || ""
                    running: !isLauncher && model.IsStartup !== true
                    active: model.IsActive === true
                    zoom: win.zoomAt(x + width / 2)
                    shift: win.shiftFor(x + width / 2)

                    onActivated: {
                        if (isLauncher) bounce();
                        provider.item.activate(index, active, isLauncher);
                    }
                    onMiddleClicked: {
                        bounce();
                        provider.item.newInstance(index);
                    }
                    onContextMenu: (px, py) => {
                        const p = win.contentItem.mapFromItem(null, px, py);
                        const entries = isLauncher
                            ? [{ text: "Apri", icon: "arrow-right", action: () => { bounce(); provider.item.activate(index, false, true); } }]
                            : [{ text: "Nuova finestra", icon: "plus", action: () => { bounce(); provider.item.newInstance(index); } },
                               { separator: true },
                               { text: "Chiudi", icon: "close", danger: true, action: () => provider.item.close(index) }];
                        zone.openMenu(p.x, p.y, entries);
                    }
                }
            }

            // Separatore tra le app e Launchpad/Cestino
            Item {
                id: separator
                readonly property bool isDockSlot: true
                width: 13
                height: Theme.dockIcon
                Rectangle {
                    x: (parent.width - width) / 2 + win.shiftFor(separator.x + separator.width / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: Theme.dockIcon * 0.7
                    color: Theme.borderHi
                }
            }

            DockItem {
                id: launchpad
                iconName: "arc-launchpad"
                label: "Launchpad"
                active: Shell.overlay === "launcher"
                zoom: win.zoomAt(x + width / 2)
                shift: win.shiftFor(x + width / 2)
                onActivated: Shell.toggleLauncher()
            }
            DockItem {
                id: trash
                iconName: "user-trash"
                label: "Cestino"
                zoom: win.zoomAt(x + width / 2)
                shift: win.shiftFor(x + width / 2)
                onActivated: Shell.openTrash()
                onContextMenu: (px, py) => {
                    const p = win.contentItem.mapFromItem(null, px, py);
                    zone.openMenu(p.x, p.y, [
                        { text: "Apri il Cestino", icon: "trash", action: () => Shell.openTrash() },
                        { text: "Svuota il Cestino", icon: "close", danger: true,
                          action: () => Shell.run("kioclient", ["exec", "trash:/"]) }
                    ]);
                }
            }
        }

        Loader {
            id: provider
            source: "DockTasks.qml"
            onStatusChanged: {
                // Senza org.kde.taskmanager: solo le app fissate
                if (status === Loader.Error && source.toString().indexOf("DockTasks") >= 0) {
                    console.warn("arc-shell: libtaskmanager non disponibile, dock senza finestre aperte");
                    source = "DockLaunchers.qml";
                }
            }
        }

        // --- Menu contestuale delle icone (sopra la dock)
        function openMenu(px, py, entries) {
            menu.popup(px - menu.width / 2, 0, entries);
            menu.y = py - menu.height - 10;
            Qt.callLater(win.updateRegions);
        }
        ContextMenu {
            id: menu
            onDone: Qt.callLater(win.updateRegions)
        }
        // Un clic fuori dal menu (ma nella finestra) lo chiude
        MouseArea {
            anchors.fill: parent
            z: -1
            enabled: menu.visible
            onClicked: menu.close()
        }
    }
}
