import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "pa.menu"

  readonly property color iconColor: button.active && button.useActiveColor ? button.activeColor : button.foreground

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Menu"
    opticalSize: Style.bar.iconCanvas + 2
    iconComponent: Component {
      OmIcon {
        anchors.fill: parent
        iconSize: width
        color: root.iconColor
      }
    }
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
