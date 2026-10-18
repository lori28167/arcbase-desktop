// Centro di controllo (stato di sistema nella topbar): interruttori Wi‑Fi,
// Bluetooth, Non disturbare e cattura schermo; luminosità e volume; musica in
// riproduzione; batteria; utente e sessione. La pagina Wi‑Fi elenca le reti.
import QtQuick
import org.arcbase.core
import "."

GlassPanel {
    id: panel

    property string page: "main"   // "main" | "wifi" | "power"

    width: 360
    height: (page === "wifi" ? wifiPage.height : mainPage.height) + 32
    clip: true

    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

    // Il clic nel pannello non lo chiude
    MouseArea { anchors.fill: parent }

    // ============================================================ pagina principale
    Column {
        id: mainPage
        x: panel.page === "main" ? 16 : -panel.width
        y: 16
        width: panel.width - 32
        spacing: 12
        Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        // --- Interruttori
        Grid {
            columns: 2
            spacing: 10
            width: parent.width

            Tile {
                icon: Shell.wifiEnabled ? (Shell.networkType === "ethernet" ? "ethernet" : "wifi") : "wifi-off"
                title: "Wi‑Fi"
                subtitle: !Shell.wifiEnabled ? "Disattivato" : Shell.networkName !== "" ? Shell.networkName : "Non connesso"
                checked: Shell.wifiEnabled
                expandable: true
                onToggled: Shell.wifiEnabled = !Shell.wifiEnabled
                onExpanded: { Shell.scanWifi(); panel.page = "wifi"; }
            }
            Tile {
                icon: "bluetooth"
                title: "Bluetooth"
                subtitle: !Shell.bluetoothAvailable ? "Non disponibile" : Shell.bluetoothEnabled ? "Attivo" : "Disattivato"
                checked: Shell.bluetoothEnabled
                enabled: Shell.bluetoothAvailable
                expandable: true
                onToggled: Shell.bluetoothEnabled = !Shell.bluetoothEnabled
                onExpanded: Shell.openSettings("kcm_bluetooth")
            }
            Tile {
                icon: Notifications.doNotDisturb ? "bell-off" : "moon-small"
                title: "Non disturbare"
                subtitle: Notifications.doNotDisturb ? "Attivo" : "Disattivato"
                checked: Notifications.doNotDisturb
                onToggled: Notifications.doNotDisturb = !Notifications.doNotDisturb
            }
            Tile {
                icon: "sun"
                title: "Luce notturna"
                subtitle: Shell.nightLight ? "Toni caldi" : "Disattivata"
                checked: Shell.nightLight
                expandable: true
                onToggled: Shell.nightLight = !Shell.nightLight
                onExpanded: Shell.openSettings("kcm_nightlight")
            }
            Tile {
                // Modalità aereo: Wi‑Fi e Bluetooth spenti insieme
                readonly property bool airplane: !Shell.wifiEnabled && (!Shell.bluetoothAvailable || !Shell.bluetoothEnabled)
                icon: "airplane"
                title: "Modalità aereo"
                subtitle: airplane ? "Attiva" : "Disattivata"
                checked: airplane
                onToggled: {
                    const on = !airplane;
                    Shell.wifiEnabled = !on;
                    if (Shell.bluetoothAvailable) Shell.bluetoothEnabled = !on;
                }
            }
            Tile {
                icon: "camera"
                title: "Cattura"
                subtitle: "Schermo o finestra"
                onToggled: Shell.screenshot()
            }
        }

        // --- Schermo e suono
        GlassCard {
            width: parent.width
            height: sliders.height + 28

            Column {
                id: sliders
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 14

                Column {
                    visible: Shell.brightness >= 0
                    width: parent.width
                    spacing: 8
                    Caption { text: "Schermo" }
                    Row {
                        spacing: 12
                        width: parent.width
                        ArcIcon { anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; name: "sun"; color: Theme.text }
                        ArcSlider {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 30
                            value: Shell.brightness
                            onMoved: v => Shell.setBrightness(v)
                        }
                    }
                }
                Column {
                    width: parent.width
                    spacing: 8
                    Caption { text: "Suono" }
                    Row {
                        spacing: 12
                        width: parent.width
                        MouseArea {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18
                            onClicked: Shell.toggleMute()
                            ArcIcon { anchors.fill: parent; name: Shell.muted ? "volume-off" : "volume"; color: Theme.text }
                        }
                        ArcSlider {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 30
                            value: Shell.muted ? 0 : Shell.volume
                            onMoved: v => Shell.setVolume(v)
                        }
                    }
                }
            }
        }

        // --- Musica
        GlassCard {
            visible: Media.available
            width: parent.width
            height: 76

            Rectangle {
                id: art
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 52; height: 52
                radius: 12
                color: Theme.surface3
                clip: true
                Image {
                    anchors.fill: parent
                    source: Media.artUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                }
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
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                RoundButton { icon: "previous"; filled: true; size: 32; enabled: Media.canGoPrevious; onClicked: Media.previous() }
                RoundButton { icon: Media.playing ? "pause" : "play"; filled: !Media.playing; size: 38; onClicked: Media.playPause() }
                RoundButton { icon: "next"; filled: true; size: 32; enabled: Media.canGoNext; onClicked: Media.next() }
            }
        }

        // --- Batteria
        GlassCard {
            visible: Shell.batteryPresent
            width: parent.width
            height: 52
            BatteryIcon {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                level: Shell.batteryLevel
                charging: Shell.charging
                color: Theme.text
            }
            Text {
                x: 52
                anchors.verticalCenter: parent.verticalCenter
                text: Shell.batteryLevel + "%" + (Shell.charging ? " · in carica" : "")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            MouseArea { anchors.fill: parent; onClicked: Shell.openSettings("kcm_powerdevilprofilesconfig") }
        }

        // --- Utente e sessione
        Item {
            width: parent.width
            height: 44

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Rectangle {
                    width: 36; height: 36; radius: 18
                    color: Theme.surface3
                    border.width: 1
                    border.color: Theme.borderHi
                    Text {
                        anchors.centerIn: parent
                        text: Shell.fullName.charAt(0).toUpperCase()
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Shell.fullName
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                RoundButton { icon: "settings"; size: 36; onClicked: Shell.openSettings() }
                RoundButton { icon: "lock"; size: 36; onClicked: Shell.lock() }
                RoundButton { icon: "power"; size: 36; active: powerRow.visible; onClicked: powerRow.visible = !powerRow.visible }
            }
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

    // ============================================================ pagina Wi‑Fi
    Column {
        id: wifiPage
        x: panel.page === "wifi" ? 16 : panel.width
        y: 16
        width: panel.width - 32
        spacing: 10
        Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        Item {
            width: parent.width
            height: 36
            RoundButton { anchors.verticalCenter: parent.verticalCenter; icon: "chevron-left"; size: 34; onClicked: panel.page = "main" }
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
                        panel.page = "main";
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSm
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

    // ============================================================ componenti
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

    // Interruttore grande: icona in un cerchio (bianco se attivo), testo e,
    // se espandibile, la freccia per i dettagli
    component Tile: Rectangle {
        id: tile
        property string icon
        property string title
        property string subtitle
        property bool checked: false
        property bool expandable: false
        signal toggled()
        signal expanded()

        width: (parent.width - 10) / 2
        height: 78
        radius: Theme.rLg
        color: tileArea.containsMouse ? Theme.surface2 : Theme.surface1
        border.width: 1
        border.color: Theme.border
        opacity: enabled ? 1 : 0.5

        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: tile.toggled()
        }
        // Icona in alto, nome in basso: i nomi lunghi restano interi
        Rectangle {
            id: bubble
            x: 12
            y: 11
            width: 30; height: 30; radius: 15
            color: tile.checked ? Theme.accent : Theme.surface3
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            ArcIcon { anchors.centerIn: parent; width: 16; height: 16; name: tile.icon; color: tile.checked ? Theme.accentText : Theme.text }
        }
        Column {
            anchors { left: parent.left; leftMargin: 13; right: parent.right; rightMargin: 10; bottom: parent.bottom; bottomMargin: 10 }
            Text { width: parent.width; text: tile.title; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { width: parent.width; text: tile.subtitle; elide: Text.ElideRight; color: Theme.muted; font.family: Theme.font; font.pixelSize: 11 }
        }
        MouseArea {
            id: chevron
            visible: tile.expandable
            anchors { right: parent.right; top: parent.top }
            width: 40
            height: 40
            hoverEnabled: true
            onClicked: tile.expanded()
            Rectangle {
                anchors.centerIn: parent
                width: 26; height: 26; radius: 13
                color: chevron.containsMouse ? Theme.surface3 : "transparent"
                ArcIcon { anchors.centerIn: parent; width: 13; height: 13; name: "chevron-right"; color: Theme.muted; strokeWidth: 2.2 }
            }
        }
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
