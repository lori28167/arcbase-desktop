// arc-shell: compone le superfici della scrivania arc UI.
// Sfondo su ogni schermo; scrivania con i widget, topbar, dock, notifiche,
// indicatore a schermo e pannelli a tutto schermo sul primo schermo.
import QtQuick
import QtQml
import QtQml.Models
import "."

QtObject {
    id: shell

    property Instantiator wallpapers: Instantiator {
        model: Qt.application.screens
        delegate: WallpaperWindow {
            required property var modelData
            targetScreen: modelData
        }
    }

    property DesktopWindow desktop: DesktopWindow {}
    property TopBarWindow topBar: TopBarWindow {}
    property DockWindow dock: DockWindow {}
    property NotificationsWindow notifications: NotificationsWindow {}
    property OsdWindow osd: OsdWindow {}
    property OverlayWindow overlay: OverlayWindow {}
}
