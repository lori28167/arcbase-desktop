// Launchpad come nei vecchi macOS, con in più:
// - la topbar si trasforma nella barra di ricerca (e torna topbar alla chiusura);
// - cartelle: si trascina un'app su un'altra per crearne una, su una cartella
//   per aggiungerla, fuori dalla cartella aperta per toglierla; trascinando
//   tra le icone si riordina. Le cartelle sono riquadri 2×2 come widget: le
//   app dentro si avviano subito, il riquadro apre la cartella;
// - ricerca stile Spotlight: app in alto, poi file, impostazioni, calcoli,
//   conversioni, finestre... da KRunner (Search).
// La disposizione si salva in Shell.launchpadLayout.
import QtQuick
import org.arcbase.core
import "."

Item {
    id: pad

    property bool closing: false

    // ------------------------------------------------------------ apertura/chiusura
    // p: 0 = barra in alto (topbar), 1 = barra di ricerca e griglia
    property real p: 0
    Behavior on p { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    Component.onCompleted: {
        Applications.filter = "";
        Search.query = "";
        load();
        p = 1;
        search.forceActiveFocus();
    }
    onClosingChanged: if (closing) {
        folderId = "";
        p = 0;
    }
    function setQuery(text) { search.text = text; }
    // Griglia attenuata dietro la cartella aperta
    property real folderDim: folderId !== "" ? 0.08 : 1
    Behavior on folderDim { NumberAnimation { duration: Theme.fast } }
    readonly property real gridOpacity: Math.max(0, (p - 0.35) / 0.65)

    // ------------------------------------------------------------ disposizione
    property var items: []          // [{type: "app", id} | {type: "folder", id, name, apps}]
    property string folderId: ""    // cartella aperta

    function load() {
        let saved = [];
        try {
            if (Shell.launchpadLayout !== "") saved = JSON.parse(Shell.launchpadLayout);
        } catch (e) {
            saved = [];
        }
        const known = {};
        for (const id of Applications.allIds) known[id] = true;
        const used = {};
        const list = [];
        for (const e of saved) {
            if (e.type === "folder") {
                const apps = (e.apps || []).filter(a => known[a] && !used[a]);
                apps.forEach(a => used[a] = true);
                if (apps.length > 1) list.push({ type: "folder", id: e.id, name: e.name || "Cartella", apps: apps });
                else if (apps.length === 1) list.push({ type: "app", id: apps[0] });
            } else if (known[e.id] && !used[e.id]) {
                used[e.id] = true;
                list.push({ type: "app", id: e.id });
            }
        }
        for (const id of Applications.allIds) if (!used[id]) list.push({ type: "app", id: id });
        items = list;
    }
    function save(list) {
        // Una cartella con una sola app torna app
        const clean = [];
        for (const e of list) {
            if (e.type === "folder" && e.apps.length === 1) clean.push({ type: "app", id: e.apps[0] });
            else if (e.type !== "folder" || e.apps.length > 0) clean.push(e);
        }
        items = clean;
        Shell.launchpadLayout = JSON.stringify(clean);
        if (folderId !== "" && !clean.some(e => e.id === folderId)) folderId = "";
    }
    function copy() { return items.map(e => e.type === "folder" ? { type: "folder", id: e.id, name: e.name, apps: e.apps.slice() } : { type: "app", id: e.id }); }
    function indexOfId(list, id) { return list.findIndex(e => e.id === id); }
    function folderOf(id) { return items.find(e => e.id === id && e.type === "folder"); }

    readonly property var categoryNames: ({
        "AudioVideo": "Multimedia", "Audio": "Multimedia", "Video": "Multimedia", "Development": "Sviluppo",
        "Education": "Istruzione", "Game": "Giochi", "Graphics": "Grafica", "Network": "Internet", "Office": "Ufficio",
        "Science": "Scienza", "Settings": "Impostazioni", "System": "Sistema", "Utility": "Accessori"
    })
    function folderName(a, b) {
        const ca = Applications.categories(a), cb = Applications.categories(b);
        for (const c of ca) if (cb.indexOf(c) >= 0 && categoryNames[c]) return categoryNames[c];
        return "Cartella";
    }

    function createFolder(dragged, target) {
        const list = copy();
        const t = indexOfId(list, target);
        const folder = { type: "folder", id: "folder-" + Date.now(), name: folderName(dragged, target), apps: [target, dragged] };
        list[t] = folder;
        list.splice(indexOfId(list, dragged), 1);
        save(list);
    }
    function addToFolder(dragged, folder) {
        const list = copy();
        list.splice(indexOfId(list, dragged), 1);
        list[indexOfId(list, folder)].apps.push(dragged);
        save(list);
    }
    function moveBefore(dragged, target) {
        const list = copy();
        const item = list.splice(indexOfId(list, dragged), 1)[0];
        const t = target === "" ? list.length : indexOfId(list, target);
        list.splice(t < 0 ? list.length : t, 0, item);
        save(list);
    }
    function removeFromFolder(app, folder) {
        const list = copy();
        const f = indexOfId(list, folder);
        list[f].apps.splice(list[f].apps.indexOf(app), 1);
        list.splice(f + 1, 0, { type: "app", id: app });
        save(list);
    }
    function moveInFolder(app, before, folder) {
        const list = copy();
        const apps = list[indexOfId(list, folder)].apps;
        apps.splice(apps.indexOf(app), 1);
        const t = apps.indexOf(before);
        apps.splice(t < 0 ? apps.length : t, 0, app);
        save(list);
    }
    function renameFolder(folder, name) {
        const list = copy();
        list[indexOfId(list, folder)].name = name.trim() !== "" ? name.trim() : "Cartella";
        save(list);
    }

    // ------------------------------------------------------------ griglia a pagine
    // Griglia: le misure vengono dalla cartella (2×2 celle). Il suo lato va
    // dal bordo di un'icona a quello dell'icona dopo (cella + icona) e vale
    // 2,465 volte le sue icone grandi, che sono 1,15 volte le app (come la
    // Libreria app di iPhone). Quindi cella = 1,835 icone visibili:
    // icone da 106 (85 visibili), celle quadrate da 155, al massimo 7×4.
    readonly property real appIcon: 106
    readonly property real appBody: appIcon * Theme.iconBody
    readonly property real labelSpace: 28          // spazio + riga del nome
    readonly property real cellSize: Math.round(appBody * 1.835)
    readonly property int columns: Math.max(4, Math.min(7, Math.floor((width - 160) / cellSize)))
    // Margine generoso sopra e sotto: 3 righe su 900 px, 4 da 1080 in su
    readonly property int rows: Math.max(2, Math.min(4, Math.floor((height - 360) / cellSize)))
    readonly property real cellW: Math.min(cellSize, (width - 120) / columns)
    readonly property real cellH: Math.min(cellSize, pages.height / rows)
    // Dove sta l'icona nella cella (anche la cartella si allinea a questa riga)
    readonly property real iconTop: (cellH - appIcon - labelSpace) / 2
    // Alone attorno a un'icona: angoli concentrici con quelli visibili dell'icona
    function haloRadius(size) { return (size - appBody) / 2 + appBody * Theme.iconCorner; }
    readonly property real gridX: (width - columns * cellW) / 2
    readonly property real gridY: (pages.height - rows * cellH) / 2

    // Posizioni: app 1×1, cartelle 2×2, al primo posto libero in ordine di lettura
    readonly property var placed: {
        const out = [];
        let page = 0;
        let used = [];
        const free = (c, r, w, h) => {
            if (c + w > columns || r + h > rows) return false;
            for (let y = r; y < r + h; ++y) for (let x = c; x < c + w; ++x) if (used[y * columns + x]) return false;
            return true;
        };
        for (const item of items) {
            const w = item.type === "folder" ? 2 : 1, h = w;
            let spot = null;
            for (let attempt = 0; attempt < 2 && !spot; ++attempt) {
                for (let r = 0; r < rows && !spot; ++r) for (let c = 0; c < columns && !spot; ++c) if (free(c, r, w, h)) spot = [c, r];
                if (!spot) { page++; used = []; }
            }
            if (!spot) continue;
            for (let y = spot[1]; y < spot[1] + h; ++y) for (let x = spot[0]; x < spot[0] + w; ++x) used[y * columns + x] = true;
            out.push({ item: item, page: page, col: spot[0], row: spot[1], w: w, h: h });
        }
        return out;
    }
    readonly property int pageCount: placed.length > 0 ? placed[placed.length - 1].page + 1 : 1

    // ------------------------------------------------------------ trascinamento
    property string dragId: ""
    property string dragFrom: ""     // cartella da cui arriva, "" = griglia
    property string dropHint: ""     // id del riquadro su cui cadrebbe (cartella/nuova cartella)

    function hitTest(px, py) {
        const local = pages.mapFromItem(pad, px, py);
        const x = local.x - gridX, y = local.y - gridY;
        const col = Math.floor(x / cellW), row = Math.floor(y / cellH);
        for (const p of placed) {
            if (p.page !== pages.currentIndex) continue;
            if (col >= p.col && col < p.col + p.w && row >= p.row && row < p.row + p.h) {
                const fx = (x - p.col * cellW) / (p.w * cellW), fy = (y - p.row * cellH) / (p.h * cellH);
                const onto = p.item.type === "folder" || (fx > 0.22 && fx < 0.78 && fy > 0.08 && fy < 0.68);
                return { item: p.item, onto: onto };
            }
        }
        return null;
    }
    function dragMoved(px, py) {
        if (folderId !== "") { dropHint = ""; return; }
        const hit = hitTest(px, py);
        const dragged = items.find(e => e.id === dragId);
        dropHint = hit && hit.onto && hit.item.id !== dragId && dragged && dragged.type === "app" ? hit.item.id : "";
        // Bordo destro/sinistro: pagina successiva/precedente
        edgeFlip.direction = px < 60 ? -1 : px > pad.width - 60 ? 1 : 0;
    }
    function dropped(px, py) {
        const id = dragId, from = dragFrom;
        dragId = ""; dragFrom = ""; dropHint = ""; edgeFlip.direction = 0;
        if (id === "") return;
        if (from !== "") {
            const inside = folderPanel.contains(folderPanel.mapFromItem(pad, px, py));
            if (!inside) { removeFromFolder(id, from); folderId = ""; return; }
            const target = folderGrid.childAt(folderGrid.mapFromItem(pad, px, py).x, folderGrid.mapFromItem(pad, px, py).y);
            if (target && target.appId && target.appId !== id) moveInFolder(id, target.appId, from);
            return;
        }
        const hit = hitTest(px, py);
        const dragged = items.find(e => e.id === id);
        if (!dragged) return;
        if (hit && hit.item.id !== id) {
            if (hit.onto && dragged.type === "app" && hit.item.type === "app") createFolder(id, hit.item.id);
            else if (hit.onto && dragged.type === "app" && hit.item.type === "folder") addToFolder(id, hit.item.id);
            else moveBefore(id, hit.item.id);
        } else if (!hit) {
            // Spazio vuoto: in fondo alla pagina corrente
            const onPage = placed.filter(p => p.page === pages.currentIndex);
            const next = placed.find(p => p.page > pages.currentIndex);
            if (onPage.length > 0 && onPage[onPage.length - 1].item.id !== id) moveBefore(id, next ? next.item.id : "");
        }
    }
    Timer {
        id: edgeFlip
        property int direction: 0
        interval: 650
        repeat: true
        running: direction !== 0 && pad.dragId !== ""
        onTriggered: pages.currentIndex = Math.max(0, Math.min(pad.pageCount - 1, pages.currentIndex + direction))
    }

    // ------------------------------------------------------------ ricerca
    readonly property bool searching: search.text.trim() !== ""
    property int selected: 0
    readonly property int appResults: Math.min(Applications.count, columns * 2)
    readonly property int resultCount: appResults + Search.results.length
    function activate(i) {
        if (i < appResults) Applications.launchAt(i);
        else Search.run(i - appResults);
    }

    // ============================================================ grafica
    // Velo e sfocatura (la sfocatura vera la fa KWin)
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: pad.p
    }
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (pad.folderId !== "") pad.folderId = "";
            else Shell.hideOverlay();
        }
        onWheel: wheel => wheelFlip(wheel)
    }
    property real wheelAccumulated: 0
    function wheelFlip(wheel) {
        if (searching) return;
        wheelAccumulated += wheel.angleDelta.y + wheel.angleDelta.x;
        if (Math.abs(wheelAccumulated) >= 120) {
            pages.currentIndex = Math.max(0, Math.min(pageCount - 1, pages.currentIndex + (wheelAccumulated < 0 ? 1 : -1)));
            wheelAccumulated = 0;
        }
    }

    // --- Pagine di app e cartelle
    ListView {
        id: pages
        anchors { top: parent.top; topMargin: 150; bottom: dots.top; bottomMargin: 24; left: parent.left; right: parent.right }
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 380
        boundsBehavior: Flickable.StopAtBounds
        interactive: pad.pageCount > 1 && pad.dragId === ""
        model: pad.pageCount
        clip: true
        visible: !pad.searching
        opacity: pad.gridOpacity * pad.folderDim
        scale: 1.06 - 0.06 * pad.p

        delegate: Item {
            id: page
            required property int index
            width: pages.width
            height: pages.height

            Repeater {
                model: pad.placed.filter(p => p.page === page.index)
                Loader {
                    required property var modelData
                    x: pad.gridX + modelData.col * pad.cellW
                    y: pad.gridY + modelData.row * pad.cellH
                    width: modelData.w * pad.cellW
                    height: modelData.h * pad.cellH
                    sourceComponent: modelData.item.type === "folder" ? folderTile : appTile
                    onLoaded: {
                        item.entry = modelData.item;
                    }
                }
            }
        }
    }

    // --- Puntini delle pagine
    Row {
        id: dots
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.dockHeight + Theme.gap + 34
        spacing: 12
        visible: pad.pageCount > 1 && !pad.searching
        opacity: pad.gridOpacity
        Repeater {
            model: pad.pageCount
            MouseArea {
                required property int index
                width: 10
                height: 10
                onClicked: pages.currentIndex = index
                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: Qt.rgba(1, 1, 1, pages.currentIndex === parent.index ? 0.95 : 0.35)
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                }
            }
        }
    }

    // --- Risultati della ricerca
    Flickable {
        id: results
        visible: pad.searching
        opacity: pad.gridOpacity
        anchors { top: parent.top; topMargin: 140; bottom: parent.bottom; bottomMargin: Theme.dockHeight + 2 * Theme.gap; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width - 120, pad.columns * pad.cellW)
        contentHeight: resultsColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: resultsColumn
            width: parent.width
            spacing: 18

            Flow {
                width: parent.width
                Repeater {
                    model: Applications
                    Loader {
                        required property int index
                        required property string storageId
                        visible: index < pad.appResults
                        width: pad.cellW
                        height: visible ? pad.cellH : 0
                        sourceComponent: appTile
                        onLoaded: {
                            item.entry = { type: "app", id: storageId };
                            item.highlighted = Qt.binding(() => pad.selected === index);
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 6
                visible: Search.results.length > 0
                Text {
                    text: "Altri risultati"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    leftPadding: 6
                    bottomPadding: 2
                }
                Repeater {
                    model: Search.results
                    MouseArea {
                        id: result
                        required property var modelData
                        required property int index
                        readonly property bool current: pad.selected === pad.appResults + index
                        width: parent.width
                        height: 56
                        hoverEnabled: true
                        onClicked: Search.run(index)
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.rLg
                            color: result.current ? Theme.surface4 : result.containsMouse ? Theme.surface3 : Theme.material
                            border.width: 1
                            border.color: Theme.materialBorder
                        }
                        AppIcon {
                            id: resultIcon
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40; height: 40
                            name: result.modelData.icon
                        }
                        Column {
                            anchors { left: resultIcon.right; leftMargin: 12; right: category.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            Text { width: parent.width; text: result.modelData.text; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                            Text { width: parent.width; visible: text !== ""; text: result.modelData.subtext; elide: Text.ElideMiddle; color: Theme.muted; font.family: Theme.font; font.pixelSize: 12 }
                        }
                        Text {
                            id: category
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: result.modelData.category
                            color: Theme.sub
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                    }
                }
            }

            Text {
                visible: pad.resultCount === 0 && !Search.busy
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 40
                text: "Nessun risultato"
                color: Theme.muted
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.3)
                font.family: Theme.font
                font.pixelSize: 22
                font.weight: Font.Light
            }
        }
    }

    // --- Cartella aperta
    MouseArea {
        anchors.fill: parent
        visible: pad.folderId !== ""
        onClicked: pad.folderId = ""
    }
    GlassPanel {
        id: folderPanel
        readonly property var folder: pad.folderId !== "" ? pad.folderOf(pad.folderId) : null
        visible: folder !== null
        anchors.centerIn: parent
        width: Math.min(pad.width - 120, 5 * pad.cellW + 48)
        height: folderTitle.height + folderGrid.height + 64
        radius: 34
        color: Qt.rgba(14 / 255, 12 / 255, 20 / 255, 0.78)
        scale: visible ? 1 : 0.9
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }

        MouseArea { anchors.fill: parent }
        TextInput {
            id: folderTitle
            anchors.horizontalCenter: parent.horizontalCenter
            y: 22
            width: parent.width - 60
            horizontalAlignment: TextInput.AlignHCenter
            text: folderPanel.folder ? folderPanel.folder.name : ""
            color: Theme.text
            selectionColor: Theme.surface4
            font.family: Theme.font
            font.pixelSize: 24
            font.weight: Font.DemiBold
            selectByMouse: true
            onEditingFinished: if (folderPanel.folder && text !== folderPanel.folder.name) pad.renameFolder(pad.folderId, text)
        }
        Flow {
            id: folderGrid
            anchors.horizontalCenter: parent.horizontalCenter
            y: folderTitle.y + folderTitle.height + 18
            width: 5 * pad.cellW
            Repeater {
                model: folderPanel.folder ? folderPanel.folder.apps : []
                Loader {
                    required property string modelData
                    readonly property string appId: modelData
                    width: pad.cellW
                    height: pad.cellH
                    sourceComponent: appTile
                    onLoaded: {
                        item.entry = { type: "app", id: modelData };
                        item.folder = pad.folderId;
                    }
                }
            }
        }
    }

    // --- La barra: topbar che diventa ricerca (e viceversa)
    GlassPanel {
        id: morph
        // Da dove parte: la topbar com'è adesso (fluttuante o attaccata)
        readonly property bool fromAttached: ActiveWindow.maximized
        readonly property rect start: fromAttached
            ? Qt.rect(0, 0, pad.width, Theme.attachedBarHeight)
            : Qt.rect(Theme.edge, Theme.edgeTop, pad.width - 2 * Theme.edge, Theme.topbarHeight)
        readonly property real startRadius: fromAttached ? 0 : Theme.topbarRadius
        readonly property rect end: Qt.rect((pad.width - endWidth) / 2, 72, endWidth, 42)
        readonly property real endWidth: search.activeFocus || search.text !== "" ? 380 : 300

        x: start.x + (end.x - start.x) * pad.p
        y: start.y + (end.y - start.y) * pad.p
        width: start.width + (end.width - start.width) * pad.p
        height: start.height + (end.height - start.height) * pad.p
        radius: startRadius + (21 - startRadius) * pad.p
        color: fromAttached ? mixColor(Theme.barLight, Theme.material, pad.p) : Theme.material
        function mixColor(a, b, k) {
            return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k);
        }

        // Il contenuto della topbar sfuma all'inizio...
        Row {
            anchors.centerIn: parent
            spacing: 14
            opacity: Math.max(0, 1 - pad.p * 2.5)
            Text { text: Clock.time; color: morph.fromAttached ? Theme.ink : Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { text: Clock.shortDate; color: morph.fromAttached ? Theme.ink : Theme.muted; font.family: Theme.font; font.pixelSize: 15 }
        }

        // ...e la ricerca appare alla fine
        Item {
            anchors.fill: parent
            opacity: Math.max(0, (pad.p - 0.55) / 0.45)

            MouseArea { anchors.fill: parent; onClicked: search.forceActiveFocus() }
            ArcIcon {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                width: 17; height: 17
                name: "search"
                color: Theme.muted
            }
            TextInput {
                id: search
                anchors { left: searchIcon.right; right: parent.right; leftMargin: 10; rightMargin: 16; verticalCenter: parent.verticalCenter }
                color: Theme.text
                selectionColor: Theme.surface4
                font.family: Theme.font
                font.pixelSize: 16
                clip: true
                onTextChanged: {
                    Applications.filter = text;
                    Search.query = text;
                    pad.selected = 0;
                    pad.folderId = "";
                }
                Keys.onReturnPressed: pad.searching ? pad.activate(pad.selected) : undefined
                Keys.onEnterPressed: pad.searching ? pad.activate(pad.selected) : undefined
                Keys.onDownPressed: pad.selected = Math.min(pad.resultCount - 1, pad.selected + (pad.selected < pad.appResults ? pad.columns : 1))
                Keys.onUpPressed: pad.selected = Math.max(0, pad.selected - (pad.selected < pad.appResults + 1 ? pad.columns : 1))
                Keys.onTabPressed: pad.selected = Math.min(pad.resultCount - 1, pad.selected + 1)
                Keys.onLeftPressed: event => {
                    if (pad.searching || cursorPosition > 0) { event.accepted = false; return; }
                    pages.currentIndex = Math.max(0, pages.currentIndex - 1);
                }
                Keys.onRightPressed: event => {
                    if (pad.searching || cursorPosition < text.length) { event.accepted = false; return; }
                    pages.currentIndex = Math.min(pad.pageCount - 1, pages.currentIndex + 1);
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text === ""
                    text: "Cerca app, file, impostazioni…"
                    color: Theme.sub
                    font: search.font
                }
            }
        }
    }

    // --- Icona trascinata
    Image {
        id: dragProxy
        visible: pad.dragId !== ""
        width: 88
        height: 88
        sourceSize.width: 176
        sourceSize.height: 176
        z: 100
        scale: 1.1
        opacity: 0.92
    }

    // ============================================================ riquadri
    // App: icona grande ed etichetta; trascinabile
    Component {
        id: appTile
        MouseArea {
            id: tile
            property var entry: ({})
            property string folder: ""
            property bool highlighted: false
            readonly property var app: entry.id ? Applications.byId(entry.id) : ({})
            readonly property string appId: entry.id || ""
            readonly property bool dragging: pad.dragId !== "" && pad.dragId === appId
            readonly property bool hinted: pad.dropHint !== "" && pad.dropHint === appId

            hoverEnabled: true
            drag.target: pad.searching ? null : dragProxy
            drag.threshold: 8
            onPressed: mouse => {
                const pos = icon.mapToItem(pad, 0, 0);
                dragProxy.x = pos.x;
                dragProxy.y = pos.y;
                dragProxy.source = icon.source;
            }
            onPositionChanged: mouse => {
                if (drag.active && pad.dragId === "") {
                    pad.dragId = appId;
                    pad.dragFrom = folder;
                }
                if (pad.dragId !== "") {
                    const pt = mapToItem(pad, mouse.x, mouse.y);
                    pad.dragMoved(pt.x, pt.y);
                }
            }
            onReleased: mouse => {
                if (pad.dragId !== "") {
                    const pt = mapToItem(pad, mouse.x, mouse.y);
                    pad.dropped(pt.x, pt.y);
                }
            }
            onClicked: if (pad.dragId === "") Applications.launch(appId)

            Rectangle {
                anchors.centerIn: icon
                width: icon.width + 22
                height: width
                radius: pad.haloRadius(width)
                color: Theme.surface3
                visible: tile.highlighted
            }
            // Cartella che sta per nascere: alone attorno all'icona
            Rectangle {
                anchors.centerIn: icon
                width: icon.width + 26
                height: width
                radius: pad.haloRadius(width)
                color: Theme.surface4
                visible: tile.hinted
            }
            AppIcon {
                id: icon
                readonly property string source: "image://icon/" + name
                anchors.horizontalCenter: parent.horizontalCenter
                y: pad.iconTop
                width: pad.appIcon
                height: pad.appIcon
                name: tile.app.iconName || "application-x-executable"
                opacity: tile.dragging ? 0.25 : tile.pressed ? 0.8 : 1
                scale: tile.hinted ? 1.08 : tile.containsMouse && !tile.dragging ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
            }
            Text {
                id: label
                anchors { top: icon.bottom; topMargin: 10; left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6 }
                text: tile.app.name || ""
                color: Theme.text
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.35)
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                opacity: tile.dragging ? 0.25 : 1
            }
        }
    }

    // Cartella (2×2 celle) come la Libreria app di iPhone: quadrato di vetro
    // con 3 icone grandi e, nel quarto posto, 4 piccole in 2×2 (7 app
    // avviabili; "+N" se sono di più). Il quadrato va dal bordo delle icone
    // della prima cella a quello delle icone della seconda, in orizzontale e
    // in verticale; il nome sta sulla riga dei nomi. Raggio concentrico.
    Component {
        id: folderTile
        MouseArea {
            id: ftile
            property var entry: ({ apps: [] })
            readonly property string appId: entry.id || ""
            readonly property bool hinted: pad.dropHint !== "" && pad.dropHint === appId
            readonly property bool dragging: pad.dragId !== "" && pad.dragId === appId
            readonly property var apps: entry.apps || []

            // Lato visibile di un'icona grande e spazi, in proporzione
            readonly property real labelHeight: 24
            readonly property real inset: (pad.appIcon - pad.appBody) / 2   // margine trasparente delle icone
            readonly property real side: Math.min(pad.cellW, pad.cellH) + pad.appBody
            readonly property real body: side / 2.465
            readonly property real edge: body * 0.17           // dal bordo del contenitore
            readonly property real gap: body * 0.125           // tra icone grandi
            readonly property real smallGap: body * 0.054      // tra icone piccole
            readonly property real smallBody: (body - smallGap) / 2

            hoverEnabled: true
            drag.target: dragProxy
            drag.threshold: 8
            onPressed: {
                const pos = card.mapToItem(pad, card.width / 2 - 44, card.height / 2 - 44);
                dragProxy.x = pos.x;
                dragProxy.y = pos.y;
                dragProxy.source = "image://icon/folder";
            }
            onPositionChanged: mouse => {
                if (drag.active && pad.dragId === "") {
                    pad.dragId = appId;
                    pad.dragFrom = "";
                }
                if (pad.dragId !== "") {
                    const pt = mapToItem(pad, mouse.x, mouse.y);
                    pad.dragMoved(pt.x, pt.y);
                }
            }
            onReleased: mouse => {
                if (pad.dragId !== "") {
                    const pt = mapToItem(pad, mouse.x, mouse.y);
                    pad.dropped(pt.x, pt.y);
                }
            }
            onClicked: if (pad.dragId === "") pad.folderId = appId

            GlassPanel {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: pad.iconTop + ftile.inset
                width: 2 * ftile.body + ftile.gap + 2 * ftile.edge
                height: 2 * ftile.body + ftile.gap + 2 * ftile.edge
                // Concentrico: angolo dell'icona + distanza dal bordo
                radius: ftile.body * Theme.iconCorner + ftile.edge
                opacity: ftile.dragging ? 0.3 : 1
                scale: ftile.hinted ? 1.04 : ftile.containsMouse ? 1.015 : 1
                border.color: ftile.hinted ? Theme.borderHi : Theme.materialBorder
                Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }

                // 3 posti grandi: in alto a sinistra, in alto a destra, in basso a sinistra
                Repeater {
                    model: ftile.apps.slice(0, 3)
                    FolderIcon {
                        required property int index
                        x: ftile.edge + (index % 2) * (ftile.body + ftile.gap)
                        y: ftile.edge + Math.floor(index / 2) * (ftile.body + ftile.gap)
                        side: ftile.body
                        onLaunched: Applications.launch(modelData)
                    }
                }
                // Quarto posto: 4 piccole (dalla quarta app)
                Repeater {
                    model: ftile.apps.slice(3, 7)
                    FolderIcon {
                        required property int index
                        x: ftile.edge + ftile.body + ftile.gap + (index % 2) * (ftile.smallBody + ftile.smallGap)
                        y: ftile.edge + ftile.body + ftile.gap + Math.floor(index / 2) * (ftile.smallBody + ftile.smallGap)
                        side: ftile.smallBody
                        more: index === 3 && ftile.apps.length > 7
                        extra: ftile.apps.length - 6
                        onLaunched: Applications.launch(modelData)
                        onMoreClicked: pad.folderId = ftile.appId
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // Sulla riga dei nomi della seconda fila
                y: pad.cellH + pad.iconTop + pad.appIcon + 10
                width: card.width
                horizontalAlignment: Text.AlignHCenter
                text: ftile.entry.name || ""
                elide: Text.ElideRight
                color: Theme.text
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.35)
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.Medium
                opacity: ftile.dragging ? 0.3 : 1
            }
        }
    }

    // Un'icona nell'anteprima della cartella: "side" è il lato visibile,
    // l'immagine è più grande (le icone hanno un margine trasparente)
    component FolderIcon: MouseArea {
        id: icon
        required property string modelData
        property real side
        property bool more: false
        property int extra: 0
        signal launched()
        signal moreClicked()
        width: side
        height: side
        hoverEnabled: true
        onClicked: more ? moreClicked() : launched()
        AppIcon {
            anchors.centerIn: parent
            width: icon.side / Theme.iconBody
            height: width
            visible: !icon.more
            name: Applications.byId(icon.modelData).iconName || "application-x-executable"
            scale: icon.pressed ? 0.9 : icon.containsMouse ? 1.06 : 1
            Behavior on scale { NumberAnimation { duration: Theme.fast } }
        }
        Rectangle {
            anchors.fill: parent
            visible: icon.more
            radius: width * Theme.iconCorner
            color: Theme.surface3
            Text {
                anchors.centerIn: parent
                text: "+" + icon.extra
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Math.max(10, icon.side * 0.36)
                font.weight: Font.DemiBold
            }
        }
    }
}
