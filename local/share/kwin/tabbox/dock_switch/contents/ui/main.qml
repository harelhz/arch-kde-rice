/*
 * "Dock Switch" — minimal KWin task switcher.
 * One row of app icons on a rounded panel styled like the dock,
 * a soft highlight on the selected app, and its window title underneath.
 */
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.kwin as KWin

KWin.TabBoxSwitcher {
    id: tabBox

    // --- look -------------------------------------------------------------
    readonly property int iconSize: 64
    readonly property int cell: 92          // icon + breathing room
    readonly property int pad: 14           // panel inner padding
    readonly property int radius: 24        // panel corner radius
    readonly property color panelColor: Qt.rgba(0.15, 0.15, 0.17, 0.88)
    readonly property color rimColor: Qt.rgba(1, 1, 1, 0.14)
    readonly property color pickColor: Qt.rgba(1, 1, 1, 0.13)
    // ----------------------------------------------------------------------

    Instantiator {
        active: tabBox.visible
        delegate: PlasmaCore.Dialog {
            location: PlasmaCore.Types.Floating
            backgroundHints: PlasmaCore.Dialog.NoBackground
            visible: true
            flags: Qt.ToolTip | Qt.X11BypassWindowManagerHint
            x: tabBox.screenGeometry.x + Math.round((tabBox.screenGeometry.width - panel.width) / 2)
            y: tabBox.screenGeometry.y + Math.round((tabBox.screenGeometry.height - panel.height) / 2)

            mainItem: Rectangle {
                id: panel
                readonly property int maxWidth: Math.floor(tabBox.screenGeometry.width * 0.9)
                width: Math.min(Math.max(list.count, 1) * tabBox.cell + tabBox.pad * 2, maxWidth)
                height: tabBox.pad + tabBox.cell + title.height + tabBox.pad
                radius: tabBox.radius
                color: tabBox.panelColor
                border.width: 1
                border.color: tabBox.rimColor

                opacity: 0
                scale: 0.96
                Component.onCompleted: { opacity = 1; scale = 1; }
                Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                ListView {
                    id: list
                    x: tabBox.pad
                    y: tabBox.pad
                    width: parent.width - tabBox.pad * 2
                    height: tabBox.cell
                    orientation: ListView.Horizontal
                    interactive: false
                    clip: true
                    model: tabBox.model
                    currentIndex: tabBox.currentIndex
                    highlightMoveDuration: 140
                    highlightResizeDuration: 0
                    preferredHighlightBegin: width / 2 - tabBox.cell / 2
                    preferredHighlightEnd: width / 2 + tabBox.cell / 2
                    highlightRangeMode: count * tabBox.cell > width ? ListView.ApplyRange : ListView.NoHighlightRange

                    highlight: Rectangle {
                        radius: 18
                        color: tabBox.pickColor
                    }

                    delegate: MouseArea {
                        readonly property string caption: model.caption
                        width: tabBox.cell
                        height: tabBox.cell
                        onClicked: tabBox.model.activate(index)

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: tabBox.iconSize
                            height: tabBox.iconSize
                            source: model.icon
                            opacity: model.minimized ? 0.5 : 1
                        }
                    }

                    Connections {
                        target: tabBox
                        function onCurrentIndexChanged() { list.currentIndex = tabBox.currentIndex; }
                    }
                }

                Text {
                    id: title
                    anchors.top: list.bottom
                    anchors.topMargin: 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, parent.width - tabBox.pad * 4)
                    text: list.currentItem ? list.currentItem.caption : ""
                    color: "#f2f2f5"
                    font.family: "Inter"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    bottomPadding: 2
                }
            }

            onSceneGraphError: () => {}
        }
    }
}
