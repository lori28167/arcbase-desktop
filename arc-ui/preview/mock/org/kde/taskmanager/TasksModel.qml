// Mock di libtaskmanager: app fissate; un clic "apre" l'app (puntino),
// un clic sull'app attiva la minimizza, clic centrale = nuova istanza
import QtQuick

ListModel {
    id: model

    enum GroupMode { GroupDisabled, GroupApplications }
    enum SortMode { SortDisabled, SortManual, SortAlpha }

    property int groupMode
    property bool groupInline
    property bool separateLaunchers
    property bool launchInPlace
    property int sortMode
    property bool filterByVirtualDesktop
    property bool filterByScreen
    property bool filterByActivity
    property var launcherList: []

    onLauncherListChanged: {
        clear();
        for (const l of launcherList) {
            const id = l.replace(/^applications:/, "").replace(/\.desktop$/, "");
            const running = id === "org.kde.dolphin" || id === "firefox";
            append({ AppId: id, AppName: id.split(".").pop(), display: id, IsLauncher: !running,
                     IsWindow: running, IsActive: id === "firefox", IsStartup: false });
        }
    }
    // Finestra attiva (la finestra di esempio dell'anteprima)
    property var activeTask: makeActiveTask()
    function makeActiveTask() {
        return { valid: WindowState.visible && WindowState.active, row: 0, maximized: WindowState.maximized,
                 title: WindowState.title };
    }
    readonly property Connections windowState: Connections {
        target: WindowState
        function onVisibleChanged() { model.activeTask = model.makeActiveTask(); }
        function onActiveChanged() { model.activeTask = model.makeActiveTask(); }
        function onMaximizedChanged() { model.activeTask = model.makeActiveTask(); }
        function onTitleChanged() { model.activeTask = model.makeActiveTask(); }
    }
    function data(index, role) {
        if (!index || !index.valid) return undefined;
        if (role === AbstractTasksModel.IsMaximized) return WindowState.maximized;
        if (role === AbstractTasksModel.IsFullScreen) return false;
        if (role === AbstractTasksModel.AppName || role === Qt.DisplayRole) return WindowState.title;
        return undefined;
    }
    function isWindowIndex(i) { return typeof i === "object" && i !== null; }
    function requestToggleMaximized(i) { if (isWindowIndex(i)) WindowState.maximized = !WindowState.maximized; }

    function makeModelIndex(i) { return i; }
    function requestActivate(i) {
        for (let r = 0; r < count; ++r) setProperty(r, "IsActive", r === i);
        setProperty(i, "IsLauncher", false);
        setProperty(i, "IsWindow", true);
    }
    function requestToggleMinimized(i) {
        if (isWindowIndex(i)) { WindowState.visible = false; return; }
        setProperty(i, "IsActive", false);
    }
    function requestNewInstance(i) { requestActivate(i); }
    function requestClose(i) {
        if (isWindowIndex(i)) { WindowState.visible = false; WindowState.maximized = false; return; }
        setProperty(i, "IsActive", false);
        setProperty(i, "IsWindow", false);
        setProperty(i, "IsLauncher", true);
    }
}
