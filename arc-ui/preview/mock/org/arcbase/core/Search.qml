// Mock della ricerca KRunner (search.cpp): calcoli, file, impostazioni finti
pragma Singleton
import QtQuick

QtObject {
    id: search
    property string query: ""
    property var results: []
    property bool busy: false
    signal launched()

    onQueryChanged: {
        const q = query.trim();
        if (q.length < 2) { results = []; return; }
        const list = [];
        if (/^[0-9+\-*\/(). ]+$/.test(q)) {
            try { list.push({ text: String(eval(q)), subtext: "Copia il risultato", icon: "accessories-calculator", category: "Calcolatrice" }); } catch (e) {}
        }
        list.push({ text: q + " — appunti.pdf", subtext: "/home/arc/Documenti", icon: "okular", category: "File" });
        list.push({ text: "Foto " + q + ".jpg", subtext: "/home/arc/Immagini/Vacanze", icon: "gwenview", category: "File" });
        list.push({ text: "Impostazioni: " + q, subtext: "Impostazioni di sistema", icon: "preferences-system", category: "Impostazioni" });
        list.push({ text: "Cerca “" + q + "” sul web", subtext: "DuckDuckGo", icon: "firefox", category: "Web" });
        results = list;
    }
    function run(i) { console.log("risultato", results[i] ? results[i].text : i); launched(); Shell.hideOverlay(); }
}
