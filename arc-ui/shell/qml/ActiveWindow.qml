// Stato della finestra attiva per topbar e dock: se è ingrandita la topbar
// si attacca ai bordi e ne mostra nome e pulsanti, la dock si nasconde.
// Senza libtaskmanager: nessuna finestra (la shell resta com'è).
pragma Singleton
import QtQuick

QtObject {
    id: active

    readonly property bool present: loader.item ? loader.item.present : false
    readonly property bool maximized: loader.item ? loader.item.maximized : false
    readonly property string appName: loader.item ? loader.item.appName : ""
    readonly property string title: loader.item ? loader.item.title : ""
    // Il nome mostrato nella topbar: quello dell'app, altrimenti il titolo
    readonly property string name: appName !== "" ? appName : title

    function minimize() { if (loader.item) loader.item.minimize(); }
    function toggleMaximize() { if (loader.item) loader.item.toggleMaximize(); }
    function close() { if (loader.item) loader.item.close(); }

    readonly property Loader loader: Loader {
        source: "ActiveWindowTasks.qml"
        onStatusChanged: if (status === Loader.Error) console.warn("arc-shell: libtaskmanager non disponibile, niente stato della finestra attiva")
    }
}
