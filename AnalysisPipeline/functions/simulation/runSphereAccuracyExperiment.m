function results = runSphereAccuracyExperiment(powersD, cfg, outputRoot, conditions)
%RUNSPHEREACCURACYEXPERIMENT Separate inverse and image-derived sphere error.
%   RESULTS = RUNSPHEREACCURACYEXPERIMENT(POWERSD, CFG, OUTPUTROOT) compares
%   exact continuous mire coordinates, an ideal 2x image, the standard
%   synthetic image, and a 0.5x image. Images and a CSV report are written
%   below OUTPUTROOT. This is a matched-model engineering experiment, not a
%   physical calibration.

arguments
    powersD (1,:) double {mustBeFinite, mustBePositive}
    cfg struct
    outputRoot (1,1) string
    conditions (1,:) string = ["exact-coordinates", "ideal-high-resolution", ...
        "standard-image", "low-resolution"]
end

allowed = ["exact-coordinates", "ideal-high-resolution", ...
    "standard-image", "low-resolution"];
if any(~ismember(conditions, allowed)) || numel(unique(conditions)) ~= numel(conditions)
    error('SmartKC:SphereExperiment:InvalidConditions', ...
        'Conditions must be unique members of: %s.', strjoin(allowed, ', '));
end
if numel(unique(powersD)) ~= numel(powersD)
    error('SmartKC:SphereExperiment:DuplicatePower', ...
        'Sphere powers must be unique.');
end

ensureFolder(char(outputRoot));
imageRoot = fullfile(char(outputRoot), 'Images');
ensureFolder(imageRoot);
scenarios = syntheticSphereScenarios(powersD);
rowCount = numel(powersD) * numel(conditions);
SphereK_D = nan(rowCount, 1);
Condition = strings(rowCount, 1);
ImageHeightPx = nan(rowCount, 1);
ImageWidthPx = nan(rowCount, 1);
NoiseSigma = nan(rowCount, 1);
BlurSigmaPx = nan(rowCount, 1);
RecoveredSteepD = nan(rowCount, 1);
RecoveredFlatD = nan(rowCount, 1);
SteepErrorD = nan(rowCount, 1);
FlatErrorD = nan(rowCount, 1);
MaximumAbsoluteErrorD = nan(rowCount, 1);
ResidualCylinderD = nan(rowCount, 1);
DetectedMires = nan(rowCount, 1);
RuntimeSeconds = nan(rowCount, 1);
Status = strings(rowCount, 1);
AccuracyCriterionD = nan(rowCount, 1);
AccuracyCheck = strings(rowCount, 1);
ErrorMessage = strings(rowCount, 1);

row = 0;
for powerIndex = 1:numel(powersD)
    scenario = scenarios(powerIndex);
    for conditionIndex = 1:numel(conditions)
        row = row + 1;
        condition = conditions(conditionIndex);
        SphereK_D(row) = powersD(powerIndex);
        Condition(row) = condition;
        timer = tic;
        try
            if condition == "exact-coordinates"
                [metrics, mireCount] = runExactCoordinates(scenario, cfg);
                imageSize = [NaN, NaN];
                noiseSigma = 0;
                blurSigma = 0;
            else
                [metrics, mireCount, imageSize, noiseSigma, blurSigma] = ...
                    runImageCondition(scenario, cfg, condition, imageRoot, ...
                    powersD(powerIndex));
            end
            ImageHeightPx(row) = imageSize(1);
            ImageWidthPx(row) = imageSize(2);
            NoiseSigma(row) = noiseSigma;
            BlurSigmaPx(row) = blurSigma;
            RecoveredSteepD(row) = metrics.SimKSteepD;
            RecoveredFlatD(row) = metrics.SimKFlatD;
            SteepErrorD(row) = metrics.SimKSteepD - SphereK_D(row);
            FlatErrorD(row) = metrics.SimKFlatD - SphereK_D(row);
            MaximumAbsoluteErrorD(row) = max(abs([SteepErrorD(row), ...
                FlatErrorD(row)]));
            ResidualCylinderD(row) = metrics.CylinderD;
            DetectedMires(row) = mireCount;
            Status(row) = "COMPLETED";
            if condition == "exact-coordinates"
                AccuracyCriterionD(row) = 0.01;
            else
                AccuracyCriterionD(row) = cfg.simulation.RegularPowerToleranceD;
            end
            if MaximumAbsoluteErrorD(row) <= AccuracyCriterionD(row)
                AccuracyCheck(row) = "PASS";
            else
                AccuracyCheck(row) = "FAIL";
            end
        catch exception
            Status(row) = "FAILED";
            AccuracyCheck(row) = "FAIL";
            ErrorMessage(row) = string(exception.message);
        end
        RuntimeSeconds(row) = toc(timer);
        fprintf('[Sphere experiment] %.2f D | %s | %s | %.2f s\n', ...
            SphereK_D(row), Condition(row), Status(row), RuntimeSeconds(row));
    end
end

results = table(SphereK_D, Condition, ImageHeightPx, ImageWidthPx, ...
    NoiseSigma, BlurSigmaPx, RecoveredSteepD, RecoveredFlatD, ...
    SteepErrorD, FlatErrorD, MaximumAbsoluteErrorD, ResidualCylinderD, ...
    DetectedMires, RuntimeSeconds, Status, AccuracyCriterionD, ...
    AccuracyCheck, ErrorMessage);
writetable(results, fullfile(char(outputRoot), ...
    'sphere_accuracy_experiment.csv'));
end

function [metrics, mireCount] = runExactCoordinates(scenario, cfg)
exactCfg = cfg;
exactCfg.simulation.AngularSamples = round(360 / cfg.localization.AngleStepDeg);
exactScenario = scenario;
exactScenario.NoiseSigma = 0;
exactScenario.BlurSigma = 0;
exactScenario.GlareStrength = 0;
[~, truth] = simulatePlacidoImage(exactScenario, exactCfg);
exactCfg.camera.SensorSizeMm = truth.calibration.effectiveSensorSizeMm;
exactCfg.calibration.IsDeviceSpecific = true;
matrices = exactMatrices(truth);
pre = struct('OriginalSize', exactCfg.simulation.ImageSize);
reconstruction = arcStepReconstruct(matrices, pre, exactCfg, "smartkcpp");
surface = fitZernikeSurface(reconstruction, exactCfg);
metrics = computeSimK(surface, exactCfg);
mireCount = median(matrices.MireCountByAngle);
end

function [metrics, mireCount, imageSize, noiseSigma, blurSigma] = ...
        runImageCondition(scenario, cfg, condition, imageRoot, powerD)
switch condition
    case "ideal-high-resolution"
        scale = 2;
        scenario.NoiseSigma = 0;
        scenario.BlurSigma = 0;
        scenario.GlareStrength = 0;
    case "standard-image"
        scale = 1;
    case "low-resolution"
        scale = 0.5;
    otherwise
        error('SmartKC:SphereExperiment:InvalidImageCondition', ...
            'Unsupported image condition: %s.', condition);
end

runCfg = scaledImageConfiguration(cfg, scale);
[image, truth] = simulatePlacidoImage(scenario, runCfg);
stem = sprintf('sphere_%s_%s', powerToken(powerD), ...
    replace(char(condition), '-', '_'));
imagePath = fullfile(imageRoot, [stem, '.png']);
imwrite(image, imagePath);
runCfg.camera.SensorSizeMm = truth.calibration.effectiveSensorSizeMm;
runCfg.calibration.IsDeviceSpecific = true;
runCfg.calibration.ProfileName = "Matched sphere accuracy experiment";
runCfg.segmentation.ExecutionMode = "robust-classical-synthetic";
runCfg.preprocessing.PupilRadiusFraction = [0.018, 0.04];
result = runSmartKCPipeline(imagePath, runCfg, '');
if result.SmartKCPP.Status ~= "COMPLETED"
    error('SmartKC:SphereExperiment:PipelineFailed', '%s', ...
        result.SmartKCPP.ErrorMessage);
end
metrics = result.SmartKCPP.Metrics;
mireCount = result.SmartKCPP.Quality.MedianMiresPerAngle;
imageSize = runCfg.simulation.ImageSize;
noiseSigma = scenario.NoiseSigma;
blurSigma = scenario.BlurSigma;
end

function cfg = scaledImageConfiguration(cfg, scale)
baseSize = double(cfg.simulation.ImageSize);
cfg.simulation.ImageSize = round(baseSize .* scale);
cfg.simulation.RingWidthPixels = cfg.simulation.RingWidthPixels * scale;
shortSide = min(cfg.simulation.ImageSize);
cfg.preprocessing.CropSizePx = shortSide;
cfg.preprocessing.MinimumCropSizePx = shortSide;
cfg.preprocessing.CenterRefineRadiusPx = max(2, ...
    cfg.preprocessing.CenterRefineRadiusPx * scale);
cfg.preprocessing.FlatFieldSigmaPx = max(4, ...
    cfg.preprocessing.FlatFieldSigmaPx * scale);
cfg.segmentation.SmallGaussianSigmaPx = max(0.4, ...
    cfg.segmentation.SmallGaussianSigmaPx * scale);
cfg.segmentation.LargeGaussianSigmaPx = max(2, ...
    cfg.segmentation.LargeGaussianSigmaPx * scale);
cfg.segmentation.MinimumComponentAreaPx = max(2, round( ...
    cfg.segmentation.MinimumComponentAreaPx * scale ^ 2));
cfg.segmentation.MaximumGapToBridgePx = max(1, round( ...
    cfg.segmentation.MaximumGapToBridgePx * scale));
cfg.localization.InnerRadiusPx = max(2, 4 * scale);
cfg.localization.MinimumRingSpacingPx = max(2, ...
    cfg.localization.MinimumRingSpacingPx * scale);
cfg.localization.GraphRadialTolerancePx = max(1.5, ...
    cfg.localization.GraphRadialTolerancePx * scale);
end

function matrices = exactMatrices(truth)
matrices = struct();
matrices.RadiiPx = truth.radiiPixels;
matrices.AnglesDeg = truth.anglesDeg;
matrices.MireCountByAngle = sum(isfinite(truth.radiiPixels), 1);
matrices.CoverageByMire = mean(isfinite(truth.radiiPixels), 2);
end

function token = powerToken(powerD)
token = char(compose('%.2f', powerD));
token = regexprep(token, '0+$', '');
token = regexprep(token, '\.$', '');
token = strrep(token, '.', 'p');
end
