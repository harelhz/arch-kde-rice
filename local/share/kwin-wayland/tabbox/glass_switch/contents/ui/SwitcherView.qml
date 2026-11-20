/*
 * Glass Switch — the visible part of the switcher.
 * Live window previews on a "liquid glass" panel: whatever is behind the panel
 * (wallpaper + your windows) is rebuilt, blurred and saturated, then topped with
 * a light sheen and a specular rim.
 */
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWin

Window {
    id: win

    property rect screenGeometry
    property var model
    property int currentIndex: 0
    signal activated(int index)

    // ---- look ---------------------------------------------------------------
    readonly property int thumbW: 260
    readonly property int thumbH: Math.round(thumbW * Math.max(1, screenGeometry.height) / Math.max(1, screenGeometry.width))
    readonly property int cellPad: 14
    readonly property int cellW: thumbW + cellPad * 2
    readonly property int cellH: thumbH + cellPad * 2 + 30
    readonly property int pad: 16
    readonly property int radius: 32
    readonly property real dim: 0.22                       // darken the rest of the screen
    readonly property color tint: Qt.rgba(0.10, 0.10, 0.13, 0.20)
    readonly property color textColor: Qt.rgba(1, 1, 1, 0.92)
    // -------------------------------------------------------------------------

    x: screenGeometry.x
    y: screenGeometry.y
    width: screenGeometry.width
    height: screenGeometry.height
    flags: Qt.ToolTip | Qt.BypassWindowManagerHint | Qt.FramelessWindowHint
    color: "transparent"
    visible: true

    // Snapshot of what is on screen right now (bottom → top), to blur behind the glass.
    property var behind: []
    Component.onCompleted: {
        const d = KWin.Workspace.currentDesktop;
        const all = KWin.Workspace.stackingOrder;
        const out = [];
        for (let i = 0; i < all.length; i++) {
            const w = all[i];
            if (!w || w.deleted || w.minimized || w.hidden || w.hiddenByShowDesktop) continue;
            if (w.tooltip || w.popupWindow || w.outline || w.onScreenDisplay || w.appletPopup || w.splash) continue;
            let here = w.onAllDesktops;
            const ds = w.desktops || [];
            for (let j = 0; !here && j < ds.length; j++) here = ds[j] === d;
            if (here) out.push(w);
        }
        behind = out;
    }

    // ---- rebuilt screen (only ever shown blurred, through the glass) --------
    Item {
        id: scene
        width: win.width
        height: win.height

        KWin.DesktopBackground {
            anchors.fill: parent
            activity: KWin.Workspace.currentActivity
            desktop: KWin.Workspace.currentDesktop
            outputName: win.screen ? win.screen.name : ""
        }
        Repeater {
            model: win.behind
            delegate: KWin.WindowThumbnail {
                required property var modelData
                client: modelData
                x: modelData.frameGeometry.x - win.screenGeometry.x
                y: modelData.frameGeometry.y - win.screenGeometry.y
                width: modelData.frameGeometry.width
                height: modelData.frameGeometry.height
            }
        }
    }

    // gentle dim over the real screen
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, win.dim)
    }

    // ---- layout ------------------------------------------------------------
    readonly property int maxCols: Math.max(1, Math.floor((width * 0.9 - pad * 2) / cellW))
    readonly property int maxRows: Math.max(1, Math.floor((height * 0.8 - pad * 2) / cellH))
    readonly property int cols: Math.max(1, Math.min(grid.count, maxCols))
    readonly property int rows: Math.max(1, Math.min(Math.ceil(grid.count / cols), maxRows))
    readonly property int spill: 60   // extra backdrop around the panel so the blur has real edges

    RectangularShadow {
        anchors.fill: panel
        radius: win.radius
        offset.y: 14
        blur: 48
        spread: 0
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    Item {
        id: panel
        width: win.cols * win.cellW + win.pad * 2
        height: win.rows * win.cellH + win.pad * 2
        anchors.centerIn: parent

        opacity: 0
        scale: 0.97
        Component.onCompleted: { opacity = 1; scale = 1; }
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

        // blurred backdrop, clipped to the rounded panel
        ShaderEffectSource {
            id: backdrop
            sourceItem: scene
            hideSource: true
            live: true
            visible: false
            sourceRect: Qt.rect(panel.x - win.spill, panel.y - win.spill, panel.width + win.spill * 2, panel.height + win.spill * 2)
            width: panel.width + win.spill * 2
            height: panel.height + win.spill * 2
        }
        Item {
            id: glassMask
            x: -win.spill; y: -win.spill
            width: panel.width + win.spill * 2
            height: panel.height + win.spill * 2
            visible: false
            layer.enabled: true
            Rectangle {
                x: win.spill; y: win.spill
                width: panel.width; height: panel.height
                radius: win.radius
                antialiasing: true
            }
        }
        MultiEffect {
            x: -win.spill; y: -win.spill
            width: panel.width + win.spill * 2
            height: panel.height + win.spill * 2
            source: backdrop
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            blurMultiplier: 0.6
            saturation: 0.45
            brightness: 0.06
            maskEnabled: true
            maskSource: glassMask
            maskThresholdMin: 0.4
            maskSpreadAtMin: 0.3
        }

        // tint + top sheen
        Rectangle {
            anchors.fill: parent
            radius: win.radius
            color: win.tint
        }
        Rectangle {
            anchors.fill: parent
            radius: win.radius
            gradient: Gradient {
                GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.13) }
                GradientStop { position: 0.28; color: Qt.rgba(1, 1, 1, 0.03) }
                GradientStop { position: 1.0;  color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        // specular rim: bright top, fades on the sides, catches light again at the bottom
        Rectangle {
            id: rimLight
            anchors.fill: parent
            radius: win.radius
            visible: false
            layer.enabled: true
            gradient: Gradient {
                GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, 0.70) }
                GradientStop { position: 0.30; color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 1.0;  color: Qt.rgba(1, 1, 1, 0.38) }
            }
        }
        Rectangle {
            id: rimShape
            anchors.fill: parent
            radius: win.radius
            color: "transparent"
            border.width: 1.5
            border.color: "white"
            antialiasing: true
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: rimLight
            maskEnabled: true
            maskSource: rimShape
            maskThresholdMin: 0.1
            maskSpreadAtMin: 0.4
        }

        // ---- windows --------------------------------------------------------
        GridView {
            id: grid
            x: win.pad; y: win.pad
            width: win.cols * win.cellW
            height: win.rows * win.cellH
            cellWidth: win.cellW
            cellHeight: win.cellH
            model: win.model
            currentIndex: win.currentIndex
            interactive: false
            clip: true
            keyNavigationWraps: true
            highlightMoveDuration: 170
            highlightFollowsCurrentItem: true

            // selected window: a smaller pane of glass
            highlight: Rectangle {
                width: win.cellW; height: win.cellH
                radius: 22
                color: Qt.rgba(1, 1, 1, 0.11)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.28)
                antialiasing: true
            }

            delegate: MouseArea {
                id: cell
                // works with KWin's model (roles) and a plain JS array (test harness)
                readonly property var it: model.modelData !== undefined ? model.modelData : model
                readonly property bool selected: GridView.isCurrentItem
                width: win.cellW
                height: win.cellH
                hoverEnabled: true
                onClicked: win.activated(index)

                Item {
                    id: thumbBox
                    x: win.cellPad; y: win.cellPad
                    width: win.thumbW; height: win.thumbH

                    KWin.WindowThumbnail {
                        anchors.fill: parent
                        wId: cell.it.windowId
                        opacity: cell.selected ? 1 : 0.82
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }
                    Kirigami.Icon {
                        width: 40; height: 40
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.bottom
                        anchors.verticalCenterOffset: -6
                        source: cell.it.icon
                    }
                }

                Text {
                    anchors.top: thumbBox.bottom
                    anchors.topMargin: 18
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: win.thumbW
                    text: cell.it.caption || ""
                    color: win.textColor
                    opacity: cell.selected ? 1 : 0.7
                    font.family: "Inter"
                    font.pixelSize: 13
                    font.weight: cell.selected ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
