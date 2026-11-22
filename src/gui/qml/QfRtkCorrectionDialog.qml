import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield.core
import org.qfield.gui
import "QfRtkMath.js" as RtkMath

/**
 * Project correction configuration: pole height, correction mode, elevation
 * handling, control points and the least squares solution.
 *
 * \ingroup qml_gui
 */
QfPopup {
  id: popup
  parent: mainWindow.contentItem

  property var rtkSettings: undefined
  property var positioning: undefined
  property var qualitySettings: undefined
  property var mapSettings: undefined

  width: mainWindow.width - QfTheme.popupScreenEdgeHorizontalMargin * 2
  height: mainWindow.height - Math.max(QfTheme.popupScreenEdgeVerticalMargin * 2, mainWindow.sceneTopMargin * 2 + 4, mainWindow.sceneBottomMargin * 2 + 4)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  focus: visible
  closePolicy: Popup.CloseOnEscape

  readonly property var solution: popup.rtkSettings ? popup.rtkSettings.solution : ({})
  readonly property bool hasSolution: !!popup.rtkSettings && ((popup.rtkSettings.correctionMode === 1 && popup.solution && popup.solution.mode === 1) || (popup.rtkSettings.correctionMode === 2 && popup.solution && popup.solution.mode === 2))
  readonly property int controlPointCount: popup.rtkSettings && popup.rtkSettings.controlPoints ? popup.rtkSettings.controlPoints.length : 0
  readonly property bool solutionStale: !!popup.rtkSettings && popup.rtkSettings.correctionMode !== 0 && !popup.hasSolution

  function formatNumber(value, digits) {
    return isFinite(Number(value)) ? Number(value).toFixed(digits) : "-";
  }

  function syncFields() {
    if (!popup.rtkSettings) {
      return;
    }
    poleHeightField.text = isFinite(Number(popup.rtkSettings.antennaHeight)) ? Number(popup.rtkSettings.antennaHeight).toFixed(3) : "";
    elevationOffsetField.text = isFinite(Number(popup.rtkSettings.elevationOffset)) ? Number(popup.rtkSettings.elevationOffset).toFixed(3) : "";
    singleModeRadio.checked = popup.rtkSettings.correctionMode === 1;
    multiModeRadio.checked = popup.rtkSettings.correctionMode === 2;
    followPlanarRadio.checked = popup.rtkSettings.elevationMode === 0;
    independentElevationRadio.checked = popup.rtkSettings.elevationMode === 1;
    correctionEnabledSwitch.checked = popup.rtkSettings.correctionEnabled;
  }

  function solveError(result) {
    switch (result.error) {
    case "incomplete":
      return qsTr("Control point %1 is incomplete").arg((result.index !== undefined ? result.index : 0) + 1);
    case "notenough":
      return popup.rtkSettings && popup.rtkSettings.correctionMode === 1 ? qsTr("At least one control point is required") : qsTr("At least two control points are required for a four parameter correction");
    case "degenerate":
      return qsTr("Control points overlap, unable to solve");
    default:
      return qsTr("Unable to solve the correction parameters");
    }
  }

  function solve() {
    if (!popup.rtkSettings) {
      return;
    }
    if (popup.rtkSettings.correctionMode !== 1 && popup.rtkSettings.correctionMode !== 2) {
      displayToast(qsTr("Please select a correction mode"), 'warning');
      return;
    }
    if (popup.mapSettings && popup.mapSettings.destinationCrs && popup.mapSettings.destinationCrs.isGeographic) {
      displayToast(qsTr("The project CRS is geographic, planar correction is unavailable"), 'warning');
      return;
    }

    const result = popup.rtkSettings.correctionMode === 1 ? RtkMath.solveSinglePoint(popup.rtkSettings.controlPoints) : RtkMath.solveFourParameter(popup.rtkSettings.controlPoints);
    if (!result.ok) {
      displayToast(popup.solveError(result), 'warning');
      return;
    }

    result.solvedAt = new Date().toISOString();
    popup.rtkSettings.solution = result;
    popup.rtkSettings.correctionEnabled = true;
    displayToast(qsTr("Correction solved: %1 points, RMS %2 m").arg(result.count).arg(Number(result.rms).toFixed(4)));
  }

  function commitControlPoint(point) {
    if (!popup.rtkSettings) {
      return;
    }
    let list = popup.rtkSettings.controlPoints ? popup.rtkSettings.controlPoints.slice() : [];
    if (controlPointDialog.pointIndex >= 0 && controlPointDialog.pointIndex < list.length) {
      list[controlPointDialog.pointIndex] = point;
    } else {
      list.push(point);
    }
    popup.rtkSettings.controlPoints = list;
    // Editing the control points invalidates the previous solution.
    popup.rtkSettings.solution = ({});
  }

  function removeControlPoint(index) {
    if (!popup.rtkSettings || !popup.rtkSettings.controlPoints) {
      return;
    }
    let list = popup.rtkSettings.controlPoints.slice();
    list.splice(index, 1);
    popup.rtkSettings.controlPoints = list;
    popup.rtkSettings.solution = ({});
  }

  onAboutToShow: popup.syncFields()

  QfDialog {
    id: resetDialog
    parent: mainWindow.contentItem
    title: qsTr("Reset correction parameters")
    standardButtons: Dialog.NoButton

    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      text: qsTr("The solved correction parameters will be cleared. The pole height and the control points are kept.")
    }

    RowLayout {
      width: parent.width
      spacing: 8

      Item {
        Layout.fillWidth: true
      }

      QfButton {
        text: qsTr("Cancel")
        onClicked: resetDialog.close()
      }

      QfButton {
        text: qsTr("Reset")
        bgcolor: QfTheme.errorColor
        onClicked: {
          resetDialog.close();
          popup.rtkSettings.resetCorrection();
          popup.syncFields();
          displayToast(qsTr("Correction parameters have been reset, pole height kept"));
        }
      }
    }
  }

  QfRtkControlPointDialog {
    id: controlPointDialog
    rtkSettings: popup.rtkSettings
    positioning: popup.positioning
    qualitySettings: popup.qualitySettings

    onSaved: function (point) {
      popup.commitControlPoint(point);
    }
  }

  Page {
    id: page
    width: parent.width
    height: parent.height
    padding: 5

    header: QfPageHeader {
      title: qsTr("RTK correction")
      showBackButton: false
      showCancelButton: false
      showApplyButton: true

      onApply: popup.close()
    }

    ScrollView {
      topPadding: 0
      leftPadding: 5
      rightPadding: 5
      bottomPadding: 0
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical: QfScrollBar {}
      contentWidth: formLayout.childrenRect.width
      contentHeight: formLayout.childrenRect.height
      width: parent.width
      height: parent.height
      clip: true

      ColumnLayout {
        id: formLayout
        spacing: 8
        width: page.width - 20

        RowLayout {
          Layout.fillWidth: true

          Label {
            text: qsTr("Pole height")
            font: QfTheme.defaultFont
            color: QfTheme.mainTextColor
            Layout.fillWidth: true
          }

          QfTextField {
            id: poleHeightField
            Layout.preferredWidth: 130
            font: QfTheme.defaultFont
            horizontalAlignment: TextInput.AlignRight
            suffixText: qsTr("m")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator {
              locale: 'C'
              bottom: 0
              top: 10
            }

            onTextChanged: {
              if (!popup.rtkSettings || text.length === 0 || isNaN(text)) {
                return;
              }
              const value = parseFloat(text);
              if (value >= 0) {
                popup.rtkSettings.antennaHeight = value;
              }
            }
          }
        }

        Label {
          text: qsTr("The pole height is stored per project and applied to every measured point.")
          font: QfTheme.tipFont
          color: QfTheme.secondaryTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: QfTheme.controlBorderColor
        }

        RowLayout {
          Layout.fillWidth: true

          Label {
            text: qsTr("Enable coordinate correction")
            font: QfTheme.defaultFont
            color: QfTheme.mainTextColor
            Layout.fillWidth: true
          }

          QfSwitch {
            id: correctionEnabledSwitch
            checked: popup.rtkSettings ? popup.rtkSettings.correctionEnabled : false
            onCheckedChanged: {
              if (popup.rtkSettings) {
                popup.rtkSettings.correctionEnabled = checked;
              }
            }
          }
        }

        Label {
          text: qsTr("Correction mode")
          font: QfTheme.strongFont
          color: QfTheme.mainTextColor
          Layout.fillWidth: true
          Layout.topMargin: 4
        }

        RadioButton {
          id: singleModeRadio
          text: qsTr("Single-point translation correction")
          font: QfTheme.defaultFont
          Layout.fillWidth: true
          onClicked: {
            if (popup.rtkSettings) {
              popup.rtkSettings.correctionMode = 1;
              popup.rtkSettings.solution = ({});
            }
          }
        }

        RadioButton {
          id: multiModeRadio
          text: qsTr("Multi-point four parameter correction")
          font: QfTheme.defaultFont
          Layout.fillWidth: true
          onClicked: {
            if (popup.rtkSettings) {
              popup.rtkSettings.correctionMode = 2;
              popup.rtkSettings.solution = ({});
            }
          }
        }

        Label {
          text: qsTr("Elevation")
          font: QfTheme.strongFont
          color: QfTheme.mainTextColor
          Layout.fillWidth: true
          Layout.topMargin: 4
        }

        RadioButton {
          id: followPlanarRadio
          text: qsTr("Elevation follows the planar correction")
          font: QfTheme.defaultFont
          Layout.fillWidth: true
          onClicked: {
            if (popup.rtkSettings) {
              popup.rtkSettings.elevationMode = 0;
            }
          }
        }

        RadioButton {
          id: independentElevationRadio
          text: qsTr("Independent elevation correction")
          font: QfTheme.defaultFont
          Layout.fillWidth: true
          onClicked: {
            if (popup.rtkSettings) {
              popup.rtkSettings.elevationMode = 1;
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          enabled: independentElevationRadio.checked || (popup.rtkSettings && popup.rtkSettings.elevationMode === 1)

          Label {
            text: qsTr("Elevation offset")
            font: QfTheme.defaultFont
            color: QfTheme.mainTextColor
            Layout.fillWidth: true
          }

          QfTextField {
            id: elevationOffsetField
            Layout.preferredWidth: 130
            font: QfTheme.defaultFont
            horizontalAlignment: TextInput.AlignRight
            suffixText: qsTr("m")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator {
              locale: 'C'
            }

            onTextChanged: {
              if (!popup.rtkSettings || text.length === 0 || isNaN(text)) {
                return;
              }
              popup.rtkSettings.elevationOffset = parseFloat(text);
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: QfTheme.controlBorderColor
        }

        RowLayout {
          Layout.fillWidth: true

          Label {
            text: qsTr("Control points")
            font: QfTheme.strongFont
            color: QfTheme.mainTextColor
            Layout.fillWidth: true
          }

          QfButton {
            text: qsTr("Add")
            onClicked: controlPointDialog.loadPoint({}, -1)
          }
        }

        Label {
          visible: popup.controlPointCount === 0
          text: qsTr("No control points yet. Add at least one for a single-point correction or two for a four parameter correction.")
          font: QfTheme.tipFont
          color: QfTheme.secondaryTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 4

          Repeater {
            model: popup.rtkSettings ? popup.rtkSettings.controlPoints : []

            delegate: Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 62
              radius: 4
              color: QfTheme.controlBackgroundAlternateColor

              RowLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 6

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0

                  Text {
                    text: modelData.name !== undefined && modelData.name !== "" ? modelData.name : qsTr("Control point %1").arg(index + 1)
                    font: QfTheme.strongTipFont
                    color: QfTheme.mainTextColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    text: qsTr("Known: %1, %2, %3").arg(popup.formatNumber(modelData.kx, 3)).arg(popup.formatNumber(modelData.ky, 3)).arg(popup.formatNumber(modelData.kh, 3))
                    font: QfTheme.tinyFont
                    color: QfTheme.secondaryTextColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    text: qsTr("Measured: %1, %2, %3").arg(popup.formatNumber(modelData.mx, 3)).arg(popup.formatNumber(modelData.my, 3)).arg(popup.formatNumber(modelData.mh, 3))
                    font: QfTheme.tinyFont
                    color: QfTheme.secondaryTextColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                }

                QfToolButton {
                  iconSource: QfTheme.getThemeVectorIcon("ic_edit_attributes_white_24dp")
                  iconColor: QfTheme.toolButtonColor
                  bgcolor: "transparent"
                  width: 36
                  height: 36
                  onClicked: controlPointDialog.loadPoint(modelData, index)
                }

                QfToolButton {
                  iconSource: QfTheme.getThemeVectorIcon("ic_remove_white_24dp")
                  iconColor: QfTheme.toolButtonColor
                  bgcolor: "transparent"
                  width: 36
                  height: 36
                  onClicked: popup.removeControlPoint(index)
                }
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: QfTheme.controlBorderColor
        }

        Label {
          text: {
            if (popup.hasSolution) {
              if (popup.solution.mode === 1) {
                return qsTr("Single-point correction: dX %1 m, dY %2 m, dH %3 m").arg(popup.formatNumber(popup.solution.dx, 4)).arg(popup.formatNumber(popup.solution.dy, 4)).arg(popup.formatNumber(popup.solution.dz, 4));
              }
              return qsTr("Four parameter correction: %1 points, RMS %2 m, scale %3, rotation %4°").arg(popup.solution.count).arg(popup.formatNumber(popup.solution.rms, 4)).arg(popup.formatNumber(popup.solution.scale, 6)).arg(popup.formatNumber(popup.solution.rotation, 4));
            }
            return popup.solutionStale ? qsTr("No valid solution, solve again after editing the control points") : qsTr("Not solved yet");
          }
          font: QfTheme.tipFont
          color: popup.hasSolution ? QfTheme.mainTextColor : QfTheme.secondaryTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        QfButton {
          Layout.fillWidth: true
          text: qsTr("Start solving")
          onClicked: popup.solve()
        }

        QfButton {
          Layout.fillWidth: true
          text: qsTr("Reset correction parameters")
          bgcolor: QfTheme.errorColor
          onClicked: resetDialog.open()
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.minimumHeight: mainWindow.sceneBottomMargin
        }
      }
    }
  }
}
