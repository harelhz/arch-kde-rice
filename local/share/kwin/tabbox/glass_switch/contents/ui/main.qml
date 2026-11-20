/*
 * Glass Switch — KWin task switcher entry point.
 * The look lives in SwitcherView.qml (same folder).
 */
import QtQuick
import org.kde.kwin as KWin

KWin.TabBoxSwitcher {
    id: tabBox

    Instantiator {
        active: tabBox.visible
        delegate: SwitcherView {
            screenGeometry: tabBox.screenGeometry
            model: tabBox.model
            currentIndex: tabBox.currentIndex
            onActivated: index => tabBox.model.activate(index)
        }
    }
}
