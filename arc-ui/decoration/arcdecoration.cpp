#include "arcdecoration.h"

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/DecorationShadow>
#include <KPluginFactory>

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
// Barra del titolo: vetro chiaro sopra la sfocatura di KWin, testo scuro
const QColor titleActive(255, 255, 255, 82);
const QColor titleInactive(255, 255, 255, 46);
const QColor textActive(17, 17, 20, 235);
const QColor textInactive(17, 17, 20, 120);
const QColor outline(255, 255, 255, 34);

// Pulsanti: cerchi scuri con simbolo bianco
const QColor buttonNormal(58, 58, 62, 225);
const QColor buttonHover(34, 34, 38, 240);
const QColor buttonPressed(20, 20, 22, 250);
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
    connect(w, &KDecoration3::DecoratedWindow::captionChanged, this, [this] {
        update(titleBar());
    });
    // Pulsanti a destra (riduci, ingrandisci, chiudi: ButtonsOnRight in
    // kwinrc). Il gruppo li ricrea da solo se cambia l'impostazione.
    m_buttons = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Right, this, &Button::create);
    m_buttons->setSpacing(Metrics::buttonSpacing);
    connect(m_buttons, &KDecoration3::DecorationButtonGroup::geometryChanged, this, &Decoration::positionButtons);

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
    const QRectF group = m_buttons->geometry();
    const QPointF pos(window()->width() - group.width() - Metrics::buttonsRight, (Metrics::titleHeight - Metrics::buttonSize) / 2);
    if (group.topLeft() != pos) {
        m_buttons->setPos(pos);
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
    // disegna la barra del titolo
    setBorderRadius(KDecoration3::BorderRadius(0, 0, radius, radius));
    if (maximized) {
        setBorderOutline(KDecoration3::BorderOutline());
    } else {
        setBorderOutline(KDecoration3::BorderOutline(1, outline, KDecoration3::BorderRadius(radius)));
    }

    // Sfocatura di KWin dietro la barra del titolo
    const QPainterPath path = titlePath(QRectF(0, 0, width, Metrics::titleHeight), radius);
    setBlurRegion(QRegion(path.toFillPolygon().toPolygon()));

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
    painter->setBrush(active ? titleActive : titleInactive);
    painter->drawPath(titlePath(bar, rounded ? Metrics::cornerRadius : 0));

    // Nome dell'app a sinistra
    QFont font = settings()->font();
    font.setPixelSize(13);
    font.setWeight(QFont::Medium);
    painter->setFont(font);
    painter->setPen(active ? textActive : textInactive);
    const qreal buttonsWidth = m_buttons ? m_buttons->geometry().width() + Metrics::buttonsRight + 12 : 0;
    const QRectF textRect(Metrics::titleLeft, 0, width - Metrics::titleLeft - buttonsWidth, Metrics::titleHeight);
    const QString caption = painter->fontMetrics().elidedText(window()->caption(), Qt::ElideRight, int(textRect.width()));
    painter->drawText(textRect, Qt::AlignLeft | Qt::AlignVCenter, caption);
    painter->restore();

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

    // Simbolo bianco su una griglia di 20×20 centrata nel pulsante
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
