#include "notifications.h"

#include <KService>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QTimer>
#include <QUrl>

namespace
{
constexpr int defaultTimeout = 6000;
constexpr int maxVisible = 5;
constexpr int maxHistory = 50;
} // namespace

// --- Modello comune ---------------------------------------------------------------------

int NotificationList::rowOf(uint id) const
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i).id == id) {
            return i;
        }
    }
    return -1;
}

void NotificationList::prepend(const NotificationItem &item)
{
    beginInsertRows(QModelIndex(), 0, 0);
    m_items.prepend(item);
    endInsertRows();
    Q_EMIT countChanged();
}

NotificationItem NotificationList::take(int row)
{
    beginRemoveRows(QModelIndex(), row, row);
    NotificationItem item = m_items.takeAt(row);
    endRemoveRows();
    Q_EMIT countChanged();
    return item;
}

int NotificationList::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_items.size();
}

QVariant NotificationList::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid)) {
        return {};
    }
    const NotificationItem &item = m_items.at(index.row());
    switch (role) {
    case IdRole:
        return item.id;
    case AppNameRole:
        return item.appName;
    case IconRole:
        return item.icon;
    case SummaryRole:
        return item.summary;
    case BodyRole:
        return item.body;
    case ActionsRole:
        return item.actions;
    case UrgencyRole:
        return item.urgency;
    case TimeRole:
        return item.time;
    }
    return {};
}

QHash<int, QByteArray> NotificationList::roleNames() const
{
    return {
        {IdRole, "notificationId"},
        {AppNameRole, "appName"},
        {IconRole, "icon"},
        {SummaryRole, "summary"},
        {BodyRole, "body"},
        {ActionsRole, "actions"},
        {UrgencyRole, "urgency"},
        {TimeRole, "time"},
    };
}

// --- Storico ------------------------------------------------------------------------------

void NotificationHistory::add(NotificationItem item)
{
    item.timer = nullptr;
    const int existing = rowOf(item.id);
    if (existing >= 0) {
        take(existing);
    }
    prepend(item);
    while (m_items.size() > maxHistory) {
        take(m_items.size() - 1);
    }
}

void NotificationHistory::dismiss(uint id)
{
    const int row = rowOf(id);
    if (row >= 0) {
        take(row);
    }
}

void NotificationHistory::clearAll()
{
    if (m_items.isEmpty()) {
        return;
    }
    beginResetModel();
    m_items.clear();
    endResetModel();
    Q_EMIT countChanged();
}

// --- Server -------------------------------------------------------------------------------

Notifications::Notifications(QObject *parent)
    : NotificationList(parent)
    , m_history(this)
{
}

bool Notifications::registerService()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(QStringLiteral("/org/freedesktop/Notifications"), this,
                            QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportScriptableSignals)) {
        qWarning("arc-shell: impossibile esportare /org/freedesktop/Notifications");
        return false;
    }
    const auto reply = bus.interface()->registerService(QStringLiteral("org.freedesktop.Notifications"),
                                                        QDBusConnectionInterface::ReplaceExistingService,
                                                        QDBusConnectionInterface::AllowReplacement);
    if (!reply.isValid() || reply.value() != QDBusConnectionInterface::ServiceRegistered) {
        qWarning("arc-shell: org.freedesktop.Notifications è già di un altro processo");
        return false;
    }
    return true;
}

void Notifications::setDoNotDisturb(bool enabled)
{
    if (enabled == m_doNotDisturb) {
        return;
    }
    m_doNotDisturb = enabled;
    Q_EMIT doNotDisturbChanged();
}

QStringList Notifications::GetCapabilities()
{
    return {QStringLiteral("body"), QStringLiteral("body-markup"), QStringLiteral("body-hyperlinks"),
            QStringLiteral("actions"), QStringLiteral("icon-static")};
}

QString Notifications::GetServerInformation(QString &vendor, QString &version, QString &spec_version)
{
    vendor = QStringLiteral("ArcBase");
    version = QStringLiteral("1.0");
    spec_version = QStringLiteral("1.2");
    return QStringLiteral("arc-shell");
}

QString Notifications::iconFor(const QString &appIcon, const QVariantMap &hints) const
{
    QString icon = appIcon;
    if (icon.isEmpty()) {
        icon = hints.value(QStringLiteral("image-path")).toString();
    }
    if (icon.isEmpty()) {
        const QString desktopEntry = hints.value(QStringLiteral("desktop-entry")).toString();
        if (const KService::Ptr service = KService::serviceByDesktopName(desktopEntry)) {
            icon = service->icon();
        }
    }
    // Il QML riceve un URL: file locale o icona del tema (image://icon/)
    if (icon.startsWith(QLatin1Char('/'))) {
        return QUrl::fromLocalFile(icon).toString();
    }
    if (icon.startsWith(QLatin1String("file://"))) {
        return icon;
    }
    return QStringLiteral("image://icon/") + (icon.isEmpty() ? QStringLiteral("dialog-information") : icon);
}

uint Notifications::Notify(const QString &app_name, uint replaces_id, const QString &app_icon, const QString &summary,
                           const QString &body, const QStringList &actions, const QVariantMap &hints, int expire_timeout)
{
    NotificationItem item;
    item.id = replaces_id && rowOf(replaces_id) >= 0 ? replaces_id : m_nextId++;
    item.appName = app_name;
    item.icon = iconFor(app_icon, hints);
    item.summary = summary;
    item.body = body;
    for (int i = 0; i + 1 < actions.size(); i += 2) {
        // "default" è il clic sulla notifica, non un pulsante
        if (actions.at(i) != QLatin1String("default")) {
            item.actions << QVariantMap{{QStringLiteral("key"), actions.at(i)}, {QStringLiteral("label"), actions.at(i + 1)}};
        }
    }
    item.urgency = hints.value(QStringLiteral("urgency"), 1).toInt();
    item.resident = hints.value(QStringLiteral("resident")).toBool();
    item.time = QDateTime::currentDateTime();
    // Le critiche restano finché non vengono chiuse
    item.timeout = expire_timeout < 0 ? (item.urgency >= 2 ? 0 : defaultTimeout) : expire_timeout;

    // "Non disturbare": niente a schermo (tranne le critiche), solo storico
    if (m_doNotDisturb && item.urgency < 2) {
        m_history.add(item);
        return item.id;
    }

    const uint id = item.id;
    if (item.timeout > 0) {
        item.timer = new QTimer(this);
        item.timer->setSingleShot(true);
        item.timer->setInterval(item.timeout);
        connect(item.timer, &QTimer::timeout, this, [this, id] {
            close(id, Expired);
        });
        item.timer->start();
    }

    const int existing = rowOf(id);
    if (existing >= 0) {
        delete m_items[existing].timer;
        m_items[existing] = item;
        Q_EMIT dataChanged(index(existing), index(existing));
        return id;
    }

    // Le più recenti in cima; oltre il limite scadono le più vecchie
    prepend(item);
    while (m_items.size() > maxVisible) {
        close(m_items.constLast().id, Expired);
    }
    return id;
}

void Notifications::CloseNotification(uint id)
{
    close(id, ClosedByCall);
    m_history.dismiss(id);
}

void Notifications::dismiss(uint id)
{
    close(id, Dismissed);
}

void Notifications::invoke(uint id, const QString &actionKey)
{
    const int row = rowOf(id);
    if (row < 0) {
        return;
    }
    Q_EMIT ActionInvoked(id, actionKey);
    if (!m_items.at(row).resident) {
        close(id, Dismissed);
    }
}

void Notifications::setHovered(uint id, bool hovered)
{
    const int row = rowOf(id);
    if (row < 0 || !m_items.at(row).timer) {
        return;
    }
    if (hovered) {
        m_items.at(row).timer->stop();
    } else {
        m_items.at(row).timer->start(); // riparte da capo
    }
}

void Notifications::close(uint id, CloseReason reason)
{
    const int row = rowOf(id);
    if (row < 0) {
        return;
    }
    NotificationItem item = take(row);
    if (item.timer) {
        item.timer->deleteLater();
    }
    // Le scadute restano nel centro notifiche
    if (reason == Expired) {
        m_history.add(item);
    }
    Q_EMIT NotificationClosed(id, reason);
}
