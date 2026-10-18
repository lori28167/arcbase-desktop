// Finestra attiva da libtaskmanager di KDE: titolo, app, stato ingrandito e
// comandi (riduci, ingrandisci, chiudi). Caricato da ActiveWindow.qml.
import QtQuick
import org.kde.taskmanager as TaskManager

Item {
    id: source

    // TasksModel.data() non notifica: si rilegge a ogni cambiamento del modello
    property int revision: 0
    readonly property var index: revision >= 0 ? tasks.activeTask : undefined
    readonly property bool present: index !== undefined && index.valid
    readonly property bool maximized: present && tasks.data(index, TaskManager.AbstractTasksModel.IsMaximized) === true
    readonly property bool fullScreen: present && tasks.data(index, TaskManager.AbstractTasksModel.IsFullScreen) === true
    readonly property string appName: present ? (tasks.data(index, TaskManager.AbstractTasksModel.AppName) || "") : ""
    readonly property string title: present ? (tasks.data(index, Qt.DisplayRole) || "") : ""

    function minimize() { if (present) tasks.requestToggleMinimized(index); }
    function toggleMaximize() { if (present) tasks.requestToggleMaximized(index); }
    function close() { if (present) tasks.requestClose(index); }

    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: true
        filterByScreen: false
        filterByActivity: false
        onActiveTaskChanged: source.revision++
        onDataChanged: source.revision++
        onCountChanged: source.revision++
    }
}
