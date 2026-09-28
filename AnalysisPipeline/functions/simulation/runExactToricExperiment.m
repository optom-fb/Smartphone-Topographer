function results = runExactToricExperiment(cfg, outputRoot, scenarios)
%RUNEXACTTORICEXPERIMENT Isolate toric inverse-pipeline error by stage.
%   Exact simulated mire coordinates bypass rasterization, segmentation,
%   centre estimation, and peak localization. A dense truth-surface fit
%   separately defines the matched 3 mm SimK reference. This is an
%   engineering diagnostic, not a clinical or device calibration.

arguments
    cfg struct
    outputRoot (1,1) string
    scenarios (1,:) struct = struct.empty(1, 0)
end
if isempty(scenarios)
    allScenarios = defaultSyntheticScenarios();
    scenarios = allScenarios(2:7);
end
if any(string({scenarios.SurfaceClass}) ~= "regular-astigmatism")
    error('SmartKC:ToricExperiment:InvalidScenario', ...
        'Every scenario must have SurfaceClass="regular-astigmatism".');
end

ensureFolder(char(outputRoot));
rowCount = numel(scenarios);
ScenarioName = strings(rowCount, 1);
Orientation = strings(rowCount, 1);
Severity = strings(rowCount, 1);
AsphericityQ = nan(rowCount, 1);
NominalSteepD = nan(rowCount, 1);
NominalFlatD = nan(rowCount, 1);
NominalCylinderD = nan(rowCount, 1);
ExpectedSteepAxisDeg = nan(rowCount, 1);
TruthReferenceSteepD = nan(rowCount, 1);
TruthReferenceFlatD = nan(rowCount, 1);
TruthReferenceCylinderD = nan(rowCount, 1);
TruthReferenceSteepAxisDeg = nan(rowCount, 1);
NominalToTruthMaximumKDifferenceD = nan(rowCount, 1);
RecoveredSteepD = nan(rowCount, 1);
RecoveredFlatD = nan(rowCount, 1);
RecoveredCylinderD = nan(rowCount, 1);
RecoveredSteepAxisDeg = nan(rowCount, 1);
RecoveredToTruthMaximumKDifferenceD = nan(rowCount, 1);
RecoveredToTruthCylinderDifferenceD = nan(rowCount, 1);
RecoveredToTruthAxisDifferenceDeg = nan(rowCount, 1);
RecoveredMaximumNominalKErrorD = nan(rowCount, 1);
ArcStepSagRMSEum = nan(rowCount, 1);
ArcStepMedianAbsoluteSagErrorUm = nan(rowCount, 1);
TruthZernikeFitRMSEum = nan(rowCount, 1);
RecoveredZernikeFitRMSEum = nan(rowCount, 1);
RecoveredMapSagRMSEum = nan(rowCount, 1);
MiresPerMeridian = nan(rowCount, 1);
RuntimeSeconds = nan(rowCount, 1);
Status = strings(rowCount, 1);
ErrorMessage = strings(rowCount, 1);

for row = 1:rowCount
    scenario = scenarios(row);
    ScenarioName(row) = string(scenario.Name);
    Orientation(row) = string(scenario.AstigmatismOrientation);
    Severity(row) = string(scenario.Severity);
    AsphericityQ(row) = scenario.Q;
    NominalSteepD(row) = cfg.metrics.DioptreFactor / scenario.RsteepMm;
    NominalFlatD(row) = cfg.metrics.DioptreFactor / scenario.RflatMm;
    NominalCylinderD(row) = NominalSteepD(row) - NominalFlatD(row);
    expectedFlatAxis = mod(180 - scenario.AxisDeg, 180);
    ExpectedSteepAxisDeg(row) = mod(expectedFlatAxis + 90, 180);
    timer = tic;
    try
        runCfg = cfg;
        runCfg.simulation.AngularSamples = round(360 / ...
            cfg.localization.AngleStepDeg);
        exactScenario = scenario;
        exactScenario.NoiseSigma = 0;
        exactScenario.BlurSigma = 0;
        exactScenario.GlareStrength = 0;
        [~, truth] = simulatePlacidoImage(exactScenario, runCfg);
        runCfg.camera.SensorSizeMm = ...
            truth.calibration.effectiveSensorSizeMm;
        runCfg.calibration.IsDeviceSpecific = true;
        runCfg.calibration.ProfileName = ...
            "Matched exact-coordinate toric experiment";

        [truthMetrics, truthSurface] = ...
            computeSyntheticTruthSimK(truth, runCfg);

        matrices = exactMatrices(truth);
        pre = struct('OriginalSize', runCfg.simulation.ImageSize);
        reconstruction = arcStepReconstruct( ...
            matrices, pre, runCfg, "smartkcpp");
        recoveredSurface = fitZernikeSurface(reconstruction, runCfg);
        recoveredMetrics = computeSimK(recoveredSurface, runCfg);

        TruthReferenceSteepD(row) = truthMetrics.SimKSteepD;
        TruthReferenceFlatD(row) = truthMetrics.SimKFlatD;
        TruthReferenceCylinderD(row) = truthMetrics.CylinderD;
        TruthReferenceSteepAxisDeg(row) = truthMetrics.SimKSteepAxisDeg;
        NominalToTruthMaximumKDifferenceD(row) = max(abs([ ...
            truthMetrics.SimKSteepD - NominalSteepD(row), ...
            truthMetrics.SimKFlatD - NominalFlatD(row)]));

        RecoveredSteepD(row) = recoveredMetrics.SimKSteepD;
        RecoveredFlatD(row) = recoveredMetrics.SimKFlatD;
        RecoveredCylinderD(row) = recoveredMetrics.CylinderD;
        RecoveredSteepAxisDeg(row) = recoveredMetrics.SimKSteepAxisDeg;
        RecoveredToTruthMaximumKDifferenceD(row) = max(abs([ ...
            recoveredMetrics.SimKSteepD - truthMetrics.SimKSteepD, ...
            recoveredMetrics.SimKFlatD - truthMetrics.SimKFlatD]));
        RecoveredToTruthCylinderDifferenceD(row) = ...
            recoveredMetrics.CylinderD - truthMetrics.CylinderD;
        RecoveredToTruthAxisDifferenceDeg(row) = axialDifference( ...
            recoveredMetrics.SimKSteepAxisDeg, ...
            truthMetrics.SimKSteepAxisDeg);
        RecoveredMaximumNominalKErrorD(row) = max(abs([ ...
            recoveredMetrics.SimKSteepD - NominalSteepD(row), ...
            recoveredMetrics.SimKFlatD - NominalFlatD(row)]));

        [ArcStepSagRMSEum(row), ArcStepMedianAbsoluteSagErrorUm(row)] = ...
            reconstructionSagError(reconstruction, truth);
        TruthZernikeFitRMSEum(row) = truthSurface.FitRMSEum;
        RecoveredZernikeFitRMSEum(row) = recoveredSurface.FitRMSEum;
        RecoveredMapSagRMSEum(row) = mapSagError(recoveredSurface, truth);
        MiresPerMeridian(row) = median(matrices.MireCountByAngle);
        Status(row) = "COMPLETED";
    catch exception
        Status(row) = "FAILED";
        ErrorMessage(row) = string(exception.message);
    end
    RuntimeSeconds(row) = toc(timer);
    fprintf('[Exact toric] %s | %s | %.2f s\n', ...
        ScenarioName(row), Status(row), RuntimeSeconds(row));
end

results = table(ScenarioName, Orientation, Severity, AsphericityQ, ...
    NominalSteepD, NominalFlatD, NominalCylinderD, ExpectedSteepAxisDeg, ...
    TruthReferenceSteepD, TruthReferenceFlatD, TruthReferenceCylinderD, ...
    TruthReferenceSteepAxisDeg, NominalToTruthMaximumKDifferenceD, ...
    RecoveredSteepD, RecoveredFlatD, RecoveredCylinderD, ...
    RecoveredSteepAxisDeg, RecoveredToTruthMaximumKDifferenceD, ...
    RecoveredToTruthCylinderDifferenceD, ...
    RecoveredToTruthAxisDifferenceDeg, RecoveredMaximumNominalKErrorD, ...
    ArcStepSagRMSEum, ArcStepMedianAbsoluteSagErrorUm, ...
    TruthZernikeFitRMSEum, RecoveredZernikeFitRMSEum, ...
    RecoveredMapSagRMSEum, MiresPerMeridian, RuntimeSeconds, Status, ...
    ErrorMessage);
writetable(results, fullfile(char(outputRoot), ...
    'exact_toric_experiment.csv'));
end

function matrices = exactMatrices(truth)
matrices = struct();
matrices.RadiiPx = truth.radiiPixels;
matrices.AnglesDeg = truth.anglesDeg;
matrices.MireCountByAngle = sum(isfinite(truth.radiiPixels), 1);
matrices.CoverageByMire = mean(isfinite(truth.radiiPixels), 2);
end

function [rmseUm, medianAbsoluteUm] = reconstructionSagError( ...
        reconstruction, truth)
points = reconstruction.Points;
truthAxis = truth.surface.xMm(1, :);
truthSag = interp2(truthAxis, truthAxis, truth.surface.sagMm, ...
    points.Xmm, -points.Ymm, 'linear');
valid = isfinite(truthSag) & isfinite(points.SagMm);
errorsMm = points.SagMm(valid) - truthSag(valid);
rmseUm = 1000 * sqrt(mean(errorsMm .^ 2));
medianAbsoluteUm = 1000 * median(abs(errorsMm));
end

function rmseUm = mapSagError(surface, truth)
truthAxis = truth.surface.xMm(1, :);
truthSag = interp2(truthAxis, truthAxis, truth.surface.sagMm, ...
    surface.Xmm, -surface.Ymm, 'linear');
valid = surface.Mask & isfinite(surface.SagMm) & isfinite(truthSag);
errorsMm = surface.SagMm(valid) - truthSag(valid);
rmseUm = 1000 * sqrt(mean(errorsMm .^ 2));
end

function difference = axialDifference(firstDeg, secondDeg)
difference = abs(mod(firstDeg - secondDeg + 90, 180) - 90);
end
