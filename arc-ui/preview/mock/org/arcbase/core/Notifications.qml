// Mock del server notifiche: stesse regole di notifications.cpp (scadenza
// dopo 6 s, critiche fisse, mouse sopra = pausa, al massimo 5, le scadute
// vanno nello storico, "Non disturbare" le manda direttamente nello storico)
pragma Singleton
import QtQuick

ListModel {
    id: model

    property int nextId: 1
    property bool doNotDisturb: false
    readonly property HistoryModel history: HistoryModel {}

    function push(appName, icon, summary, body, urgency) {
        const item = { notificationId: nextId++, appName: appName, icon: "image://icon/" + icon,
                       summary: summary, body: body, actions: [], urgency: urgency, time: new Date(),
                       expires: urgency >= 2 ? 0 : Date.now() + 6000 };
        if (doNotDisturb && urgency < 2) {
            history.add(item);
            return;
        }
        insert(0, item);
        while (count > 5) expire(count - 1);
    }
    function rowOf(id) {
        for (let i = 0; i < count; ++i) if (get(i).notificationId === id) return i;
        return -1;
    }
    function expire(row) {
        const g = get(row);
        history.add({ notificationId: g.notificationId, appName: g.appName, icon: g.icon, summary: g.summary,
                      body: g.body, urgency: g.urgency, time: g.time });
        remove(row);
    }
    function dismiss(id) { const r = rowOf(id); if (r >= 0) remove(r); }
    function invoke(id, key) { console.log("azione", id, key); dismiss(id); }
    function setHovered(id, hovered) {
        const r = rowOf(id);
        if (r >= 0 && get(r).expires !== 0) setProperty(r, "expires", hovered ? -1 : Date.now() + 6000);
    }

    readonly property Timer expiry: Timer {
        interval: 250
        repeat: true
        running: model.count > 0
        onTriggered: {
            for (let i = model.count - 1; i >= 0; --i) {
                const e = model.get(i).expires;
                if (e > 0 && e < Date.now()) model.expire(i);
            }
        }
    }

    Component.onCompleted: {
        const old = (id, app, icon, summary, body, minutes) => history.add({ notificationId: id, appName: app, icon: "image://icon/" + icon,
            summary: summary, body: body, urgency: 1, time: new Date(Date.now() - minutes * 60000) });
        old(901, "Telegram", "telegram", "Luca", "Hai visto il nuovo trailer?", 95);
        old(902, "Telegram", "telegram", "Giulia", "Ci vediamo alle 18 in piazza?", 70);
        old(903, "Telegram", "telegram", "Gruppo Arc", "3 nuovi messaggi", 40);
        old(904, "Calendario", "office-calendar", "Revisione del progetto Arc", "Oggi alle 18:00 · Sala riunioni", 30);
        old(905, "Firefox", "firefox", "Download completato", "arcbase-desktop.iso (2,1 GB)", 20);
        history.add({ notificationId: 900, appName: "Konsole", icon: "image://icon/utilities-terminal",
                      summary: "Comando completato", body: "arc upgrade: 42 pacchetti aggiornati.", urgency: 1,
                      time: new Date(Date.now() - 3600 * 1000) });
        push("Discover", "plasmadiscover", "Aggiornamenti disponibili",
             "12 pacchetti Arch e 3 del layer Debian possono essere aggiornati.", 1);
    }
}
