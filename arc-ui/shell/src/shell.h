// arc-shell — stato di sistema e azioni esposte al QML e su D-Bus
// (org.arcbase.Shell /Shell: toggleLauncher, showControlCenter, hideOverlay...)
#pragma once

#include <QObject>
#include <QProcess>
#include <QSettings>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QWindow>

class Shell : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.arcbase.Shell")

    // Pannello a tutto schermo aperto:
    // "" | "launcher" | "control" | "notifications" | "wallpaper"
    Q_PROPERTY(QString overlay READ overlay WRITE setOverlay NOTIFY overlayChanged)

    Q_PROPERTY(bool batteryPresent READ batteryPresent NOTIFY batteryChanged)
    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY batteryChanged)
    Q_PROPERTY(bool charging READ charging NOTIFY batteryChanged)

    // "wifi" | "ethernet" | "none"
    Q_PROPERTY(QString networkType READ networkType NOTIFY networkChanged)
    Q_PROPERTY(QString networkName READ networkName NOTIFY networkChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled WRITE setWifiEnabled NOTIFY networkChanged)
    // [{ssid, signal, secure, active}] dall'ultima scansione
    Q_PROPERTY(QVariantList wifiNetworks READ wifiNetworks NOTIFY wifiNetworksChanged)

    Q_PROPERTY(bool bluetoothAvailable READ bluetoothAvailable NOTIFY bluetoothChanged)
    Q_PROPERTY(bool bluetoothEnabled READ bluetoothEnabled WRITE setBluetoothEnabled NOTIFY bluetoothChanged)

    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY volumeChanged)
    // 0..1, oppure -1 se lo schermo non lo permette (desktop, VM)
    Q_PROPERTY(double brightness READ brightness NOTIFY brightnessChanged)

    Q_PROPERTY(QString userName READ userName CONSTANT)
    Q_PROPERTY(QString fullName READ fullName CONSTANT)
    Q_PROPERTY(QString wallpaper READ wallpaper WRITE setWallpaper NOTIFY wallpaperChanged)
    Q_PROPERTY(QStringList dockLaunchers READ dockLaunchers CONSTANT)
    // Launchpad: ordine delle app e cartelle (JSON: [{type, id, name, apps}])
    Q_PROPERTY(QString launchpadLayout READ launchpadLayout WRITE setLaunchpadLayout NOTIFY launchpadLayoutChanged)
    // Luce notturna di KWin (toni caldi)
    Q_PROPERTY(bool nightLight READ nightLight WRITE setNightLight NOTIFY nightLightChanged)
    // Widget della scrivania (JSON: [{id, kind, size, col, row, options}])
    Q_PROPERTY(QString widgetLayout READ widgetLayout WRITE setWidgetLayout NOTIFY widgetLayoutChanged)

public:
    // Stessi valori di LayerShellQt::Window
    enum Layer { LayerBackground = 0, LayerBottom = 1, LayerTop = 2, LayerOverlay = 3 };
    Q_ENUM(Layer)
    enum Anchor { AnchorTop = 1, AnchorBottom = 2, AnchorLeft = 4, AnchorRight = 8 };
    Q_ENUM(Anchor)
    enum Keyboard { KeyboardNone = 0, KeyboardExclusive = 1, KeyboardOnDemand = 2 };
    Q_ENUM(Keyboard)

    explicit Shell(QObject *parent = nullptr);

    QString overlay() const { return m_overlay; }
    void setOverlay(const QString &overlay);

    bool batteryPresent() const { return m_batteryPresent; }
    int batteryLevel() const { return m_batteryLevel; }
    bool charging() const { return m_charging; }
    QString networkType() const { return m_networkType; }
    QString networkName() const { return m_networkName; }
    bool wifiEnabled() const { return m_wifiEnabled; }
    void setWifiEnabled(bool enabled);
    QVariantList wifiNetworks() const { return m_wifiNetworks; }
    bool bluetoothAvailable() const { return m_bluetoothAvailable; }
    bool bluetoothEnabled() const { return m_bluetoothEnabled; }
    void setBluetoothEnabled(bool enabled);
    double volume() const { return m_volume; }
    bool muted() const { return m_muted; }
    double brightness() const { return m_brightness; }
    QString userName() const;
    QString fullName() const;
    QString wallpaper() const;
    void setWallpaper(const QString &url);
    QStringList dockLaunchers() const;
    QString widgetLayout() const;
    void setWidgetLayout(const QString &layout);
    QString launchpadLayout() const;
    void setLaunchpadLayout(const QString &layout);
    bool nightLight() const { return m_nightLight; }
    void setNightLight(bool enabled);

    // Superficie layer-shell: va chiamata prima di mostrare la finestra
    Q_INVOKABLE void configureLayer(QWindow *window, const QString &scope, int layer, int anchors,
                                    int exclusiveZone, int keyboard, int marginTop = 0, int marginRight = 0,
                                    int marginBottom = 0, int marginLeft = 0);
    // Cambia margini e spazio riservato di una superficie già mostrata
    // (topbar attaccata ai bordi, dock nascosta con un'app a tutto schermo)
    Q_INVOKABLE void updateLayer(QWindow *window, int exclusiveZone, int marginTop = 0, int marginRight = 0,
                                 int marginBottom = 0, int marginLeft = 0);
    // Sfocatura di KWin dietro i rettangoli arrotondati {x, y, width, height, radius}
    Q_INVOKABLE void setBlur(QWindow *window, const QVariantList &rects);
    // Zona che riceve il mouse; lista vuota = tutta la finestra
    Q_INVOKABLE void setInputRegion(QWindow *window, const QVariantList &rects);

    Q_INVOKABLE QString iconForApp(const QString &appId) const;
    Q_INVOKABLE void run(const QString &program, const QStringList &arguments = {});
    Q_INVOKABLE void openSettings(const QString &module = QString());
    Q_INVOKABLE void openTrash();
    Q_INVOKABLE void screenshot();
    // Immagini disponibili come sfondo: [{url, name}]
    Q_INVOKABLE QVariantList wallpapers() const;

    Q_INVOKABLE void setVolume(double volume);
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void setBrightness(double brightness);
    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectWifi(const QString &ssid);

    Q_INVOKABLE void lock();
    Q_INVOKABLE void suspend();
    Q_INVOKABLE void logout();
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void shutdown();

public Q_SLOTS:
    Q_SCRIPTABLE void toggleLauncher();
    Q_SCRIPTABLE void showControlCenter();
    Q_SCRIPTABLE void showNotifications();
    Q_SCRIPTABLE void hideOverlay();

Q_SIGNALS:
    void overlayChanged();
    void batteryChanged();
    void networkChanged();
    void wifiNetworksChanged();
    void bluetoothChanged();
    void volumeChanged();
    void brightnessChanged();
    void wallpaperChanged();
    void widgetLayoutChanged();
    void launchpadLayoutChanged();
    void nightLightChanged();

private Q_SLOTS:
    void onBatteryEvent();
    void onNetworkEvent();
    void onBluetoothEvent();

private:
    void readBattery();
    void readNetwork();
    void readBluetooth();
    void readVolume();
    void readBrightness();
    void readNightLight();
    void schedule(int what);
    enum Pending { PendingBattery = 1, PendingNetwork = 2, PendingBluetooth = 4, PendingVolume = 8 };
    void callShutdown(const QString &method);

    QSettings m_settings;
    QString m_overlay;
    QTimer m_slowTimer;
    QTimer m_fastTimer;
    QTimer m_eventDelay;
    QProcess m_audioEvents;
    int m_pending = 0;
    bool m_nightLight = false;

    bool m_batteryPresent = false;
    int m_batteryLevel = 0;
    bool m_charging = false;
    QString m_networkType = QStringLiteral("none");
    QString m_networkName;
    bool m_wifiEnabled = false;
    QVariantList m_wifiNetworks;
    bool m_bluetoothAvailable = false;
    bool m_bluetoothEnabled = false;
    double m_volume = 0;
    bool m_muted = false;
    double m_brightness = -1;
    int m_brightnessMax = 0;
    QString m_brightnessDisplay; // percorso D-Bus dello schermo (org.kde.ScreenBrightness)
    bool m_brightnessLegacy = false;
};
