// arc-shell — indicatore a schermo (OSD) di volume, luminosità e altro.
// I servizi di KDE (tasti audio di plasma-pa, powerdevil, kded) lo chiedono
// a org.kde.plasmashell /org/kde/osdService: nella sessione arc lo fornisce
// arc-shell al posto di plasmashell.
#pragma once

#include <QObject>

class Osd : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.osdService")

public:
    explicit Osd(QObject *parent = nullptr);

    bool registerService();

public Q_SLOTS:
    Q_SCRIPTABLE void volumeChanged(int percent, int maximumPercent = 100);
    Q_SCRIPTABLE void microphoneVolumeChanged(int percent);
    Q_SCRIPTABLE void mediaPlayerVolumeChanged(int percent, const QString &playerName, const QString &playerIconName);
    Q_SCRIPTABLE void brightnessChanged(int percent);
    Q_SCRIPTABLE void screenBrightnessChanged(const QString &displayId, const QString &label, int percent, bool showDisplayLabel);
    Q_SCRIPTABLE void keyboardBrightnessChanged(int percent);
    Q_SCRIPTABLE void kbdLayoutChanged(const QString &layoutName);
    Q_SCRIPTABLE void virtualDesktopChanged(const QString &currentVirtualDesktopName);
    Q_SCRIPTABLE void touchpadEnabledChanged(bool touchpadEnabled);
    Q_SCRIPTABLE void wifiEnabledChanged(bool wifiEnabled);
    Q_SCRIPTABLE void bluetoothEnabledChanged(bool bluetoothEnabled);
    Q_SCRIPTABLE void wwanEnabledChanged(bool wwanEnabled);
    Q_SCRIPTABLE void showText(const QString &icon, const QString &text);

Q_SIGNALS:
    // icon: nome di ArcIcon; value: 0..100 con barra, -1 solo testo
    void shown(const QString &icon, int value, const QString &text);
};
