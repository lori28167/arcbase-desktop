// Fonte di riserva se libtaskmanager non è disponibile: solo app fissate,
// con gli stessi ruoli di TasksModel
import QtQuick
import org.arcbase.core

Item {
    readonly property alias model: launchers

    function activate(index, isActive, isLauncher) {
        Applications.launch(launchers.get(index).storageId);
    }
    function newInstance(index) {
        activate(index, false, true);
    }
    function close(index) {}

    ListModel {
        id: launchers
    }

    Component.onCompleted: {
        for (const launcher of Shell.dockLaunchers) {
            const storageId = launcher.replace(/^applications:/, "");
            const appId = storageId.replace(/\.desktop$/, "");
            launchers.append({ AppId: appId, AppName: appId.split(".").pop(), display: appId, storageId: storageId,
                               IsLauncher: true, IsWindow: false, IsActive: false, IsStartup: false });
        }
    }
}
