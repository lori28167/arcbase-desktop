// Token di arc UI (da ArcBase/ui/arc-ui.css, :root) e misure della shell
pragma Singleton
import QtQuick

QtObject {
    // --- Materiale unico di tutti i pannelli (topbar, dock, widget, centro di
    //     controllo, notifiche, menu): vetro scuro sfocato da KWin
    readonly property color material: Qt.rgba(14 / 255, 12 / 255, 20 / 255, 0.62)
    readonly property color materialBorder: Qt.rgba(1, 1, 1, 0.14)
    readonly property color materialInset: Qt.rgba(1, 1, 1, 0.16)
    // Topbar attaccata ai bordi (app ingrandita): vetro chiaro, testo scuro
    readonly property color barLight: Qt.rgba(1, 1, 1, 0.44)
    readonly property color barLightBorder: Qt.rgba(1, 1, 1, 0.6)
    readonly property color ink: "#16131c"
    readonly property color inkMuted: Qt.rgba(22 / 255, 19 / 255, 28 / 255, 0.62)
    readonly property color inkHover: Qt.rgba(0, 0, 0, 0.07)
    // Velo dietro Launchpad e finestre modali
    readonly property color scrim: Qt.rgba(8 / 255, 6 / 255, 12 / 255, 0.38)

    // --- Superfici dentro i pannelli: --arc-surface-*
    readonly property color surface1: Qt.rgba(1, 1, 1, 0.05)
    readonly property color surface2: Qt.rgba(1, 1, 1, 0.08)
    readonly property color surface3: Qt.rgba(1, 1, 1, 0.13)
    readonly property color surface4: Qt.rgba(1, 1, 1, 0.20)
    readonly property color border: Qt.rgba(1, 1, 1, 0.10)
    readonly property color borderHi: Qt.rgba(1, 1, 1, 0.18)

    // --- Testo: --arc-text, --arc-muted, --arc-sub
    readonly property color text: Qt.rgba(1, 1, 1, 0.95)
    readonly property color muted: Qt.rgba(1, 1, 1, 0.60)
    readonly property color sub: Qt.rgba(1, 1, 1, 0.36)

    // --- Accenti: --arc-accent è bianco; i colori solo per gli stati
    readonly property color accent: "#ffffff"
    readonly property color accentText: "#0f0d14"
    readonly property color brand: "#8c52ff"
    readonly property color green: "#22c55e"
    readonly property color yellow: "#f59e0b"
    readonly property color red: "#ef4444"
    readonly property color blue: "#3b82f6"

    // --- Raggi: --arc-r-*
    readonly property int rXs: 6
    readonly property int rSm: 10
    readonly property int rMd: 14
    readonly property int rLg: 20
    readonly property int rXl: 28
    // Raggi concentrici: in un gruppo annidato l'elemento interno ha il
    // raggio di quello esterno meno la distanza tra i due bordi, così le
    // curve restano parallele (finestre, pannelli, menu, widget, dock)
    function inner(outer, pad) { return Math.max(0, outer - pad); }
    function outer(inner, pad) { return inner + pad; }
    // Elementi affiancati in un gruppo (barra laterale | contenuto): gli
    // angoli rivolti al vicino restano piccoli
    readonly property int groupInner: 6
    // Angoli di un elemento in un gruppo: grande (concentrico) solo dove
    // entrambi i lati dell'angolo sono sul bordo del gruppo, piccolo dove
    // c'è un vicino. Ordine: [alto-sx, alto-dx, basso-dx, basso-sx]
    function groupCorners(outer, top, right, bottom, left) {
        const c = (a, b) => a && b ? outer : Math.min(groupInner, outer);
        return [c(top, left), c(top, right), c(bottom, right), c(bottom, left)];
    }
    readonly property int r2xl: 36

    // --- Tipografia
    readonly property string font: "Google Sans Flex"

    // --- Misure della shell (mockup 1440×1024)
    readonly property int edge: 24          // distanza dai bordi dello schermo
    readonly property int edgeTop: 20
    readonly property int gap: 16
    readonly property int topbarHeight: 52
    readonly property int topbarRadius: 18
    readonly property int attachedBarHeight: 44
    readonly property int panelTop: edgeTop + topbarHeight + 10   // sotto la topbar

    // Dock: icone e ingrandimento "a onda"
    readonly property int dockIcon: 54
    readonly property int dockPadding: 10
    readonly property int dockSpacing: 8
    // Margine uguale su tutti i lati; angoli concentrici a quelli delle icone:
    // raggio del corpo dell'icona + distanza dal bordo della dock
    readonly property int dockHeight: dockIcon + 2 * dockPadding
    readonly property int dockRadius: Math.round(dockIcon * ((1 - iconBody) / 2 + iconBody * iconCorner) + dockPadding)

    // Icone delle app (Ticly Sequoia): corpo squircle all'80% del riquadro
    readonly property real iconBody: 0.797
    readonly property real iconCorner: 0.2237
    readonly property real dockZoom: 1.6           // ingrandimento massimo
    readonly property real dockZoomRange: 2.6      // icone coinvolte per lato

    // Widget: griglia come le card del mockup (S = 1×1, M = 2×1, L = 2×2)
    readonly property int cellWidth: 179
    readonly property int cellHeight: 185
    readonly property int cellGap: 8         // widget vicini: un gruppo
    readonly property int widgetRadius: 26

    // --- Movimento: --spring, --ease-out
    readonly property int fast: 150
    readonly property int normal: 260
    readonly property int slow: 420
}
