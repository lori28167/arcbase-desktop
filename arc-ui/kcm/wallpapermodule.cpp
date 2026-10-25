#include "wallpapermodule.h"

#include <KPluginFactory>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>

K_PLUGIN_CLASS_WITH_JSON(WallpaperModule, "kcm_arcwallpaper.json")

namespace
{
QDBusMessage shellCall(const QString &method)
{
    return QDBusMessage::createMethodCall(QStringLiteral("org.arcbase.Shell"), QStringLiteral("/Shell"),
                                          QStringLiteral("org.arcbase.Shell"), method);
}
} // namespace

WallpaperModule::WallpaperModule(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    // La scelta si applica subito: niente pulsanti Applica/Predefiniti
    setButtons(NoAdditionalButton);
    refresh();
}

void WallpaperModule::refresh()
{
    const QDBusReply<QStringList> files = QDBusConnection::sessionBus().call(shellCall(QStringLiteral("wallpaperFiles")));
    const QDBusReply<QString> current = QDBusConnection::sessionBus().call(shellCall(QStringLiteral("currentWallpaper")));
    m_shellRunning = files.isValid();
    m_wallpapers = files.isValid() ? files.value() : QStringList();
    m_current = current.isValid() ? current.value() : QString();
    Q_EMIT changed();
}

void WallpaperModule::choose(const QString &path)
{
    QDBusMessage call = shellCall(QStringLiteral("applyWallpaper"));
    call << path;
    QDBusConnection::sessionBus().call(call);
    refresh();
}

void WallpaperModule::addImage(const QUrl &url)
{
    const QString source = url.toLocalFile();
    if (!QFile::exists(source)) {
        return;
    }
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + QStringLiteral("/Sfondi");
    QDir().mkpath(dir);
    const QString target = dir + QLatin1Char('/') + QFileInfo(source).fileName();
    if (source != target) {
        QFile::remove(target);
        QFile::copy(source, target);
    }
    choose(target);
}

#include "wallpapermodule.moc"
