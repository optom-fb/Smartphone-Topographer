function exportTable = mirePointsForCsv(candidates, pre, cfg)
%MIREPOINTSFORCSV Convert internal pixel detections to sensor-plane mm.
%   Internal localization remains in pixels. CSV coordinates are exported
%   relative to the detected Placido centre on the camera sensor plane.
%   The pixel-ray and physical sensor-plane angle conventions are named
%   separately so the y-axis inversion and anisotropic pixel pitch remain
%   explicit.
%   These are not corneal-surface coordinates; quantitative interpretation
%   still requires a validated device calibration.

required = {'X','Y','RadiusPx','WidthPx','AngleDeg'};
missing = required(~ismember(required, candidates.Properties.VariableNames));
if ~isempty(missing)
    error('SmartKC:MissingMireExportColumns', ...
        'Candidate table is missing: %s.', strjoin(missing, ', '));
end

imageHeight = pre.OriginalSize(1);
imageWidth = pre.OriginalSize(2);
sensorSizeMm = getProcessingSensorSizeMm(pre, cfg);
pitchXmm = sensorSizeMm(1) / imageWidth;
pitchYmm = sensorSizeMm(2) / imageHeight;

sensorXmm = (candidates.X-pre.CenterPx(1)) * pitchXmm;
sensorYmm = -(candidates.Y-pre.CenterPx(2)) * pitchYmm;
sensorRadiusMm = hypot(sensorXmm, sensorYmm);
sensorAngleDegCCW = mod(atan2d(sensorYmm, sensorXmm), 360);
radialPitchMm = hypot(cosd(candidates.AngleDeg)*pitchXmm, ...
    sind(candidates.AngleDeg)*pitchYmm);
sensorWidthMm = candidates.WidthPx .* radialPitchMm;

rowCount = height(candidates);
spatialUnit = repmat("mm", rowCount, 1);
coordinateFrame = repmat( ...
    "camera-sensor-plane; origin=detected-centre; x=right; y=superior", ...
    rowCount, 1);
if cfg.calibration.IsDeviceSpecific
    calibrationStatus = repmat("DEVICE_PROFILE_SET_REQUIRES_VALIDATION", ...
        rowCount, 1);
else
    calibrationStatus = repmat("UNCALIBRATED_REFERENCE_GEOMETRY", rowCount, 1);
end

exportTable = candidates;
exportTable.ImageRayAngleDegCW = candidates.AngleDeg;
exportTable.SensorAngleDegCCW = sensorAngleDegCCW;
exportTable.SensorXmm = sensorXmm;
exportTable.SensorYmm = sensorYmm;
exportTable.SensorRadiusMm = sensorRadiusMm;
exportTable.SensorWidthMm = sensorWidthMm;
exportTable.SpatialUnit = spatialUnit;
exportTable.CoordinateFrame = coordinateFrame;
exportTable.CalibrationStatus = calibrationStatus;
exportTable = removevars(exportTable, ...
    {'AngleDeg','X','Y','RadiusPx','WidthPx'});
end
