// Ora corrente condivisa da topbar e widget
pragma Singleton
import QtQuick

QtObject {
    id: clock

    property date now: new Date()

    readonly property string time: Qt.formatTime(now, "HH:mm")
    // "gio 13 ott" con la lingua di sistema
    readonly property string shortDate: Qt.locale().toString(now, "ddd d MMM")
    readonly property string longDate: Qt.locale().toString(now, "dddd d MMMM")

    readonly property Timer timer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: clock.now = new Date()
    }
}
