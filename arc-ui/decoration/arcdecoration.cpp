#include "arcdecoration.h"

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/DecorationShadow>
#include <KPluginFactory>

#include <QFontMetricsF>
#include <QPainter>
#include <QPainterPath>
#include <QRegion>

#include <cmath>

K_PLUGIN_FACTORY_WITH_JSON(ArcDecorationFactory, "arc.json", registerPlugin<Arc::Decoration>(); registerPlugin<Arc::Button>();)

namespace Arc
{

using KDecoration3::DecorationButtonType;

namespace
{
// Barra del titolo: lo stesso vetro scuro dei pannelli arc (Theme.material)
// sopra la sfocatura di KWin, testo chiaro
const QColor titleActive(14, 12, 20, 158);
const QColor titleInactive(14, 12, 20, 190);
const QColor textActive(255, 255, 255, 240);
const QColor textInactive(255, 255, 255, 130);
const QColor outline(255, 255, 255, 34);

// Pillole della barra: vetro un po' più chiaro; quella del nome di più
const QColor pill(255, 255, 255, 22);
const QColor namePillFill(255, 255, 255, 36);
const QColor menuHover(255, 255, 255, 44);

// Pulsanti: cerchi scuri come i pannelli del contenuto, simbolo bianco
const QColor buttonNormal(37, 34, 44, 235);
const QColor buttonHover(64, 60, 74, 245);
const QColor buttonPressed(84, 79, 96, 250);
const QColor closeHover(229, 72, 77, 245);
const QColor closePressed(190, 45, 50, 250);

// Forma della barra: angoli in alto arrotondati, in basso dritti
QPainterPath titlePath(const QRectF &rect, qreal radius)
{
    QPainterPath path;
    path.moveTo(rect.left(), rect.bottom());
    path.lineTo(rect.left(), rect.top() + radius);
    path.arcTo(QRectF(rect.left(), rect.top(), 2 * radius, 2 * radius), 180, -90);
    path.lineTo(rect.right() - radius, rect.top());
    path.arcTo(QRectF(rect.right() - 2 * radius, rect.top(), 2 * radius, 2 * radius), 90, -90);
    path.lineTo(rect.right(), rect.bottom());
    path.closeSubpath();
    return path;
}

// Distanza con segno da un rettangolo arrotondato centrato in (0, 0)
qreal roundedRectDistance(qreal px, qreal py, qreal halfWidth, qreal halfHeight, qreal radius)
{
    const qreal qx = std::abs(px) - (halfWidth - radius);
    const qreal qy = std::abs(py) - (halfHeight - radius);
    const qreal outside = std::hypot(std::max(qx, 0.0), std::max(qy, 0.0));
    return outside + std::min(std::max(qx, qy), 0.0) - radius;
}

// Ombra morbida (gaussiana) attorno alla finestra, vuota sotto la finestra
std::shared_ptr<KDecoration3::DecorationShadow> makeShadow(qreal strength)
{
    const int s = Metrics::shadowSize;
    const qreal r = Metrics::cornerRadius;
    const int core = int(2 * r) + 1;
    const int size = 2 * s + core;
    const qreal sigma = s / 2.6;
    const qreal half = core / 2.0;

    QImage image(size, size, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    for (int y = 0; y < size; ++y) {
        auto *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < size; ++x) {
            const qreal px = x + 0.5 - size / 2.0;
            const qreal py = y + 0.5 - size / 2.0;
            // Sotto la finestra niente ombra (la barra è trasparente)
            if (roundedRectDistance(px, py, half, half, r) <= 0) {
                continue;
            }
            const qreal d = std::max<qreal>(0, roundedRectDistance(px, py - Metrics::shadowOffset, half, half, r));
            const int alpha = qBound(0, int(255 * strength * std::exp(-(d * d) / (2 * sigma * sigma))), 255);
            line[x] = qRgba(0, 0, 0, alpha);
        }
    }

    auto shadow = std::make_shared<KDecoration3::DecorationShadow>();
    shadow->setPadding(QMarginsF(s, s, s, s));
    shadow->setInnerShadowRect(QRectF(s + half, s + half, 1, 1));
    shadow->setShadow(image);
    return shadow;
}
} // namespace

// --- Decorazione ---------------------------------------------------------------------

Decoration::Decoration(QObject *parent, const QVariantList &args)
    : KDecoration3::Decoration(parent, args)
{
}

bool Decoration::isSystemApp() const
{
    // windowClass() = "<nome> <classe>", es. "dolphin org.kde.dolphin"
    static const QStringList apps = {QStringLiteral("org.kde.dolphin"), QStringLiteral("systemsettings"),
                                     QStringLiteral("org.kde.kinfocenter"), QStringLiteral("org.kde.discover"),
                                     QStringLiteral("org.kde.plasma-systemmonitor"), QStringLiteral("org.kde.ark"),
                                     QStringLiteral("org.kde.spectacle"), QStringLiteral("org.kde.gwenview"),
                                     QStringLiteral("org.kde.okular"), QStringLiteral("org.kde.kate"),
                                     QStringLiteral("org.kde.konsole"), QStringLiteral("org.kde.kcalc"),
                                     QStringLiteral("org.arcbase.installer")};
    const QStringList parts = window()->windowClass().toLower().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        // Le app ArcScript (app_id org.arcos.<nome>) e quelle di arcbase
        if (apps.contains(part) || part.startsWith(QLatin1String("org.arcos.")) || part.startsWith(QLatin1String("org.arcbase."))) {
            return true;
        }
    }
    return false;
}

namespace
{
QFont captionFont(const QFont &base)
{
    QFont font = base;
    font.setPixelSize(13);
    font.setWeight(QFont::Medium);
    return font;
}
}

QRectF Decoration::namePill() const
{
    const QFontMetricsF metrics(captionFont(settings()->font()));
    const qreal limit = std::max<qreal>(0, buttonsPill().left() - 2 * Metrics::margin - Metrics::pillSpacing);
    const qreal width = std::min(limit, metrics.horizontalAdvance(window()->caption()) + 2 * Metrics::pillPadding);
    return QRectF(Metrics::margin, Metrics::margin, std::max<qreal>(width, 0), Metrics::pillHeight);
}

QRectF Decoration::buttonsPill() const
{
    const qreal width = m_buttons ? m_buttons->geometry().width() + 2 * Metrics::buttonsPadding : 0;
    return QRectF(window()->width() - Metrics::margin - width, Metrics::margin, width, Metrics::pillHeight);
}

bool Decoration::isMaximized() const
{
    return window()->isMaximized();
}

bool Decoration::init()
{
    auto w = window();
    connect(w, &KDecoration3::DecoratedWindow::widthChanged, this, &Decoration::updateLayout);
    connect(w, &KDecoration3::DecoratedWindow::heightChanged, this, &Decoration::updateLayout);
    connect(w, &KDecoration3::DecoratedWindow::maximizedChanged, this, &Decoration::updateLayout);
    connect(w, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, &Decoration::updateLayout);
    connect(w, &KDecoration3::DecoratedWindow::activeChanged, this, [this] {
        updateShadow();
        update();
    });
    // Il nome cambia la larghezza della sua pillola, e quindi dove va il menu
    connect(w, &KDecoration3::DecoratedWindow::captionChanged, this, &Decoration::updateLayout);
    connect(w, &KDecoration3::DecoratedWindow::hasApplicationMenuChanged, this, &Decoration::updateLayout);
    connect(w, &KDecoration3::DecoratedWindow::paletteChanged, this, [this] {
        update();
    });
    // Pulsanti a destra (riduci, ingrandisci, chiudi: ButtonsOnRight in
    // kwinrc). Il gruppo li ricrea da solo se cambia l'impostazione.
    m_buttons = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Right, this, &Button::create);
    m_buttons->setSpacing(Metrics::buttonSpacing);
    connect(m_buttons, &KDecoration3::DecorationButtonGroup::geometryChanged, this, &Decoration::positionButtons);
    // Pillola del menu dell'app (quando l'app lo esporta): un clic lo apre
    m_menu = new Button(DecorationButtonType::ApplicationMenu, this, this);

    setOpaque(false);
    updateLayout();
    updateShadow();
    return true;
}

void Decoration::positionButtons()
{
    if (!m_buttons) {
        return;
    }
    const QRectF pill = buttonsPill();
    const QPointF pos(pill.left() + Metrics::buttonsPadding, pill.top() + Metrics::buttonsPadding);
    if (m_buttons->geometry().topLeft() != pos) {
        m_buttons->setPos(pos);
    }
    if (m_menu) {
        // Accanto al nome, se c'è spazio prima dei pulsanti
        const QRectF name = namePill();
        const qreal x = name.right() + Metrics::pillSpacing;
        const QFontMetricsF metrics(captionFont(settings()->font()));
        const qreal width = metrics.horizontalAdvance(QStringLiteral("Menu")) + 2 * Metrics::pillPadding + 22;
        const bool fits = x + width + Metrics::pillSpacing <= pill.left();
        m_menu->setGeometry(QRectF(x, Metrics::margin, width, Metrics::pillHeight));
        m_menu->setVisible(isSystemApp() && window()->hasApplicationMenu() && fits && !isMaximized());
    }
}

void Decoration::updateLayout()
{
    const qreal width = window()->width();
    const bool maximized = isMaximized();
    const Qt::Edges edges = window()->adjacentScreenEdges();
    const bool tiled = edges != Qt::Edges();
    const qreal radius = maximized || tiled ? 0 : Metrics::cornerRadius;

    setBorders(QMarginsF(0, Metrics::titleHeight, 0, 0));
    const qreal grip = maximized ? 0 : Metrics::resizeBorder;
    setResizeOnlyBorders(QMarginsF(grip, grip, grip, grip));
    setTitleBar(QRectF(0, 0, width, Metrics::titleHeight));

    // KWin arrotonda gli angoli in basso del contenuto; quelli in alto li
    // disegna la barra del titolo. Il contenuto continua il vetro della barra
    // (Kvantum: sfondo trasparente, pannelli incassati)
    setBorderRadius(KDecoration3::BorderRadius(0, 0, radius, radius));
    if (maximized) {
        setBorderOutline(KDecoration3::BorderOutline());
    } else {
        setBorderOutline(KDecoration3::BorderOutline(1, outline, KDecoration3::BorderRadius(radius)));
    }

    // Sfocatura di KWin dietro la barra del titolo
    // Vetro (sfocatura di KWin) solo per le app di sistema: le altre hanno
    // la barra del colore del loro sfondo, senza stacco dal contenuto
    if (isSystemApp()) {
        const QPainterPath path = titlePath(QRectF(0, 0, width, Metrics::titleHeight), radius);
        setBlurRegion(QRegion(path.toFillPolygon().toPolygon()));
    } else {
        setBlurRegion(QRegion());
    }

    positionButtons();
    update();
}

void Decoration::updateShadow()
{
    setShadow(makeShadow(window()->isActive() ? 0.42 : 0.24));
}

void Decoration::paint(QPainter *painter, const QRectF &repaintArea)
{
    const bool active = window()->isActive();
    const qreal width = window()->width();
    const bool rounded = !isMaximized() && window()->adjacentScreenEdges() == Qt::Edges();
    const QRectF bar(0, 0, width, Metrics::titleHeight);

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setPen(Qt::NoPen);
    const bool system = isSystemApp();
    // App di terze parti: la barra continua lo sfondo dell'app (il colore
    // Window della sua palette); nome e pulsanti ci stanno sopra
    const QColor appBackground = window()->palette().color(QPalette::Window);
    const bool lightApp = appBackground.lightnessF() > 0.6;
    painter->setBrush(system ? (active ? titleActive : titleInactive) : appBackground);
    painter->drawPath(titlePath(bar, rounded ? Metrics::cornerRadius : 0));

    // Pillola dei pulsanti a destra
    const QRectF buttons = buttonsPill();
    const qreal pillRadius = Metrics::pillHeight / 2;
    painter->setBrush(!system && lightApp ? QColor(0, 0, 0, 18) : pill);
    painter->drawRoundedRect(buttons, pillRadius, pillRadius);

    // Nome dell'app: in una pillola per le app di sistema, semplice per le altre
    painter->setFont(captionFont(settings()->font()));
    QRectF textRect;
    if (system) {
        const QRectF name = namePill();
        painter->setBrush(namePillFill);
        painter->drawRoundedRect(name, pillRadius, pillRadius);
        textRect = name.adjusted(Metrics::pillPadding, 0, -Metrics::pillPadding, 0);
    } else {
        const qreal left = Metrics::margin + Metrics::pillPadding;
        textRect = QRectF(left, Metrics::margin, buttons.left() - left - Metrics::pillSpacing, Metrics::pillHeight);
    }
    if (!system && lightApp) {
        painter->setPen(QColor(28, 26, 34, active ? 230 : 130));
    } else {
        painter->setPen(active ? textActive : textInactive);
    }
    const QString caption = painter->fontMetrics().elidedText(window()->caption(), Qt::ElideRight, int(textRect.width()));
    painter->drawText(textRect, Qt::AlignLeft | Qt::AlignVCenter, caption);
    painter->restore();

    if (m_menu && m_menu->isVisible()) {
        m_menu->paint(painter, repaintArea);
    }

    if (m_buttons) {
        m_buttons->paint(painter, repaintArea);
    }
}

// --- Pulsanti --------------------------------------------------------------------------

Button::Button(DecorationButtonType type, Decoration *decoration, QObject *parent)
    : KDecoration3::DecorationButton(type, decoration, parent)
{
    setGeometry(QRectF(0, 0, Metrics::buttonSize, Metrics::buttonSize));
    connect(this, &KDecoration3::DecorationButton::hoveredChanged, this, [this] {
        update();
    });
    connect(this, &KDecoration3::DecorationButton::pressedChanged, this, [this] {
        update();
    });
    connect(decoration->window(), &KDecoration3::DecoratedWindow::activeChanged, this, [this] {
        update();
    });
}

Button::Button(QObject *parent, const QVariantList &args)
    : Button(args.at(0).value<DecorationButtonType>(), args.at(1).value<Decoration *>(), parent)
{
}

KDecoration3::DecorationButton *Button::create(DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent)
{
    auto *arc = qobject_cast<Decoration *>(decoration);
    if (!arc) {
        return nullptr;
    }
    const auto w = decoration->window();
    switch (type) {
    case DecorationButtonType::Close: {
        auto *button = new Button(type, arc, parent);
        button->setVisible(w->isCloseable());
        connect(w, &KDecoration3::DecoratedWindow::closeableChanged, button, &Button::setVisible);
        return button;
    }
    case DecorationButtonType::Maximize: {
        auto *button = new Button(type, arc, parent);
        button->setVisible(w->isMaximizeable());
        connect(w, &KDecoration3::DecoratedWindow::maximizeableChanged, button, &Button::setVisible);
        return button;
    }
    case DecorationButtonType::Minimize: {
        auto *button = new Button(type, arc, parent);
        button->setVisible(w->isMinimizeable());
        connect(w, &KDecoration3::DecoratedWindow::minimizeableChanged, button, &Button::setVisible);
        return button;
    }
    default:
        // Il design ha solo questi tre pulsanti
        return nullptr;
    }
}

void Button::paint(QPainter *painter, const QRectF &repaintArea)
{
    Q_UNUSED(repaintArea)
    if (!isVisible()) {
        return;
    }
    const QRectF rect = geometry();
    const bool close = type() == DecorationButtonType::Close;
    const bool active = decoration()->window()->isActive();

    if (type() == DecorationButtonType::ApplicationMenu) {
        // Pillola "≡ Menu"
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing);
        painter->setPen(Qt::NoPen);
        painter->setBrush(isHovered() || isPressed() ? menuHover : pill);
        painter->drawRoundedRect(rect, rect.height() / 2, rect.height() / 2);
        QPen pen(active ? textActive : textInactive);
        pen.setWidthF(1.6);
        pen.setCapStyle(Qt::RoundCap);
        painter->setPen(pen);
        const qreal x = rect.left() + Metrics::pillPadding;
        const qreal y = rect.center().y();
        for (const qreal dy : {-4.0, 0.0, 4.0}) {
            painter->drawLine(QPointF(x, y + dy), QPointF(x + 12, y + dy));
        }
        painter->setFont(captionFont(decoration()->settings()->font()));
        painter->drawText(rect.adjusted(Metrics::pillPadding + 22, 0, 0, 0), Qt::AlignLeft | Qt::AlignVCenter, QStringLiteral("Menu"));
        painter->restore();
        return;
    }

    QColor fill = buttonNormal;
    if (isPressed()) {
        fill = close ? closePressed : buttonPressed;
    } else if (isHovered()) {
        fill = close ? closeHover : buttonHover;
    }
    if (!active && !isHovered()) {
        fill.setAlphaF(fill.alphaF() * 0.45);
    }

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setPen(Qt::NoPen);
    painter->setBrush(fill);
    painter->drawEllipse(rect);

    // Simbolo bianco centrato nel pulsante
    QPen pen(QColor(255, 255, 255, active || isHovered() ? 245 : 200));
    pen.setWidthF(1.6);
    pen.setCapStyle(Qt::RoundCap);
    pen.setJoinStyle(Qt::RoundJoin);
    painter->setPen(pen);
    painter->setBrush(Qt::NoBrush);
    painter->translate(rect.center());

    switch (type()) {
    case DecorationButtonType::Minimize:
        // Freccia giù
        painter->drawPolyline(QPolygonF({QPointF(-3.6, -1.6), QPointF(0, 2), QPointF(3.6, -1.6)}));
        break;
    case DecorationButtonType::Maximize:
        if (isChecked()) {
            // Ripristina: frecce verso l'interno
            painter->drawPolyline(QPolygonF({QPointF(-0.6, -4.2), QPointF(-0.6, -0.6), QPointF(-4.2, -0.6)}));
            painter->drawPolyline(QPolygonF({QPointF(0.6, 4.2), QPointF(0.6, 0.6), QPointF(4.2, 0.6)}));
        } else {
            // Ingrandisci: frecce verso gli angoli
            painter->drawPolyline(QPolygonF({QPointF(0.2, -4), QPointF(4, -4), QPointF(4, -0.2)}));
            painter->drawPolyline(QPolygonF({QPointF(-0.2, 4), QPointF(-4, 4), QPointF(-4, 0.2)}));
        }
        break;
    case DecorationButtonType::Close:
        painter->drawLine(QPointF(-3.3, -3.3), QPointF(3.3, 3.3));
        painter->drawLine(QPointF(3.3, -3.3), QPointF(-3.3, 3.3));
        break;
    default:
        break;
    }
    painter->restore();
}

} // namespace Arc

#include "arcdecoration.moc"
