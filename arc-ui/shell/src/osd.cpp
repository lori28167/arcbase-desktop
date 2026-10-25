#include "osd.h"

#include <QDBusConnection>

Osd::Osd(QObject *parent)
    : QObject(parent)
{
}

bool Osd::registerService()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    // Nella sessione Plasma il nome è di plasmashell: lì arc-shell non gira
    if (!bus.registerService(QStringLiteral("org.kde.plasmashell"))) {
        qWarning("arc-shell: org.kde.plasmashell è già occupato, niente OSD");
        return false;
    }
    return bus.registerObject(QStringLiteral("/org/kde/osdService"), this, QDBusConnection::ExportScriptableSlots);
}

void Osd::volumeChanged(int percent, int maximumPercent)
{
    const int value = maximumPercent > 0 ? percent * 100 / maximumPercent : percent;
    Q_EMIT shown(percent == 0 ? QStringLiteral("volume-off") : QStringLiteral("volume"), value, QString());
}

void Osd::microphoneVolumeChanged(int percent)
{
    Q_EMIT shown(QStringLiteral("microphone"), percent, QString());
}

void Osd::mediaPlayerVolumeChanged(int percent, const QString &playerName, const QString &playerIconName)
{
    Q_UNUSED(playerIconName)
    Q_EMIT shown(QStringLiteral("music"), percent, playerName);
}

void Osd::brightnessChanged(int percent)
{
    Q_EMIT shown(QStringLiteral("sun"), percent, QString());
}

void Osd::screenBrightnessChanged(const QString &displayId, const QString &label, int percent, bool showDisplayLabel)
{
    Q_UNUSED(displayId)
    Q_EMIT shown(QStringLiteral("sun"), percent, showDisplayLabel ? label : QString());
}

void Osd::keyboardBrightnessChanged(int percent)
{
    Q_EMIT shown(QStringLiteral("keyboard"), percent, QString());
}

void Osd::kbdLayoutChanged(const QString &layoutName)
{
    Q_EMIT shown(QStringLiteral("keyboard"), -1, layoutName);
}

void Osd::virtualDesktopChanged(const QString &currentVirtualDesktopName)
{
    Q_EMIT shown(QStringLiteral("grid"), -1, currentVirtualDesktopName);
}

void Osd::touchpadEnabledChanged(bool touchpadEnabled)
{
    Q_EMIT shown(QStringLiteral("touchpad"), -1, touchpadEnabled ? QStringLiteral("Touchpad attivo") : QStringLiteral("Touchpad disattivato"));
}

void Osd::wifiEnabledChanged(bool wifiEnabled)
{
    Q_EMIT shown(wifiEnabled ? QStringLiteral("wifi") : QStringLiteral("wifi-off"), -1,
                 wifiEnabled ? QStringLiteral("Wi‑Fi attivo") : QStringLiteral("Wi‑Fi disattivato"));
}

void Osd::bluetoothEnabledChanged(bool bluetoothEnabled)
{
    Q_EMIT shown(QStringLiteral("bluetooth"), -1,
                 bluetoothEnabled ? QStringLiteral("Bluetooth attivo") : QStringLiteral("Bluetooth disattivato"));
}

void Osd::wwanEnabledChanged(bool wwanEnabled)
{
    Q_EMIT shown(QStringLiteral("antenna"), -1, wwanEnabled ? QStringLiteral("Rete mobile attiva") : QStringLiteral("Rete mobile disattivata"));
}

void Osd::showText(const QString &icon, const QString &text)
{
    Q_UNUSED(icon)
    Q_EMIT shown(QStringLiteral("info"), -1, text);
}
