// Centro di controllo (stato di sistema nella topbar), due pannelli:
// 1) tessere a pillola (cerchio bianco = attivo; clic sul cerchio accende o
//    spegne, sul resto apre i dettagli), volume e luminosità, musica;
// 2) utente (foto, nome), Impostazioni, blocco e spegnimento.
// "Modifica" sceglie e ordina le tessere (Shell.controlTiles). La pagina Wi‑Fi
// elenca le reti.
import QtQuick
import org.arcbase.core
import "."

Item {
    id: root

    // I due pannelli sono un gruppo: angoli esterni grandi, quelli che si
    // guardano piccoli
    readonly property int panelRadius: Theme.outer(35, 14)

    property string page: "main"   // "main" | "wifi"
    property bool editing: false
    // Rettangoli da sfocare (OverlayWindow): i due pannelli
    readonly property var blurRects: [
        { x: panel.x, y: panel.y, width: panel.width, height: panel.height, radius: panel.radius, corners: panel.corners },
        { x: profile.x, y: profile.y, width: profile.width, height: profile.height, radius: profile.radius, corners: profile.corners }
    ]

    width: 372
    height: column.height

    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

    // Tutte le tessere possibili
    readonly property var catalog: ({
        "wifi": { icon: Shell.wifiEnabled ? (Shell.networkType === "ethernet" ? "ethernet" : "wifi") : "wifi-off", title: "Wi‑Fi",
                  subtitle: !Shell.wifiEnabled ? "Disattivato" : Shell.networkName !== "" ? Shell.networkName : "Non connesso",
                  checked: Shell.wifiEnabled, toggle: () => Shell.wifiEnabled = !Shell.wifiEnabled,
                  open: () => { Shell.scanWifi(); root.page = "wifi"; } },
        "bluetooth": { icon: "bluetooth", title: "Bluetooth",
                       subtitle: !Shell.bluetoothAvailable ? "Non disponibile" : Shell.bluetoothEnabled ? "Attivo" : "Disattivato",
                       checked: Shell.bluetoothEnabled, toggle: () => Shell.bluetoothEnabled = !Shell.bluetoothEnabled,
                       open: () => Shell.openSettings("kcm_bluetooth") },
        "dnd": { icon: Notifications.doNotDisturb ? "bell-off" : "moon-small", title: "Silenzioso",
                 subtitle: Notifications.doNotDisturb ? "Attivo" : "Disattivato", checked: Notifications.doNotDisturb,
                 toggle: () => Notifications.doNotDisturb = !Notifications.doNotDisturb, open: () => Shell.openSettings("kcm_notifications") },
        "nightlight": { icon: "sun", title: "Notte", subtitle: Shell.nightLight ? "Toni caldi" : "Disattivata",
                        checked: Shell.nightLight, toggle: () => Shell.nightLight = !Shell.nightLight,
                        open: () => Shell.openSettings("kcm_nightlight") },
        "airplane": { icon: "airplane", title: "Aereo",
                      subtitle: root.airplane ? "Attiva" : "Disattivata", checked: root.airplane,
                      toggle: () => { const on = !root.airplane; Shell.wifiEnabled = !on; if (Shell.bluetoothAvailable) Shell.bluetoothEnabled = !on; },
                      open: () => Shell.openSettings("kcm_networkmanagement") },
        "screenshot": { icon: "camera", title: "Cattura", subtitle: "Schermo o finestra", checked: false,
                        toggle: () => Shell.screenshot(), open: () => Shell.screenshot() }
    })
    readonly property var allTiles: ["wifi", "bluetooth", "dnd", "nightlight", "airplane", "screenshot"]
    readonly property bool airplane: !Shell.wifiEnabled && (!Shell.bluetoothAvailable || !Shell.bluetoothEnabled)
    function toggleTile(id) {
        const list = Shell.controlTiles.slice();
        const i = list.indexOf(id);
        if (i >= 0) list.splice(i, 1); else list.push(id);
        Shell.controlTiles = list;
    }

    Column {
        id: column
        width: parent.width
        spacing: 8          // pannelli in gruppo: vicini come i widget

        // ======================================================== pannello 1
        GlassPanel {
            id: panel
            width: parent.width
            height: (root.page === "wifi" ? wifiPage.height : mainPage.height) + 28
            radius: root.panelRadius
            readonly property var corners: Theme.groupCorners(root.panelRadius, true, true, false, true)
            topLeftRadius: corners[0]; topRightRadius: corners[1]; bottomRightRadius: corners[2]; bottomLeftRadius: corners[3]
            clip: true
            Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            // Il clic nel pannello non lo chiude
            MouseArea { anchors.fill: parent }

            Column {
                id: mainPage
                x: root.page === "main" ? 14 : -panel.width
                y: 14
                width: panel.width - 28
                spacing: 10
                Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

                Flow {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: root.editing ? root.allTiles : Shell.controlTiles
                        PillTile {
                            required property string modelData
                            readonly property var info: root.catalog[modelData] || ({})
                            tileId: modelData
                            width: (mainPage.width - 10) / 2
                            icon: info.icon || ""
                            title: info.title || ""
                            subtitle: info.subtitle || ""
                            checked: info.checked === true
                            editing: root.editing
                            shown: Shell.controlTiles.indexOf(modelData) >= 0
                            onToggled: if (info.toggle) info.toggle()
                            onOpened: if (info.open) info.open()
                            onEditToggled: root.toggleTile(modelData)
                        }
                    }
                }

                SliderPill {
                    width: parent.width
                    icon: Shell.muted ? "volume-off" : "volume"
                    value: Shell.muted ? 0 : Shell.volume
                    onIconClicked: Shell.toggleMute()
                    onMoved: v => Shell.setVolume(v)
                }
                SliderPill {
                    visible: Shell.brightness >= 0
                    width: parent.width
                    icon: "sun"
                    value: Shell.brightness
                    onMoved: v => Shell.setBrightness(v)
                }

                // Musica (solo se qualcosa suona)
                Rectangle {
                    visible: Media.available
                    width: parent.width
                    height: 70
                    radius: 35
                    color: Theme.surface2
                    border.width: 1
                    border.color: Theme.border
                    Rectangle {
                        id: art
                        x: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 56; height: 56; radius: 28
                        color: Theme.surface3
                        clip: true
                        Image { anchors.fill: parent; source: Media.artUrl; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                        ArcIcon { anchors.centerIn: parent; width: 22; height: 22; name: "music"; color: Theme.muted; visible: Media.artUrl === "" }
                    }
                    Column {
                        anchors { left: art.right; leftMargin: 12; right: controls.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        Text { width: parent.width; text: Media.title || Media.player; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { width: parent.width; text: Media.artist || Media.player; elide: Text.ElideRight; color: Theme.muted; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Row {
                        id: controls
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        RoundButton { icon: "previous"; filled: true; size: 32; enabled: Media.canGoPrevious; onClicked: Media.previous() }
                        RoundButton { icon: Media.playing ? "pause" : "play"; filled: !Media.playing; size: 38; onClicked: Media.playPause() }
                        RoundButton { icon: "next"; filled: true; size: 32; enabled: Media.canGoNext; onClicked: Media.next() }
                    }
                }
            }

            // ============================================================ pagina Wi‑Fi
            Column {
                id: wifiPage
                x: root.page === "wifi" ? 14 : panel.width
                y: 16
                width: panel.width - 28
                spacing: 10
                Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

                Item {
                    width: parent.width
                    height: 36
                    RoundButton { anchors.verticalCenter: parent.verticalCenter; icon: "chevron-left"; size: 34; onClicked: root.page = "main" }
                    Text {
                        x: 46
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wi‑Fi"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Switch {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Shell.wifiEnabled
                        onToggled: Shell.wifiEnabled = !Shell.wifiEnabled
                    }
                }

                Caption { text: Shell.wifiEnabled ? "Reti disponibili" : "Wi‑Fi disattivato"; topPadding: 4 }

                Column {
                    width: parent.width
                    spacing: 2
                    visible: Shell.wifiEnabled
                    Repeater {
                        model: Shell.wifiNetworks.slice(0, 8)
                        MouseArea {
                            id: net
                            required property var modelData
                            width: parent.width
                            height: 40
                            hoverEnabled: true
                            onClicked: {
                                if (!modelData.active) Shell.connectWifi(modelData.ssid);
                                root.page = "main";
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: net.containsMouse ? Theme.surface2 : "transparent"
                            }
                            SignalBars { x: 10; anchors.verticalCenter: parent.verticalCenter; strength: net.modelData.signal }
                            Text {
                                x: 40
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 90
                                text: net.modelData.ssid
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 14
                                font.weight: net.modelData.active ? Font.DemiBold : Font.Normal
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                ArcIcon { visible: net.modelData.secure; width: 14; height: 14; name: "lock"; color: Theme.sub }
                                ArcIcon { visible: net.modelData.active; width: 16; height: 16; name: "check"; color: Theme.text; strokeWidth: 2.2 }
                            }
                        }
                    }
                    Text {
                        visible: Shell.wifiNetworks.length === 0
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        topPadding: 10
                        bottomPadding: 10
                        text: "Ricerca in corso…"
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.border }
                MouseArea {
                    id: netSettings
                    width: parent.width
                    height: 34
                    hoverEnabled: true
                    onClicked: Shell.openSettings("kcm_networkmanagement")
                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Impostazioni di rete…"
                        color: netSettings.containsMouse ? Theme.text : Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                }
            }

        }

        // ======================================================== pannello 2
        GlassPanel {
            id: profile
            width: parent.width
            height: profileColumn.height + 28
            radius: root.panelRadius
            readonly property var corners: Theme.groupCorners(root.panelRadius, false, true, true, true)
            topLeftRadius: corners[0]; topRightRadius: corners[1]; bottomRightRadius: corners[2]; bottomLeftRadius: corners[3]
            MouseArea { anchors.fill: parent }

            Column {
                id: profileColumn
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 12

                Row {
                    spacing: 16
                    Rectangle {
                        width: 92; height: 92; radius: 46
                        color: Theme.surface4
                        clip: true
                        Text {
                            anchors.centerIn: parent
                            visible: Shell.avatar === ""
                            text: Shell.fullName.charAt(0).toUpperCase()
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 38
                            font.weight: Font.DemiBold
                        }
                        Image { anchors.fill: parent; source: Shell.avatar; fillMode: Image.PreserveAspectCrop; visible: Shell.avatar !== "" }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text { text: Shell.fullName; color: Theme.text; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Medium }
                        Text { text: Shell.userName + "@" + Shell.hostName; color: Theme.muted; font.family: Theme.font; font.pixelSize: 13 }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 10
                    // Impostazioni (pillola larga)
                    MouseArea {
                        id: settingsPill
                        width: parent.width - 2 * 80 - 20
                        height: 70
                        hoverEnabled: true
                        onClicked: Shell.openSettings()
                        Rectangle {
                            anchors.fill: parent
                            radius: 35
                            color: settingsPill.containsMouse ? Theme.surface3 : Theme.surface2
                            border.width: 1
                            border.color: Theme.border
                        }
                        Rectangle {
                            x: 7
                            anchors.verticalCenter: parent.verticalCenter
                            width: 56; height: 56; radius: 28
                            color: Theme.accent
                            ArcIcon { anchors.centerIn: parent; width: 22; height: 22; name: "settings"; color: Theme.accentText }
                        }
                        Text {
                            x: 76
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Impostazioni"
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                    }
                    RoundPill { icon: "lock"; onClicked: Shell.lock() }
                    RoundPill { icon: "power"; active: powerRow.visible; onClicked: powerRow.visible = !powerRow.visible }
                }
                Row {
                    id: powerRow
                    visible: false
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    PowerChoice { icon: "moon"; label: "Sospendi"; onClicked: Shell.suspend() }
                    PowerChoice { icon: "logout"; label: "Esci"; onClicked: Shell.logout() }
                    PowerChoice { icon: "restart"; label: "Riavvia"; onClicked: Shell.reboot() }
                    PowerChoice { icon: "power"; label: "Spegni"; danger: true; onClicked: Shell.shutdown() }
                }
            }
        }

        // "Modifica" (sceglie le tessere)
        MouseArea {
            id: editButton
            anchors.horizontalCenter: parent.horizontalCenter
            width: editLabel.implicitWidth + 40
            height: 32
            hoverEnabled: true
            onClicked: { root.page = "main"; root.editing = !root.editing; }
            GlassPanel { anchors.fill: parent; radius: 16 }
            Rectangle { anchors.fill: parent; radius: 16; color: editButton.containsMouse ? Theme.surface2 : "transparent" }
            Text {
                id: editLabel
                anchors.centerIn: parent
                text: root.editing ? "Fine" : "Modifica controlli"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    // ============================================================ componenti
    // Tessera a pillola: cerchio con l'icona (bianco se attivo) e testo
    component PillTile: Item {
        id: tile
        property string tileId
        property string icon
        property string title
        property string subtitle
        property bool checked: false
        property bool editing: false
        property bool shown: true
        signal toggled()
        signal opened()
        signal editToggled()

        height: 70
        opacity: editing && !shown ? 0.45 : 1

        MouseArea {
            id: body
            anchors.fill: parent
            hoverEnabled: true
            onClicked: tile.editing ? tile.editToggled() : tile.opened()
        }
        Rectangle {
            anchors.fill: parent
            radius: 35
            color: body.containsMouse ? Theme.surface3 : Theme.surface2
            border.width: 1
            border.color: Theme.border
        }
        MouseArea {
            id: bubble
            x: 7
            anchors.verticalCenter: parent.verticalCenter
            width: 56; height: 56
            enabled: !tile.editing
            onClicked: tile.toggled()
            Rectangle {
                anchors.fill: parent
                radius: 28
                color: tile.checked ? Theme.accent : Theme.surface3
                scale: bubble.pressed ? 0.94 : 1
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Behavior on scale { NumberAnimation { duration: Theme.fast } }
                ArcIcon { anchors.centerIn: parent; width: 20; height: 20; name: tile.icon; color: tile.checked ? Theme.accentText : Theme.text }
            }
        }
        Column {
            anchors { left: bubble.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            Text { width: parent.width; text: tile.title; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { width: parent.width; text: tile.subtitle; elide: Text.ElideRight; color: Theme.muted; font.family: Theme.font; font.pixelSize: 11 }
        }
        // In modifica: + per aggiungere, − per togliere
        Rectangle {
            visible: tile.editing
            anchors { right: parent.right; top: parent.top; rightMargin: -2; topMargin: -2 }
            width: 22; height: 22; radius: 11
            color: tile.shown ? Theme.red : Theme.green
            ArcIcon { anchors.centerIn: parent; width: 12; height: 12; strokeWidth: 2.6; name: tile.shown ? "minus" : "plus"; color: "white" }
        }
    }

    // Cursore a pillola (volume, luminosità): icona e barra bianca
    component SliderPill: Item {
        id: pill
        property string icon
        property real value: 0
        signal moved(real value)
        signal iconClicked()
        height: 70
        Rectangle {
            anchors.fill: parent
            radius: 35
            color: Theme.surface2
            border.width: 1
            border.color: Theme.border
        }
        MouseArea {
            id: iconArea
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34
            onClicked: pill.iconClicked()
            ArcIcon { anchors.centerIn: parent; width: 22; height: 22; name: pill.icon; color: Theme.text }
        }
        Item {
            id: track
            anchors { left: iconArea.right; leftMargin: 18; right: parent.right; rightMargin: 30; verticalCenter: parent.verticalCenter }
            height: 30
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 10
                radius: 5
                color: Theme.surface4
                Rectangle {
                    width: Math.max(height, parent.width * Math.max(0, Math.min(1, pill.value)))
                    height: parent.height
                    radius: 5
                    color: "white"
                }
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                function set(mx) { pill.moved(Math.max(0, Math.min(1, (mx - 8) / track.width))); }
                onPressed: mouse => set(mouse.x)
                onPositionChanged: mouse => { if (pressed) set(mouse.x); }
            }
        }
    }

    // Pulsante rotondo a pillola (blocco, spegnimento)
    component RoundPill: MouseArea {
        id: rp
        property string icon
        property bool active: false
        width: 80
        height: 70
        hoverEnabled: true
        Rectangle {
            anchors.fill: parent
            radius: 35
            color: rp.active ? Theme.accent : rp.containsMouse ? Theme.surface3 : Theme.surface2
            border.width: 1
            border.color: Theme.border
        }
        ArcIcon { anchors.centerIn: parent; width: 22; height: 22; name: rp.icon; color: rp.active ? Theme.accentText : Theme.text }
    }

    component Caption: Text {
        color: Theme.sub
        font.family: Theme.font
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
    }

    component GlassCard: Rectangle {
        radius: Theme.rLg
        color: Theme.surface1
        border.width: 1
        border.color: Theme.border
    }

    component RoundButton: MouseArea {
        id: round
        property string icon
        property bool filled: false
        property bool active: false
        property int size: 36
        width: size
        height: size
        hoverEnabled: true
        opacity: enabled ? 1 : 0.35
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: round.active ? Theme.surface4 : round.containsMouse ? Theme.surface3 : Theme.surface2
            scale: round.pressed ? 0.94 : 1
        }
        ArcIcon {
            anchors.centerIn: parent
            width: round.size * 0.46; height: width
            name: round.icon
            filled: round.filled
            color: Theme.text
        }
    }

    component PowerChoice: MouseArea {
        id: choice
        property string icon
        property string label
        property bool danger: false
        width: 74
        height: 66
        hoverEnabled: true
        Rectangle {
            anchors.fill: parent
            radius: Theme.rMd
            color: choice.containsMouse ? (choice.danger ? Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.22) : Theme.surface3) : Theme.surface1
            border.width: 1
            border.color: Theme.border
        }
        ArcIcon { anchors.horizontalCenter: parent.horizontalCenter; y: 12; width: 20; height: 20; name: choice.icon; color: choice.danger && choice.containsMouse ? "#fca5a5" : Theme.text }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 9
            text: choice.label
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 11
        }
    }

    component Switch: MouseArea {
        id: sw
        property bool checked: false
        signal toggled()
        width: 44
        height: 26
        onClicked: sw.toggled()
        Rectangle {
            anchors.fill: parent
            radius: 13
            color: sw.checked ? Theme.accent : Theme.surface3
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Rectangle {
                x: sw.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: 10
                color: sw.checked ? Theme.accentText : Theme.text
                Behavior on x { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
            }
        }
    }

    component SignalBars: Row {
        id: bars
        property int strength: 0
        spacing: 2
        Repeater {
            model: 4
            Rectangle {
                required property int index
                anchors.bottom: parent.bottom
                width: 3
                height: 5 + index * 3
                radius: 1
                color: bars.strength >= index * 25 + 10 ? Theme.text : Theme.surface4
            }
        }
    }
}
