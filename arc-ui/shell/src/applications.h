// arc-shell — elenco delle applicazioni installate (KService) per il launcher
#pragma once

#include <KService>

#include <QAbstractListModel>

class Applications : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    // Tutte le app (storageId in ordine alfabetico), anche con una ricerca attiva
    Q_PROPERTY(QStringList allIds READ allIds NOTIFY appsChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        GenericNameRole,
        IconRole,
        StorageIdRole,
    };
    Q_ENUM(Roles)

    explicit Applications(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString filter() const { return m_filter; }
    void setFilter(const QString &filter);
    int count() const { return m_shown.size(); }

    // {name, genericName, iconName, storageId} della riga (pagine del Launchpad)
    Q_INVOKABLE QVariantMap get(int row) const;
    // {name, genericName, iconName, storageId} di un'app qualsiasi
    Q_INVOKABLE QVariantMap byId(const QString &storageId) const;
    // Categorie freedesktop (Office, Graphics...) per il nome delle cartelle
    Q_INVOKABLE QStringList categories(const QString &storageId) const;
    QStringList allIds() const;
    Q_INVOKABLE void launch(const QString &storageId);
    Q_INVOKABLE void launchAt(int row);
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void filterChanged();
    void countChanged();
    void appsChanged();
    void launched();

private:
    void applyFilter();

    KService::List m_all;
    KService::List m_shown;
    QString m_filter;
};
