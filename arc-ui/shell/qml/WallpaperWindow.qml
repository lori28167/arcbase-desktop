// Sfondo della scrivania (uno per schermo), sotto tutte le finestre
import QtQuick
import QtQuick.Window
import org.arcbase.core
import "."

Window {
    id: win

    property var targetScreen

    screen: targetScreen
    color: "#0f0d14"
    width: 800
    height: 600
    visible: false

    Component.onCompleted: {
        Shell.configureLayer(win, "arc-wallpaper", Shell.LayerBackground,
                             Shell.AnchorTop | Shell.AnchorBottom | Shell.AnchorLeft | Shell.AnchorRight,
                             -1, Shell.KeyboardNone);
        visible = true;
    }

    Image {
        anchors.fill: parent
        source: Shell.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: win.width * Screen.devicePixelRatio
        sourceSize.height: win.height * Screen.devicePixelRatio
        opacity: status === Image.Ready ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.slow }
        }
    }
}
