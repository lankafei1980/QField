import QtQuick
import QtQuick.Layouts
import org.qfield.core
import org.qfield.gui
import "QfRtkStatus.js" as RtkStatus

/**
 * Compact two line status card on the right hand side of the main screen:
 * correction state and the project pole height. Tapping it opens the correction
 * configuration dialog.
 *
 * \ingroup qml_gui
 */
Rectangle {
  id: card

  property var projectSettings: undefined

  signal configureRequested()

  readonly property string correctionState: RtkStatus.correctionState(card.projectSettings ? card.projectSettings.correctionEnabled : false, card.projectSettings ? card.projectSettings.correctionMode : 0, card.projectSettings ? card.projectSettings.solution : ({}), card.projectSettings ? card.projectSettings.elevationOffset : 0)

  readonly property string correctionText: {
    switch (card.correctionState) {
    case "single":
      return qsTr("Single-point correction");
    case "multi":
      return qsTr("Multi-point correction");
    case "elevation":
      return qsTr("Elevation correction");
    default:
      return qsTr("No correction");
    }
  }

  readonly property color correctionColor: card.correctionState === "none" ? QfTheme.secondaryTextColor : QfTheme.mainColor

  visible: !!card.projectSettings && card.projectSettings.projectFilePath !== ""
  radius: 4
  color: "#66000000"
  border.color: "#33ffffff"
  border.width: 1
  implicitWidth: content.implicitWidth + 16
  implicitHeight: content.implicitHeight + 10
  width: implicitWidth
  height: implicitHeight

  ColumnLayout {
    id: content
    anchors.centerIn: parent
    spacing: 2

    RowLayout {
      spacing: 4
      Layout.alignment: Qt.AlignRight

      Text {
        text: card.correctionText
        color: card.correctionColor
        font: QfTheme.tipFont
        style: Text.Outline
        styleColor: "#aa000000"
      }

      Image {
        source: QfTheme.getThemeVectorIcon("ic_tune_white_24dp")
        sourceSize.width: 12
        sourceSize.height: 12
        opacity: 0.85
        fillMode: Image.PreserveAspectFit
      }
    }

    RowLayout {
      spacing: 4
      Layout.alignment: Qt.AlignRight

      Image {
        source: QfTheme.getThemeVectorIcon("ic_rtk_pole_white_24dp")
        sourceSize.width: 11
        sourceSize.height: 14
        fillMode: Image.PreserveAspectFit
      }

      Text {
        text: qsTr("Pole height: %1 m").arg(Number(card.projectSettings ? card.projectSettings.antennaHeight : 0).toFixed(3))
        color: QfTheme.mainTextColor
        font: QfTheme.tipFont
        style: Text.Outline
        styleColor: "#aa000000"
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: card.configureRequested()
  }
}
