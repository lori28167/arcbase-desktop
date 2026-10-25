// Modulo "Sfondo": elenco degli sfondi e scelta, tramite arc-shell (D-Bus)
#pragma once

#include <KQuickConfigModule>

#include <QStringList>

class WallpaperModule : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QStringList wallpapers READ wallpapers NOTIFY changed)
    Q_PROPERTY(QString current READ current NOTIFY changed)
    Q_PROPERTY(bool shellRunning READ shellRunning NOTIFY changed)

public:
    WallpaperModule(QObject *parent, const KPluginMetaData &data);

    QStringList wallpapers() const { return m_wallpapers; }
    QString current() const { return m_current; }
    bool shellRunning() const { return m_shellRunning; }

    // Applica subito, come lo sfondo di Plasma
    Q_INVOKABLE void choose(const QString &path);
    // Copia un'immagine in ~/Immagini/Sfondi e la sceglie
    Q_INVOKABLE void addImage(const QUrl &url);

Q_SIGNALS:
    void changed();

private:
    void refresh();

    QStringList m_wallpapers;
    QString m_current;
    bool m_shellRunning = false;
};
