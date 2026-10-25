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
// Barra: una riga di pillole dentro il vetro della finestra (nome dell'app,
// menu, pulsanti), poi il contenuto
constexpr qreal margin = 8;           // dal bordo della finestra alle pillole
constexpr qreal pillHeight = 40;
constexpr qreal pillSpacing = 8;
constexpr qreal pillPadding = 16;     // testo dentro le pillole
constexpr qreal titleHeight = margin + pillHeight + margin;
constexpr qreal cornerRadius = pillHeight / 2 + margin;   // concentrico: pillole (20) + margine (8)
constexpr qreal buttonSize = 26;
constexpr qreal buttonSpacing = 8;
constexpr qreal buttonsPadding = (pillHeight - buttonSize) / 2;
constexpr qreal contentRadius = cornerRadius - margin;    // pannelli del contenuto (Kvantum)
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
    // App di sistema (Dolphin, Impostazioni, app ArcScript...): il nome è in
    // una pillola e c'è la pillola del menu; le altre app hanno il nome semplice
    bool isSystemApp() const;
    QRectF namePill() const;
    QRectF buttonsPill() const;

private:
    void updateLayout();
    void positionButtons();
    void updateShadow();

    KDecoration3::DecorationButtonGroup *m_buttons = nullptr;
    KDecoration3::DecorationButton *m_menu = nullptr;   // pillola del menu dell'app
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
