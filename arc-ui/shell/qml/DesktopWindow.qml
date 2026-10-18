// Scrivania: livello sotto le finestre con i widget su una griglia (S = 1×1,
// M = 2×1, L = 2×2 celle, come le card del mockup) e il menu del tasto destro.
// Modifica: pressione lunga su un widget o "Modifica widget" dal menu; poi si
// trascina, si cambia dimensione e contenuto, si aggiunge o si toglie.
// La disposizione si salva in Shell.widgetLayout (JSON).
import QtQuick
import QtQuick.Window
import org.arcbase.core
import "."

Window {
    id: win

    property bool editing: false
    property string settingsFor: ""     // widget con il pannello "Contenuto" aperto
    property bool galleryOpen: false

    readonly property int originX: Theme.edge
    readonly property int originY: Theme.panelTop + 6
    readonly property int stepX: Theme.cellWidth + Theme.cellGap
    readonly property int stepY: Theme.cellHeight + Theme.cellGap
    readonly property int columns: Math.max(2, Math.floor((width - 2 * Theme.edge + Theme.cellGap) / stepX))
    readonly property int rows: Math.max(2, Math.floor((height - originY - Theme.dockHeight - 2 * Theme.gap + Theme.cellGap) / stepY))

    readonly property var kinds: [
        { kind: "clock", name: "Orologio", icon: "clock-face", description: "Ora e data, digitale o analogico" },
        { kind: "calendar", name: "Calendario", icon: "widgets", description: "Il giorno e il mese" },
        { kind: "media", name: "Musica", icon: "music", description: "Cosa sta suonando" },
        { kind: "weather", name: "Meteo", icon: "cloud-sun", description: "Previsioni della tua città" },
        { kind: "system", name: "Sistema", icon: "settings", description: "Batteria, rete e suono" },
        { kind: "notes", name: "Note", icon: "pencil", description: "Un appunto sempre in vista" }
    ]
    readonly property var defaultLayout: [
        { id: "clock", kind: "clock", size: "m", col: 0, row: 0, options: {} },
        { id: "calendar", kind: "calendar", size: "m", col: 0, row: 1, options: {} }
    ]

    color: "transparent"
    width: 1280
    height: 800
    visible: false

    Component.onCompleted: {
        Shell.configureLayer(win, "arc-desktop", Shell.LayerBottom,
                             Shell.AnchorTop | Shell.AnchorBottom | Shell.AnchorLeft | Shell.AnchorRight,
                             -1, Shell.KeyboardOnDemand);
        load();
        visible = true;
    }

    // ------------------------------------------------------------ disposizione
    ListModel { id: layout }

    function span(size) {
        return size === "s" ? [1, 1] : size === "l" ? [2, 2] : [2, 1];
    }
    function load() {
        let list = defaultLayout;
        try {
            if (Shell.widgetLayout !== "") list = JSON.parse(Shell.widgetLayout);
        } catch (e) {
            console.warn("arc-shell: disposizione dei widget non valida, uso quella predefinita");
        }
        layout.clear();
        for (const w of list) {
            layout.append({ wid: String(w.id), kind: w.kind, size: w.size || "m", col: w.col | 0, row: w.row | 0,
                            optionsJson: JSON.stringify(w.options || {}) });
        }
    }
    function save() {
        const list = [];
        for (let i = 0; i < layout.count; ++i) {
            const w = layout.get(i);
            list.push({ id: w.wid, kind: w.kind, size: w.size, col: w.col, row: w.row, options: JSON.parse(w.optionsJson) });
        }
        Shell.widgetLayout = JSON.stringify(list);
        Qt.callLater(updateBlur);
    }
    function indexOf(wid) {
        for (let i = 0; i < layout.count; ++i) if (layout.get(i).wid === wid) return i;
        return -1;
    }
    function fits(col, row, size, ignore) {
        const [w, h] = span(size);
        if (col < 0 || row < 0 || col + w > columns || row + h > rows) return false;
        for (let i = 0; i < layout.count; ++i) {
            const o = layout.get(i);
            if (o.wid === ignore) continue;
            const [ow, oh] = span(o.size);
            if (col < o.col + ow && o.col < col + w && row < o.row + oh && o.row < row + h) return false;
        }
        return true;
    }
    function freeSpot(size, ignore) {
        for (let col = 0; col < columns; ++col)
            for (let row = 0; row < rows; ++row)
                if (fits(col, row, size, ignore)) return [col, row];
        return null;
    }
    function add(kind) {
        const size = kind === "notes" || kind === "media" ? "m" : "s";
        const spot = freeSpot(size, "") || freeSpot("s", "");
        if (!spot) return;
        layout.append({ wid: kind + "-" + Date.now(), kind: kind, size: fits(spot[0], spot[1], size, "") ? size : "s",
                        col: spot[0], row: spot[1], optionsJson: "{}" });
        galleryOpen = false;
        save();
    }
    function remove(wid) {
        const i = indexOf(wid);
        if (i >= 0) layout.remove(i);
        if (settingsFor === wid) settingsFor = "";
        save();
    }
    function resize(wid, size) {
        const i = indexOf(wid);
        const w = layout.get(i);
        if (fits(w.col, w.row, size, wid)) {
            layout.setProperty(i, "size", size);
        } else {
            const spot = freeSpot(size, wid);
            if (!spot) return;
            layout.setProperty(i, "size", size);
            layout.setProperty(i, "col", spot[0]);
            layout.setProperty(i, "row", spot[1]);
        }
        save();
    }
    function moveTo(wid, x, y) {
        const i = indexOf(wid);
        const w = layout.get(i);
        const col = Math.round((x - originX) / stepX);
        const row = Math.round((y - originY) / stepY);
        if (fits(col, row, w.size, wid)) {
            layout.setProperty(i, "col", col);
            layout.setProperty(i, "row", row);
            save();
        }
    }
    function setKind(wid, kind) {
        const i = indexOf(wid);
        layout.setProperty(i, "kind", kind);
        layout.setProperty(i, "optionsJson", "{}");
        save();
    }
    function setOption(wid, key, value) {
        const i = indexOf(wid);
        if (i < 0) return;
        const options = JSON.parse(layout.get(i).optionsJson);
        options[key] = value;
        layout.setProperty(i, "optionsJson", JSON.stringify(options));
        save();
    }

    function updateGhost(frame) {
        const c = Math.round((frame.x - originX) / stepX);
        const r = Math.round((frame.y - originY) / stepY);
        ghost.x = originX + c * stepX;
        ghost.y = originY + r * stepY;
        ghost.width = frame.width;
        ghost.height = frame.height;
        ghost.valid = fits(c, r, frame.size, frame.wid);
    }

    // ------------------------------------------------------------ sfocatura
    function updateBlur() {
        const rects = [];
        for (let i = 0; i < widgets.count; ++i) {
            const f = widgets.itemAt(i);
            if (f) rects.push({ x: f.x, y: f.y, width: f.width, height: f.height, radius: f.radius });
        }
        for (const p of [toolbar, gallery, settings, menu]) {
            if (p.visible) rects.push({ x: p.x, y: p.y, width: p.width, height: p.height, radius: p.radius });
        }
        Shell.setBlur(win, rects);
    }
    onWidthChanged: Qt.callLater(updateBlur)
    onHeightChanged: Qt.callLater(updateBlur)
    onEditingChanged: {
        if (!editing) {
            settingsFor = "";
            galleryOpen = false;
        }
        Qt.callLater(updateBlur);
    }
    onSettingsForChanged: Qt.callLater(updateBlur)
    onGalleryOpenChanged: Qt.callLater(updateBlur)

    // ------------------------------------------------------------ scrivania
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (menu.visible) {
                menu.close();
                return;
            }
            if (mouse.button === Qt.RightButton) {
                Shell.hideOverlay();
                menu.popup(mouse.x, mouse.y, [
                    { text: win.editing ? "Fine modifica" : "Modifica widget", icon: "pencil", action: () => win.editing = !win.editing },
                    { text: "Aggiungi widget…", icon: "plus", action: () => { win.editing = true; win.galleryOpen = true; } },
                    { separator: true },
                    { text: "Cambia sfondo…", icon: "image", action: () => Shell.overlay = "wallpaper" },
                    { text: "Impostazioni schermo", icon: "display", action: () => Shell.openSettings("kcm_kscreen") },
                    { text: "Impostazioni", icon: "settings", action: () => Shell.openSettings() }
                ]);
                Qt.callLater(win.updateBlur);
                return;
            }
            Shell.hideOverlay();
            if (win.settingsFor !== "") win.settingsFor = "";
            else if (win.galleryOpen) win.galleryOpen = false;
            else if (win.editing) win.editing = false;
        }
    }

    // Griglia visibile in modifica
    Repeater {
        model: win.editing ? win.columns * win.rows : 0
        Rectangle {
            required property int index
            x: win.originX + Math.floor(index / win.rows) * win.stepX
            y: win.originY + (index % win.rows) * win.stepY
            width: Theme.cellWidth
            height: Theme.cellHeight
            radius: Theme.widgetRadius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
        }
    }

    // Dove finirebbe il widget trascinato
    Rectangle {
        id: ghost
        property bool valid: false
        visible: false
        radius: Theme.widgetRadius
        color: valid ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.14)
        border.width: 2
        border.color: valid ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.5)
    }

    Repeater {
        id: widgets
        model: layout
        onItemAdded: Qt.callLater(win.updateBlur)
        onItemRemoved: Qt.callLater(win.updateBlur)

        WidgetFrame {
            id: frame
            // wid, kind e size sono di WidgetFrame: qui diventano ruoli richiesti
            required wid
            required kind
            required size
            required property int col
            required property int row
            required property string optionsJson

            readonly property var spanSize: win.span(size)
            readonly property real homeX: win.originX + col * win.stepX
            readonly property real homeY: win.originY + row * win.stepY

            x: homeX
            y: homeY
            width: spanSize[0] * Theme.cellWidth + (spanSize[0] - 1) * Theme.cellGap
            height: spanSize[1] * Theme.cellHeight + (spanSize[1] - 1) * Theme.cellGap
            Behavior on x { enabled: !frame.dragging; NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !frame.dragging; NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            onXChanged: {
                if (dragging) win.updateGhost(frame);
                Qt.callLater(win.updateBlur);
            }
            onYChanged: {
                if (dragging) win.updateGhost(frame);
                Qt.callLater(win.updateBlur);
            }
            onWidthChanged: Qt.callLater(win.updateBlur)
            onHeightChanged: Qt.callLater(win.updateBlur)

            editing: win.editing
            options: JSON.parse(optionsJson)

            onEditRequested: win.editing = true
            onRemoveRequested: win.remove(wid)
            onSizeRequested: s => win.resize(wid, s)
            onSettingsRequested: win.settingsFor = (win.settingsFor === wid ? "" : wid)
            onOptionChanged: (key, value) => win.setOption(wid, key, value)
            onDraggingChanged: ghost.visible = dragging
            onDropped: (dx, dy) => {
                win.moveTo(wid, dx, dy);
                // Torna al posto (o va nel nuovo): la posizione segue di nuovo la griglia
                x = Qt.binding(() => homeX);
                y = Qt.binding(() => homeY);
            }
        }
    }

    // ------------------------------------------------------------ barra di modifica
    GlassPanel {
        id: toolbar
        visible: win.editing
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.panelTop
        width: toolbarRow.width + 16
        height: 48
        radius: 24

        Row {
            id: toolbarRow
            anchors.centerIn: parent
            spacing: 6
            PillButton { icon: "plus"; text: "Aggiungi widget"; onClicked: win.galleryOpen = !win.galleryOpen }
            PillButton { icon: "check"; text: "Fine"; primary: true; onClicked: win.editing = false }
        }
    }

    // ------------------------------------------------------------ galleria
    GlassPanel {
        id: gallery
        visible: win.galleryOpen
        anchors.horizontalCenter: parent.horizontalCenter
        y: toolbar.y + toolbar.height + 12
        width: Math.min(parent.width - 96, 860)
        height: 150

        MouseArea { anchors.fill: parent }
        Row {
            anchors.centerIn: parent
            spacing: 12
            Repeater {
                model: win.kinds
                MouseArea {
                    id: kindButton
                    required property var modelData
                    width: (gallery.width - 40 - (win.kinds.length - 1) * 12) / win.kinds.length
                    height: 118
                    hoverEnabled: true
                    onClicked: win.add(modelData.kind)
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rLg
                        color: kindButton.containsMouse ? Theme.surface3 : Theme.surface1
                        border.width: 1
                        border.color: Theme.border
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 16
                        width: 44; height: 44; radius: 14
                        color: Theme.surface3
                        ArcIcon { anchors.centerIn: parent; width: 22; height: 22; name: kindButton.modelData.icon; color: Theme.text }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 70
                        text: kindButton.modelData.name
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 89
                        width: parent.width - 12
                        horizontalAlignment: Text.AlignHCenter
                        text: kindButton.modelData.description
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 10
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ contenuto di un widget
    GlassPanel {
        id: settings
        readonly property int index: win.indexOf(win.settingsFor)
        readonly property var target: index >= 0 ? widgets.itemAt(index) : null
        readonly property var current: index >= 0 ? layout.get(index) : null
        readonly property var options: current ? JSON.parse(current.optionsJson) : ({})

        visible: target !== null && win.editing
        x: target ? Math.min(target.x + target.width + 14, win.width - width - 16) : 0
        y: target ? Math.min(target.y, win.height - height - 16) : 0
        width: 260
        height: settingsColumn.height + 28
        radius: Theme.rXl

        MouseArea { anchors.fill: parent }
        Column {
            id: settingsColumn
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 4

            Text {
                text: "Contenuto"
                bottomPadding: 6
                color: Theme.sub
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
            }
            Repeater {
                model: win.kinds
                MouseArea {
                    id: choice
                    required property var modelData
                    readonly property bool selected: settings.current !== null && settings.current.kind === modelData.kind
                    width: settingsColumn.width
                    height: 36
                    hoverEnabled: true
                    onClicked: win.setKind(win.settingsFor, modelData.kind)
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSm
                        color: choice.selected ? Theme.surface3 : choice.containsMouse ? Theme.surface2 : "transparent"
                    }
                    ArcIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 17; height: 17; name: choice.modelData.icon; color: Theme.text }
                    Text {
                        x: 38
                        anchors.verticalCenter: parent.verticalCenter
                        text: choice.modelData.name
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                    ArcIcon { visible: choice.selected; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; strokeWidth: 2.2; name: "check"; color: Theme.text }
                }
            }

            // Opzioni del tipo scelto
            Rectangle { visible: optionsColumn.children.length > 0 && optionsColumn.height > 0; width: parent.width; height: 1; color: Theme.border }
            Column {
                id: optionsColumn
                width: parent.width
                spacing: 4
                topPadding: 4

                OptionSwitch {
                    visible: settings.current !== null && settings.current.kind === "clock"
                    text: "Analogico"
                    checked: settings.options.analog === true
                    onToggled: win.setOption(win.settingsFor, "analog", !checked)
                }
                OptionSwitch {
                    visible: settings.current !== null && settings.current.kind === "clock"
                    text: "Mostra i secondi"
                    checked: settings.options.seconds === true
                    onToggled: win.setOption(win.settingsFor, "seconds", !checked)
                }
                Rectangle {
                    visible: settings.current !== null && settings.current.kind === "weather"
                    width: parent.width
                    height: 36
                    radius: Theme.rSm
                    color: Theme.surface2
                    border.width: 1
                    border.color: cityInput.activeFocus ? Theme.borderHi : Theme.border
                    ArcIcon { id: cityIcon; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; name: "location"; color: Theme.muted }
                    TextInput {
                        id: cityInput
                        anchors { left: cityIcon.right; right: parent.right; leftMargin: 8; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: settings.options.city || "Trento"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                        clip: true
                        onEditingFinished: win.setOption(win.settingsFor, "city", text)
                    }
                }
                OptionSwitch {
                    visible: settings.current !== null && settings.current.kind === "calendar"
                    text: "Settimana da domenica"
                    checked: settings.options.sundayFirst === true
                    onToggled: win.setOption(win.settingsFor, "sundayFirst", !checked)
                }
                Row {
                    visible: settings.current !== null && settings.current.kind === "notes"
                    spacing: 8
                    topPadding: 6
                    bottomPadding: 4
                    Repeater {
                        model: ["", "#facc15", "#4ade80", "#60a5fa", "#f472b6", "#a78bfa"]
                        MouseArea {
                            id: swatch
                            required property string modelData
                            width: 26; height: 26
                            onClicked: win.setOption(win.settingsFor, "tint", modelData)
                            Rectangle {
                                anchors.fill: parent
                                radius: 13
                                color: swatch.modelData === "" ? Theme.surface3 : swatch.modelData
                                border.width: (settings.options.tint || "") === swatch.modelData ? 2 : 1
                                border.color: (settings.options.tint || "") === swatch.modelData ? Theme.accent : Theme.border
                            }
                        }
                    }
                }
            }
        }
    }

    ContextMenu {
        id: menu
        onDone: Qt.callLater(win.updateBlur)
    }

    // ------------------------------------------------------------ componenti
    component PillButton: MouseArea {
        id: pill
        property string icon
        property string text
        property bool primary: false
        width: pillRow.width + 28
        height: 34
        hoverEnabled: true
        Rectangle {
            anchors.fill: parent
            radius: 17
            color: pill.primary ? Theme.accent : pill.containsMouse ? Theme.surface3 : Theme.surface2
        }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 7
            ArcIcon { anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; strokeWidth: 2.2; name: pill.icon; color: pill.primary ? Theme.accentText : Theme.text }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.primary ? Theme.accentText : Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }
    }

    component OptionSwitch: MouseArea {
        id: option
        property string text
        property bool checked: false
        signal toggled()
        width: parent ? parent.width : 220
        height: 36
        onClicked: option.toggled()
        Text {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: option.text
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 24; radius: 12
            color: option.checked ? Theme.accent : Theme.surface3
            Rectangle {
                x: option.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18; radius: 9
                color: option.checked ? Theme.accentText : Theme.text
                Behavior on x { NumberAnimation { duration: Theme.fast } }
            }
        }
    }
}
