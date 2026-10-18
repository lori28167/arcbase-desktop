// arc-shell — shell grafica di arc UI per la sessione arc (KWin Wayland).
// Ogni elemento (sfondo, topbar, dock, widget, launcher, notifiche) è una
// superficie layer-shell disegnata in QML: nessun componente di Plasma.
#include "applications.h"
#include "media.h"
#include "notifications.h"
#include "osd.h"
#include "search.h"
#include "shell.h"

#include <QDBusConnection>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickImageProvider>

namespace
{
// image://icon/<nome> → icona del tema (Papirus) alla dimensione richiesta
class IconProvider : public QQuickImageProvider
{
public:
    IconProvider()
        : QQuickImageProvider(QQuickImageProvider::Pixmap)
    {
    }

    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        const int width = requestedSize.width() > 0 ? requestedSize.width() : 64;
        const int height = requestedSize.height() > 0 ? requestedSize.height() : width;
        QIcon icon = QIcon::fromTheme(id);
        if (icon.isNull()) {
            icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
        }
        const QPixmap pixmap = icon.pixmap(QSize(width, height));
        if (size) {
            *size = pixmap.size();
        }
        return pixmap;
    }
};
} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication::setDesktopFileName(QStringLiteral("org.arcbase.shell"));
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("arc-shell"));
    app.setOrganizationDomain(QStringLiteral("arcbase.org"));
    app.setQuitOnLastWindowClosed(false);
    QIcon::setFallbackThemeName(QStringLiteral("hicolor"));

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerService(QStringLiteral("org.arcbase.Shell"))) {
        qCritical("arc-shell è già in esecuzione");
        return 1;
    }

    Shell shell;
    Applications applications;
    Notifications notifications;
    Media media;
    Osd osd;
    Search search;
    bus.registerObject(QStringLiteral("/Shell"), &shell, QDBusConnection::ExportScriptableSlots);
    notifications.registerService();
    osd.registerService();
    QObject::connect(&applications, &Applications::launched, &shell, &Shell::hideOverlay);
    QObject::connect(&search, &Search::launched, &shell, &Shell::hideOverlay);

    qmlRegisterSingletonInstance("org.arcbase.core", 1, 0, "Shell", &shell);
    qmlRegisterSingletonInstance("org.arcbase.core", 1, 0, "Applications", &applications);
    qmlRegisterSingletonInstance("org.arcbase.core", 1, 0, "Notifications", &notifications);
    qmlRegisterSingletonInstance("org.arcbase.core", 1, 0, "Media", &media);
    qmlRegisterSingletonInstance("org.arcbase.core", 1, 0, "Osd", &osd);
    qmlRegisterSingletonInstance("org.arcbase.core", 1, 0, "Search", &search);

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] {
            QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));

    return app.exec();
}
