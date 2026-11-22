.pragma library

/**
 * Fix quality reported by NMEA GGA / the positioning source, mapped to the
 * states used by the on-screen Chinese status label.
 *
 * The label text itself lives in QfGnssStatusLabel.qml so that it can be
 * translated (a JS library has no translation context).
 */
function gnssState(active, info, collecting) {
  if (collecting) {
    return "capturing";
  }
  if (!active) {
    return "nofix";
  }
  if (!info || !info.latitudeValid) {
    return "acquiring";
  }
  switch (info.quality) {
  case 4:
    return "fixed";
  case 5:
    return "float";
  case 2:
    return "dgps";
  case 0:
    return "nofix";
  default:
    // 1 = autonomous, 3 = PPS, 6/7/8 = estimated/manual/simulation: all show
    // as a single (non-differential) solution.
    return "single";
  }
}

/**
 * Maps a state to a theme colour key: good, warning, error, main or gray.
 */
function gnssColorKey(state) {
  switch (state) {
  case "fixed":
    return "good";
  case "float":
  case "dgps":
    return "warning";
  case "single":
  case "acquiring":
    return "error";
  case "capturing":
    return "main";
  default:
    return "gray";
  }
}

/**
 * Derives the correction status shown on the main screen.
 *
 * @param enabled         master "enable coordinate correction" switch
 * @param mode            selected mode: 0 none, 1 single point, 2 four parameter
 * @param solution        last solved parameters ({} when never solved)
 * @param elevationOffset independent elevation offset in metres
 */
function correctionState(enabled, mode, solution, elevationOffset) {
  if (!enabled) {
    return "none";
  }
  if (mode === 2 && solution && solution.mode === 2) {
    return "multi";
  }
  if (mode === 1 && solution && solution.mode === 1) {
    return "single";
  }
  if (elevationOffset && Math.abs(elevationOffset) > 1e-9) {
    return "elevation";
  }
  return "none";
}

/**
 * Whether a sample fulfils the configured capture quality control.
 *
 * @param info          QfGnssPositionInformation
 * @param requireFixed  accept RTK fixed solutions only
 * @param maxHrms       horizontal limit in metres (0 disables the check)
 * @param maxVrms       vertical limit in metres (0 disables the check)
 */
function sampleIsValid(info, requireFixed, maxHrms, maxVrms) {
  if (!info || !info.latitudeValid || !info.longitudeValid) {
    return false;
  }
  if (requireFixed && info.quality !== 4) {
    return false;
  }
  if (info.quality === 0 || info.quality === -1) {
    return false;
  }
  if (maxHrms > 0 && (!info.haccValid || !(info.hacc <= maxHrms))) {
    return false;
  }
  if (maxVrms > 0 && (!info.vaccValid || !(info.vacc <= maxVrms))) {
    return false;
  }
  return true;
}

/**
 * Human readable reason for the most common capture blockers. Returns a key,
 * the Chinese text lives in the QML that owns the toast.
 */
function blockerKey(active, info, deviceSupportsNtrip, ntripEnabled, ntripValid, ntripState, ntripCurrentness, requireFixed) {
  if (!active || !info || !info.latitudeValid) {
    return "noposition";
  }
  if (!requireFixed) {
    // Without the fixed solution requirement a local/autonomous solution is
    // acceptable, so the state of the differential service is irrelevant.
    return "";
  }
  if (!deviceSupportsNtrip) {
    return "nodifferential";
  }
  if (!ntripEnabled) {
    return "ntripdisabled";
  }
  if (!ntripValid) {
    return "ntripinvalid";
  }
  if (ntripState === 0) {
    // QfPositioningSource::NtripState::Disconnected
    return "ntripdisconnected";
  }
  if (ntripState === 1) {
    // QfPositioningSource::NtripState::Connecting
    return "ntripconnecting";
  }
  if (!ntripCurrentness) {
    return "ntripstale";
  }
  if (requireFixed && info.quality !== 4) {
    return "notfixed";
  }
  return "";
}
