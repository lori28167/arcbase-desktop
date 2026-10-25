// Mock dello storico notifiche (NotificationHistory in notifications.cpp)
import QtQuick

ListModel {
    function add(item) {
        insert(0, { notificationId: item.notificationId, appName: item.appName, icon: item.icon,
                    summary: item.summary, body: item.body, actions: [], urgency: item.urgency, time: item.time });
        while (count > 50) remove(count - 1);
    }
    function dismiss(id) {
        for (let i = 0; i < count; ++i) if (get(i).notificationId === id) { remove(i); return; }
    }
    function clearAll() { clear(); }
}
