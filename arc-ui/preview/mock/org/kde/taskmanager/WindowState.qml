// Mock: stato della finestra di esempio dell'anteprima (SampleWindow.qml),
// condiviso con TasksModel.activeTask/data come farebbe KWin
pragma Singleton
import QtQuick

QtObject {
    property bool visible: true
    property bool active: true
    property bool maximized: false
    property string title: "Nome App"
}
