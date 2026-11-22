import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield.core
import org.qfield.gui

/**
 * Editor for a single correction control point. Coordinates are expressed in the
 * project CRS. The measured coordinates can be filled from a quality controlled
 * GNSS capture.
 *
 * \ingroup qml_gui
 */
QfPopup {
  id: popup
  parent: mainWindow.contentItem

  signal saved(var point)

  property var rtkSettings: undefined
  property var positioning: undefined
  property var qualitySettings: undefined
  property int pointIndex: -1

  width: mainWindow.width - QfTheme.popupScreenEdgeHorizontalMargin * 2
  height: mainWindow.height - Math.max(QfTheme.popupScreenEdgeVerticalMargin * 2, mainWindow.sceneTopMargin * 2 + 4, mainWindow.sceneBottomMargin * 2 + 4)
  x: (mainWindow.width - width) / 2
  y: (mainWindow.height - height) / 2
  focus: visible
  closePolicy: Popup.CloseOnEscape

  function loadPoint(point, index) {
    popup.pointIndex = index;
    cpName.text = point && point.name !== undefined ? String(point.name) : "";
    cpMx.text = point && point.mx !== undefined && point.mx !== "" ? String(point.mx) : "";
    cpMy.text = point && point.my !== undefined && point.my !== "" ? String(point.my) : "";
    cpMh.text = point && point.mh !== undefined && point.mh !== "" ? String(point.mh) : "";
    cpKx.text = point && point.kx !== undefined && point.kx !== "" ? String(point.kx) : "";
    cpKy.text = point && point.ky !== undefined && point.ky !== "" ? String(point.ky) : "";
    cpKh.text = point && point.kh !== undefined && point.kh !== "" ? String(point.kh) : "";
    popup.open();
  }

  function save() {
    const mx = parseFloat(cpMx.text);
    const my = parseFloat(cpMy.text);
    const kx = parseFloat(cpKx.text);
    const ky = parseFloat(cpKy.text);
    if (!isFinite(mx) || !isFinite(my) || !isFinite(kx) || !isFinite(ky)) {
      displayToast(qsTr("Please fill in the known and measured X and Y coordinates"), 'warning');
      return;
    }
    popup.saved({
      "name": cpName.text,
      "mx": mx,
      "my": my,
      "mh": cpMh.text === "" ? "" : parseFloat(cpMh.text),
      "kx": kx,
      "ky": ky,
      "kh": cpKh.text === "" ? "" : parseFloat(cpKh.text)
    });
    popup.close();
  }

  QfRtkCapture {
    id: capture
    positioning: popup.positioning
    qualitySettings: popup.qualitySettings
    rtkSettings: popup.rtkSettings
    applyProjectCorrection: false

    onFinished: function (point, forced) {
      cpMx.text = Number(point.x).toFixed(4);
      cpMy.text = Number(point.y).toFixed(4);
      cpMh.text = isFinite(point.z) ? Number(point.z).toFixed(4) : "";
      displayToast(qsTr("Measured coordinates captured"));
      capture.reset();
    }

    onBlocked: function (reason, canForce) {
      displayToast(capture.describeReason(reason), 'warning');
    }

    onFailed: function (reason) {
      displayToast(capture.describeReason(reason), 'error');
      capture.reset();
    }
  }

  Page {
    id: page
    width: parent.width
    height: parent.height
    padding: 5

    header: QfPageHeader {
      title: qsTr("Control point")
      showBackButton: false
      showCancelButton: true
      showApplyButton: true

      onCancel: popup.close()
      onApply: popup.save()
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

        Label {
          text: qsTr("Name")
          font: QfTheme.defaultFont
          color: QfTheme.mainTextColor
          Layout.fillWidth: true
        }

        QfTextField {
          id: cpName
          Layout.fillWidth: true
          font: QfTheme.defaultFont
        }

        Label {
          text: qsTr("Known coordinates (project CRS)")
          font: QfTheme.strongFont
          color: QfTheme.mainTextColor
          Layout.fillWidth: true
          Layout.topMargin: 6
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          QfTextField {
            id: cpKx
            Layout.fillWidth: true
            font: QfTheme.defaultFont
            placeholderText: qsTr("X")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator {
              locale: 'C'
            }
          }

          QfTextField {
            id: cpKy
            Layout.fillWidth: true
            font: QfTheme.defaultFont
            placeholderText: qsTr("Y")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator {
              locale: 'C'
            }
          }

          QfTextField {
            id: cpKh
            Layout.fillWidth: true
            font: QfTheme.defaultFont
            placeholderText: qsTr("H")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator {
              locale: 'C'
            }
          }
        }

        Label {
          text: qsTr("Measured coordinates (project CRS)")
          font: QfTheme.strongFont
          color: QfTheme.mainTextColor
          Layout.fillWidth: true
          Layout.topMargin: 6
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          QfTextField {
            id: cpMx
            Layout.fillWidth: true
            font: QfTheme.defaultFont
            placeholderText: qsTr("X")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator {
              locale: 'C'
            }
          }

          QfTextField {
            id: cpMy
            Layout.fillWidth: true
            font: QfTheme.defaultFont
            placeholderText: qsTr("Y")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator {
              locale: 'C'
            }
          }

          QfTextField {
            id: cpMh
            Layout.fillWidth: true
            font: QfTheme.defaultFont
            placeholderText: qsTr("H")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            validator: DoubleValidator {
              locale: 'C'
            }
          }
        }

        QfButton {
          Layout.fillWidth: true
          text: qsTr("Capture current coordinates")
          enabled: capture.state !== "collecting"
          onClicked: capture.start()
        }

        Label {
          text: qsTr("The capture follows the GNSS capture quality control settings; the existing corrections are not applied.")
          font: QfTheme.tipFont
          color: QfTheme.secondaryTextColor
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
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
