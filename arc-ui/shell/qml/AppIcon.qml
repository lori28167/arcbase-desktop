// Icona di un'app nella shell (dock, Launchpad, cartelle, ricerca, notifiche):
// l'icona del tema (Ticly Sequoia, poi Breeze o quella dell'app) così com'è.
import QtQuick
import org.arcbase.core
import "."

Item {
    id: icon

    property string name
    // In alternativa un URL (notifiche): image://icon/<nome> o un file
    property string url
    readonly property string iconName: url.startsWith("image://icon/") ? url.substring(13) : url !== "" ? "" : name
    // Simbolo di arc (ArcIcon) al posto di un'icona del tema (es. Launchpad)
    property string glyph
    property real pressedOpacity: 1

    implicitWidth: 64
    implicitHeight: 64

    ArcIcon {
        visible: icon.glyph !== ""
        anchors.centerIn: parent
        width: icon.width * 0.5
        height: width
        name: icon.glyph
        color: Theme.text
        strokeWidth: 1.6
        opacity: icon.pressedOpacity
    }
    // Le icone Ticly hanno già il margine (corpo all'80%); quelle delle app
    // riempiono tutto il riquadro, quindi si riducono alla stessa misura
    readonly property bool ownShape: iconName !== "" && Shell.hasOwnShape(iconName)
    Image {
        visible: icon.glyph === ""
        anchors.centerIn: parent
        width: icon.ownShape ? icon.width : icon.width * Theme.iconBody
        height: width
        source: icon.iconName !== "" ? "image://icon/" + icon.iconName : icon.url
        sourceSize.width: Math.ceil(icon.width * 2)
        sourceSize.height: Math.ceil(icon.width * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        opacity: icon.pressedOpacity
    }
}
