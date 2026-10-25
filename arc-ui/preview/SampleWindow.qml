// Anteprima della decorazione arc (arc-ui/decoration, plugin C++ di KWin):
// stesse misure e colori di arcdecoration.cpp. Un solo corpo di vetro scuro
// con in alto una riga di pillole: nome dell'app e menu (app di sistema; le
// altre hanno il nome semplice) e i pulsanti tondi scuri a destra.
// Si trascina dalla barra; doppio clic o pulsante centrale = ingrandisci.
// Ingrandita come in KWin con BorderlessMaximizedWindows: niente barra del
// titolo, la finestra va da sotto la topbar (attaccata) al fondo dello
// schermo e la topbar ne mostra nome e pulsanti (stato in WindowState).
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import org.arcbase.core
import org.kde.taskmanager
import "../shell/qml"

Item {
    id: win

    // false = app di terze parti: barra attaccata al contenuto (Firefox finto);
    // non segue lo stato condiviso della finestra attiva
    property bool system: true
    readonly property string title: system ? WindowState.title : "Firefox"
    readonly property bool active: system ? WindowState.active : !WindowState.active
    readonly property bool maximized: system && WindowState.maximized
    visible: WindowState.visible
    property rect normalGeometry: Qt.rect(430, 130, 580, 400)

    // Misure di Metrics in arcdecoration.h; si animano con la stessa curva e
    // durata della topbar (come l'effetto "maximize" di KWin)
    // Metrics: margine 8, pillole alte 40, barra 56; angoli concentrici:
    // finestra 28 = pillola 20 + margine 8, pannelli interni 28 - 8 = 20
    readonly property real fullTitle: 56
    property real titleHeight: maximized ? 0 : fullTitle
    property real radius: maximized ? 0 : Theme.outer(20, 8)
    property bool dragging: false
    readonly property real bodyY: titleHeight
    readonly property color panelColor: Qt.rgba(37 / 255, 34 / 255, 44 / 255, 0.96)

    x: maximized ? 0 : normalGeometry.x
    y: maximized ? Theme.attachedBarHeight : normalGeometry.y
    width: maximized ? parent.width : normalGeometry.width
    height: maximized ? parent.height - Theme.attachedBarHeight : normalGeometry.height
    Behavior on x { enabled: !win.dragging; NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !win.dragging; NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: !win.dragging; NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: !win.dragging; NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    Behavior on titleHeight { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    Behavior on radius { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }

    // Ombra (makeShadow: gaussiana spostata in basso)
    RectangularShadow {
        anchors.fill: frame
        offset.y: 10
        radius: win.radius
        blur: 40
        spread: 0
        color: Qt.rgba(0, 0, 0, win.active ? 0.42 : 0.24)
        opacity: win.radius / 28
    }

    Item {
        id: frame
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // Barra del titolo: sfondo sfocato (come il blur di KWin) + vetro chiaro
        ShaderEffectSource {
            id: behind
            x: 0; y: 0
            width: win.width; height: win.height
            sourceItem: Shell.wallpaperHost
            sourceRect: Qt.rect(win.x, win.y, win.width, win.height)
            visible: false
        }
        MultiEffect {
            anchors.fill: behind
            source: behind
            blurEnabled: true
            blurMax: 64
            blur: 1.0
            autoPaddingEnabled: false
        }
        // Vetro scuro su tutta la finestra delle app di sistema; le altre app
        // hanno il loro sfondo fino in cima, con nome e pulsanti sopra
        Rectangle {
            visible: win.system
            width: parent.width
            height: parent.height
            color: Qt.rgba(14 / 255, 12 / 255, 20 / 255, win.active ? 0.62 : 0.75)
        }

        // App di terze parti: il suo contenuto (pagina web finta)
        Rectangle {
            visible: !win.system
            width: parent.width
            height: parent.height
            color: "#f9f9fb"
            Rectangle {
                width: parent.width; height: win.titleHeight + 40; color: "#ececf0"
                Rectangle { x: 12; y: win.titleHeight + 7; width: parent.width - 24; height: 26; radius: 13; color: "white"; border.color: "#d8d8de"
                    Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "arcbase.org"; color: "#55525c"; font.family: Theme.font; font.pixelSize: 12 } }
            }
            Column {
                x: 28; y: win.titleHeight + 64; spacing: 12
                Text { text: "Arcbase Desktop"; color: "#1c1a22"; font.family: Theme.font; font.pixelSize: 26; font.weight: Font.Bold }
                Repeater { model: 5; Rectangle { width: 260 + (index % 2) * 80; height: 10; radius: 5; color: "#e1e0e6" } }
            }
        }

        // Contenuto: un Dolphin finto con le icone di sistema Ticly Sequoia
        Item {
            id: app
            visible: win.system
            y: win.bodyY
            width: parent.width
            height: parent.height - win.bodyY
            readonly property string base: Qt.resolvedUrl(".build/ticly/ticly-sequoia/")
            function png(ctx, n) { return base + "96x96/" + ctx + "/" + n + ".png"; }
            function svg(ctx, n) { return base + "scalable/" + ctx + "/" + n + ".svg"; }

            // Barra laterale e contenuto: due pannelli scuri incassati nel vetro
            Rectangle {
                id: side
                x: 8
                width: 170
                height: parent.height - 8
                // Gruppo: angoli verso il bordo concentrici, verso il vicino piccoli
                radius: Theme.groupInner
                topLeftRadius: Theme.inner(28, 8)
                bottomLeftRadius: Theme.inner(28, 8)
                color: win.panelColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                Column {
                    x: 10; y: 12; spacing: 2
                    Text { text: "Risorse"; color: Qt.rgba(1, 1, 1, 0.55); font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; leftPadding: 6; bottomPadding: 4 }
                    Repeater {
                        model: [["user-home", "Home"], ["user-desktop", "Scrivania"], ["folder-documents", "Documenti"], ["folder-download", "Scaricati"],
                                ["folder-pictures", "Immagini"], ["folder-music", "Musica"], ["folder-videos", "Video"], ["user-trash", "Cestino"]]
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: 150; height: 30; radius: Theme.inner(20, 10)
                            color: index === 0 ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                            Row {
                                x: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                Image { width: 18; height: 18; sourceSize: Qt.size(36, 36); source: app.png("places", parent.parent.modelData[0]) }
                                Text { text: parent.parent.modelData[1]; color: Qt.rgba(1, 1, 1, 0.92); font.family: Theme.font; font.pixelSize: 13 }
                            }
                        }
                    }
                }
            }
            // Contenuto incassato (vista dei file): pannello arrotondato
            Rectangle {
                id: content
                anchors { left: side.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 8; topMargin: 0 }
                radius: Theme.groupInner
                topRightRadius: Theme.inner(28, 8)
                bottomRightRadius: Theme.inner(28, 8)
                color: win.panelColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
            }
            Flow {
                anchors { left: content.left; right: content.right; top: content.top; margins: 16 }
                spacing: 10
                Repeater {
                    model: [["png", "places", "folder-documents", "Documenti"], ["png", "places", "folder-download", "Scaricati"],
                            ["png", "places", "folder-pictures", "Immagini"], ["png", "places", "folder-music", "Musica"],
                            ["png", "places", "folder-videos", "Video"], ["png", "places", "folder", "Progetti"],
                            ["svg", "mimetypes", "application-pdf", "fattura.pdf"], ["svg", "mimetypes", "image-jpeg", "dolomiti.jpg"],
                            ["svg", "mimetypes", "x-office-document", "lettera.odt"], ["svg", "mimetypes", "application-zip", "backup.zip"]]
                    Column {
                        id: file
                        required property var modelData
                        width: 84; spacing: 4
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 56; height: 56; sourceSize: Qt.size(112, 112)
                            source: file.modelData[0] === "png" ? app.png(file.modelData[1], file.modelData[2]) : app.svg(file.modelData[1], file.modelData[2])
                        }
                        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: file.modelData[3]; color: Qt.rgba(1, 1, 1, 0.9); font.family: Theme.font; font.pixelSize: 12 }
                    }
                }
            }
        }
    }
    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: win.radius; color: "black" }
    }
    // Bordo di vetro (BorderOutline 1 px)
    Rectangle {
        anchors.fill: parent
        radius: win.radius
        color: "transparent"
        visible: !win.maximized
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.13)
    }

    // Trascina e doppio clic sulla barra
    MouseArea {
        visible: !win.maximized
        width: parent.width
        height: win.titleHeight
        property point start
        onReleased: win.dragging = false
        onPressed: mouse => {
            win.dragging = true;
            WindowState.active = win.system;
            start = Qt.point(mouse.x, mouse.y);
        }
        onPositionChanged: mouse => {
            if (!pressed || win.maximized) return;
            win.normalGeometry = Qt.rect(win.normalGeometry.x + mouse.x - start.x, win.normalGeometry.y + mouse.y - start.y,
                                         win.normalGeometry.width, win.normalGeometry.height);
        }
        onDoubleClicked: WindowState.maximized = !WindowState.maximized
    }

    // Ridimensiona dai bordi e dagli angoli (come resizeBorder in
    // arcdecoration.h: KWin fa lo stesso sulla finestra vera)
    Repeater {
        model: [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]]
        MouseArea {
            id: grip
            required property var modelData
            readonly property int dx: modelData[0]
            readonly property int dy: modelData[1]
            readonly property int band: 8
            visible: !win.maximized
            x: dx < 0 ? -band / 2 : dx > 0 ? win.width - band / 2 : band
            y: dy < 0 ? -band / 2 : dy > 0 ? win.height - band / 2 : band
            width: dx === 0 ? win.width - 2 * band : band * 2
            height: dy === 0 ? win.height - 2 * band : band * 2
            z: 10
            cursorShape: dx === 0 ? Qt.SizeVerCursor : dy === 0 ? Qt.SizeHorCursor
                         : dx === dy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
            property point start
            property rect from
            onPressed: mouse => {
                win.dragging = true;
                WindowState.active = win.system;
                start = mapToItem(win.parent, mouse.x, mouse.y);
                from = win.normalGeometry;
            }
            onReleased: win.dragging = false
            onPositionChanged: mouse => {
                if (!pressed) return;
                const p = mapToItem(win.parent, mouse.x, mouse.y);
                const minW = 360, minH = 240;
                let x = from.x, y = from.y, w = from.width, h = from.height;
                if (dx > 0) w = Math.max(minW, from.width + p.x - start.x);
                if (dx < 0) { w = Math.max(minW, from.width - (p.x - start.x)); x = from.x + from.width - w; }
                if (dy > 0) h = Math.max(minH, from.height + p.y - start.y);
                if (dy < 0) { h = Math.max(minH, from.height - (p.y - start.y)); y = from.y + from.height - h; }
                win.normalGeometry = Qt.rect(x, y, w, h);
            }
        }
    }

    // Riga di pillole: nome, menu (app di sistema), pulsanti
    Item {
        id: bar
        opacity: win.titleHeight / win.fullTitle
        visible: opacity > 0
        x: 8; y: 8
        width: parent.width - 16
        height: 40
        // Sul vetro scuro pillole chiare; sullo sfondo chiaro dell'app scure
        readonly property color pill: win.system ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.07)
        readonly property color text: win.system ? Qt.rgba(1, 1, 1, win.active ? 0.94 : 0.5)
                                                 : Qt.rgba(28 / 255, 26 / 255, 34 / 255, win.active ? 0.9 : 0.5)

        Rectangle {
            id: namePill
            visible: win.system
            width: Math.min(nameText.implicitWidth + 32, buttonsPill.x - 8)
            height: 40; radius: 20
            color: Qt.rgba(1, 1, 1, 0.14)
        }
        Text {
            id: nameText
            x: 16
            width: win.system ? namePill.width - 32 : buttonsPill.x - 24
            height: 40
            verticalAlignment: Text.AlignVCenter
            text: win.title
            elide: Text.ElideRight
            color: bar.text
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        // Menu dell'app (come la pillola ApplicationMenu della decorazione)
        Rectangle {
            id: menuPill
            visible: win.system && x + width + 8 <= buttonsPill.x
            x: namePill.width + 8
            width: menuRow.implicitWidth + 16
            height: 40; radius: 20
            color: bar.pill
            Row {
                id: menuRow
                x: 8
                height: parent.height
                Repeater {
                    model: ["File", "Trova", "Preferenze", "Impostazioni"]
                    MouseArea {
                        id: entry
                        required property string modelData
                        width: entryText.implicitWidth + 18
                        height: 30
                        anchors.verticalCenter: parent.verticalCenter
                        hoverEnabled: true
                        Rectangle { anchors.fill: parent; radius: 15; color: entry.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent" }
                        Text { id: entryText; anchors.centerIn: parent; text: entry.modelData; color: bar.text; font.family: Theme.font; font.pixelSize: 13 }
                    }
                }
            }
        }

        Rectangle {
            id: buttonsPill
            x: parent.width - width
            width: buttons.width + 14
            height: 40; radius: 20
            color: bar.pill
            Row {
                id: buttons
                anchors.centerIn: parent
                spacing: 8
                TitleButton { glyph: "M9.4 11.4 L13 15 L16.6 11.4"; onClicked: WindowState.visible = false }
                TitleButton {
                    glyph: win.maximized ? "M12.4 8.8 V12.4 H8.8 M13.6 17.2 V13.6 H17.2" : "M13.2 9 H17 V12.8 M12.8 17 H9 V13.2"
                    onClicked: WindowState.maximized = !WindowState.maximized
                }
                TitleButton { glyph: "M9.7 9.7 L16.3 16.3 M16.3 9.7 L9.7 16.3"; danger: true; onClicked: WindowState.visible = false }
            }
        }
    }

    component TitleButton: MouseArea {
        id: button
        property string glyph
        property bool danger: false
        width: 26
        height: 26
        hoverEnabled: true
        Rectangle {
            anchors.fill: parent
            radius: 13
            color: button.pressed ? (button.danger ? Qt.rgba(190 / 255, 45 / 255, 50 / 255, 0.98) : Qt.rgba(84 / 255, 79 / 255, 96 / 255, 0.98))
                 : button.containsMouse ? (button.danger ? Qt.rgba(229 / 255, 72 / 255, 77 / 255, 0.96) : Qt.rgba(64 / 255, 60 / 255, 74 / 255, 0.96))
                 : win.panelColor
            opacity: win.active || button.containsMouse ? 1 : 0.6
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.96)
                strokeWidth: 1.6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: button.glyph }
            }
        }
    }
}
