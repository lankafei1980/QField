import QtCore
import QtQuick

/**
 * Project scoped RTK parameters: pole height, the correction settings and the
 * control points. They are stored in the same per-project QSettings namespace
 * that QField already uses for the map rotation and layer styles, so they never
 * write to (potentially read-only) project files.
 *
 * \ingroup qml_gui
 */
Item {
  id: root

  visible: false

  /*! Path of the currently opened project (projectInfo.filePath). */
  property string projectFilePath: ""

  /*! Pole height used as a seed for projects that do not have any stored value. */
  property real defaultAntennaHeight: 0

  property real antennaHeight: 0
  property bool correctionEnabled: false
  // 0 = none, 1 = single point, 2 = four parameter
  property int correctionMode: 0
  // 0 = follow planar correction, 1 = independent elevation offset
  property int elevationMode: 0
  property real elevationOffset: 0
  property var controlPoints: []
  property var solution: ({})

  property bool loading: false

  readonly property string settingsKey: "/qgis/projectInfo/" + root.projectFilePath + "/rtk/settings"

  function load() {
    root.loading = true;

    let data = null;
    if (root.projectFilePath !== "") {
      const raw = store.value(root.settingsKey, "");
      if (raw && typeof raw === "string" && raw.length > 0) {
        try {
          data = JSON.parse(raw);
        } catch (error) {
          data = null;
        }
      }
    }

    if (data && typeof data === "object") {
      root.antennaHeight = isNaN(parseFloat(data.antennaHeight)) ? 0 : parseFloat(data.antennaHeight);
      root.correctionEnabled = data.correctionEnabled === true;
      root.correctionMode = isNaN(parseInt(data.correctionMode)) ? 0 : parseInt(data.correctionMode);
      root.elevationMode = isNaN(parseInt(data.elevationMode)) ? 0 : parseInt(data.elevationMode);
      root.elevationOffset = isNaN(parseFloat(data.elevationOffset)) ? 0 : parseFloat(data.elevationOffset);
      root.controlPoints = Array.isArray(data.controlPoints) ? data.controlPoints : [];
      root.solution = data.solution && typeof data.solution === "object" ? data.solution : ({});
      root.loading = false;
    } else {
      root.antennaHeight = root.defaultAntennaHeight > 0 ? root.defaultAntennaHeight : 0;
      root.correctionEnabled = false;
      root.correctionMode = 0;
      root.elevationMode = 0;
      root.elevationOffset = 0;
      root.controlPoints = [];
      root.solution = ({});
      root.loading = false;
      if (root.projectFilePath !== "") {
        root.save();
      }
    }
  }

  function serialize() {
    return JSON.stringify({
      "antennaHeight": root.antennaHeight,
      "correctionEnabled": root.correctionEnabled,
      "correctionMode": root.correctionMode,
      "elevationMode": root.elevationMode,
      "elevationOffset": root.elevationOffset,
      "controlPoints": root.controlPoints,
      "solution": root.solution
    });
  }

  function save() {
    if (root.loading || root.projectFilePath === "") {
      return;
    }
    store.setValue(root.settingsKey, root.serialize());
  }

  /**
   * Clears the solved parameters and disables the correction. The pole height
   * and the control point list are intentionally kept.
   */
  function resetCorrection() {
    root.correctionEnabled = false;
    root.correctionMode = 0;
    root.elevationMode = 0;
    root.elevationOffset = 0;
    root.solution = ({});
    root.save();
  }

  function hasValidSolution() {
    if (!root.correctionEnabled || !root.solution) {
      return false;
    }
    return (root.correctionMode === 1 && root.solution.mode === 1) || (root.correctionMode === 2 && root.solution.mode === 2);
  }

  onProjectFilePathChanged: root.load()
  Component.onCompleted: root.load()

  onAntennaHeightChanged: root.save()

  onCorrectionEnabledChanged: root.save()

  onCorrectionModeChanged: root.save()

  onElevationModeChanged: root.save()

  onElevationOffsetChanged: root.save()

  onControlPointsChanged: root.save()

  onSolutionChanged: root.save()

  Settings {
    id: store
  }
}
