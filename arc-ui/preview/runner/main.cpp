// arc-preview — anteprima di arc-shell senza KDE (macOS o Linux con Qt 6).
// Carica i veri QML di arc-ui/shell con dei mock al posto delle parti in C++
// e di KDE, disegna icone segnaposto e ricarica tutto quando un file cambia.
//
// Uso: arc-preview <file.qml> <mock> <out> <repo>
#include <QDirIterator>
#include <QFile>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QHash>
#include <QPainter>
#include <QPainterPath>
#include <QPointer>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickWindow>
#include <QSvgRenderer>
#include <QTimer>
#include <QUrl>

namespace
{
// image://icon/<nome>: cerca nelle cartelle di ARC_ICONS (arc icons, WhiteSur);
// se manca, un quadrato colorato con l'iniziale (sul sistema: Papirus)
class PlaceholderIcons : public QQuickImageProvider
{
public:
    PlaceholderIcons()
        : QQuickImageProvider(QQuickImageProvider::Image)
    {
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override
    {
        const int s = requested.width() > 0 ? requested.width() : 64;
        QString svg;
        const QStringList dirs = qEnvironmentVariable("ARC_ICONS").split(QLatin1Char(':'), Qt::SkipEmptyParts);
        for (const QString &dir : dirs) {
            if (QFile::exists(dir + QLatin1Char('/') + id + QStringLiteral(".svg"))) {
                svg = dir + QLatin1Char('/') + id + QStringLiteral(".svg");
                break;
            }
        }
        if (!svg.isEmpty()) {
            QImage img(s, s, QImage::Format_ARGB32_Premultiplied);
            img.fill(Qt::transparent);
            QPainter painter(&img);
            QSvgRenderer(svg).render(&painter);
            if (size) {
                *size = img.size();
            }
            return img;
        }
        static const QHash<QString, QPair<QColor, QColor>> colors = {
            {QStringLiteral("org.kde.dolphin"), {QColor("#4fb3ff"), QColor("#1d6fd6")}},
            {QStringLiteral("firefox"), {QColor("#ffb03a"), QColor("#e2442f")}},
            {QStringLiteral("org.kde.konsole"), {QColor("#3b3f4a"), QColor("#16181d")}},
            {QStringLiteral("org.kde.kate"), {QColor("#7aa7ff"), QColor("#3a5bd6")}},
            {QStringLiteral("org.kde.discover"), {QColor("#38d39f"), QColor("#0f8a6b")}},
            {QStringLiteral("systemsettings"), {QColor("#9aa3b5"), QColor("#4f5869")}},
        };
        const uint h = qHash(id);
        const auto pair = colors.value(id, {QColor::fromHsv(h % 360, 140, 230), QColor::fromHsv((h % 360 + 30) % 360, 200, 150)});
        QImage img(s, s, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing);
        QLinearGradient g(0, 0, 0, s);
        g.setColorAt(0, pair.first);
        g.setColorAt(1, pair.second);
        QPainterPath path;
        path.addRoundedRect(QRectF(s * 0.06, s * 0.06, s * 0.88, s * 0.88), s * 0.22, s * 0.22);
        p.fillPath(path, g);
        p.setPen(Qt::white);
        QFont f(QStringLiteral("Inter"));
        f.setPixelSize(s * 0.42);
        f.setWeight(QFont::DemiBold);
        p.setFont(f);
        p.drawText(QRectF(0, 0, s, s), Qt::AlignCenter, id.section(QLatin1Char('.'), -1).left(1).toUpper());
        if (size) {
            *size = img.size();
        }
        return img;
    }
};
} // namespace

// Ricrea il motore QML a ogni modifica (così anche i singleton come Theme
// ripartono da zero) e mantiene posizione e dimensione della finestra
class Preview : public QObject
{
    Q_OBJECT

public:
    Preview(QString qml, QString mock, QString out, QString repo)
        : m_qml(std::move(qml))
        , m_mock(std::move(mock))
        , m_out(std::move(out))
        , m_repo(std::move(repo))
    {
        m_debounce.setSingleShot(true);
        m_debounce.setInterval(250);
        connect(&m_debounce, &QTimer::timeout, this, &Preview::reload);
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_debounce, qOverload<>(&QTimer::start));
        connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_debounce, qOverload<>(&QTimer::start));

        // touch <out>/grab → salva <out>/live-N.png con lo stato attuale delle finestre
        m_grab.setInterval(500);
        connect(&m_grab, &QTimer::timeout, this, [this] {
            const QString request = m_out + QStringLiteral("/grab");
            if (!QFile::exists(request) || !m_engine) {
                return;
            }
            QFile::remove(request);
            int n = 0;
            for (QObject *object : m_engine->rootObjects()) {
                if (auto *window = qobject_cast<QQuickWindow *>(object)) {
                    window->grabWindow().save(m_out + QStringLiteral("/live-%1.png").arg(n++));
                    for (QObject *child : window->findChildren<QQuickWindow *>()) {
                        auto *sub = static_cast<QQuickWindow *>(child);
                        if (sub->isVisible() && sub->x() > -10000) {
                            sub->grabWindow().save(m_out + QStringLiteral("/live-%1.png").arg(n++));
                        }
                    }
                }
            }
            qInfo("schermate salvate: %d", n);
        });
        m_grab.start();
    }

    Q_INVOKABLE void reload()
    {
        if (m_engine) {
            for (QObject *object : m_engine->rootObjects()) {
                if (auto *window = qobject_cast<QQuickWindow *>(object)) {
                    m_geometry = window->geometry();
                }
            }
            m_engine->deleteLater();
        }
        QTimer::singleShot(0, this, &Preview::load);
    }

private:
    void load()
    {
        m_engine = new QQmlApplicationEngine(this);
        m_engine->addImportPath(m_mock);
        m_engine->addImageProvider(QStringLiteral("icon"), new PlaceholderIcons);
        QQmlContext *ctx = m_engine->rootContext();
        ctx->setContextProperty(QStringLiteral("preview"), this);
        ctx->setContextProperty(QStringLiteral("outDir"), m_out);
        ctx->setContextProperty(QStringLiteral("shots"), qEnvironmentVariableIsSet("ARC_PREVIEW_SHOTS"));
        ctx->setContextProperty(QStringLiteral("animShots"), qEnvironmentVariable("ARC_PREVIEW_ANIM"));
        ctx->setContextProperty(QStringLiteral("previewGeometry"), m_geometry);
        ctx->setContextProperty(QStringLiteral("mainUrl"), QUrl::fromLocalFile(m_repo + QStringLiteral("/arc-ui/shell/qml/Main.qml")));
        ctx->setContextProperty(QStringLiteral("sddmUrl"),
                                QUrl::fromLocalFile(qEnvironmentVariable("SDDM_MAIN", m_repo + QStringLiteral("/arc-ui/theme/sddm/Main.qml"))));
        const QString wallpaper = m_repo + QStringLiteral("/arc-ui/wallpaper/dolomiti.jpg");
        ctx->setContextProperty(QStringLiteral("wallpaperUrl"), QUrl::fromLocalFile(wallpaper).toString());
        ctx->setContextProperty(QStringLiteral("wallpaperPath"), wallpaper);
        m_engine->load(QUrl::fromLocalFile(m_qml));
        watch();
    }

    // Gli editor salvano spesso sostituendo il file: si ri-aggiungono i percorsi
    void watch()
    {
        if (!m_watcher.files().isEmpty()) {
            m_watcher.removePaths(m_watcher.files());
        }
        if (!m_watcher.directories().isEmpty()) {
            m_watcher.removePaths(m_watcher.directories());
        }
        QStringList paths;
        const QStringList roots = {m_repo + QStringLiteral("/arc-ui/shell/qml"), m_repo + QStringLiteral("/arc-ui/theme/sddm"), m_mock};
        for (const QString &root : roots) {
            paths << root;
            QDirIterator it(root, {QStringLiteral("*.qml"), QStringLiteral("qmldir"), QStringLiteral("*.svg")},
                            QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
            while (it.hasNext()) {
                paths << it.next();
            }
        }
        m_watcher.addPaths(paths);
    }

    QString m_qml, m_mock, m_out, m_repo;
    QPointer<QQmlApplicationEngine> m_engine;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QTimer m_grab;
    QRect m_geometry;
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("arc-preview"));
    if (argc < 5) {
        qCritical("uso: arc-preview <file.qml> <mock> <out> <repo>");
        return 2;
    }
    Preview preview(QString::fromLocal8Bit(argv[1]), QString::fromLocal8Bit(argv[2]), QString::fromLocal8Bit(argv[3]),
                    QString::fromLocal8Bit(argv[4]));
    preview.reload();
    return app.exec();
}

#include "main.moc"
