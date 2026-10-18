// Anteprima interattiva di arc-shell: il vero Main.qml dentro uno "schermo"
// finto (le superfici layer-shell sono disposte da mock/.../Host.qml) e un
// pannello per simulare notifiche, batteria, rete e audio.
// Ctrl+Spazio = tasto Meta (launcher). Con ARC_PREVIEW_SHOTS salva le schermate.
import QtQuick
import org.arcbase.core
import org.kde.taskmanager

Window {
    id: root

    x: previewGeometry.width > 0 ? previewGeometry.x : 40
    y: previewGeometry.width > 0 ? previewGeometry.y : 40
    width: previewGeometry.width > 0 ? previewGeometry.width : 1440
    height: previewGeometry.width > 0 ? previewGeometry.height : 900
    visible: true
    color: "black"
    title: "arc UI — anteprima (i file QML si ricaricano da soli · tasto destro sulla scrivania per il menu)"

    Item {
        id: screen
        anchors.fill: parent
    }

    Shortcut {
        sequence: "Ctrl+Space"
        context: Qt.ApplicationShortcut
        onActivated: Shell.toggleLauncher()
    }

    property var shellObject

    // Finestra di esempio con la decorazione arc (sopra la scrivania, sotto topbar e dock)
    SampleWindow {
        id: sample
        parent: screen
        z: 150
    }

    Component.onCompleted: {
        Shell.screenItem = screen;
        const component = Qt.createComponent(mainUrl);
        if (component.status !== Component.Ready) {
            console.error(component.errorString());
            return;
        }
        shellObject = component.createObject(root);
        if (animShots !== "") {
            WindowState.visible = animShots !== "launcher";
            WindowState.maximized = false;
            animStart.start();
        } else if (shots) {
            applyShot(shotList[0][1]);
            step.start();
        } else {
            panel.visible = true;
        }
    }

    // --- Schermate automatiche (ARC_PREVIEW_SHOTS=1) ---------------------------
    property int stage: 0
    readonly property var shotList: [["fullscreen", "fullscreen"], ["window", "window"], ["desktop", ""], ["launcher", "launcher"], ["launcher-folder", "launcher-folder"], ["launcher-search", "launcher-search"], ["control", "control"],
                                     ["notifications", "notifications"], ["widgets", "edit"], ["wallpaper", "wallpaper"]]
    function applyShot(mode) {
        WindowState.visible = mode === "window" || mode === "fullscreen";
        WindowState.maximized = mode === "fullscreen";
        root.shellObject.desktop.editing = mode === "edit";
        const launcherShot = mode.indexOf("launcher-") === 0;
        Shell.overlay = mode === "edit" || mode === "window" || mode === "fullscreen" ? "" : launcherShot ? "launcher" : mode;
        if (launcherShot) {
            launchpadAction.mode = mode;
            launchpadAction.restart();
        }
    }
    Timer {
        id: step
        interval: 1800
        onTriggered: {
            const name = root.shotList[root.stage][0];
            screen.grabToImage(result => {
                result.saveToFile(outDir + "/" + name + ".png");
                console.log("salvato", outDir + "/" + name + ".png");
                root.stage++;
                if (root.stage >= root.shotList.length) {
                    Qt.quit();
                    return;
                }
                root.applyShot(root.shotList[root.stage][1]);
                step.start();
            });
        }
    }

    Timer {
        id: launchpadAction
        property string mode
        interval: 700
        onTriggered: {
            const pad = root.shellObject.overlay.launchpad;
            if (!pad) return;
            if (mode === "launcher-folder") pad.folderId = "folder-internet";
            if (mode === "launcher-search") pad.setQuery("12*4");
        }
    }

    // --- Fotogrammi dell'ingrandimento (ARC_PREVIEW_ANIM=1) ------------------
    property int frame: 0
    readonly property var frameTimes: [0, 70, 140, 210, 300, 700]
    Timer {
        id: animStart
        interval: 1500
        onTriggered: {
            if (animShots === "launcher") Shell.toggleLauncher();
            else WindowState.maximized = true;
            root.frame = 0;
            animFrame.interval = root.frameTimes[0] + 1;
            animFrame.start();
        }
    }
    Timer {
        id: animFrame
        onTriggered: {
            const n = root.frame;
            screen.grabToImage(result => result.saveToFile(outDir + "/anim-" + n + ".png"));
            root.frame++;
            if (root.frame >= root.frameTimes.length) {
                quitTimer.start();
                return;
            }
            interval = root.frameTimes[root.frame] - root.frameTimes[n];
            start();
        }
    }
    Timer { id: quitTimer; interval: 800; onTriggered: Qt.quit() }

    // --- Pannello di simulazione ---------------------------------------------------
    Window {
        id: panel
        visible: false
        x: root.x + root.width + 12
        y: root.y
        width: 260
        height: column.implicitHeight + 32
        color: "#16131d"
        title: "Simula"

        Column {
            id: column
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 6

            Label { text: "Notifiche" }
            Button { text: "Notifica normale"; onClicked: Notifications.push("Dolphin", "org.kde.dolphin", "Copia completata", "3 file copiati in <b>Documenti</b>.", 1) }
            Button { text: "Notifica critica"; onClicked: Notifications.push("Sistema", "systemsettings", "Batteria quasi scarica", "Collega l'alimentatore: resta il 5%.", 2) }

            Button { text: Notifications.doNotDisturb ? "Non disturbare: attivo" : "Non disturbare: spento"; onClicked: Notifications.doNotDisturb = !Notifications.doNotDisturb }

            Label { text: "Tasti e musica" }
            Row {
                spacing: 6
                Button { width: 70; text: "Vol −"; onClicked: { Shell.setVolume(Math.max(0, Shell.volume - 0.1)); Osd.show("volume", Math.round(Shell.volume * 100), ""); } }
                Button { width: 70; text: "Vol +"; onClicked: { Shell.setVolume(Math.min(1, Shell.volume + 0.1)); Osd.show("volume", Math.round(Shell.volume * 100), ""); } }
                Button { width: 74; text: "Luce"; onClicked: { Shell.setBrightness(Shell.brightness >= 1 ? 0.3 : Shell.brightness + 0.1); Osd.show("sun", Math.round(Shell.brightness * 100), ""); } }
            }
            Button { text: Media.available ? "Musica: chiudi il lettore" : "Musica: apri un lettore"; onClicked: Media.available = !Media.available }

            Label { text: "Batteria  " + Shell.batteryLevel + "%" + (Shell.charging ? " (in carica)" : "") }
            Row {
                spacing: 6
                Button { width: 70; text: "−10%"; onClicked: Shell.batteryLevel = Math.max(1, Shell.batteryLevel - 10) }
                Button { width: 70; text: "+10%"; onClicked: Shell.batteryLevel = Math.min(100, Shell.batteryLevel + 10) }
                Button { width: 74; text: "Carica"; onClicked: Shell.charging = !Shell.charging }
            }
            Button { text: Shell.batteryPresent ? "Senza batteria (desktop)" : "Con batteria (portatile)"; onClicked: Shell.batteryPresent = !Shell.batteryPresent }

            Label { text: "Rete  " + Shell.networkType }
            Row {
                spacing: 6
                Button { width: 70; text: "Wi‑Fi"; onClicked: { Shell.networkType = "wifi"; Shell.networkName = "Casa"; } }
                Button { width: 70; text: "Cavo"; onClicked: { Shell.networkType = "ethernet"; Shell.networkName = "Cablata 1"; } }
                Button { width: 74; text: "Nessuna"; onClicked: { Shell.networkType = "none"; Shell.networkName = ""; } }
            }

            Label { text: "Finestra" }
            Button { text: WindowState.visible ? "Chiudi la finestra di esempio" : "Apri la finestra di esempio"; onClicked: { WindowState.visible = !WindowState.visible; WindowState.active = true; } }
            Button { text: WindowState.maximized ? "Ripristina (esci da tutto schermo)" : "Ingrandisci a tutto schermo"; onClicked: { WindowState.visible = true; WindowState.maximized = !WindowState.maximized; } }
            Button { text: WindowState.active ? "Finestra: attiva" : "Finestra: inattiva"; onClicked: WindowState.active = !WindowState.active }

            Label { text: "Pannelli" }
            Button { text: "Launcher (Ctrl+Spazio)"; onClicked: Shell.toggleLauncher() }
            Button { text: "Centro di controllo"; onClicked: Shell.overlay === "control" ? Shell.hideOverlay() : Shell.showControlCenter() }
            Button { text: "Centro notifiche"; onClicked: Shell.overlay === "notifications" ? Shell.hideOverlay() : Shell.showNotifications() }
            Button { text: root.shellObject && root.shellObject.desktop.editing ? "Fine modifica widget" : "Modifica widget"; onClicked: root.shellObject.desktop.editing = !root.shellObject.desktop.editing }
            Button { text: "Cambia sfondo"; onClicked: Shell.overlay = "wallpaper" }
            Button { text: "Ricarica QML"; onClicked: preview.reload() }
        }

        component Label: Text {
            topPadding: 8
            color: Qt.rgba(1, 1, 1, 0.55)
            font.family: "Inter"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
        }
        component Button: MouseArea {
            id: button
            property string text
            width: parent ? parent.width : 200
            height: 30
            hoverEnabled: true
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: button.pressed ? Qt.rgba(1, 1, 1, 0.20) : button.containsMouse ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.07)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
            }
            Text {
                anchors.centerIn: parent
                text: button.text
                color: "white"
                font.family: "Inter"
                font.pixelSize: 12
            }
        }
    }
}
