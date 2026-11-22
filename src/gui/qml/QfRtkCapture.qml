import QtQuick
import org.qfield.core
import "QfRtkMath.js" as RtkMath
import "QfRtkStatus.js" as RtkStatus

/**
 * Point capture state machine.
 *
 * Reads the system wide quality control settings and the project correction
 * settings, collects N valid GNSS fixes, averages them, projects the mean with
 * the same coordinate transformer that drives the live position (so the height
 * handling is identical) and applies the project correction.
 *
 * \ingroup qml_gui
 */
Item {
  id: root

  visible: false

  property var positioning: undefined
  property var qualitySettings: undefined
  property var rtkSettings: undefined

  /**
   * When false the project correction is not applied, which is what control
   * point measurement needs (the correction is what is being solved there).
   */
  property bool applyProjectCorrection: true

  // "idle", "collecting", "succeeded", "failed"
  property string captureState: "idle"
  property int acceptedCount: 0
  property int targetCount: 5
  property real progress: 0
  property string failureReason: ""
  property var lastPoint: undefined
  property bool lastForced: false

  readonly property bool collecting: root.captureState === "collecting"
  readonly property bool busy: root.captureState === "collecting"

  // One accepted sample per second keeps the average meaningful and the ring visible.
  property int sampleIntervalMs: 1000

  property var samples: []
  property double lastSampleTime: 0

  signal finished(var point, bool forced)
  signal blocked(string reason, bool canForce)
  signal failed(string reason)

  Timer {
    id: timeoutTimer
    repeat: false
    onTriggered: root.failCapture("timeout")
  }

  Connections {
    target: root.positioning

    function onPositionInformationChanged() {
      root.tryCollect(false);
    }
  }

  function describeReason(reason) {
    switch (reason) {
    case "noposition":
      return qsTr("No positioning, unable to capture");
    case "nodifferential":
      return qsTr("The positioning device does not support differential corrections, fixed solution unavailable");
    case "ntripdisabled":
      return qsTr("NTRIP corrections are disabled, fixed solution unavailable");
    case "ntripinvalid":
      return qsTr("No GNSS account or NTRIP service configured");
    case "ntripdisconnected":
      return qsTr("The differential service is not connected");
    case "ntripconnecting":
      return qsTr("The differential service is connecting");
    case "ntripstale":
      return qsTr("Differential data interrupted, check account or network");
    case "notfixed":
      return qsTr("Differential service connected but no fixed solution, check account, mount point or CRS");
    case "quality":
      return qsTr("Fix status or accuracy out of limits, cannot capture");
    case "timeout":
      return qsTr("Sampling timed out, capture failed");
    default:
      return qsTr("Fix status or accuracy out of limits, cannot capture");
    }
  }

  function isNtripReason(reason) {
    return reason === "ntripdisabled" || reason === "ntripinvalid" || reason === "ntripdisconnected" || reason === "ntripconnecting" || reason === "ntripstale" || reason === "notfixed";
  }

  function reset() {
    timeoutTimer.stop();
    root.captureState = "idle";
    root.samples = [];
    root.acceptedCount = 0;
    root.progress = 0;
    root.failureReason = "";
    root.lastPoint = undefined;
    root.lastForced = false;
    root.lastSampleTime = 0;
  }

  function cancel() {
    if (root.captureState === "collecting") {
      root.reset();
    }
  }

  function blockerReason() {
    const info = root.positioning ? root.positioning.positionInformation : undefined;
    const active = root.positioning ? root.positioning.active : false;
    const ntripEnabled = root.positioning ? root.positioning.enableNtrip : false;
    const ntripState = root.positioning ? root.positioning.ntripState : 0;
    const ntripCurrentness = root.positioning && root.positioning.ntripCurrentness !== undefined ? root.positioning.ntripCurrentness : true;
    const ntripValid = root.positioning && root.positioning.ntripSettings ? root.positioning.ntripSettings.isValid : false;
    // QfAbstractGnssReceiver::NtripCorrection
    const supportsNtrip = root.positioning ? (root.positioning.deviceCapabilities & QfAbstractGnssReceiver.NtripCorrection) !== 0 : false;
    const requireFixed = root.qualitySettings ? root.qualitySettings.rtkRequireFixedSolution : true;
    return RtkStatus.blockerKey(active, info, supportsNtrip, ntripEnabled, ntripValid, ntripState, ntripCurrentness, requireFixed);
  }

  function informationIsFresh(info) {
    if (!info || !info.utcDateTime) {
      return true;
    }
    const stamp = info.utcDateTime.getTime();
    return !isFinite(stamp) || Date.now() - stamp < 10000;
  }

  function currentSampleIsValid() {
    const info = root.positioning ? root.positioning.positionInformation : undefined;
    if (!root.positioning || !info || !root.informationIsFresh(info)) {
      return false;
    }
    return RtkStatus.sampleIsValid(info, root.qualitySettings.rtkRequireFixedSolution, root.qualitySettings.rtkMaxHrms, root.qualitySettings.rtkMaxVrms);
  }

  function start() {
    if (!root.positioning || !root.qualitySettings) {
      return false;
    }
    if (root.captureState === "collecting") {
      return false;
    }

    root.reset();

    const reason = root.blockerReason();
    if (reason !== "") {
      const canForce = root.qualitySettings.rtkAllowForcedCapture === true && root.positioning.active && root.positioning.positionInformation && root.positioning.positionInformation.latitudeValid;
      root.blocked(reason, canForce);
      return false;
    }

    if (!root.currentSampleIsValid()) {
      const canForce = root.qualitySettings.rtkAllowForcedCapture === true;
      root.blocked("quality", canForce);
      return false;
    }

    root.targetCount = Math.max(1, root.qualitySettings.rtkSampleCount);
    root.captureState = "collecting";
    timeoutTimer.interval = Math.max(5, root.qualitySettings.rtkSampleTimeoutSeconds) * 1000;
    timeoutTimer.start();
    root.tryCollect(true);
    return true;
  }

  function tryCollect(immediate) {
    if (root.captureState !== "collecting") {
      return;
    }

    const info = root.positioning ? root.positioning.positionInformation : undefined;
    if (!info || !root.informationIsFresh(info)) {
      return;
    }

    const now = Date.now();
    if (!immediate && now - root.lastSampleTime < root.sampleIntervalMs) {
      return;
    }

    if (!RtkStatus.sampleIsValid(info, root.qualitySettings.rtkRequireFixedSolution, root.qualitySettings.rtkMaxHrms, root.qualitySettings.rtkMaxVrms)) {
      return;
    }

    root.samples.push({
      "latitude": info.latitude,
      "longitude": info.longitude,
      "elevation": info.elevation
    });
    root.lastSampleTime = now;
    root.acceptedCount = root.samples.length;
    root.progress = Math.min(1, root.acceptedCount / root.targetCount);

    if (root.acceptedCount >= root.targetCount) {
      const point = root.buildPoint(true);
      if (point === undefined) {
        root.failCapture("noposition");
        return;
      }
      timeoutTimer.stop();
      root.captureState = "succeeded";
      root.lastPoint = point;
      root.lastForced = false;
      root.finished(point, false);
    }
  }

  /**
   * Emergency capture: uses the mean of the samples collected so far when there
   * are any, otherwise the current position.
   */
  function forceCapture() {
    if (root.captureState === "collecting") {
      timeoutTimer.stop();
    }
    const point = root.buildPoint(root.samples.length > 0);
    if (point === undefined) {
      root.failCapture("noposition");
      return;
    }
    root.captureState = "succeeded";
    root.lastPoint = point;
    root.lastForced = true;
    root.finished(point, true);
  }

  function failCapture(reason) {
    timeoutTimer.stop();
    root.captureState = "failed";
    root.failureReason = reason;
    root.failed(reason);
  }

  function buildPoint(useSamples) {
    if (!root.positioning) {
      return undefined;
    }

    let mean = null;
    if (useSamples && root.samples.length > 0) {
      mean = RtkMath.meanSamples(root.samples);
    } else {
      const info = root.positioning.positionInformation;
      if (!info || !info.latitudeValid) {
        return undefined;
      }
      mean = {
        "latitude": info.latitude,
        "longitude": info.longitude,
        "elevation": info.elevation
      };
    }
    if (!mean || !isFinite(mean.latitude) || !isFinite(mean.longitude)) {
      return undefined;
    }

    const transformer = root.positioning.coordinateTransformer;
    if (!transformer) {
      return undefined;
    }

    const sourcePoint = QfGeometryUtils.point(mean.longitude, mean.latitude, mean.elevation);
    const projected = transformer.transformPosition(sourcePoint);
    if (!projected || !isFinite(projected.x) || !isFinite(projected.y)) {
      return undefined;
    }

    const settings = root.rtkSettings;
    const correctionsEnabled = root.applyProjectCorrection && settings && settings.correctionEnabled === true;
    const corrected = RtkMath.applyCorrection(projected.x, projected.y, projected.z, correctionsEnabled, settings ? settings.correctionMode : 0, settings ? settings.solution : ({}), settings ? settings.elevationMode : 0, settings ? settings.elevationOffset : 0);

    return QfGeometryUtils.point(corrected.x, corrected.y, corrected.z);
  }
}
