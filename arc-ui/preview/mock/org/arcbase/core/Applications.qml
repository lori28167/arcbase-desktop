// Mock dell'elenco app (applications.cpp): stessa ricerca per nome
pragma Singleton
import QtQuick

ListModel {
    id: apps

    property string filter: ""
    signal launched()

    readonly property var all: [
        ["Ark", "org.kde.ark"], ["Calcolatrice", "accessories-calculator"], ["Centro informazioni", "org.kde.kinfocenter"],
        ["Discover", "plasmadiscover"], ["Dolphin", "system-file-manager"], ["Editor di testo", "accessories-text-editor"],
        ["Firefox", "firefox"], ["Gwenview", "org.kde.gwenview"], ["Impostazioni di sistema", "preferences-system"],
        ["Installa Arcbase Desktop", "system-software-install"], ["Kate", "org.kde.kate"], ["Konsole", "utilities-terminal"],
        ["Monitor di sistema", "utilities-system-monitor"], ["Okular", "org.kde.okular"], ["Spectacle", "org.kde.spectacle"],
        ["GIMP (Debian)", "gimp"], ["LibreOffice Writer", "libreoffice-writer"], ["VLC", "vlc"],
        ["Thunderbird", "thunderbird"], ["Visual Studio Code", "code"], ["Blender", "blender"],
        ["Inkscape", "inkscape"], ["Krita", "org.kde.krita"], ["OBS Studio", "obs"], ["Steam", "steam"],
        ["Telegram", "telegram"], ["Audacity", "audacity"], ["Kdenlive", "org.kde.kdenlive"], ["Shotwell", "shotwell"],
        ["Transmission", "transmission"], ["Filezilla", "filezilla"], ["Discord", "discord"], ["Zoom", "zoom"],
        ["Signal", "signal"], ["Bitwarden", "bitwarden"], ["Spotify", "spotify"], ["Chromium", "chromium"],
        ["KeePassXC", "keepassxc"], ["Calibre", "calibre"], ["Darktable", "darktable"]
    ]

    readonly property var allIds: all.map(a => a[1] + ".desktop")
    function byId(id) {
        const a = all.find(x => x[1] + ".desktop" === id);
        return a ? { name: a[0], genericName: "", iconName: a[1], storageId: id } : ({});
    }
    readonly property var groups: ({
        "Graphics": ["gimp", "org.kde.krita", "inkscape", "blender", "darktable", "org.kde.gwenview", "shotwell"],
        "AudioVideo": ["vlc", "audacity", "org.kde.kdenlive", "spotify", "obs"],
        "Network": ["firefox", "thunderbird", "telegram", "discord", "zoom", "signal", "chromium", "filezilla", "transmission"],
        "Office": ["libreoffice-writer", "org.kde.okular", "calibre"],
        "Development": ["utilities-terminal", "code", "org.kde.kate"],
        "System": ["preferences-system", "org.kde.kinfocenter", "utilities-system-monitor", "plasmadiscover", "system-software-install", "system-file-manager"],
        "Utility": ["accessories-calculator", "accessories-text-editor", "org.kde.ark", "org.kde.spectacle", "keepassxc", "bitwarden"],
        "Game": ["steam"]
    })
    function categories(id) {
        const icon = id.replace(/\.desktop$/, "");
        return Object.keys(groups).filter(k => groups[k].indexOf(icon) >= 0);
    }

    function launch(storageId) {
        console.log("avvio", storageId);
        launched();
        Shell.hideOverlay();
    }
    function launchAt(row) {
        if (row >= 0 && row < count) launch(get(row).storageId);
    }
    function refill() {
        clear();
        const needle = filter.trim().toLowerCase();
        for (const a of all) {
            if (needle === "" || a[0].toLowerCase().indexOf(needle) >= 0)
                append({ name: a[0], genericName: "", iconName: a[1], storageId: a[1] + ".desktop" });
        }
    }
    onFilterChanged: refill()
    Component.onCompleted: refill()
}
