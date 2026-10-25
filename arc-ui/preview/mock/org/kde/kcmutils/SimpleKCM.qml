// Mock di KCM.SimpleKCM (KCMUtils): pagina scorrevole con margini
import QtQuick
import QtQuick.Controls

ScrollView {
    id: page
    default property alias content: holder.data
    contentWidth: availableWidth
    padding: 20
    Item {
        id: holder
        width: page.availableWidth
        height: childrenRect.height
    }
}
