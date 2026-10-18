// Anteprima della decorazione arc (arc-ui/decoration, plugin C++ di KWin):
// stesse misure e colori di arcdecoration.cpp. Barra del titolo di vetro
// sfocato, nome a sinistra, pulsanti tondi scuri a destra, angoli arrotondati.
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

    readonly property string title: WindowState.title
    readonly property bool active: WindowState.active
    readonly property bool maximized: WindowState.maximized
    visible: WindowState.visible
    property rect normalGeometry: Qt.rect(430, 130, 580, 400)

    // Misure di Metrics in arcdecoration.h; si animano con la stessa curva e
    // durata della topbar (come l'effetto "maximize" di KWin)
    property real titleHeight: maximized ? 0 : 38
    property real radius: maximized ? 0 : 18
    property bool dragging: false

    x: maximized ? 0 : normalGeometry.x
    y: maximized ? Theme.attachedBarHeight : normalGeometry.y
    width: maximized ? parent.width : normalGeometry.width
    height: maximized ? parent.height - Theme.attachedBarHeight : normalGeometry.height
    Behavior on x { enabled: !win.dragging; NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !win.dragging; NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
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
        opacity: win.radius / 18
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
            width: win.width; height: win.titleHeight
            sourceItem: Shell.wallpaperHost
            sourceRect: Qt.rect(win.x, win.y, win.width, win.titleHeight)
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
        Rectangle {
            width: parent.width
            height: win.titleHeight
            color: Qt.rgba(1, 1, 1, win.active ? 0.32 : 0.18)
        }

        // Contenuto dell'app (segnaposto come nel design)
        Rectangle {
            y: win.titleHeight
            width: parent.width
            height: parent.height - win.titleHeight
            color: "#5a5a5a"
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
        border.width: win.maximized ? 0 : 1
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
            WindowState.active = true;
            start = Qt.point(mouse.x, mouse.y);
        }
        onPositionChanged: mouse => {
            if (!pressed || win.maximized) return;
            win.normalGeometry = Qt.rect(win.normalGeometry.x + mouse.x - start.x, win.normalGeometry.y + mouse.y - start.y,
                                         win.normalGeometry.width, win.normalGeometry.height);
        }
        onDoubleClicked: WindowState.maximized = !WindowState.maximized
    }

    Text {
        opacity: win.titleHeight / 38
        visible: opacity > 0
        x: 17
        width: buttons.x - 29
        height: win.titleHeight
        verticalAlignment: Text.AlignVCenter
        text: win.title
        elide: Text.ElideRight
        color: Qt.rgba(17 / 255, 17 / 255, 20 / 255, win.active ? 0.92 : 0.47)
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.Medium
    }

    Row {
        opacity: win.titleHeight / 38
        visible: opacity > 0
        id: buttons
        x: parent.width - width - 11
        y: (win.titleHeight - 20) / 2
        spacing: 8
        TitleButton { glyph: "M6.4 8.4 L10 12 L13.6 8.4"; onClicked: WindowState.visible = false }
        TitleButton {
            glyph: win.maximized ? "M9.4 5.8 V9.4 H5.8 M10.6 14.2 V10.6 H14.2" : "M10.2 6 H14 V9.8 M9.8 14 H6 V10.2"
            onClicked: WindowState.maximized = !WindowState.maximized
        }
        TitleButton { glyph: "M6.7 6.7 L13.3 13.3 M13.3 6.7 L6.7 13.3"; danger: true; onClicked: WindowState.visible = false }
    }

    component TitleButton: MouseArea {
        id: button
        property string glyph
        property bool danger: false
        width: 20
        height: 20
        hoverEnabled: true
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: button.pressed ? (button.danger ? Qt.rgba(190 / 255, 45 / 255, 50 / 255, 0.98) : Qt.rgba(20 / 255, 20 / 255, 22 / 255, 0.98))
                 : button.containsMouse ? (button.danger ? Qt.rgba(229 / 255, 72 / 255, 77 / 255, 0.96) : Qt.rgba(34 / 255, 34 / 255, 38 / 255, 0.94))
                 : Qt.rgba(58 / 255, 58 / 255, 62 / 255, win.active ? 0.88 : 0.4)
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
