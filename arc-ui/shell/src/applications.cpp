#include "applications.h"

#include <KApplicationTrader>
#include <KIO/ApplicationLauncherJob>
#include <KSycoca>

#include <QCollator>

#include <algorithm>

Applications::Applications(QObject *parent)
    : QAbstractListModel(parent)
{
    refresh();
    // Nuove app installate (pacman, arc export...) compaiono senza riavviare
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &Applications::refresh);
}

void Applications::refresh()
{
    m_all = KApplicationTrader::query([](const KService::Ptr &service) {
        return !service->noDisplay() && service->showOnCurrentPlatform()
            && service->desktopEntryName() != QLatin1String("org.arcbase.shell");
    });
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    std::sort(m_all.begin(), m_all.end(), [&collator](const KService::Ptr &a, const KService::Ptr &b) {
        return collator.compare(a->name(), b->name()) < 0;
    });
    applyFilter();
    Q_EMIT appsChanged();
}

QStringList Applications::allIds() const
{
    QStringList ids;
    ids.reserve(m_all.size());
    for (const KService::Ptr &service : m_all) {
        ids << service->storageId();
    }
    return ids;
}

QVariantMap Applications::byId(const QString &storageId) const
{
    const KService::Ptr service = KService::serviceByStorageId(storageId);
    if (!service) {
        return {};
    }
    return {
        {QStringLiteral("name"), service->name()},
        {QStringLiteral("genericName"), service->genericName()},
        {QStringLiteral("iconName"), service->icon().isEmpty() ? QStringLiteral("application-x-executable") : service->icon()},
        {QStringLiteral("storageId"), service->storageId()},
    };
}

QStringList Applications::categories(const QString &storageId) const
{
    const KService::Ptr service = KService::serviceByStorageId(storageId);
    return service ? service->categories() : QStringList();
}

void Applications::setFilter(const QString &filter)
{
    if (filter == m_filter) {
        return;
    }
    m_filter = filter;
    Q_EMIT filterChanged();
    applyFilter();
}

void Applications::applyFilter()
{
    const QString needle = m_filter.trimmed();
    beginResetModel();
    m_shown.clear();
    for (const KService::Ptr &service : std::as_const(m_all)) {
        if (needle.isEmpty() || service->name().contains(needle, Qt::CaseInsensitive)
            || service->genericName().contains(needle, Qt::CaseInsensitive)
            || service->keywords().join(QLatin1Char(' ')).contains(needle, Qt::CaseInsensitive)
            || service->exec().section(QLatin1Char(' '), 0, 0).contains(needle, Qt::CaseInsensitive)) {
            m_shown << service;
        }
    }
    // Chi inizia con il testo cercato viene prima
    if (!needle.isEmpty()) {
        std::stable_sort(m_shown.begin(), m_shown.end(), [&needle](const KService::Ptr &a, const KService::Ptr &b) {
            return a->name().startsWith(needle, Qt::CaseInsensitive) && !b->name().startsWith(needle, Qt::CaseInsensitive);
        });
    }
    endResetModel();
    Q_EMIT countChanged();
}

int Applications::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_shown.size();
}

QVariant Applications::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid)) {
        return {};
    }
    const KService::Ptr &service = m_shown.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return service->name();
    case GenericNameRole:
        return service->genericName();
    case IconRole:
        return service->icon().isEmpty() ? QStringLiteral("application-x-executable") : service->icon();
    case StorageIdRole:
        return service->storageId();
    }
    return {};
}

QHash<int, QByteArray> Applications::roleNames() const
{
    return {
        {NameRole, "name"},
        {GenericNameRole, "genericName"},
        {IconRole, "iconName"},
        {StorageIdRole, "storageId"},
    };
}

QVariantMap Applications::get(int row) const
{
    if (row < 0 || row >= m_shown.size()) {
        return {};
    }
    const QModelIndex idx = index(row);
    return {
        {QStringLiteral("name"), data(idx, NameRole)},
        {QStringLiteral("genericName"), data(idx, GenericNameRole)},
        {QStringLiteral("iconName"), data(idx, IconRole)},
        {QStringLiteral("storageId"), data(idx, StorageIdRole)},
    };
}

void Applications::launch(const QString &storageId)
{
    const KService::Ptr service = KService::serviceByStorageId(storageId);
    if (!service) {
        qWarning("arc-shell: applicazione sconosciuta %s", qPrintable(storageId));
        return;
    }
    auto *job = new KIO::ApplicationLauncherJob(service);
    job->start();
    Q_EMIT launched();
}

void Applications::launchAt(int row)
{
    if (row >= 0 && row < m_shown.size()) {
        launch(m_shown.at(row)->storageId());
    }
}
