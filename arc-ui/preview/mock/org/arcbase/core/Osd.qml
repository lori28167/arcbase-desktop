// Mock del servizio OSD (osd.cpp): il pannello "Simula" chiama show()
pragma Singleton
import QtQuick

QtObject {
    signal shown(string icon, int value, string text)
    function show(icon, value, text) { shown(icon, value, text); }
}
