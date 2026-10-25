// Una superficie layer-shell nello schermo finto: posizione da ancore e
// margini come in KWin, sfocatura simulata dietro i rettangoli di setBlur
import QtQuick
import QtQuick.Effects

Item {
    id: host

    property var win
    property string scope
    property int surfaceLayer
    property int anchorsMask
    property int mt
    property int mr
    property int mb
    property int ml
    property int order
    property var blurRects: []

    readonly property bool aL: anchorsMask & 4
    readonly property bool aR: anchorsMask & 8
    readonly property bool aT: anchorsMask & 1
    readonly property bool aB: anchorsMask & 2

    z: surfaceLayer * 100 + order
    width: aL && aR ? parent.width - ml - mr : win.width
    height: aT && aB ? parent.height - mt - mb : win.height
    x: aL ? ml : aR ? parent.width - width - mr : (parent.width - width) / 2
    y: aT ? mt : aB ? parent.height - height - mb : (parent.height - height) / 2
    visible: win.visible

    // Sfocatura come l'effetto blur di KWin: lo sfondo dietro, sfocato e ritagliato
    Repeater {
        model: host.blurRects
        Item {
            id: blurItem
            required property var modelData
            readonly property int pad: 48
            x: modelData.x - pad
            y: modelData.y - pad
            width: modelData.width + 2 * pad
            height: modelData.height + 2 * pad
            z: -1

            ShaderEffectSource {
                id: source
                anchors.fill: parent
                sourceItem: Shell.wallpaperHost
                sourceRect: Qt.rect(host.x + blurItem.x, host.y + blurItem.y, blurItem.width, blurItem.height)
                visible: false
            }
            Item {
                id: mask
                anchors.fill: parent
                layer.enabled: true
                visible: false
                Rectangle {
                    x: blurItem.pad
                    y: blurItem.pad
                    width: blurItem.modelData.width
                    height: blurItem.modelData.height
                    radius: blurItem.modelData.radius
                    readonly property var corners: blurItem.modelData.corners || null
                    topLeftRadius: corners ? corners[0] : radius
                    topRightRadius: corners ? corners[1] : radius
                    bottomRightRadius: corners ? corners[2] : radius
                    bottomLeftRadius: corners ? corners[3] : radius
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: source
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                blur: 1.0
                saturation: 0.15
                maskEnabled: true
                maskSource: mask
            }
        }
    }

    Component.onCompleted: {
        if (aL && aR) win.width = Qt.binding(() => host.width);
        if (aT && aB) win.height = Qt.binding(() => host.height);
        const kids = [];
        for (let i = 0; i < win.contentItem.children.length; ++i) kids.push(win.contentItem.children[i]);
        for (const k of kids) k.parent = host;
        win.flags = Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.Tool;
        win.x = -30000;
        win.y = -30000;
    }
}
