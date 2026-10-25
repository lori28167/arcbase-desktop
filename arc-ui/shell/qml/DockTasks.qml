// Fonte delle icone della dock con libtaskmanager di KDE: app fissate e
// finestre aperte raggruppate per app (richiede l'interfaccia Wayland
// org_kde_plasma_window_management, concessa da org.arcbase.shell.desktop)
import QtQuick
import org.kde.taskmanager as TaskManager
import org.arcbase.core

Item {
    readonly property alias model: tasks

    function activate(index, isActive, isLauncher) {
        const modelIndex = tasks.makeModelIndex(index);
        if (isActive && !isLauncher) {
            tasks.requestToggleMinimized(modelIndex);
        } else {
            tasks.requestActivate(modelIndex);
        }
    }
    function newInstance(index) {
        tasks.requestNewInstance(tasks.makeModelIndex(index));
    }
    function close(index) {
        tasks.requestClose(tasks.makeModelIndex(index));
    }

    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        separateLaunchers: false
        launchInPlace: true
        sortMode: TaskManager.TasksModel.SortManual
        filterByVirtualDesktop: false
        filterByScreen: false
        filterByActivity: false
        launcherList: Shell.dockLaunchers
    }
}
