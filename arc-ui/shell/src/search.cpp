#include "search.h"

#include <KRunner/AbstractRunner>
#include <KRunner/RunnerManager>

#include <QIcon>

#include <algorithm>

namespace
{
constexpr int maxResults = 12;
// Le app sono già nella griglia del Launchpad
const QString appsRunner = QStringLiteral("krunner_services");
} // namespace

Search::Search(QObject *parent)
    : QObject(parent)
    , m_manager(new KRunner::RunnerManager(this))
{
    // Si cerca un attimo dopo l'ultima lettera: meno lavoro mentre si scrive
    m_delay.setSingleShot(true);
    m_delay.setInterval(140);
    connect(&m_delay, &QTimer::timeout, this, [this] {
        if (m_query.trimmed().size() < 2) {
            m_manager->reset();
            update({});
            setBusy(false);
            return;
        }
        setBusy(true);
        m_manager->launchQuery(m_query);
    });
    connect(m_manager, &KRunner::RunnerManager::matchesChanged, this, &Search::update);
    connect(m_manager, &KRunner::RunnerManager::queryFinished, this, [this] {
        setBusy(false);
    });
}

void Search::setQuery(const QString &query)
{
    if (query == m_query) {
        return;
    }
    m_query = query;
    Q_EMIT queryChanged();
    m_delay.start();
}

void Search::setBusy(bool busy)
{
    if (busy != m_busy) {
        m_busy = busy;
        Q_EMIT busyChanged();
    }
}

void Search::update(const QList<KRunner::QueryMatch> &matches)
{
    QList<KRunner::QueryMatch> list;
    for (const KRunner::QueryMatch &match : matches) {
        if (match.isValid() && match.isEnabled() && (!match.runner() || match.runner()->id() != appsRunner)) {
            list << match;
        }
    }
    std::stable_sort(list.begin(), list.end(), [](const KRunner::QueryMatch &a, const KRunner::QueryMatch &b) {
        if (a.categoryRelevance() != b.categoryRelevance()) {
            return a.categoryRelevance() > b.categoryRelevance();
        }
        return a.relevance() > b.relevance();
    });
    if (list.size() > maxResults) {
        list.resize(maxResults);
    }

    m_matches = list;
    m_results.clear();
    for (const KRunner::QueryMatch &match : std::as_const(m_matches)) {
        QString icon = match.iconName();
        if (icon.isEmpty()) {
            icon = match.icon().name();
        }
        m_results << QVariantMap{
            {QStringLiteral("text"), match.text()},
            {QStringLiteral("subtext"), match.subtext()},
            {QStringLiteral("icon"), icon.isEmpty() ? QStringLiteral("system-search") : icon},
            {QStringLiteral("category"), match.matchCategory()},
        };
    }
    Q_EMIT resultsChanged();
}

void Search::run(int index)
{
    if (index < 0 || index >= m_matches.size()) {
        return;
    }
    if (m_manager->run(m_matches.at(index))) {
        Q_EMIT launched();
    }
}
