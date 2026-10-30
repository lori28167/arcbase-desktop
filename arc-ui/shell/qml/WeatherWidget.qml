// Widget Meteo (Open-Meteo, senza chiave): città dalle opzioni ("city").
// S: icona e temperatura · M: città, condizioni, massima e minima · L: + 5 giorni
// Contatta geocoding-api.open-meteo.com e api.open-meteo.com solo quando il
// widget è sulla scrivania; si aggiorna ogni 30 minuti.
import QtQuick
import org.arcbase.core
import "."

Item {
    id: widget

    property string size: "m"
    property var options: ({})
    signal optionChanged(string key, var value)

    readonly property string city: (options.city || "Trento").trim()
    property string place: ""
    property real temperature: NaN
    property int code: -1
    property bool day: true
    property var daily: []          // [{date, code, max, min}]
    property string error: ""
    // Le risposte di una ricerca superata (città cambiata) si ignorano
    property int serial: 0

    onCityChanged: Qt.callLater(refresh)
    Component.onCompleted: Qt.callLater(refresh)
    Timer { interval: 30 * 60 * 1000; running: true; repeat: true; onTriggered: widget.refresh() }

    // Senza rete (di solito all'avvio della sessione, prima che NetworkManager
    // si colleghi) o con il servizio fuori uso si riprova presto e appena la
    // rete cambia, non dopo mezz'ora
    property bool offline: false
    function fail() {
        widget.error = "Meteo non disponibile";
        widget.offline = true;
        retry.restart();
    }
    Timer { id: retry; interval: 60 * 1000; onTriggered: widget.refresh() }
    Connections {
        target: Shell
        ignoreUnknownSignals: true
        function onNetworkChanged() {
            if (widget.offline && Shell.networkType !== "none") Qt.callLater(widget.refresh);
        }
    }

    function get(url, done) {
        const id = serial;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || id !== widget.serial) return;
            if (xhr.status !== 200) { widget.fail(); return; }
            try { done(JSON.parse(xhr.responseText)); } catch (e) { widget.fail(); }
        };
        xhr.open("GET", url);
        xhr.send();
    }
    function refresh() {
        ++serial;
        offline = false;
        retry.stop();
        if (city === "") return;
        get("https://geocoding-api.open-meteo.com/v1/search?count=1&language=it&format=json&name=" + encodeURIComponent(city), geo => {
            if (!geo.results || geo.results.length === 0) { widget.error = "Città non trovata"; return; }
            const r = geo.results[0];
            widget.place = r.name;
            get("https://api.open-meteo.com/v1/forecast?latitude=" + r.latitude + "&longitude=" + r.longitude
                + "&current=temperature_2m,weather_code,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min"
                + "&timezone=auto&forecast_days=6", f => {
                widget.error = "";
                widget.offline = false;
                widget.temperature = f.current.temperature_2m;
                widget.code = f.current.weather_code;
                widget.day = f.current.is_day === 1;
                const days = [];
                for (let i = 0; i < f.daily.time.length; ++i)
                    days.push({ date: f.daily.time[i], code: f.daily.weather_code[i], max: f.daily.temperature_2m_max[i], min: f.daily.temperature_2m_min[i] });
                widget.daily = days;
            });
        });
    }

    // Codici WMO → icona e testo
    function icon(c, isDay) {
        if (c === 0) return isDay ? "sun" : "moon-small";
        if (c <= 2) return "cloud-sun";
        if (c === 3) return "cloud";
        if (c === 45 || c === 48) return "fog";
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return "snow";
        if (c >= 95) return "storm";
        if (c >= 51) return "rain";
        return "cloud";
    }
    function label(c) {
        if (c === 0) return "Sereno";
        if (c === 1) return "Poco nuvoloso";
        if (c === 2) return "Parzialmente nuvoloso";
        if (c === 3) return "Coperto";
        if (c === 45 || c === 48) return "Nebbia";
        if (c >= 51 && c <= 57) return "Pioviggine";
        if (c >= 61 && c <= 67) return "Pioggia";
        if (c >= 71 && c <= 77) return "Neve";
        if (c >= 80 && c <= 82) return "Rovesci";
        if (c === 85 || c === 86) return "Rovesci di neve";
        if (c >= 95) return "Temporale";
        return "";
    }
    function deg(v) { return isNaN(v) ? "--" : Math.round(v) + "°"; }

    // --- Errore o caricamento
    Column {
        visible: widget.code < 0
        anchors.centerIn: parent
        spacing: 8
        ArcIcon { anchors.horizontalCenter: parent.horizontalCenter; width: 28; height: 28; name: "cloud"; color: Theme.sub }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: widget.error !== "" ? widget.error : "Meteo di " + widget.city + "…"
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 13
        }
    }

    Item {
        visible: widget.code >= 0
        anchors.fill: parent
        anchors.margins: 20

        // Città
        Row {
            spacing: 5
            ArcIcon { anchors.verticalCenter: parent.verticalCenter; width: 13; height: 13; name: "location"; color: Theme.muted; strokeWidth: 2 }
            Text {
                text: widget.place
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: widget.size === "s" ? 13 : 15
                font.weight: Font.DemiBold
            }
        }
        // Temperatura
        Text {
            y: 22
            text: widget.deg(widget.temperature)
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: widget.size === "s" ? 44 : 58
            font.weight: Font.Light
        }
        ArcIcon {
            anchors.right: parent.right
            y: widget.size === "s" ? 2 : 4
            width: widget.size === "s" ? 30 : 40; height: width
            name: widget.icon(widget.code, widget.day)
            color: Theme.text
            strokeWidth: 1.6
        }
        Column {
            visible: widget.size !== "s"
            anchors.left: parent.left
            y: widget.size === "l" ? 96 : parent.height - height
            spacing: 2
            Text { text: widget.label(widget.code); color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
            Text {
                visible: widget.daily.length > 0
                text: widget.daily.length > 0 ? "Max " + widget.deg(widget.daily[0].max) + "  Min " + widget.deg(widget.daily[0].min) : ""
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: 13
            }
        }
        Text {
            visible: widget.size === "s"
            anchors.bottom: parent.bottom
            text: widget.label(widget.code)
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 12
            width: parent.width
            elide: Text.ElideRight
        }

        // L: prossimi giorni
        Column {
            visible: widget.size === "l"
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: 6
            Rectangle { width: parent.width; height: 1; color: Theme.border }
            Repeater {
                model: widget.daily.slice(1, 6)
                Item {
                    required property var modelData
                    width: parent.width
                    height: 26
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const d = Qt.locale().dayName(new Date(modelData.date + "T12:00:00").getDay(), Locale.ShortFormat);
                            return d.charAt(0).toUpperCase() + d.slice(1);
                        }
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 14
                    }
                    ArcIcon { anchors.centerIn: parent; width: 20; height: 20; name: widget.icon(modelData.code, true); color: Theme.text }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: widget.deg(modelData.min) + "  " + widget.deg(modelData.max)
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.features: ({ "tnum": 1 })
                    }
                }
            }
        }
    }
}
