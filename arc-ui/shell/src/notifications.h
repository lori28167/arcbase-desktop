// arc-shell — server delle notifiche (org.freedesktop.Notifications 1.2),
// notifiche visibili e storico per il centro notifiche
#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QHash>
#include <QStringList>
#include <QVariantMap>

class QTimer;

struct NotificationItem {
    uint id = 0;
    QString appName;
    QString icon;
    QString summary;
    QString body;
    QVariantList actions; // [{key, label}]
    int urgency = 1;
    bool resident = false;
    int timeout = 0; // ms, 0 = finché non viene chiusa
    QDateTime time;
    QTimer *timer = nullptr;
};

// Modello comune: le notifiche a schermo e lo storico usano gli stessi ruoli
class NotificationList : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        AppNameRole,
        IconRole,
        SummaryRole,
        BodyRole,
        ActionsRole,
        UrgencyRole,
        TimeRole,
    };
    Q_ENUM(Roles)

    using QAbstractListModel::QAbstractListModel;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return m_items.size(); }

Q_SIGNALS:
    void countChanged();

protected:
    int rowOf(uint id) const;
    void prepend(const NotificationItem &item);
    NotificationItem take(int row);

    QList<NotificationItem> m_items;
};

// Storico (centro notifiche): le notifiche scadute o arrivate in "Non disturbare"
class NotificationHistory : public NotificationList
{
    Q_OBJECT

public:
    using NotificationList::NotificationList;

    void add(NotificationItem item);
    Q_INVOKABLE void dismiss(uint id);
    Q_INVOKABLE void clearAll();
};

class Notifications : public NotificationList
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")
    Q_PROPERTY(bool doNotDisturb READ doNotDisturb WRITE setDoNotDisturb NOTIFY doNotDisturbChanged)
    Q_PROPERTY(NotificationHistory *history READ history CONSTANT)

public:
    // Motivi di chiusura (specifica freedesktop)
    enum CloseReason { Expired = 1, Dismissed = 2, ClosedByCall = 3 };

    explicit Notifications(QObject *parent = nullptr);

    // Prende il nome org.freedesktop.Notifications sul bus di sessione
    bool registerService();

    bool doNotDisturb() const { return m_doNotDisturb; }
    void setDoNotDisturb(bool enabled);
    NotificationHistory *history() { return &m_history; }

    Q_INVOKABLE void dismiss(uint id);
    Q_INVOKABLE void invoke(uint id, const QString &actionKey);
    // Il mouse sopra la notifica ne ferma la scadenza
    Q_INVOKABLE void setHovered(uint id, bool hovered);

public Q_SLOTS:
    Q_SCRIPTABLE uint Notify(const QString &app_name, uint replaces_id, const QString &app_icon, const QString &summary,
                             const QString &body, const QStringList &actions, const QVariantMap &hints,
                             int expire_timeout);
    Q_SCRIPTABLE void CloseNotification(uint id);
    Q_SCRIPTABLE QStringList GetCapabilities();
    Q_SCRIPTABLE QString GetServerInformation(QString &vendor, QString &version, QString &spec_version);

Q_SIGNALS:
    Q_SCRIPTABLE void NotificationClosed(uint id, uint reason);
    Q_SCRIPTABLE void ActionInvoked(uint id, const QString &action_key);
    void doNotDisturbChanged();

private:
    void close(uint id, CloseReason reason);
    QString iconFor(const QString &appIcon, const QVariantMap &hints) const;

    NotificationHistory m_history;
    bool m_doNotDisturb = false;
    uint m_nextId = 1;
};
