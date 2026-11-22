import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qgis
import org.qfield.core
import org.qfield.gui

/**
 * \ingroup qml_gui
 */
QfVisibilityFadingRow {
  id: digitizingToolbar

  property QfRubberbandModel rubberbandModel
  property MapSettings mapSettings

  property bool cogoEnabled: false
  property var cogoOperationSettings: undefined
  property alias cogoExecutor: cogoExecutor

  property bool showConfirmButton: true //<! if the geometry type is point, it will never be shown
  property bool screenHovering: false //<! if the stylus pen is used, one should not use the add button

  property bool geometryRequested: false
  property var geometryRequestedItem
  property VectorLayer geometryRequestedLayer

  property alias digitizingLogger: digitizingLogger
  property alias cancelDialog: cancelDialog

  readonly property bool isDigitizing: rubberbandModel ? rubberbandModel.vertexCount > 1 : false //!< Readonly

  property bool geometryValid: false

  signal requestJumpToPoint(var center, real scale, bool handleMargins)
  signal requestPosition(var item, bool fromCoordinateLocator)
  signal requestPositioningSettings

  /**
   * Project scoped RTK settings (pole height and correction). When set, point
   * layers are captured through the RTK point capture flow.
   */
  property var rtkSettings: undefined

  onStateVisibleChanged: {
    // Leaving the digitizing state (screen lock, geofence, project change...)
    // must never leave a capture running in the background.
    if (!stateVisible && rtkCapture && rtkCapture.collecting) {
      rtkCapture.cancel();
    }
  }

  function cancelRtkCapture() {
    if (rtkCapture) {
      rtkCapture.cancel();
    }
  }

  readonly property bool rtkPointMode: !!rubberbandModel && rubberbandModel.geometryType === Qgis.GeometryType.Point && digitizingToolbar.rtkSettings !== undefined && digitizingToolbar.rtkSettings !== null && !cogoEnabled

  spacing: 4

  /* This signal is emitted when the digitized geometry has been confirmed.
   * The correspoding handler is \c onConfirmed.
   */
  signal confirmed
  /* This signal is emitted when the user cancels geometry digitizing.
   * The correspoding handler is \c onCancel.
   */
  signal cancel
  signal vertexCountChanged

  Connections {
    target: rubberbandModel

    property bool deferredVertexCountChanged: false

    function onCurrentCoordinateChanged() {
      if (deferredVertexCountChanged) {
        const vertices = rubberbandModel.vertices;
        if (vertices[rubberbandModel.vertexCount - 1] !== vertices[rubberbandModel.vertexCount - 2]) {
          processVertexCountChanged();
          deferredVertexCountChanged = false;
        }
      }
    }

    function onVertexCountChanged() {
      if (rubberbandModel.geometryType === Qgis.GeometryType.Line && rubberbandModel.vertexCount === 2) {
        deferredVertexCountChanged = true;
      } else if (rubberbandModel.geometryType === Qgis.GeometryType.Polygon && rubberbandModel.vertexCount === 3) {
        deferredVertexCountChanged = true;
      } else {
        processVertexCountChanged();
      }
    }
  }

  function processVertexCountChanged() {
    // check whether geometry is valid and can be confirmed
    checkGeometryValidity();

    // emit the signal of digitizingToolbar
    vertexCountChanged();
  }

  QfDigitizingLogger {
    id: digitizingLogger

    project: qgisProject
    mapSettings: digitizingToolbar.mapSettings
    digitizingLayer: rubberbandModel ? rubberbandModel.vectorLayer : null

    positionInformation: positionSource.positionInformation
    positionLocked: coordinateLocator.positionLocked
    topSnappingResult: coordinateLocator.topSnappingResult
    cloudUserInformation: projectInfo.cloudUserInformation
  }

  QfToolButton {
    id: cancelButton
    iconSource: QfTheme.getThemeVectorIcon("ic_clear_white_24dp")
    visible: rubberbandModel && rubberbandModel.vertexCount > 1
    round: true
    bgcolor: QfTheme.darkRed

    onClicked: {
      dashBoard.shouldReturnHome = false;
      if (stateMachine.state !== "measure") {
        cancelDialog.open();
      } else {
        digitizingLogger.clearCoordinates();
        rubberbandModel.reset();
        cancel();
      }
    }
  }

  QfToolButton {
    id: confirmButton
    iconSource: QfTheme.getThemeVectorIcon("ic_check_white_24dp")
    visible: {
      if (!showConfirmButton) {
        false;
      } else {
        geometryValid;
      }
    }
    round: true
    bgcolor: !enabled ? QfTheme.toolButtonBackgroundSemiOpaqueColor : QfTheme.mainColor

    onClicked: {
      dashBoard.shouldReturnHome = false;
      confirm();
    }
  }

  QfCogoOperations {
    id: cogoOperations
    enabled: digitizingToolbar.cogoEnabled

    mapSettings: digitizingToolbar.mapSettings
    cogoOperationSettings: digitizingToolbar.cogoOperationSettings

    onEnabledChanged: {
      digitizingToolbar.cogoOperationSettings.visible = enabled;
      checkGeometryValidity();
    }

    onRequestJumpToPoint: function (center, scale, handleMargins) {
      digitizingToolbar.requestJumpToPoint(center, scale, handleMargins);
    }

    onRequestPosition: function (item, fromCoordinateLocator) {
      digitizingToolbar.requestPosition(item, fromCoordinateLocator);
    }

    QfCogoExecutor {
      id: cogoExecutor

      name: digitizingToolbar.cogoOperationSettings ? digitizingToolbar.cogoOperationSettings.name : ""
      parameterValues: digitizingToolbar.cogoOperationSettings ? digitizingToolbar.cogoOperationSettings.parameterValues : {}

      mapSettings: digitizingToolbar.mapSettings
      rubberbandModel: digitizingToolbar.rubberbandModel

      onParametersChanged: {
        cogoOperationSettings.parameters = parameters;
        cogoOperationSettings.clear();
      }
    }
  }

  Timer {
    id: removeVertexTimer
    interval: 700
    repeat: true

    onTriggered: {
      if (!rubberbandModel || rubberbandModel.vertexCount === 0) {
        stop();
      }
      removeVertex();
      if (interval > 100)
        interval = interval * 0.8;
    }
  }

  QfToolButton {
    id: removeVertexButton
    iconSource: QfTheme.getThemeVectorIcon("ic_remove_white_24dp")
    iconColor: QfTheme.toolButtonColor
    visible: rubberbandModel && rubberbandModel.vertexCount > 1
    round: true
    bgcolor: QfTheme.toolButtonBackgroundColor

    onPressed: {
      removeVertex();
      removeVertexTimer.interval = 700;
      removeVertexTimer.restart();
    }
    onReleased: {
      removeVertexTimer.stop();
    }
    onCanceled: {
      removeVertexTimer.stop();
    }
  }

  Item {
    id: addVertexButtonContainer
    width: addVertexButton.width + 10
    height: addVertexButton.height

    /**
     * Integrated ring around the capture button: shows the sampling progress and
     * turns red when a capture fails.
     */
    QfProgressRing {
      id: captureProgressRing
      anchors.centerIn: addVertexButton
      size: addVertexButton.width + 10
      width: size
      height: size
      from: 0
      to: 1
      value: Math.max(0, Math.min(1, rtkCapture.progress))
      strokeWidth: 3
      color: rtkCapture.captureState === "failed" ? QfTheme.errorColor : QfTheme.mainColor
      backgroundColor: "#33ffffff"
      visible: rtkCapture.captureState === "collecting" || rtkCapture.captureState === "succeeded" || rtkCapture.captureState === "failed"
    }

    /**
     * Chinese GNSS fix state, right above the capture button.
     */
    QfGnssStatusLabel {
      id: gnssStatusLabel
      anchors.horizontalCenter: addVertexButton.horizontalCenter
      anchors.bottom: addVertexButton.top
      anchors.bottomMargin: 3
      source: positionSource
      collecting: rtkCapture.collecting
      visible: digitizingToolbar.rtkPointMode
    }

    QfToolButton {
      id: addVertexButton
      anchors.centerIn: parent
      round: true
      enabled: !rtkCapture.collecting && ((cogoEnabled && cogoExecutor.isReady) || (!cogoEnabled && !screenHovering))
      bgcolor: {
        if (!enabled) {
          QfTheme.toolButtonBackgroundSemiOpaqueColor;
        } else if (!showConfirmButton) {
          QfTheme.toolButtonBackgroundColor;
        } else if (!rubberbandModel || rubberbandModel.geometryType === Qgis.GeometryType.Point || rubberbandModel.geometryType === Qgis.GeometryType.Null) {
          QfTheme.mainColor;
        } else {
          QfTheme.toolButtonBackgroundColor;
        }
      }
      iconSource: QfTheme.getThemeVectorIcon("ic_add_white_24dp")
      iconColor: enabled ? QfTheme.toolButtonColor : QfTheme.toolButtonBackgroundSemiOpaqueColor

      property bool lastAdditionAveraged: false
      property bool averagedPositionPressAndHeld: false
      property bool averagedPositionAutoRelease: false

      Connections {
        target: positionSource

        function onAveragedPositionCountChanged() {
          if (addVertexButton.averagedPositionAutoRelease && positionSource.averagedPosition && positionSource.averagedPositionCount >= positioningSettings.averagedPositioningMinimumCount && positioningSettings.averagedPositioningAutomaticStop) {
            addVertexButton.averagedPositionPressAndHeld = true;
            addVertexButton.released();
          }
        }
      }

      onPressAndHold: {
        if (rtkPointMode) {
          // Long press has no meaning for RTK point capture: a single tap samples
          // the configured number of fixes by itself.
          return;
        }
        if (!cogoEnabled && coordinateLocator && coordinateLocator.positionLocked) {
          if (!checkAccuracyRequirement()) {
            return;
          }
          averagedPositionPressAndHeld = true;
          positionSource.averagedPosition = true;
        }
      }

      onReleased: {
        if (!averagedPositionPressAndHeld) {
          return;
        }
        averagedPositionPressAndHeld = false;
        averagedPositionAutoRelease = false;
        if (coordinateLocator && coordinateLocator.positionLocked) {
          if (positioningSettings.averagedPositioning && positioningSettings.averagedPositioningMinimumCount > positionSource.averagedPositionCount) {
            displayToast(qsTr("The collected positions count does not meet the requirement"), 'warning');
            positionSource.averagedPosition = false;
            return;
          }
          if (!checkAccuracyRequirement()) {
            positionSource.averagedPosition = false;
            return;
          }
          lastAdditionAveraged = true;
          addVertex();
          if (rubberbandModel.geometryType === Qgis.GeometryType.Point || rubberbandModel.geometryType === Qgis.GeometryType.Null) {
            confirm();
          }
          positionSource.averagedPosition = false;
        }
      }

      onCanceled: {
        if (coordinateLocator.positionLocked) {
          positionSource.averagedPosition = false;
        }
      }

      onClicked: {
        if (rtkCapture.collecting) {
          return;
        }

        if (cogoEnabled) {
          if (cogoExecutor.isReady) {
            const success = cogoExecutor.execute();
            if (success) {
              cogoOperationSettings.clear();
              // Recenter to last added vertex
              mapSettings.setCenter(rubberbandModel.lastCoordinate, true);
              if (Number(rubberbandModel.geometryType) === Qgis.GeometryType.Point) {
                confirm();
              }
            }
          }
          return;
        }

        if (rtkPointMode) {
          lastAdditionAveraged = false;
          rtkCapture.start();
          return;
        }

        if (!checkAccuracyRequirement()) {
          return;
        }
        if (coordinateLocator && coordinateLocator.positionLocked && positioningSettings.averagedPositioning && (positioningSettings.averagedPositioningMinimumCount > 1 || !positioningSettings.averagedPositioningAutomaticStop)) {
          if (!positionSource.averagedPosition) {
            averagedPositionAutoRelease = true;
            positionSource.averagedPosition = true;
          } else {
            addVertexButton.averagedPositionPressAndHeld = true;
            addVertexButton.released();
          }
          return;
        }
        lastAdditionAveraged = false;
        if (rubberbandModel.geometryType === Qgis.GeometryType.Point || rubberbandModel.geometryType === Qgis.GeometryType.Null) {
          confirm();
        } else {
          addVertex();
        }
      }
    }
  }

  /**
   * Point capture state machine: quality control, N samples, averaging and the
   * project correction.
   */
  QfRtkCapture {
    id: rtkCapture
    positioning: positionSource
    qualitySettings: positioningSettings
    rtkSettings: digitizingToolbar.rtkSettings
  }

  Timer {
    id: rtkCaptureResetTimer
    interval: 1600
    repeat: false
    onTriggered: rtkCapture.reset()
  }

  property string rtkForceMessage: ""

  Connections {
    target: rtkCapture

    function onFinished(point, forced) {
      rtkCaptureResetTimer.restart();
      digitizingToolbar.confirmAt(point);
    }

    function onFailed(reason) {
      if (positioningSettings.rtkAllowForcedCapture && rtkCapture.samples.length > 0) {
        digitizingToolbar.rtkForceMessage = qsTr("Sampling timed out, %1 valid samples collected. Do you want to save the point with the collected samples?").arg(rtkCapture.samples.length);
        rtkForceDialog.open();
      } else {
        displayToast(rtkCapture.describeReason(reason), 'error');
        rtkCaptureResetTimer.restart();
      }
    }

    function onBlocked(reason, canForce) {
      if (canForce) {
        digitizingToolbar.rtkForceMessage = qsTr("%1 Do you want to force the capture?").arg(rtkCapture.describeReason(reason));
        rtkForceDialog.open();
      } else if (rtkCapture.isNtripReason(reason)) {
        displayToast(rtkCapture.describeReason(reason), 'warning', qsTr("Go to settings"), () => {
          digitizingToolbar.requestPositioningSettings();
        });
      } else {
        displayToast(rtkCapture.describeReason(reason), 'warning');
      }
    }
  }

  QfDialog {
    id: rtkForceDialog
    parent: mainWindow.contentItem
    title: qsTr("Forced capture")
    standardButtons: Dialog.NoButton
    width: Math.min(mainWindow.width - QfTheme.popupScreenEdgeHorizontalMargin * 2, 400)
    contentHeight: forceContent.height

    Column {
      id: forceContent
      width: parent.width
      height: childrenRect.height
      spacing: 12

      Label {
        width: parent.width
        wrapMode: Text.WordWrap
        font: QfTheme.defaultFont
        color: QfTheme.mainTextColor
        text: digitizingToolbar.rtkForceMessage
      }

      RowLayout {
        width: parent.width
        spacing: 8

        Item {
          Layout.fillWidth: true
        }

        QfButton {
          text: qsTr("Cancel")
          onClicked: {
            rtkForceDialog.close();
            rtkCapture.reset();
          }
        }

        QfButton {
          text: qsTr("Force capture")
          bgcolor: QfTheme.errorColor
          onClicked: {
            rtkForceDialog.close();
            rtkCapture.forceCapture();
          }
        }
      }
    }
  }

  QfDialog {
    id: cancelDialog
    parent: mainWindow.contentItem
    title: qsTr("Cancel digitizing")
    Label {
      width: parent.width
      wrapMode: Text.WordWrap
      text: qsTr("Should the digitized geometry be discarded?")
    }
    onAccepted: {
      digitizingLogger.clearCoordinates();
      rubberbandModel.reset();
      cancel();
      visible = false;
    }
    onRejected: {
      visible = false;
    }
  }

  function checkAccuracyRequirement() {
    if (coordinateLocator && coordinateLocator.positionLocked && positioningSettings.accuracyIndicator && positioningSettings.accuracyRequirement) {
      if (positioningSettings.accuracyBad > 0 && (!coordinateLocator.positionInformation || !coordinateLocator.positionInformation.haccValid || coordinateLocator.positionInformation.hacc >= positioningSettings.accuracyBad)) {
        displayToast(qsTr("Position accuracy doesn't meet the minimum requirement, vertex not added"), 'warning');
        return false;
      }
    }
    return true;
  }

  function checkGeometryValidity() {
    const extraVertexNeed = cogoEnabled || (coordinateLocator && coordinateLocator.positionLocked && positioningSettings.averagedPositioning && positioningSettings.averagedPositioningMinimumCount > 1) ? 1 : 0;

    // set geometry valid
    if (!rubberbandModel || rubberbandModel.geometryType === Qgis.GeometryType.Point) {
      geometryValid = false;
    } else if (rubberbandModel.geometryType === Qgis.GeometryType.Line) {
      // Line: at least 2 points
      geometryValid = rubberbandModel.vertexCount > 1 + extraVertexNeed;
    } else if (rubberbandModel.geometryType === Qgis.GeometryType.Polygon) {
      // Polygon: at least 3 points
      geometryValid = rubberbandModel.vertexCount > 2 + extraVertexNeed;
    } else {
      geometryValid = false;
    }
  }

  function triggerAddVertex() {
    addVertexButton.clicked();
  }

  function addVertex() {
    digitizingLogger.addCoordinate(coordinateLocator.currentCoordinate);
    coordinateLocator.flash();
    rubberbandModel.addVertex();
  }

  function removeVertex() {
    digitizingLogger.removeLastCoordinate();
    rubberbandModel.removeVertex();
    mapSettings.setCenter(rubberbandModel.currentCoordinate, true);
  }

  function confirm() {
    // Point features must be measured at the live GNSS position. Guard the
    // map-tap path (and the volume-key path) against silently falling back to
    // the coordinate cursor target when positioning is unavailable.
    if (!geometryRequested && coordinateLocator.rtkCapturePoint === undefined && rubberbandModel && rubberbandModel.geometryType === Qgis.GeometryType.Point && (!positionSource.active || !positionSource.positionInformation || !positionSource.positionInformation.latitudeValid)) {
      displayToast(qsTr("No positioning, unable to capture"), 'warning');
      return;
    }
    rubberbandModel.frozen = true;
    if (addVertexButton.lastAdditionAveraged) {
      rubberbandModel.removeVertex();
    } else {
      digitizingLogger.addCoordinate(coordinateLocator.currentCoordinate);
    }
    confirmed();
  }

  /**
   * Commits a point that has already been measured (averaged GNSS position with
   * the project corrections applied) through the regular feature creation path.
   */
  function confirmAt(point) {
    if (!point || point.x === undefined) {
      return;
    }
    coordinateLocator.rtkCapturePoint = point;
    confirm();
    coordinateLocator.rtkCapturePoint = undefined;
  }
}
