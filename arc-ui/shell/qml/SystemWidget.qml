// Widget Sistema: batteria (o volume sui fissi), rete, Bluetooth, suono.
// S: anello di carica · M: elenco · L: elenco con volume e luminosità
import QtQuick
import QtQuick.Shapes
import org.arcbase.core
import "."

Item {
    id: widget

    property string size: "m"
    property var options: ({})
    signal optionChanged(string key, var value)

    readonly property real ringValue: Shell.batteryPresent ? Shell.batteryLevel / 100 : (Shell.muted ? 0 : Shell.volume)

    // --- S: anello
    Item {
        visible: widget.size === "s"
        anchors.centerIn: parent
        width: 112
        height: 112

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4
            ShapePath {
                strokeColor: Theme.surface3
                strokeWidth: 10
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 56; centerY: 56; radiusX: 50; radiusY: 50; startAngle: -90; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: Shell.batteryPresent && Shell.batteryLevel <= 15 && !Shell.charging ? Theme.red : Theme.accent
                strokeWidth: 10
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 56; centerY: 56; radiusX: 50; radiusY: 50; startAngle: -90; sweepAngle: 360 * Math.max(0.01, widget.ringValue) }
            }
        }
        Column {
            anchors.centerIn: parent
            ArcIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 20; height: 20
                name: Shell.batteryPresent ? "power" : (Shell.muted ? "volume-off" : "volume")
                color: Theme.muted
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(widget.ringValue * 100) + "%"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
        }
    }

    // --- M e L: elenco
    Column {
        visible: widget.size !== "s"
        x: 18
        y: 16
        width: parent.width - 36
        spacing: widget.size === "l" ? 12 : 4

        Row {
            visible: Shell.batteryPresent
            width: parent.width
            height: 34
            spacing: 12
            BatteryIcon { anchors.verticalCenter: parent.verticalCenter; level: Shell.batteryLevel; charging: Shell.charging; color: Theme.text }
            Line { text: Shell.batteryLevel + "%" + (Shell.charging ? " · in carica" : "") }
        }
        Row {
            width: parent.width
            height: 34
            spacing: 12
            ArcIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22
                name: Shell.networkType === "ethernet" ? "ethernet" : Shell.networkType === "wifi" ? "wifi" : "wifi-off"
                color: Theme.text
            }
            Line { text: Shell.networkType === "none" ? "Non connesso" : Shell.networkName }
        }
        Row {
            width: parent.width
            height: 34
            spacing: 12
            ArcIcon { anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; name: "bluetooth"; color: Theme.text }
            Line { text: !Shell.bluetoothAvailable ? "Bluetooth non disponibile" : Shell.bluetoothEnabled ? "Bluetooth attivo" : "Bluetooth spento" }
        }
        Row {
            visible: widget.size !== "l" && !Shell.batteryPresent
            width: parent.width
            height: 34
            spacing: 12
            ArcIcon { anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; name: Shell.muted ? "volume-off" : "volume"; color: Theme.text }
            Line { text: Shell.muted ? "Audio disattivato" : "Volume " + Math.round(Shell.volume * 100) + "%" }
        }

        // L: cursori
        Column {
            visible: widget.size === "l"
            width: parent.width
            spacing: 14
            topPadding: 6
            Row {
                width: parent.width
                spacing: 12
                MouseArea {
                    width: 22; height: 22
                    onClicked: Shell.toggleMute()
                    ArcIcon { anchors.fill: parent; name: Shell.muted ? "volume-off" : "volume"; color: Theme.text }
                }
                ArcSlider { width: parent.width - 34; anchors.verticalCenter: parent.verticalCenter; value: Shell.muted ? 0 : Shell.volume; onMoved: v => Shell.setVolume(v) }
            }
            Row {
                visible: Shell.brightness >= 0
                width: parent.width
                spacing: 12
                ArcIcon { width: 22; height: 22; name: "sun"; color: Theme.text }
                ArcSlider { width: parent.width - 34; anchors.verticalCenter: parent.verticalCenter; value: Shell.brightness; onMoved: v => Shell.setBrightness(v) }
            }
        }
    }

    component Line: Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 40
        elide: Text.ElideRight
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 14
    }
}
