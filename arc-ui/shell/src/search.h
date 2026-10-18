// arc-shell — ricerca stile Spotlight nel Launchpad con KRunner (KF6, senza
// grafica di Plasma): file (Baloo), impostazioni, calcoli, conversioni,
// finestre, documenti recenti, comandi... Le app le mostra già la griglia.
#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>

#include <KRunner/QueryMatch>

namespace KRunner
{
class RunnerManager;
}

class Search : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    // [{text, subtext, icon, category}] ordinati per pertinenza
    Q_PROPERTY(QVariantList results READ results NOTIFY resultsChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit Search(QObject *parent = nullptr);

    QString query() const { return m_query; }
    void setQuery(const QString &query);
    QVariantList results() const { return m_results; }
    bool busy() const { return m_busy; }

    Q_INVOKABLE void run(int index);

Q_SIGNALS:
    void queryChanged();
    void resultsChanged();
    void busyChanged();
    void launched();

private:
    void update(const QList<KRunner::QueryMatch> &matches);
    void setBusy(bool busy);

    KRunner::RunnerManager *m_manager;
    QTimer m_delay;
    QString m_query;
    QList<KRunner::QueryMatch> m_matches;
    QVariantList m_results;
    bool m_busy = false;
};
