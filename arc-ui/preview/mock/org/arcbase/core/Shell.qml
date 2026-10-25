// Mock di Shell (shell.cpp) per l'anteprima: configureLayer mette il
// contenuto delle finestre in uno "schermo" finto (vedi Host.qml); lo stato
// di sistema si cambia dal pannello "Simula".
pragma Singleton
import QtQuick
import "ticly-names.js" as Ticly

QtObject {
    id: shell

    enum Layer { LayerBackground, LayerBottom, LayerTop, LayerOverlay }
    enum Anchor { AnchorNone = 0, AnchorTop = 1, AnchorBottom = 2, AnchorLeft = 4, AnchorRight = 8 }
    enum Keyboard { KeyboardNone, KeyboardExclusive, KeyboardOnDemand }

    property Item screenItem: null
    property var hosts: []
    property int order: 0
    property Item wallpaperHost: null

    property string overlay: ""
    property bool batteryPresent: true
    property int batteryLevel: 76
    property bool charging: false
    property string networkType: "wifi"
    property string networkName: "Casa"
    property bool wifiEnabled: true
    property var wifiNetworks: []
    property bool bluetoothAvailable: true
    property bool bluetoothEnabled: false
    property real volume: 0.6
    property bool muted: false
    property real brightness: 0.8
    property string userName: "arc"
    property string fullName: "Arcbase User"
    property string wallpaper: wallpaperUrl
    // Esempio: orologio, calendario e meteo
    property string widgetLayout: "[{\"id\": \"clock\", \"kind\": \"clock\", \"size\": \"m\", \"col\": 0, \"row\": 0}, {\"id\": \"calendar\", \"kind\": \"calendar\", \"size\": \"m\", \"col\": 0, \"row\": 1}, {\"id\": \"weather\", \"kind\": \"weather\", \"size\": \"m\", \"col\": 0, \"row\": 2, \"options\": {\"city\": \"Cortina d'Ampezzo\"}}]"
    // Esempio: due cartelle già pronte
    property string launchpadLayout: "[{\"type\": \"app\", \"id\": \"system-file-manager.desktop\"}, {\"type\": \"app\", \"id\": \"firefox.desktop\"}, {\"type\": \"app\", \"id\": \"utilities-terminal.desktop\"}, {\"type\": \"folder\", \"id\": \"folder-grafica\", \"name\": \"Grafica\", \"apps\": [\"gimp.desktop\", \"org.kde.krita.desktop\", \"inkscape.desktop\", \"blender.desktop\", \"darktable.desktop\", \"shotwell.desktop\"]}, {\"type\": \"folder\", \"id\": \"folder-internet\", \"name\": \"Internet\", \"apps\": [\"telegram.desktop\", \"discord.desktop\", \"signal.desktop\", \"zoom.desktop\", \"thunderbird.desktop\", \"chromium.desktop\", \"filezilla.desktop\", \"transmission.desktop\", \"bitwarden.desktop\", \"keepassxc.desktop\"]}]"
    property bool nightLight: false
    property var controlTiles: ["wifi", "bluetooth", "dnd", "nightlight"]
    readonly property string avatar: ""
    readonly property string hostName: "arcbase"
    property var dockLaunchers: ["applications:org.kde.dolphin.desktop", "applications:firefox.desktop",
        "applications:org.kde.konsole.desktop", "applications:org.kde.kate.desktop",
        "applications:org.kde.discover.desktop", "applications:systemsettings.desktop"]

    // Come KService: nome dell'icona dal desktop file
    readonly property var icons: ({
        "org.kde.dolphin": "system-file-manager", "firefox": "firefox", "org.kde.konsole": "utilities-terminal",
        "org.kde.kate": "org.kde.kate", "org.kde.discover": "plasmadiscover", "systemsettings": "preferences-system"
    })
    readonly property var ticly: new Set(Ticly.names)
    function hasOwnShape(name) { return ticly.has(name); }
    function iconForApp(appId) { return icons[appId] || appId; }

    function configureLayer(window, scope, layer, anchors, exclusiveZone, keyboard, mt, mr, mb, ml) {
        const component = Qt.createComponent(Qt.resolvedUrl("Host.qml"));
        if (component.status !== Component.Ready) {
            console.error(component.errorString());
            return;
        }
        const host = component.createObject(screenItem, {
            win: window, scope: scope, surfaceLayer: layer, anchorsMask: anchors,
            mt: mt || 0, mr: mr || 0, mb: mb || 0, ml: ml || 0, order: order++
        });
        hosts = hosts.concat([host]);
        if (scope === "arc-wallpaper") wallpaperHost = host;
    }
    function hostOf(window) {
        for (const h of hosts) {
            if (h.win === window) return h;
        }
        return null;
    }
    function updateLayer(window, exclusiveZone, mt, mr, mb, ml) {
        const h = hostOf(window);
        if (!h) return;
        h.mt = mt || 0;
        h.mr = mr || 0;
        h.mb = mb || 0;
        h.ml = ml || 0;
    }
    function setBlur(window, rects) {
        const h = hostOf(window);
        if (h) h.blurRects = rects;
    }
    function setInputRegion(window, rects) {}

    function wallpapers() {
        const dir = wallpaperUrl.substring(0, wallpaperUrl.lastIndexOf("/") + 1);
        return ["dolomiti", "dolomiti-sera", "kronplatz", "tre-cime"].map(n => ({ url: dir + n + ".jpg", name: n }));
    }
    function scanWifi() {
        wifiNetworks = [
            { ssid: "Casa", signal: 82, secure: true, active: networkType === "wifi" },
            { ssid: "Ufficio-5G", signal: 64, secure: true, active: false },
            { ssid: "Bar Dolomiti", signal: 41, secure: false, active: false },
            { ssid: "Vicino", signal: 18, secure: true, active: false }
        ];
    }
    function connectWifi(ssid) { networkType = "wifi"; networkName = ssid; scanWifi(); }
    function run(program, args) { console.log("run", program, args); }
    function openSettings(module) { console.log("impostazioni", module || ""); overlay = ""; }
    function openTrash() { console.log("cestino"); overlay = ""; }
    function screenshot() { console.log("cattura"); overlay = ""; }
    function setVolume(v) { volume = v; muted = false; }
    function toggleMute() { muted = !muted; }
    function setBrightness(v) { brightness = Math.max(0.02, v); }
    function lock() { overlay = ""; }
    function suspend() { overlay = ""; }
    function logout() { overlay = ""; }
    function reboot() { overlay = ""; }
    function shutdown() { overlay = ""; }
    function toggleLauncher() { overlay = overlay === "launcher" ? "" : "launcher"; }
    function showControlCenter() { overlay = "control"; scanWifi(); }
    function showNotifications() { overlay = "notifications"; }
    function hideOverlay() { overlay = ""; }
}
