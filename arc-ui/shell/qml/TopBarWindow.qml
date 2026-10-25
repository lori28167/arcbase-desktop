// Topbar fluttuante: logo arc (Launchpad), ora e data (centro notifiche),
// stato di sistema a destra (centro di controllo).
// Con un'app ingrandita la topbar si attacca ai bordi e fa da barra della
// finestra (la finestra non ha decorazione: BorderlessMaximizedWindows in
// kwinrc): vetro chiaro, nome dell'app accanto al logo, pulsanti riduci,
// ripristina e chiudi prima delle icone di stato.
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import org.arcbase.core
import "."

Window {
    id: win

    readonly property bool attached: ActiveWindow.maximized
    property bool ready: false

    // Col Launchpad aperto la barra la disegna il Launchpad (che la trasforma
    // nella ricerca): qui si nasconde, e torna quando la ricerca è ridiventata
    // topbar
    property bool launchpad: false
    Connections {
        target: Shell
        function onOverlayChanged() {
            if (Shell.overlay === "launcher") {
                restoreTimer.stop();
                win.launchpad = true;
            } else if (win.launchpad) {
                restoreTimer.restart();
            }
        }
    }
    Timer {
        id: restoreTimer
        interval: Theme.slow
        onTriggered: win.launchpad = false
    }
    onLaunchpadChanged: Qt.callLater(updateRegions)

    // 0 = fluttuante, 1 = attaccata. Tutto il resto (bordi, angoli, altezza,
    // colori) si interpola da qui, così la barra si trasforma con un'unica
    // animazione insieme alla finestra che si ingrandisce
    property real t: attached ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    property color ink: attached ? Theme.ink : Theme.text
    property color inkMuted: attached ? Theme.inkMuted : Theme.muted
    Behavior on ink { ColorAnimation { duration: Theme.slow } }
    Behavior on inkMuted { ColorAnimation { duration: Theme.slow } }

    function mix(a, b, k) {
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k);
    }

    // La superficie copre sempre tutta la striscia in alto (niente margini):
    // la barra si muove al suo interno, il mouse arriva solo sulla barra
    color: "transparent"
    width: 1280
    height: Theme.edgeTop + Theme.topbarHeight
    visible: false

    Component.onCompleted: {
        Shell.configureLayer(win, "arc-topbar", Shell.LayerTop,
                             Shell.AnchorTop | Shell.AnchorLeft | Shell.AnchorRight,
                             Theme.edgeTop + Theme.topbarHeight + Theme.gap / 2, Shell.KeyboardNone);
        ready = true;
        updateLayer();
        visible = true;
    }

    // Spazio riservato: attaccata, la finestra ingrandita comincia sotto la barra
    function updateLayer() {
        if (!ready) return;
        Shell.updateLayer(win, attached ? Theme.attachedBarHeight : Theme.edgeTop + Theme.topbarHeight + Theme.gap / 2);
    }
    onAttachedChanged: updateLayer()

    function updateRegions() {
        if (launchpad) {
            Shell.setBlur(win, []);
            Shell.setInputRegion(win, [{ x: 0, y: 0, width: 1, height: 1, radius: 0 }]);
            return;
        }
        const rect = { x: bar.x, y: bar.y, width: bar.width, height: bar.height, radius: bar.radius };
        Shell.setBlur(win, [rect]);
        Shell.setInputRegion(win, [rect]);
    }
    onWidthChanged: Qt.callLater(updateRegions)
    onVisibleChanged: if (visible) Qt.callLater(updateRegions)

    GlassPanel {
        id: bar
        opacity: win.launchpad ? 0 : 1
        x: Theme.edge * (1 - win.t)
        y: Theme.edgeTop * (1 - win.t)
        width: win.width - 2 * x
        height: Theme.topbarHeight + (Theme.attachedBarHeight - Theme.topbarHeight) * win.t
        radius: Theme.topbarRadius * (1 - win.t)
        color: win.mix(Theme.material, Theme.barLight, win.t)
        border.color: Qt.rgba(1, 1, 1, 0.14 * (1 - win.t))
        onXChanged: Qt.callLater(win.updateRegions)
        onHeightChanged: Qt.callLater(win.updateRegions)

        // Attaccata: solo una riga chiara in basso
        Rectangle {
            opacity: win.t
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.barLightBorder
        }

        // --- Logo (Launchpad) e, attaccata, nome dell'app
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12 + 2 * win.t
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            BarButton {
                width: logo.width + 22
                active: Shell.overlay === "launcher"
                onClicked: Shell.toggleLauncher()

                Image {
                    id: logo
                    anchors.centerIn: parent
                    height: 18 - 2 * win.t
                    width: height * 1232 / 424
                    source: win.attached ? "assets/arc-wordmark-dark.svg" : "assets/arc-wordmark-light.svg"
                    sourceSize.height: 18 * 3
                    smooth: true
                }
            }
            Text {
                visible: win.t > 0 && ActiveWindow.name !== ""
                opacity: win.t
                anchors.verticalCenter: parent.verticalCenter
                text: ActiveWindow.name
                color: win.ink
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.Medium
                elide: Text.ElideRight
                width: Math.min(implicitWidth, win.width / 2 - 260)
            }
        }

        // --- Ora e data: apre il centro notifiche
        BarButton {
            anchors.centerIn: parent
            width: clockRow.width + 28
            active: Shell.overlay === "notifications"
            onClicked: Shell.overlay === "notifications" ? Shell.hideOverlay() : Shell.showNotifications()

            Row {
                id: clockRow
                anchors.centerIn: parent
                spacing: 14

                ArcIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Notifications.doNotDisturb
                    width: 16; height: 16
                    name: "moon-small"
                    color: win.inkMuted
                }
                Text {
                    text: Clock.time
                    color: win.ink
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.weight: win.attached ? Font.Normal : Font.DemiBold
                    font.features: ({ "tnum": 1 })
                }
                Text {
                    text: Clock.shortDate
                    color: win.attached ? win.ink : win.inkMuted
                    font.family: Theme.font
                    font.pixelSize: 15
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Notifications.history.count > 0 && !Notifications.doNotDisturb
                    width: 7; height: 7; radius: 3.5
                    color: win.ink
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            // --- Attaccata: pulsanti della finestra ingrandita (lo spazio si apre
            // insieme alla trasformazione della barra)
            Item {
                visible: win.t > 0
                anchors.verticalCenter: parent.verticalCenter
                width: windowButtons.implicitWidth * win.t
                height: 20
                clip: true
                opacity: win.t
                Row {
                    id: windowButtons
                    anchors.right: parent.right
                    spacing: 8
                    WindowButton { glyph: "M6.4 8.4 L10 12 L13.6 8.4"; onClicked: ActiveWindow.minimize() }
                    WindowButton { glyph: "M10.2 6 H14 V9.8 M9.8 14 H6 V10.2"; onClicked: ActiveWindow.toggleMaximize() }
                    WindowButton { glyph: "M6.7 6.7 L13.3 13.3 M13.3 6.7 L6.7 13.3"; danger: true; onClicked: ActiveWindow.close() }
                }
            }

            // --- Stato di sistema: apre il centro di controllo
            BarButton {
                anchors.verticalCenter: parent.verticalCenter
                width: status.width + 24
                active: Shell.overlay === "control"
                onClicked: Shell.overlay === "control" ? Shell.hideOverlay() : Shell.showControlCenter()

                Row {
                    id: status
                    anchors.centerIn: parent
                    spacing: 14

                    ArcIcon {
                        visible: Media.playing
                        width: 18; height: 18
                        name: "music"
                        color: win.ink
                    }
                    ArcIcon {
                        width: 19; height: 19
                        name: Shell.muted ? "volume-off" : "volume"
                        color: win.ink
                    }
                    ArcIcon {
                        visible: Shell.bluetoothEnabled
                        width: 18; height: 18
                        name: "bluetooth"
                        color: win.ink
                    }
                    ArcIcon {
                        width: 19; height: 19
                        name: Shell.networkType === "ethernet" ? "ethernet"
                            : Shell.networkType === "wifi" ? "wifi" : "wifi-off"
                        color: win.ink
                    }
                    Row {
                        visible: Shell.batteryPresent
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Shell.batteryLevel + "%"
                            color: win.inkMuted
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.features: ({ "tnum": 1 })
                        }
                        BatteryIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            level: Shell.batteryLevel
                            charging: Shell.charging
                            color: win.ink
                        }
                    }
                    ArcIcon {
                        width: 18; height: 18
                        name: "hexagon"
                        color: win.ink
                    }
                }
            }
        }
    }

    component BarButton: MouseArea {
        id: button
        property bool active: false
        default property alias content: holder.data
        height: 36
        hoverEnabled: true

        Rectangle {
            anchors.fill: parent
            radius: Theme.inner(Theme.topbarRadius, (Theme.topbarHeight - 36) / 2)
            color: win.attached ? Theme.inkHover : (button.active ? Theme.surface3 : Theme.surface2)
            opacity: button.containsMouse || button.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        }
        Item {
            id: holder
            anchors.fill: parent
            scale: button.pressed ? 0.95 : 1
            Behavior on scale { NumberAnimation { duration: Theme.fast } }
        }
    }

    // Pulsante tondo scuro come nella decorazione arc (arcdecoration.cpp)
    component WindowButton: MouseArea {
        id: wb
        property string glyph
        property bool danger: false
        width: 20
        height: 20
        hoverEnabled: true
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: wb.pressed ? (wb.danger ? Qt.rgba(190 / 255, 45 / 255, 50 / 255, 0.98) : Qt.rgba(20 / 255, 20 / 255, 22 / 255, 0.98))
                 : wb.containsMouse ? (wb.danger ? Qt.rgba(229 / 255, 72 / 255, 77 / 255, 0.96) : Qt.rgba(34 / 255, 34 / 255, 38 / 255, 0.94))
                 : Qt.rgba(58 / 255, 58 / 255, 62 / 255, 0.88)
        }
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: Qt.rgba(1, 1, 1, 0.96)
                    strokeWidth: 1.6
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: wb.glyph }
                }
            }
        }
    }
}
