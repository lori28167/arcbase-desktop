#include "media.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusVariant>

namespace
{
const QString prefix = QStringLiteral("org.mpris.MediaPlayer2.");
const QString path = QStringLiteral("/org/mpris/MediaPlayer2");
const QString rootInterface = QStringLiteral("org.mpris.MediaPlayer2");
const QString playerInterface = QStringLiteral("org.mpris.MediaPlayer2.Player");
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");

QVariant unwrap(const QVariant &value)
{
    if (value.canConvert<QDBusVariant>()) {
        return value.value<QDBusVariant>().variant();
    }
    return value;
}

QVariantMap toMap(const QVariant &value)
{
    const QVariant v = unwrap(value);
    if (v.canConvert<QDBusArgument>()) {
        return qdbus_cast<QVariantMap>(v.value<QDBusArgument>());
    }
    return v.toMap();
}

QDBusMessage dbusCall(const QString &service, const QString &interface, const QString &method, const QVariantList &args = {})
{
    QDBusMessage message = QDBusMessage::createMethodCall(service, path, interface, method);
    message.setArguments(args);
    return QDBusConnection::sessionBus().call(message, QDBus::Block, 300);
}

QString playbackStatus(const QString &service)
{
    const QDBusMessage reply = dbusCall(service, propertiesInterface, QStringLiteral("Get"), {playerInterface, QStringLiteral("PlaybackStatus")});
    return reply.arguments().isEmpty() ? QString() : unwrap(reply.arguments().constFirst()).toString();
}
} // namespace

Media::Media(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    const QStringList names = bus.interface()->registeredServiceNames().value();
    for (const QString &name : names) {
        if (name.startsWith(prefix)) {
            m_players << name;
        }
    }
    bus.connect(QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"), QStringLiteral("org.freedesktop.DBus"),
                QStringLiteral("NameOwnerChanged"), this, SLOT(nameOwnerChanged(QString, QString, QString)));
    // Qualunque lettore: si rilegge lo stato di quello scelto
    bus.connect(QString(), path, propertiesInterface, QStringLiteral("PropertiesChanged"), this,
                SLOT(propertiesChanged(QString, QVariantMap, QStringList)));
    choose();
}

void Media::nameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner)
{
    Q_UNUSED(oldOwner)
    if (!name.startsWith(prefix)) {
        return;
    }
    m_players.removeAll(name);
    if (!newOwner.isEmpty()) {
        m_players << name;
    }
    choose();
}

void Media::propertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated)
{
    Q_UNUSED(invalidated)
    if (interface != playerInterface) {
        return;
    }
    // Un altro lettore ha iniziato a suonare: passa a quello
    if (changed.value(QStringLiteral("PlaybackStatus")).toString() == QLatin1String("Playing")) {
        choose();
        return;
    }
    refresh();
}

void Media::choose()
{
    QString chosen;
    for (const QString &service : std::as_const(m_players)) {
        if (playbackStatus(service) == QLatin1String("Playing")) {
            chosen = service;
        }
    }
    if (chosen.isEmpty()) {
        chosen = m_players.contains(m_service) ? m_service : (m_players.isEmpty() ? QString() : m_players.constLast());
    }
    m_service = chosen;
    refresh();
}

void Media::refresh()
{
    if (m_service.isEmpty()) {
        m_player.clear();
        m_title.clear();
        m_artist.clear();
        m_artUrl.clear();
        m_playing = m_canGoNext = m_canGoPrevious = false;
        Q_EMIT changed();
        return;
    }
    const QDBusMessage identity = dbusCall(m_service, propertiesInterface, QStringLiteral("Get"), {rootInterface, QStringLiteral("Identity")});
    m_player = identity.arguments().isEmpty() ? m_service.mid(prefix.size()).section(QLatin1Char('.'), 0, 0)
                                              : unwrap(identity.arguments().constFirst()).toString();
    const QDBusMessage all = dbusCall(m_service, propertiesInterface, QStringLiteral("GetAll"), {playerInterface});
    apply(all.arguments().isEmpty() ? QVariantMap() : toMap(all.arguments().constFirst()));
}

void Media::apply(const QVariantMap &properties)
{
    const QVariantMap metadata = toMap(properties.value(QStringLiteral("Metadata")));
    m_title = metadata.value(QStringLiteral("xesam:title")).toString();
    m_artist = unwrap(metadata.value(QStringLiteral("xesam:artist"))).toStringList().join(QStringLiteral(", "));
    m_artUrl = metadata.value(QStringLiteral("mpris:artUrl")).toString();
    m_playing = properties.value(QStringLiteral("PlaybackStatus")).toString() == QLatin1String("Playing");
    m_canGoNext = properties.value(QStringLiteral("CanGoNext")).toBool();
    m_canGoPrevious = properties.value(QStringLiteral("CanGoPrevious")).toBool();
    Q_EMIT changed();
}

void Media::call(const QString &method)
{
    if (m_service.isEmpty()) {
        return;
    }
    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(m_service, path, playerInterface, method));
}

void Media::playPause()
{
    m_playing = !m_playing; // risposta immediata, poi conferma da PropertiesChanged
    Q_EMIT changed();
    call(QStringLiteral("PlayPause"));
}

void Media::next()
{
    call(QStringLiteral("Next"));
}

void Media::previous()
{
    call(QStringLiteral("Previous"));
}
