// arc — decorazione delle finestre di arc UI (KDecoration3)
#pragma once

#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationButton>
#include <KDecoration3/DecorationButtonGroup>

#include <QVariantList>

namespace Arc
{

// Misure del design (pixel logici)
namespace Metrics
{
constexpr qreal titleHeight = 38;
constexpr qreal cornerRadius = 18;
constexpr qreal titleLeft = 17;       // margine del nome dell'app
constexpr qreal buttonSize = 20;
constexpr qreal buttonSpacing = 8;
constexpr qreal buttonsRight = 11;    // margine destro dei pulsanti
constexpr qreal resizeBorder = 6;     // bordo invisibile per ridimensionare
constexpr int shadowSize = 48;
constexpr int shadowOffset = 10;
}

class Decoration : public KDecoration3::Decoration
{
    Q_OBJECT

public:
    explicit Decoration(QObject *parent = nullptr, const QVariantList &args = QVariantList());

    void paint(QPainter *painter, const QRectF &repaintArea) override;
    bool init() override;

    bool isMaximized() const;

private:
    void updateLayout();
    void positionButtons();
    void updateShadow();

    KDecoration3::DecorationButtonGroup *m_buttons = nullptr;
};

class Button : public KDecoration3::DecorationButton
{
    Q_OBJECT

public:
    Button(KDecoration3::DecorationButtonType type, Decoration *decoration, QObject *parent = nullptr);
    explicit Button(QObject *parent, const QVariantList &args);

    static KDecoration3::DecorationButton *create(KDecoration3::DecorationButtonType type, KDecoration3::Decoration *decoration,
                                                  QObject *parent);

    void paint(QPainter *painter, const QRectF &repaintArea) override;
};

} // namespace Arc
