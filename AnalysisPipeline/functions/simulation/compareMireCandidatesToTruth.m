function details = compareMireCandidatesToTruth(candidates, truth, pre, cfg, ...
        sphereK_D, scenarioName)
%COMPAREMIRECANDIDATESTOTRUTH Compare each labelled candidate to its mire.
%   Positive signed error means the detected mire lies radially outward
%   from continuous simulator truth. Sensor-plane millimetres use the same
%   effective sensor dimensions consumed by Arc-Step.

arguments
    candidates table
    truth struct
    pre struct
    cfg struct
    sphereK_D (1,1) double {mustBeFinite, mustBePositive}
    scenarioName (1,1) string
end

required = {'MireIndex', 'AngleDeg', 'RadiusPx', 'Score', 'WidthPx', ...
    'IsValid'};
if any(~ismember(required, candidates.Properties.VariableNames))
    error('SmartKC:LocalizationBaseline:CandidateSchema', ...
        'Candidate table is missing required localization fields.');
end

active = candidates(candidates.IsValid, :);
rowCount = height(active);
SphereK_D = repmat(sphereK_D, rowCount, 1);
ScenarioName = repmat(scenarioName, rowCount, 1);
MireIndex = double(active.MireIndex);
ImageAngleDeg = double(active.AngleDeg);
TruthAngleDeg = mod(-ImageAngleDeg, 360);
DetectedRadiusPx = double(active.RadiusPx);
TruthRadiusPx = nan(rowCount, 1);
EndToEndSignedErrorPx = nan(rowCount, 1);
EndToEndAbsoluteErrorPx = nan(rowCount, 1);
EndToEndSignedErrorSensorMm = nan(rowCount, 1);
EndToEndAbsoluteErrorSensorMm = nan(rowCount, 1);
cropOrigin = double(pre.CropRectangleFullPx(1:2));
DetectedXFullPx = double(active.X) + cropOrigin(1) - 1;
DetectedYFullPx = double(active.Y) + cropOrigin(2) - 1;
trueCenter = double(truth.centerPixels(:).');
DetectedRadiusFromTrueCenterPx = hypot( ...
    DetectedXFullPx - trueCenter(1), DetectedYFullPx - trueCenter(2));
DetectedTruthAngleDeg = mod(-atan2d(DetectedYFullPx - trueCenter(2), ...
    DetectedXFullPx - trueCenter(1)), 360);
CenterCompensatedTruthRadiusPx = nan(rowCount, 1);
CenterCompensatedSignedErrorPx = nan(rowCount, 1);
CenterCompensatedAbsoluteErrorPx = nan(rowCount, 1);
CenterCompensatedSignedErrorSensorMm = nan(rowCount, 1);
CenterCompensatedAbsoluteErrorSensorMm = nan(rowCount, 1);
Score = double(active.Score);
DetectedWidthPx = double(active.WidthPx);
TruthAvailable = false(rowCount, 1);

sensorSizeMm = double(cfg.camera.SensorSizeMm(:).');
imageWidth = double(pre.OriginalSize(2));
imageHeight = double(pre.OriginalSize(1));
for row = 1:rowCount
    mire = MireIndex(row);
    if mire < 1 || mire > size(truth.radiiPixels, 1)
        continue
    end
    angleDifference = abs(mod(double(truth.anglesDeg) - ...
        TruthAngleDeg(row) + 180, 360) - 180);
    [minimumAngleDifference, angleIndex] = min(angleDifference);
    if minimumAngleDifference > 0.51 * cfg.localization.AngleStepDeg || ...
            ~truth.visibleMask(mire, angleIndex) || ...
            ~isfinite(truth.radiiPixels(mire, angleIndex))
        continue
    end
    TruthAvailable(row) = true;
    TruthRadiusPx(row) = truth.radiiPixels(mire, angleIndex);
    EndToEndSignedErrorPx(row) = DetectedRadiusPx(row) - TruthRadiusPx(row);
    EndToEndAbsoluteErrorPx(row) = abs(EndToEndSignedErrorPx(row));
    sensorMmPerPixel = hypot( ...
        cosd(ImageAngleDeg(row)) * sensorSizeMm(1) / imageWidth, ...
        sind(ImageAngleDeg(row)) * sensorSizeMm(2) / imageHeight);
    EndToEndSignedErrorSensorMm(row) = ...
        EndToEndSignedErrorPx(row) * sensorMmPerPixel;
    EndToEndAbsoluteErrorSensorMm(row) = ...
        abs(EndToEndSignedErrorSensorMm(row));

    compensatedDifference = abs(mod(double(truth.anglesDeg) - ...
        DetectedTruthAngleDeg(row) + 180, 360) - 180);
    [~, compensatedAngleIndex] = min(compensatedDifference);
    CenterCompensatedTruthRadiusPx(row) = ...
        truth.radiiPixels(mire, compensatedAngleIndex);
    CenterCompensatedSignedErrorPx(row) = ...
        DetectedRadiusFromTrueCenterPx(row) - ...
        CenterCompensatedTruthRadiusPx(row);
    CenterCompensatedAbsoluteErrorPx(row) = ...
        abs(CenterCompensatedSignedErrorPx(row));
    compensatedMmPerPixel = hypot( ...
        cosd(DetectedTruthAngleDeg(row)) * sensorSizeMm(1) / imageWidth, ...
        sind(DetectedTruthAngleDeg(row)) * sensorSizeMm(2) / imageHeight);
    CenterCompensatedSignedErrorSensorMm(row) = ...
        CenterCompensatedSignedErrorPx(row) * compensatedMmPerPixel;
    CenterCompensatedAbsoluteErrorSensorMm(row) = ...
        abs(CenterCompensatedSignedErrorSensorMm(row));
end

details = table(SphereK_D, ScenarioName, MireIndex, ImageAngleDeg, ...
    TruthAngleDeg, DetectedRadiusPx, TruthRadiusPx, ...
    EndToEndSignedErrorPx, EndToEndAbsoluteErrorPx, ...
    EndToEndSignedErrorSensorMm, EndToEndAbsoluteErrorSensorMm, ...
    DetectedXFullPx, DetectedYFullPx, DetectedRadiusFromTrueCenterPx, ...
    DetectedTruthAngleDeg, CenterCompensatedTruthRadiusPx, ...
    CenterCompensatedSignedErrorPx, CenterCompensatedAbsoluteErrorPx, ...
    CenterCompensatedSignedErrorSensorMm, ...
    CenterCompensatedAbsoluteErrorSensorMm, Score, DetectedWidthPx, ...
    TruthAvailable);
end
