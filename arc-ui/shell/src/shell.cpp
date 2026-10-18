#include "shell.h"

#include <KService>
#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusVariant>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QMargins>
#include <QPainterPath>
#include <QProcess>
#include <QRegion>
#include <QRegularExpression>
#include <QUrl>
#include <QWindow>

#include <functional>
#include <pwd.h>
#include <unistd.h>

namespace
{
const QString defaultWallpaper = QStringLiteral("/usr/share/arcbase/arc-ui/wallpaper/dolomiti.jpg");
const QString installerDesktop = QStringLiteral("/usr/share/applications/arcbase-install.desktop");

// Esegue un comando senza bloccare e passa lo stdout alla callback
void capture(QObject *owner, const QString &program, const QStringList &args,
             std::function<void(const QString &)> done)
{
    auto *process = new QProcess(owner);
    QObject::connect(process, &QProcess::finished, owner, [process, done] {
        done(QString::fromUtf8(process->readAllStandardOutput()));
        process->deleteLater();
    });
    QObject::connect(process, &QProcess::errorOccurred, owner, [process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
        }
    });
    process->start(program, args);
}

QString readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromUtf8(file.readAll()).trimmed();
}

QRegion roundedRegion(const QVariantList &rects)
{
    QRegion region;
    for (const QVariant &value : rects) {
        const QVariantMap rect = value.toMap();
        const QRectF bounds(rect.value(QStringLiteral("x")).toReal(), rect.value(QStringLiteral("y")).toReal(),
                            rect.value(QStringLiteral("width")).toReal(), rect.value(QStringLiteral("height")).toReal());
        if (bounds.isEmpty()) {
            continue;
        }
        const qreal radius = rect.value(QStringLiteral("radius")).toReal();
        QPainterPath path;
        path.addRoundedRect(bounds, radius, radius);
        region += QRegion(path.toFillPolygon().toPolygon());
    }
    return region;
}
} // namespace

Shell::Shell(QObject *parent)
    : QObject(parent)
    , m_settings(QSettings::NativeFormat, QSettings::UserScope, QStringLiteral("arcbase"), QStringLiteral("arc-shell"))
{
    readBattery();
    readNetwork();
    readBluetooth();
    readVolume();
    readBrightness();
    readNightLight();

    // Lo stato arriva dagli eventi del sistema (meno risvegli, meno batteria):
    // UPower per la batteria, NetworkManager per la rete, BlueZ per il
    // Bluetooth, PipeWire (pactl subscribe) per il volume. Il controllo
    // periodico resta solo come rete di sicurezza.
    QDBusConnection system = QDBusConnection::systemBus();
    const QString properties = QStringLiteral("org.freedesktop.DBus.Properties");
    system.connect(QStringLiteral("org.freedesktop.UPower"), QStringLiteral("/org/freedesktop/UPower/devices/DisplayDevice"),
                   properties, QStringLiteral("PropertiesChanged"), this, SLOT(onBatteryEvent()));
    system.connect(QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("/org/freedesktop/NetworkManager"),
                   QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("StateChanged"), this, SLOT(onNetworkEvent()));
    system.connect(QStringLiteral("org.freedesktop.NetworkManager"), QStringLiteral("/org/freedesktop/NetworkManager"),
                   properties, QStringLiteral("PropertiesChanged"), this, SLOT(onNetworkEvent()));
    system.connect(QStringLiteral("org.bluez"), QStringLiteral("/org/bluez/hci0"), properties, QStringLiteral("PropertiesChanged"),
                   this, SLOT(onBluetoothEvent()));

    m_eventDelay.setSingleShot(true);
    m_eventDelay.setInterval(120);
    connect(&m_eventDelay, &QTimer::timeout, this, [this] {
        if (m_pending & PendingBattery) readBattery();
        if (m_pending & PendingNetwork) readNetwork();
        if (m_pending & PendingBluetooth) readBluetooth();
        if (m_pending & PendingVolume) readVolume();
        m_pending = 0;
    });

    m_slowTimer.setInterval(60000);
    connect(&m_slowTimer, &QTimer::timeout, this, [this] {
        readBattery();
        readNetwork();
        readBluetooth();
        readBrightness();
    });
    m_slowTimer.start();

    // Volume: eventi di PipeWire; se pactl manca, controllo ogni 3 secondi
    m_fastTimer.setInterval(3000);
    connect(&m_fastTimer, &QTimer::timeout, this, &Shell::readVolume);
    m_audioEvents.setProgram(QStringLiteral("pactl"));
    m_audioEvents.setArguments({QStringLiteral("subscribe")});
    connect(&m_audioEvents, &QProcess::readyReadStandardOutput, this, [this] {
        const QByteArray out = m_audioEvents.readAllStandardOutput();
        if (out.contains("sink") || out.contains("server")) {
            schedule(PendingVolume);
        }
    });
    connect(&m_audioEvents, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_fastTimer.start();
        }
    });
    connect(&m_audioEvents, &QProcess::finished, this, [this] {
        m_fastTimer.start();
    });
    m_audioEvents.start();
}

void Shell::schedule(int what)
{
    m_pending |= what;
    m_eventDelay.start();
}

void Shell::onBatteryEvent()
{
    schedule(PendingBattery);
}

void Shell::onNetworkEvent()
{
    schedule(PendingNetwork);
}

void Shell::onBluetoothEvent()
{
    schedule(PendingBluetooth);
}

QString Shell::launchpadLayout() const
{
    return m_settings.value(QStringLiteral("Launchpad/layout")).toString();
}

void Shell::setLaunchpadLayout(const QString &layout)
{
    if (layout == launchpadLayout()) {
        return;
    }
    m_settings.setValue(QStringLiteral("Launchpad/layout"), layout);
    Q_EMIT launchpadLayoutChanged();
}

// --- Luce notturna (KWin) ---------------------------------------------------------------

void Shell::readNightLight()
{
    capture(this, QStringLiteral("kreadconfig6"),
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"), QStringLiteral("NightColor"),
             QStringLiteral("--key"), QStringLiteral("Active"), QStringLiteral("--default"), QStringLiteral("false")},
            [this](const QString &out) {
                const bool on = out.trimmed() == QLatin1String("true");
                if (on != m_nightLight) {
                    m_nightLight = on;
                    Q_EMIT nightLightChanged();
                }
            });
}

void Shell::setNightLight(bool enabled)
{
    m_nightLight = enabled;
    Q_EMIT nightLightChanged();
    // Sempre attiva (non legata all'ora): la si accende e spegne da qui
    auto *write = new QProcess(this);
    const QStringList base = {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"), QStringLiteral("NightColor")};
    connect(write, &QProcess::finished, this, [write] {
        write->deleteLater();
        QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"), QStringLiteral("reconfigure")));
    });
    run(QStringLiteral("kwriteconfig6"), base + QStringList{QStringLiteral("--key"), QStringLiteral("Mode"), QStringLiteral("Constant")});
    write->start(QStringLiteral("kwriteconfig6"),
                 base + QStringList{QStringLiteral("--key"), QStringLiteral("Active"), QStringLiteral("--type"), QStringLiteral("bool"),
                                    enabled ? QStringLiteral("true") : QStringLiteral("false")});
}

void Shell::setOverlay(const QString &overlay)
{
    if (overlay == m_overlay) {
        return;
    }
    m_overlay = overlay;
    Q_EMIT overlayChanged();
    if (overlay == QLatin1String("control")) {
        readNetwork();
        readBattery();
        readBluetooth();
        readBrightness();
        scanWifi();
    }
}

void Shell::showNotifications()
{
    setOverlay(QStringLiteral("notifications"));
}

void Shell::toggleLauncher()
{
    setOverlay(m_overlay == QLatin1String("launcher") ? QString() : QStringLiteral("launcher"));
}

void Shell::showControlCenter()
{
    setOverlay(QStringLiteral("control"));
}

void Shell::hideOverlay()
{
    setOverlay(QString());
}

QString Shell::userName() const
{
    return qEnvironmentVariable("USER");
}

QString Shell::fullName() const
{
    if (const passwd *pw = getpwuid(getuid())) {
        const QString gecos = QString::fromLocal8Bit(pw->pw_gecos).section(QLatin1Char(','), 0, 0).trimmed();
        if (!gecos.isEmpty()) {
            return gecos;
        }
    }
    return userName();
}

QString Shell::wallpaper() const
{
    const QString path = m_settings.value(QStringLiteral("Shell/wallpaper"), defaultWallpaper).toString();
    if (path.contains(QLatin1String("://"))) {
        return path;
    }
    return QUrl::fromLocalFile(QFile::exists(path) ? path : defaultWallpaper).toString();
}

void Shell::setWallpaper(const QString &url)
{
    const QString path = QUrl(url).isLocalFile() ? QUrl(url).toLocalFile() : url;
    if (path == m_settings.value(QStringLiteral("Shell/wallpaper")).toString()) {
        return;
    }
    m_settings.setValue(QStringLiteral("Shell/wallpaper"), path);
    Q_EMIT wallpaperChanged();
}

QVariantList Shell::wallpapers() const
{
    static const QStringList images = {QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.png"),
                                       QStringLiteral("*.webp")};
    QVariantList list;
    QStringList seen;
    auto add = [&](const QString &path) {
        if (seen.contains(path)) {
            return;
        }
        seen << path;
        list << QVariantMap{{QStringLiteral("url"), QUrl::fromLocalFile(path).toString()},
                            {QStringLiteral("name"), QFileInfo(path).completeBaseName()}};
    };
    // Sfondi di arc, poi quelli di sistema (pacchetti di sfondi KDE: la
    // risoluzione più grande), poi Immagini/Sfondi dell'utente
    const QFileInfoList ours = QDir(QFileInfo(defaultWallpaper).path()).entryInfoList(images, QDir::Files, QDir::Name);
    for (const QFileInfo &info : ours) {
        add(info.filePath());
    }
    const QFileInfoList packages = QDir(QStringLiteral("/usr/share/wallpapers")).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QFileInfo &package : packages) {
        QFileInfo best;
        QDirIterator it(package.filePath(), images, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QFileInfo info(it.next());
            if (!best.exists() || info.size() > best.size()) {
                best = info;
            }
        }
        if (best.exists()) {
            add(best.filePath());
        }
    }
    const QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    for (const QString &dir : {pictures + QStringLiteral("/Sfondi"), pictures + QStringLiteral("/Wallpapers"), pictures}) {
        const QFileInfoList files = QDir(dir).entryInfoList(images, QDir::Files, QDir::Name);
        for (const QFileInfo &info : files) {
            add(info.filePath());
        }
    }
    return list;
}

QString Shell::widgetLayout() const
{
    return m_settings.value(QStringLiteral("Widgets/layout")).toString();
}

void Shell::setWidgetLayout(const QString &layout)
{
    if (layout == widgetLayout()) {
        return;
    }
    m_settings.setValue(QStringLiteral("Widgets/layout"), layout);
    Q_EMIT widgetLayoutChanged();
}

QStringList Shell::dockLaunchers() const
{
    static const QStringList defaults = {
        QStringLiteral("org.kde.dolphin.desktop"),
        QStringLiteral("firefox.desktop"),
        QStringLiteral("org.kde.konsole.desktop"),
        QStringLiteral("org.kde.kate.desktop"),
        QStringLiteral("org.kde.discover.desktop"),
        QStringLiteral("systemsettings.desktop"),
    };
    QStringList ids = m_settings.value(QStringLiteral("Shell/dock"), defaults).toStringList();
    // Nella sessione live l'installer è la prima icona della dock
    if (QFile::exists(installerDesktop) && !ids.contains(QLatin1String("arcbase-install.desktop"))) {
        ids.prepend(QStringLiteral("arcbase-install.desktop"));
    }
    QStringList launchers;
    for (const QString &id : std::as_const(ids)) {
        const QString trimmed = id.trimmed();
        if (!trimmed.isEmpty()) {
            launchers << QStringLiteral("applications:") + trimmed;
        }
    }
    return launchers;
}

void Shell::configureLayer(QWindow *window, const QString &scope, int layer, int anchors, int exclusiveZone,
                           int keyboard, int marginTop, int marginRight, int marginBottom, int marginLeft)
{
    if (!window) {
        return;
    }
    auto *surface = LayerShellQt::Window::get(window);
    if (!surface) {
        qWarning("arc-shell: layer-shell non disponibile per %s", qPrintable(scope));
        return;
    }
    surface->setScope(scope);
    surface->setLayer(static_cast<LayerShellQt::Window::Layer>(layer));
    surface->setAnchors(LayerShellQt::Window::Anchors::fromInt(anchors));
    surface->setExclusiveZone(exclusiveZone);
    surface->setKeyboardInteractivity(static_cast<LayerShellQt::Window::KeyboardInteractivity>(keyboard));
    surface->setMargins(QMargins(marginLeft, marginTop, marginRight, marginBottom));
}

void Shell::updateLayer(QWindow *window, int exclusiveZone, int marginTop, int marginRight, int marginBottom, int marginLeft)
{
    if (!window) {
        return;
    }
    if (auto *surface = LayerShellQt::Window::get(window)) {
        surface->setExclusiveZone(exclusiveZone);
        surface->setMargins(QMargins(marginLeft, marginTop, marginRight, marginBottom));
    }
}

void Shell::setBlur(QWindow *window, const QVariantList &rects)
{
    if (!window) {
        return;
    }
    const QRegion region = roundedRegion(rects);
    KWindowEffects::enableBlurBehind(window, !region.isEmpty(), region);
}

void Shell::setInputRegion(QWindow *window, const QVariantList &rects)
{
    if (!window) {
        return;
    }
    window->setMask(rects.isEmpty() ? QRegion() : roundedRegion(rects));
}

QString Shell::iconForApp(const QString &appId) const
{
    if (appId.isEmpty()) {
        return QStringLiteral("application-x-executable");
    }
    KService::Ptr service = KService::serviceByDesktopName(appId);
    if (!service) {
        service = KService::serviceByStorageId(appId);
    }
    if (!service) {
        service = KService::serviceByDesktopName(appId.toLower());
    }
    if (service && !service->icon().isEmpty()) {
        return service->icon();
    }
    return appId.toLower();
}

void Shell::run(const QString &program, const QStringList &arguments)
{
    if (!QProcess::startDetached(program, arguments)) {
        qWarning("arc-shell: impossibile avviare %s", qPrintable(program));
    }
}

void Shell::openSettings(const QString &module)
{
    setOverlay(QString());
    run(QStringLiteral("systemsettings"), module.isEmpty() ? QStringList() : QStringList{module});
}

void Shell::openTrash()
{
    setOverlay(QString());
    run(QStringLiteral("dolphin"), {QStringLiteral("trash:/")});
}

void Shell::screenshot()
{
    setOverlay(QString());
    run(QStringLiteral("spectacle"));
}

// --- Audio (PipeWire / WirePlumber) ------------------------------------------------

void Shell::readVolume()
{
    capture(this, QStringLiteral("wpctl"), {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")},
            [this](const QString &out) {
                // "Volume: 0.40" oppure "Volume: 0.40 [MUTED]"
                static const QRegularExpression re(QStringLiteral("Volume:\\s*([0-9.]+)"));
                const QRegularExpressionMatch match = re.match(out);
                if (!match.hasMatch()) {
                    return;
                }
                const double volume = match.captured(1).toDouble();
                const bool muted = out.contains(QLatin1String("[MUTED]"));
                if (qAbs(volume - m_volume) > 0.005 || muted != m_muted) {
                    m_volume = volume;
                    m_muted = muted;
                    Q_EMIT volumeChanged();
                }
            });
}

void Shell::setVolume(double volume)
{
    volume = qBound(0.0, volume, 1.0);
    m_volume = volume;
    Q_EMIT volumeChanged();
    run(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("-l"), QStringLiteral("1.0"),
                                  QStringLiteral("@DEFAULT_AUDIO_SINK@"), QString::number(volume, 'f', 2)});
}

void Shell::toggleMute()
{
    m_muted = !m_muted;
    Q_EMIT volumeChanged();
    run(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QStringLiteral("toggle")});
}

// --- Batteria e rete ------------------------------------------------------------------

void Shell::readBattery()
{
    bool present = false;
    int level = 0;
    bool charging = false;
    const QDir supplies(QStringLiteral("/sys/class/power_supply"));
    const QStringList entries = supplies.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &name : entries) {
        const QString base = supplies.filePath(name) + QLatin1Char('/');
        // Solo batterie del sistema, non quelle di mouse e cuffie
        if (readFile(base + QStringLiteral("type")) != QLatin1String("Battery")
            || readFile(base + QStringLiteral("scope")) == QLatin1String("Device")) {
            continue;
        }
        present = true;
        level = readFile(base + QStringLiteral("capacity")).toInt();
        const QString status = readFile(base + QStringLiteral("status"));
        charging = status == QLatin1String("Charging") || status == QLatin1String("Full");
        break;
    }
    if (present != m_batteryPresent || level != m_batteryLevel || charging != m_charging) {
        m_batteryPresent = present;
        m_batteryLevel = level;
        m_charging = charging;
        Q_EMIT batteryChanged();
    }
}

void Shell::readNetwork()
{
    capture(this, QStringLiteral("nmcli"),
            {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("TYPE,STATE,CONNECTION"), QStringLiteral("device")},
            [this](const QString &out) {
                static const QRegularExpression separator(QStringLiteral("(?<!\\\\):"));
                QString type = QStringLiteral("none");
                QString name;
                const QStringList lines = out.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
                for (const QString &line : lines) {
                    const QStringList fields = line.split(separator);
                    if (fields.size() < 3 || !fields.at(1).startsWith(QLatin1String("connected"))) {
                        continue;
                    }
                    const QString deviceType = fields.at(0);
                    QString connection = fields.at(2);
                    connection.replace(QLatin1String("\\:"), QLatin1String(":"));
                    if (deviceType == QLatin1String("ethernet")) {
                        type = deviceType;
                        name = connection;
                        break;
                    }
                    if (deviceType == QLatin1String("wifi") && type == QLatin1String("none")) {
                        type = deviceType;
                        name = connection;
                    }
                }
                if (type != m_networkType || name != m_networkName) {
                    m_networkType = type;
                    m_networkName = name;
                    Q_EMIT networkChanged();
                }
            });
    capture(this, QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi")}, [this](const QString &out) {
        const bool enabled = out.trimmed() == QLatin1String("enabled");
        if (enabled != m_wifiEnabled) {
            m_wifiEnabled = enabled;
            Q_EMIT networkChanged();
        }
    });
}

void Shell::setWifiEnabled(bool enabled)
{
    m_wifiEnabled = enabled;
    Q_EMIT networkChanged();
    run(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), enabled ? QStringLiteral("on") : QStringLiteral("off")});
}

void Shell::scanWifi()
{
    capture(this, QStringLiteral("nmcli"),
            {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"), QStringLiteral("device"),
             QStringLiteral("wifi"), QStringLiteral("list")},
            [this](const QString &out) {
                static const QRegularExpression separator(QStringLiteral("(?<!\\\\):"));
                QVariantList networks;
                QStringList seen;
                const QStringList lines = out.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
                for (const QString &line : lines) {
                    const QStringList fields = line.split(separator);
                    if (fields.size() < 4) {
                        continue;
                    }
                    QString ssid = fields.at(1);
                    ssid.replace(QLatin1String("\\:"), QLatin1String(":"));
                    if (ssid.isEmpty() || seen.contains(ssid)) {
                        continue; // reti nascoste e doppioni (più access point)
                    }
                    seen << ssid;
                    networks << QVariantMap{{QStringLiteral("ssid"), ssid},
                                            {QStringLiteral("signal"), fields.at(2).toInt()},
                                            {QStringLiteral("secure"), !fields.at(3).isEmpty() && fields.at(3) != QLatin1String("--")},
                                            {QStringLiteral("active"), fields.at(0) == QLatin1String("*")}};
                }
                m_wifiNetworks = networks;
                Q_EMIT wifiNetworksChanged();
            });
}

void Shell::connectWifi(const QString &ssid)
{
    // Se serve una password la chiede l'agente dei segreti di KDE (plasma-nm)
    run(QStringLiteral("nmcli"), {QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid});
    QTimer::singleShot(4000, this, &Shell::readNetwork);
}

void Shell::readBluetooth()
{
    capture(this, QStringLiteral("bluetoothctl"), {QStringLiteral("show")}, [this](const QString &out) {
        const bool available = out.contains(QLatin1String("Controller"));
        const bool enabled = available && out.contains(QLatin1String("Powered: yes"));
        if (available != m_bluetoothAvailable || enabled != m_bluetoothEnabled) {
            m_bluetoothAvailable = available;
            m_bluetoothEnabled = enabled;
            Q_EMIT bluetoothChanged();
        }
    });
}

void Shell::setBluetoothEnabled(bool enabled)
{
    m_bluetoothEnabled = enabled;
    Q_EMIT bluetoothChanged();
    run(QStringLiteral("bluetoothctl"), {QStringLiteral("power"), enabled ? QStringLiteral("on") : QStringLiteral("off")});
}

// --- Luminosità (powerdevil) --------------------------------------------------------------
// Plasma 6.2+: org.kde.ScreenBrightness; prima: Actions.BrightnessControl

namespace
{
const QString brightnessService = QStringLiteral("org.kde.ScreenBrightness");
const QString legacyService = QStringLiteral("org.kde.Solid.PowerManagement");
const QString legacyPath = QStringLiteral("/org/kde/Solid/PowerManagement/Actions/BrightnessControl");
const QString legacyInterface = QStringLiteral("org.kde.Solid.PowerManagement.Actions.BrightnessControl");

QVariant dbusProperty(const QString &service, const QString &path, const QString &interface, const QString &name)
{
    QDBusMessage call = QDBusMessage::createMethodCall(service, path, QStringLiteral("org.freedesktop.DBus.Properties"),
                                                       QStringLiteral("Get"));
    call << interface << name;
    const QDBusMessage reply = QDBusConnection::sessionBus().call(call, QDBus::Block, 500);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
        return {};
    }
    return reply.arguments().constFirst().value<QDBusVariant>().variant();
}

int dbusInt(const QString &service, const QString &path, const QString &interface, const QString &method)
{
    const QDBusMessage reply = QDBusConnection::sessionBus().call(
        QDBusMessage::createMethodCall(service, path, interface, method), QDBus::Block, 500);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
        return -1;
    }
    return reply.arguments().constFirst().toInt();
}
} // namespace

void Shell::readBrightness()
{
    double value = -1;
    const QStringList displays =
        dbusProperty(brightnessService, QStringLiteral("/org/kde/ScreenBrightness"), brightnessService, QStringLiteral("DisplaysDBusNames"))
            .toStringList();
    if (!displays.isEmpty()) {
        m_brightnessLegacy = false;
        m_brightnessDisplay = QStringLiteral("/org/kde/ScreenBrightness/") + displays.constFirst();
        const QString iface = brightnessService + QStringLiteral(".Display");
        m_brightnessMax = dbusProperty(brightnessService, m_brightnessDisplay, iface, QStringLiteral("MaxBrightness")).toInt();
        const int current = dbusProperty(brightnessService, m_brightnessDisplay, iface, QStringLiteral("Brightness")).toInt();
        if (m_brightnessMax > 0) {
            value = double(current) / m_brightnessMax;
        }
    } else {
        m_brightnessMax = dbusInt(legacyService, legacyPath, legacyInterface, QStringLiteral("brightnessMax"));
        const int current = dbusInt(legacyService, legacyPath, legacyInterface, QStringLiteral("brightness"));
        m_brightnessLegacy = m_brightnessMax > 0;
        if (m_brightnessLegacy && current >= 0) {
            value = double(current) / m_brightnessMax;
        }
    }
    if (qAbs(value - m_brightness) > 0.005) {
        m_brightness = value;
        Q_EMIT brightnessChanged();
    }
}

void Shell::setBrightness(double brightness)
{
    if (m_brightnessMax <= 0) {
        return;
    }
    brightness = qBound(0.02, brightness, 1.0);
    m_brightness = brightness;
    Q_EMIT brightnessChanged();
    const int value = qRound(brightness * m_brightnessMax);
    QDBusMessage call;
    if (m_brightnessLegacy) {
        call = QDBusMessage::createMethodCall(legacyService, legacyPath, legacyInterface, QStringLiteral("setBrightness"));
        call << value;
    } else {
        call = QDBusMessage::createMethodCall(brightnessService, m_brightnessDisplay,
                                              brightnessService + QStringLiteral(".Display"), QStringLiteral("SetBrightness"));
        call << value << uint(0);
    }
    QDBusConnection::sessionBus().asyncCall(call);
}

// --- Sessione ---------------------------------------------------------------------------

void Shell::callShutdown(const QString &method)
{
    setOverlay(QString());
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.Shutdown"), QStringLiteral("/Shutdown"),
                                                          QStringLiteral("org.kde.Shutdown"), method);
    QDBusConnection::sessionBus().asyncCall(message);
}

void Shell::lock()
{
    setOverlay(QString());
    run(QStringLiteral("loginctl"), {QStringLiteral("lock-session")});
}

void Shell::suspend()
{
    setOverlay(QString());
    run(QStringLiteral("systemctl"), {QStringLiteral("suspend")});
}

void Shell::logout()
{
    callShutdown(QStringLiteral("logout"));
}

void Shell::reboot()
{
    callShutdown(QStringLiteral("logoutAndReboot"));
}

void Shell::shutdown()
{
    callShutdown(QStringLiteral("logoutAndShutdown"));
}
