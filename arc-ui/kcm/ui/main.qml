// Impostazioni di sistema → Aspetto → Sfondo (arc): miniature degli sfondi,
// clic = sfondo scelto subito; "Aggiungi immagine…" copia una foto in
// ~/Immagini/Sfondi. Elenco e scelta arrivano da arc-shell.
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: root

    ColumnLayout {
        width: parent.width
        spacing: 16

        Label {
            Layout.fillWidth: true
            visible: !kcm.shellRunning
            wrapMode: Text.Wrap
            text: "La shell di arc non è in esecuzione: lo sfondo si può scegliere solo nella sessione arc."
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: "Scegli lo sfondo della scrivania e della schermata di accesso."
                wrapMode: Text.Wrap
                opacity: 0.7
            }
            Button {
                text: "Aggiungi immagine…"
                icon.name: "list-add"
                onClicked: picker.open()
            }
        }

        GridLayout {
            id: grid
            Layout.fillWidth: true
            readonly property int cell: 220
            columns: Math.max(1, Math.floor((width + columnSpacing) / (cell + columnSpacing)))
            columnSpacing: 14
            rowSpacing: 18

            Repeater {
                model: kcm.wallpapers

                ColumnLayout {
                    id: entry
                    required property string modelData
                    readonly property bool selected: modelData === kcm.current
                    Layout.preferredWidth: grid.cell
                    spacing: 6

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: width * 10 / 16

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: 16
                            color: "transparent"
                            border.width: 3
                            border.color: palette.highlight
                            visible: entry.selected
                        }
                        // Miniatura con gli angoli arrotondati come i pannelli arc
                        Rectangle {
                            id: mask
                            anchors.fill: parent
                            radius: 12
                            visible: false
                            layer.enabled: true
                        }
                        Image {
                            anchors.fill: parent
                            source: "file://" + entry.modelData
                            sourceSize.width: 440
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: mask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: kcm.choose(entry.modelData)
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: entry.modelData.split("/").pop().replace(/\.[^.]+$/, "").replace(/[-_]/g, " ")
                        font.weight: entry.selected ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }
    }

    FileDialog {
        id: picker
        title: "Aggiungi uno sfondo"
        nameFilters: ["Immagini (*.jpg *.jpeg *.png *.webp)"]
        onAccepted: kcm.addImage(selectedFile)
    }
}
