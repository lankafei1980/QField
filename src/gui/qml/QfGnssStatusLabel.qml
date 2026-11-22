import QtQuick
import org.qfield.core
import org.qfield.gui
import "QfRtkStatus.js" as RtkStatus

/**
 * Compact, colour coded GNSS fix status shown above the point capture button.
 *
 * \ingroup qml_gui
 */
Rectangle {
  id: root

  property var source: undefined
  property bool collecting: false

  readonly property string state: RtkStatus.gnssState(root.source ? root.source.active : false, root.source ? root.source.positionInformation : undefined, root.collecting)

  readonly property color statusColor: {
    switch (RtkStatus.gnssColorKey(root.state)) {
    case "good":
      return QfTheme.goodColor;
    case "warning":
      return QfTheme.warningColor;
    case "error":
      return QfTheme.errorColor;
    case "main":
      return QfTheme.mainColor;
    default:
      return "#e0e0e0";
    }
  }

  readonly property string statusText: {
    switch (root.state) {
    case "fixed":
      return qsTr("Fixed solution");
    case "float":
      return qsTr("Float solution");
    case "dgps":
      return qsTr("Differential solution");
    case "single":
      return qsTr("Single solution");
    case "acquiring":
      return qsTr("Acquiring satellites");
    case "capturing":
      return qsTr("Capturing");
    default:
      return qsTr("No fix");
    }
  }

  implicitWidth: statusLabel.width + 10
  implicitHeight: statusLabel.height + 2
  width: implicitWidth
  height: implicitHeight
  radius: 3
  color: "#99000000"
  visible: root.statusText !== ""

  Text {
    id: statusLabel
    anchors.centerIn: parent
    text: root.statusText
    color: root.statusColor
    font: QfTheme.tipFont
    style: Text.Outline
    styleColor: "#ccffffff"
  }
}
