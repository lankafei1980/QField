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
 * The card intentionally has no background: it follows the map label style of
 * the scale bar (dark text with a white outline), so it stays readable on both
 * bright and dark basemaps.
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

  // Map label style: dark glyphs with a white outline, readable on any basemap.
  readonly property color labelColor: "#212121"
  readonly property color labelOutlineColor: "#e6ffffff"

  visible: !!card.projectSettings && card.projectSettings.projectFilePath !== ""
  color: "transparent"
  implicitWidth: content.implicitWidth + 8
  implicitHeight: content.implicitHeight
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
        color: card.labelColor
        font: QfTheme.tipFont
        style: Text.Outline
        styleColor: card.labelOutlineColor
      }

      Text {
        text: "›"
        color: card.labelColor
        font: QfTheme.defaultFont
        style: Text.Outline
        styleColor: card.labelOutlineColor
      }
    }

    RowLayout {
      spacing: 4
      Layout.alignment: Qt.AlignRight

      Image {
        source: QfTheme.getThemeVectorIcon("ic_rtk_pole_dark_24dp")
        sourceSize.width: 12
        sourceSize.height: 15
        fillMode: Image.PreserveAspectFit
      }

      Text {
        text: qsTr("Pole height: %1 m").arg(Number(card.projectSettings ? card.projectSettings.antennaHeight : 0).toFixed(1))
        color: card.labelColor
        font: QfTheme.tipFont
        style: Text.Outline
        styleColor: card.labelOutlineColor
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: card.configureRequested()
  }
}
