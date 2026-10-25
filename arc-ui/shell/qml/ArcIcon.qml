// Icone lineari di arc UI (griglia 24×24, tratto arrotondato), colorabili
import QtQuick
import QtQuick.Shapes

Item {
    id: icon

    property string name
    property color color: "white"
    property real strokeWidth: 1.8
    // Riempie le forme chiuse (play, pausa...) oltre a tracciarle
    property bool filled: false

    implicitWidth: 20
    implicitHeight: 20

    readonly property var paths: ({
        "wifi": "M9.17 16.17 A4 4 0 0 1 14.83 16.17 M6.34 13.34 A8 8 0 0 1 17.66 13.34 M3.51 10.51 A12 12 0 0 1 20.49 10.51 M12 19.6 L12 19.61",
        "wifi-off": "M9.17 16.17 A4 4 0 0 1 14.83 16.17 M6.34 13.34 A8 8 0 0 1 17.66 13.34 M3.51 10.51 A12 12 0 0 1 20.49 10.51 M12 19.6 L12 19.61 M4 4 L20 20",
        "ethernet": "M9 3 H15 V8 H9 Z M12 8 V12 M5 12 H19 M5 12 V16 M19 12 V16 M2.5 16 H7.5 V21 H2.5 Z M16.5 16 H21.5 V21 H16.5 Z",
        "hexagon": "M12 2.5 L20.5 7.25 V16.75 L12 21.5 L3.5 16.75 V7.25 Z",
        "volume": "M4 9.5 H7.5 L12 5.5 V18.5 L7.5 14.5 H4 Z M15.5 9 A4.5 4.5 0 0 1 15.5 15 M18 6.5 A8 8 0 0 1 18 17.5",
        "volume-off": "M4 9.5 H7.5 L12 5.5 V18.5 L7.5 14.5 H4 Z M16 9.5 L21 14.5 M21 9.5 L16 14.5",
        "search": "M4 10.5 A6.5 6.5 0 1 1 17 10.5 A6.5 6.5 0 1 1 4 10.5 Z M15.3 15.3 L20 20",
        "grid": "M4 4 H10 V10 H4 Z M14 4 H20 V10 H14 Z M4 14 H10 V20 H4 Z M14 14 H20 V20 H14 Z",
        "settings": "M4 7 H11 M15 7 H20 M13 4.5 V9.5 M4 17 H6 M10 17 H20 M8 14.5 V19.5",
        "lock": "M7.5 11 V8 A4.5 4.5 0 0 1 16.5 8 V11 M5.5 11 H18.5 V20.5 H5.5 Z",
        "moon": "M20 14.5 A8 8 0 1 1 9.5 4 A6.5 6.5 0 0 0 20 14.5 Z",
        "logout": "M10 4 H6 A2 2 0 0 0 4 6 V18 A2 2 0 0 0 6 20 H10 M15 8 L19 12 L15 16 M19 12 H9",
        "restart": "M19.5 12 A7.5 7.5 0 1 1 17.3 6.7 M17.6 2.8 V6.9 H13.5",
        "power": "M12 3 V12 M7.05 8.05 A7 7 0 1 0 16.95 8.05",
        "close": "M6 6 L18 18 M18 6 L6 18",
        "bell": "M6 16.5 V11 A6 6 0 0 1 18 11 V16.5 L19.5 18 H4.5 Z M10 20.5 A2 2 0 0 0 14 20.5",
        "chevron-right": "M9 5 L16 12 L9 19",
        "chevron-left": "M15 5 L8 12 L15 19",
        "chevron-down": "M5 9 L12 16 L19 9",
        "arrow-right": "M5 12 H19 M13 6 L19 12 L13 18",
        "sun": "M8.5 12 A3.5 3.5 0 1 1 15.5 12 A3.5 3.5 0 1 1 8.5 12 Z M12 2.5 V4.5 M12 19.5 V21.5 M2.5 12 H4.5 M19.5 12 H21.5 M5.3 5.3 L6.7 6.7 M17.3 17.3 L18.7 18.7 M5.3 18.7 L6.7 17.3 M17.3 6.7 L18.7 5.3",
        "bluetooth": "M7 7.5 L17 16.5 L12 21 V3 L17 7.5 L7 16.5",
        "bell-off": "M6 16.5 V11 A6 6 0 0 1 15.2 5.9 M18 10.5 V16.5 L19.5 18 H8 M10 20.5 A2 2 0 0 0 14 20.5 M4 4 L20 20",
        "moon-small": "M18 13.5 A6.5 6.5 0 1 1 10.5 6 A5 5 0 0 0 18 13.5 Z",
        "play": "M8 5.5 L18.5 12 L8 18.5 Z",
        "pause": "M8.5 5.5 V18.5 M15.5 5.5 V18.5",
        "next": "M6.5 6 L14 12 L6.5 18 Z M17.5 6 V18",
        "previous": "M17.5 6 L10 12 L17.5 18 Z M6.5 6 V18",
        "plus": "M12 5 V19 M5 12 H19",
        "minus": "M5 12 H19",
        "check": "M5 12.5 L10 17.5 L19 7",
        "pencil": "M4.5 19.5 L5.3 15.7 L15.6 5.4 A1.9 1.9 0 0 1 18.6 8.4 L8.3 18.7 Z M13.8 7.2 L16.8 10.2",
        "image": "M5.5 5 H18.5 A1.5 1.5 0 0 1 20 6.5 V17.5 A1.5 1.5 0 0 1 18.5 19 H5.5 A1.5 1.5 0 0 1 4 17.5 V6.5 A1.5 1.5 0 0 1 5.5 5 Z M4.5 17 L9.5 12 L13 15.5 L15.5 13 L19.5 17 M14 8.8 A1.3 1.3 0 1 1 16.6 8.8 A1.3 1.3 0 1 1 14 8.8 Z",
        "camera": "M4 8.5 A1.5 1.5 0 0 1 5.5 7 H8 L9.5 5 H14.5 L16 7 H18.5 A1.5 1.5 0 0 1 20 8.5 V17.5 A1.5 1.5 0 0 1 18.5 19 H5.5 A1.5 1.5 0 0 1 4 17.5 Z M8.8 12.8 A3.2 3.2 0 1 1 15.2 12.8 A3.2 3.2 0 1 1 8.8 12.8 Z",
        "info": "M3.5 12 A8.5 8.5 0 1 1 20.5 12 A8.5 8.5 0 1 1 3.5 12 Z M12 11 V16.5 M12 7.8 L12 7.81",
        "music": "M9 18 V6.5 L19 4.5 V16 M9 18 A2.5 2.5 0 1 1 4 18 A2.5 2.5 0 1 1 9 18 Z M19 16 A2.5 2.5 0 1 1 14 16 A2.5 2.5 0 1 1 19 16 Z",
        "microphone": "M9 6.5 A3 3 0 0 1 15 6.5 V12 A3 3 0 0 1 9 12 Z M5.5 11.5 A6.5 6.5 0 0 0 18.5 11.5 M12 18 V21",
        "keyboard": "M3.5 7 H20.5 V17 H3.5 Z M7 10.5 L7 10.51 M10.3 10.5 L10.3 10.51 M13.7 10.5 L13.7 10.51 M17 10.5 L17 10.51 M8 14 H16",
        "touchpad": "M4 5 H20 V19 H4 Z M4 15 H20 M12 15 V19",
        "antenna": "M12 11 V21 M8.5 7.5 A5 5 0 0 0 8.5 14.5 M15.5 7.5 A5 5 0 0 1 15.5 14.5 M5.5 4.5 A9 9 0 0 0 5.5 17.5 M18.5 4.5 A9 9 0 0 1 18.5 17.5",
        "trash": "M4.5 6.5 H19.5 M9.5 6.5 V4.5 H14.5 V6.5 M6 6.5 L7 20 H17 L18 6.5",
        "widgets": "M4 4 H10.5 V10.5 H4 Z M13.5 4 H20 V10.5 H13.5 Z M4 13.5 H20 V20 H4 Z",
        "clock-face": "M3.5 12 A8.5 8.5 0 1 1 20.5 12 A8.5 8.5 0 1 1 3.5 12 Z M12 7 V12 L15.5 14",
        "cloud": "M7 18.5 H17 A4 4 0 0 0 17.6 10.55 A5.5 5.5 0 0 0 7.1 9.7 A4.4 4.4 0 0 0 7 18.5 Z",
        "cloud-sun": "M8.5 3.5 V5 M3.6 5.6 L4.6 6.6 M2 10.5 H3.5 M6.1 11.4 A3.6 3.6 0 1 1 11.9 7 M9 20 H17.5 A3.5 3.5 0 0 0 18 13.05 A5 5 0 0 0 8.6 12.3 A3.9 3.9 0 0 0 9 20 Z",
        "rain": "M7 15 H17 A4 4 0 0 0 17.6 7.05 A5.5 5.5 0 0 0 7.1 6.2 A4.4 4.4 0 0 0 7 15 Z M9 18 L8 20.5 M13 18 L12 20.5 M17 18 L16 20.5",
        "snow": "M7 15 H17 A4 4 0 0 0 17.6 7.05 A5.5 5.5 0 0 0 7.1 6.2 A4.4 4.4 0 0 0 7 15 Z M8.5 19 L8.5 19.01 M12.5 20.5 L12.5 20.51 M16.5 19 L16.5 19.01",
        "storm": "M7 14.5 H17 A4 4 0 0 0 17.6 6.55 A5.5 5.5 0 0 0 7.1 5.7 A4.4 4.4 0 0 0 7 14.5 Z M13 15.5 L11 18.5 H14 L12 21.5",
        "fog": "M4 8.5 H20 M6 12.5 H18 M4 16.5 H20",
        "location": "M12 21 C12 21 5.5 14.8 5.5 10 A6.5 6.5 0 0 1 18.5 10 C18.5 14.8 12 21 12 21 Z M9.6 10 A2.4 2.4 0 1 1 14.4 10 A2.4 2.4 0 1 1 9.6 10 Z",
        "airplane": "M10.5 4 A1.5 1.5 0 0 1 13.5 4 V9.5 L20.5 13.5 V15.5 L13.5 13.2 V18 L15.5 19.5 V21 L12 20 L8.5 21 V19.5 L10.5 18 V13.2 L3.5 15.5 V13.5 L10.5 9.5 Z",
        "display": "M3.5 5 H20.5 V16 H3.5 Z M9 20 H15 M12 16 V20"
    })

    // Antialiasing del tracciato alla dimensione reale dell'icona
    layer.enabled: true
    layer.samples: 4
    layer.smooth: true

    Shape {
        width: 24
        height: 24
        scale: Math.min(icon.width, icon.height) / 24
        transformOrigin: Item.TopLeft
        x: (icon.width - 24 * scale) / 2
        y: (icon.height - 24 * scale) / 2

        ShapePath {
            strokeColor: icon.color
            strokeWidth: icon.strokeWidth
            fillColor: icon.filled ? icon.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: icon.paths[icon.name] || ""
            }
        }
    }
}
