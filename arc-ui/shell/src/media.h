// arc-shell — lettore multimediale attivo via MPRIS (org.mpris.MediaPlayer2.*):
// titolo, artista, copertina e comandi per widget e centro di controllo
#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantMap>

class Media : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString player READ player NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString artist READ artist NOTIFY changed)
    Q_PROPERTY(QString artUrl READ artUrl NOTIFY changed)
    Q_PROPERTY(bool playing READ playing NOTIFY changed)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY changed)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY changed)

public:
    explicit Media(QObject *parent = nullptr);

    bool available() const { return !m_service.isEmpty(); }
    QString player() const { return m_player; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString artUrl() const { return m_artUrl; }
    bool playing() const { return m_playing; }
    bool canGoNext() const { return m_canGoNext; }
    bool canGoPrevious() const { return m_canGoPrevious; }

    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();

Q_SIGNALS:
    void changed();

private Q_SLOTS:
    void nameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void propertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated);

private:
    void choose();
    void refresh();
    void apply(const QVariantMap &properties);
    void call(const QString &method);

    QStringList m_players;     // servizi MPRIS presenti, il più recente in fondo
    QString m_service;         // quello mostrato
    QString m_player;
    QString m_title;
    QString m_artist;
    QString m_artUrl;
    bool m_playing = false;
    bool m_canGoNext = false;
    bool m_canGoPrevious = false;
};
