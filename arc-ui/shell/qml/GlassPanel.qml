// Il materiale di arc UI, uguale per tutti i pannelli: tinta scura, bordo
// sottile e riflesso interno in alto (--arc-inset). La sfocatura vera la fa
// KWin dietro la stessa forma (Shell.setBlur con x, y, width, height, radius).
import QtQuick
import "."

Rectangle {
    id: panel

    color: Theme.material
    radius: Theme.rXl
    border.width: 1
    border.color: Theme.materialBorder

    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 1
            leftMargin: panel.radius * 0.7
            rightMargin: panel.radius * 0.7
        }
        height: 1
        color: Theme.materialInset
    }
}
