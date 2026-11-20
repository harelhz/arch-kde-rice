/*
 * "Clean (all screens)" — KWin task switcher by Claude.
 * One identical, minimal switcher centred on every monitor; all copies follow
 * the same selection. Fades/zooms in, the selection glides between windows,
 * and the selected preview lifts while the rest dim.
 */
import QtQuick
import QtQml.Models
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kwin as KWin

KWin.TabBoxSwitcher {
    id: tabBox

    readonly property int cellWidth: Kirigami.Units.gridUnit * 17
    readonly property int cellHeight: Kirigami.Units.gridUnit * 12.5
    readonly property int glide: 260          // ms, selection movement
    readonly property int appear: 220         // ms, open animation

    Instantiator {
        model: Qt.application.screens

        delegate: PlasmaCore.Dialog {
            id: dialog
            required property var modelData
            readonly property var scr: modelData

            location: PlasmaCore.Types.Floating
            visible: tabBox.visible
            flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
            x: scr.virtualX + Math.round((scr.width - width) / 2)
            y: scr.virtualY + Math.round((scr.height - height) / 2)

            onVisibleChanged: {
                if (visible) {
                    grid.animate = false;
                    grid.currentIndex = tabBox.currentIndex;
                    content.opacity = 0;
                    content.scale = 0.94;
                    openAnim.restart();
                    Qt.callLater(function() { grid.animate = true; });
                }
            }

            mainItem: Item {
                id: content
                readonly property int maxColumns: Math.max(1, Math.floor(dialog.scr.width * 0.85 / tabBox.cellWidth))
                readonly property int maxRows: Math.max(1, Math.floor(dialog.scr.height * 0.75 / tabBox.cellHeight))
                readonly property int columns: Math.max(1, Math.min(grid.count, maxColumns))
                readonly property int rows: Math.max(1, Math.min(maxRows, Math.ceil(grid.count / columns)))

                width: columns * tabBox.cellWidth
                height: rows * tabBox.cellHeight
                transformOrigin: Item.Center

                ParallelAnimation {
                    id: openAnim
                    NumberAnimation { target: content; property: "opacity"; to: 1; duration: tabBox.appear; easing.type: Easing.OutQuint }
                    NumberAnimation { target: content; property: "scale"; to: 1; duration: tabBox.appear; easing.type: Easing.OutQuint }
                }

                GridView {
                    id: grid
                    anchors.fill: parent
                    model: tabBox.model
                    cellWidth: tabBox.cellWidth
                    cellHeight: tabBox.cellHeight
                    currentIndex: tabBox.currentIndex
                    clip: true
                    interactive: false
                    keyNavigationWraps: true
                    highlightFollowsCurrentItem: false
                    property bool animate: true

                    Connections {
                        target: tabBox
                        function onCurrentIndexChanged() { grid.currentIndex = tabBox.currentIndex; }
                    }

                    // Soft white card behind the selected window; glides as you Tab.
                    highlight: Rectangle {
                        x: grid.currentItem ? grid.currentItem.x : 0
                        y: grid.currentItem ? grid.currentItem.y : 0
                        width: grid.cellWidth
                        height: grid.cellHeight
                        Behavior on x { enabled: grid.animate; NumberAnimation { duration: tabBox.glide; easing.type: Easing.OutQuint } }
                        Behavior on y { enabled: grid.animate; NumberAnimation { duration: tabBox.glide; easing.type: Easing.OutQuint } }
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.35)
                    }

                    delegate: Item {
                        id: cell
                        required property int index
                        required property string caption
                        required property var icon
                        required property var windowId
                        readonly property bool selected: index === grid.currentIndex

                        width: grid.cellWidth
                        height: grid.cellHeight
                        opacity: selected ? 1.0 : 0.55
                        Behavior on opacity { enabled: grid.animate; NumberAnimation { duration: tabBox.glide; easing.type: Easing.OutQuint } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.largeSpacing

                            KWin.WindowThumbnail {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                wId: cell.windowId
                                scale: cell.selected ? 1.0 : 0.94
                                Behavior on scale { enabled: grid.animate; NumberAnimation { duration: tabBox.glide; easing.type: Easing.OutQuint } }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: cell.icon
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                }
                                PlasmaComponents3.Label {
                                    Layout.maximumWidth: tabBox.cellWidth - Kirigami.Units.gridUnit * 3
                                    text: cell.caption
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    font.weight: cell.selected ? Font.DemiBold : Font.Normal
                                }
                            }
                        }

                        TapHandler {
                            onSingleTapped: {
                                if (cell.index === tabBox.currentIndex) {
                                    tabBox.model.activate(cell.index);
                                } else {
                                    tabBox.currentIndex = cell.index;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
