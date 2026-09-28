function result = runSmartKCPipeline(imagePath, cfg, outputFolder)
%RUNSMARTKCPIPELINE Run paired SmartKC and SmartKC++ MATLAB workflows.
%   RESULT = RUNSMARTKCPIPELINE(IMAGEPATH) uses the central settings file.
%   RESULT = RUNSMARTKCPIPELINE(IMAGEPATH, CFG, OUTPUTFOLDER) accepts an
%   overridden configuration and optionally writes a complete audit bundle.
%
%   Quantitative outputs are research-only. The default calibration profile
%   is the public Microsoft reference geometry, not a calibration of the
%   user's phone/attachment.

projectRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(projectRoot, 'config'));
addpath(genpath(fullfile(projectRoot, 'functions')));

if nargin < 2 || isempty(cfg)
    cfg = smartKCConstants(projectRoot);
end
if nargin < 3
    outputFolder = "__DEFAULT__";
end

imagePath = char(imagePath);
pipelineTimer = tic;
timingStage = strings(0, 1);
timingSeconds = zeros(0, 1);
fprintf('[Pipeline] Preprocessing...\n');
stageTimer = tic;
pre = preprocessPlacidoImage(imagePath, cfg);
[timingStage, timingSeconds] = recordTiming( ...
    timingStage, timingSeconds, "Preprocessing", stageTimer, pipelineTimer);
if string(outputFolder) == "__DEFAULT__"
    paths = smartKCPaths(cfg, pre.CaseId);
    outputFolder = paths.OutputCaseFolder;
end

fprintf('[Pipeline] SmartKC segmentation...\n');
stageTimer = tic;
smartKCSegmentation = segmentMiresClassical(pre, cfg, "smartkc");
[timingStage, timingSeconds] = recordTiming(timingStage, timingSeconds, ...
    "SmartKC segmentation", stageTimer, pipelineTimer);
fprintf('[Pipeline] SmartKC mire localization...\n');
stageTimer = tic;
[smartKCCandidates, smartKCPolar] = extractMireCandidates( ...
    pre, smartKCSegmentation, cfg);
[timingStage, timingSeconds] = recordTiming(timingStage, timingSeconds, ...
    "SmartKC mire localization", stageTimer, pipelineTimer);
smartKCMatrices = mirePointsToMatrices(smartKCCandidates, ...
    smartKCPolar.AnglesDeg, cfg.placido.MaximumMires);
fprintf('[Pipeline] SmartKC reconstruction...\n');
stageTimer = tic;
smartKC = runReconstructionVariant("smartkc", smartKCSegmentation, ...
    smartKCCandidates, smartKCPolar, smartKCMatrices, pre, cfg);
[timingStage, timingSeconds] = recordTiming(timingStage, timingSeconds, ...
    "SmartKC reconstruction", stageTimer, pipelineTimer);

fprintf('[Pipeline] SmartKC++ segmentation...\n');
stageTimer = tic;
smartKCPPsegmentation = segmentMiresSmartKCPlus(pre, cfg);
[timingStage, timingSeconds] = recordTiming(timingStage, timingSeconds, ...
    "SmartKC++ segmentation", stageTimer, pipelineTimer);
fprintf('[Pipeline] SmartKC++ mire localization...\n');
stageTimer = tic;
[smartKCPPcandidatesRaw, smartKCPPpolar] = extractMireCandidates( ...
    pre, smartKCPPsegmentation, cfg);
[timingStage, timingSeconds] = recordTiming(timingStage, timingSeconds, ...
    "SmartKC++ mire localization", stageTimer, pipelineTimer);
fprintf('[Pipeline] SmartKC++ graph label correction...\n');
stageTimer = tic;
smartKCPPcandidates = correctMireLabelsGraph( ...
    smartKCPPcandidatesRaw, pre.CenterPx, cfg);
[timingStage, timingSeconds] = recordTiming(timingStage, timingSeconds, ...
    "SmartKC++ graph label correction", stageTimer, pipelineTimer);
smartKCPPmatrices = mirePointsToMatrices(smartKCPPcandidates, ...
    smartKCPPpolar.AnglesDeg, cfg.placido.MaximumMires);
fprintf('[Pipeline] SmartKC++ reconstruction and S07 analysis...\n');
stageTimer = tic;
smartKCPP = runReconstructionVariant("smartkcpp", smartKCPPsegmentation, ...
    smartKCPPcandidates, smartKCPPpolar, smartKCPPmatrices, pre, cfg);
[timingStage, timingSeconds] = recordTiming(timingStage, timingSeconds, ...
    "SmartKC++ reconstruction and S07", stageTimer, pipelineTimer);
smartKCPP.RawCandidates = smartKCPPcandidatesRaw;

result = struct();
result.SchemaVersion = "1.0";
result.RegistryVersion = string(cfg.RegistryVersion);
result.GeneratedAt = datetime('now', 'TimeZone', 'local');
result.SourcePath = string(imagePath);
result.ImageId = pre.ImageId;
result.CaseId = pre.CaseId;
result.Preprocessing = pre;
result.SmartKC = smartKC;
result.SmartKCPP = smartKCPP;
result.Timing = table(timingStage, timingSeconds, ...
    'VariableNames', {'Stage', 'Seconds'});
result.Calibration = struct( ...
    'ProfileName', cfg.calibration.ProfileName, ...
    'IsDeviceSpecific', cfg.calibration.IsDeviceSpecific, ...
    'ResearchOnly', cfg.ResearchOnly, ...
    'Camera', cfg.camera, ...
    'PlacidoMidpointsMm', getPlacidoMidpoints(cfg));
result.Warning = calibrationWarning(cfg);

if strlength(string(outputFolder)) > 0
    fprintf('[Pipeline] Saving audit outputs...\n');
    stageTimer = tic;
    savePipelineOutputs(result, char(outputFolder), cfg);
    [timingStage, timingSeconds] = recordTiming(timingStage, timingSeconds, ...
        "Save audit outputs", stageTimer, pipelineTimer);
end
timingStage(end + 1, 1) = "TOTAL";
timingSeconds(end + 1, 1) = toc(pipelineTimer);
result.Timing = table(timingStage, timingSeconds, ...
    'VariableNames', {'Stage', 'Seconds'});
if strlength(string(outputFolder)) > 0
    writetable(result.Timing, fullfile(char(outputFolder), ...
        'S00_stage_timings.csv'));
end
fprintf('[Pipeline] Complete in %.2f seconds.\n', timingSeconds(end));
end

function variant = runReconstructionVariant(name, segmentation, candidates, ...
        polar, matrices, pre, cfg)
variantTimer = tic;
variantStages = strings(0, 1);
variantSeconds = zeros(0, 1);
variant = struct();
variant.Name = name;
variant.Status = "FAILED";
variant.ErrorIdentifier = "";
variant.ErrorMessage = "";
variant.Segmentation = segmentation;
variant.Candidates = candidates;
variant.Polar = polar;
variant.Matrices = matrices;
if cfg.eigenRatio.Enabled && string(name) == string(cfg.eigenRatio.Pipeline)
    fprintf('[Pipeline]   %s eigen-ratio analysis...\n', name);
    operationTimer = tic;
    variant.EigenRatio = calculateMireEigenRatio( ...
        matrices, pre, cfg, string(name));
    [variantStages, variantSeconds] = recordTiming( ...
        variantStages, variantSeconds, "Eigen-ratio analysis", ...
        operationTimer, variantTimer);
else
    variant.EigenRatio = struct('Enabled', false, 'Metrics', table(), ...
        'Reason', "Not selected for S07 analysis.");
end
try
    fprintf('[Pipeline]   %s Arc-Step reconstruction...\n', name);
    operationTimer = tic;
    variant.Reconstruction = arcStepReconstruct(matrices, pre, cfg, name);
    [variantStages, variantSeconds] = recordTiming( ...
        variantStages, variantSeconds, "Arc-Step reconstruction", ...
        operationTimer, variantTimer);
    fprintf('[Pipeline]   %s Zernike surface fit...\n', name);
    operationTimer = tic;
    variant.Surface = fitZernikeSurface(variant.Reconstruction, cfg);
    [variantStages, variantSeconds] = recordTiming( ...
        variantStages, variantSeconds, "Zernike surface fit", ...
        operationTimer, variantTimer);
    fprintf('[Pipeline]   %s SimK calculation...\n', name);
    operationTimer = tic;
    variant.Metrics = computeSimK(variant.Surface, cfg);
    [variantStages, variantSeconds] = recordTiming( ...
        variantStages, variantSeconds, "SimK calculation", ...
        operationTimer, variantTimer);
    fprintf('[Pipeline]   %s quality assessment...\n', name);
    operationTimer = tic;
    variant.Quality = assessMireAndReconstructionQuality( ...
        matrices, variant.Reconstruction, variant.Surface, cfg);
    [variantStages, variantSeconds] = recordTiming( ...
        variantStages, variantSeconds, "Quality assessment", ...
        operationTimer, variantTimer);
    variant.Status = "COMPLETED";
catch exception
    variant.ErrorIdentifier = string(exception.identifier);
    variant.ErrorMessage = string(exception.message);
    variant.Reconstruction = struct();
    variant.Surface = struct();
    variant.Metrics = struct();
    variant.Quality = struct();
end
variant.Timing = table(variantStages, variantSeconds, ...
    'VariableNames', {'Stage', 'Seconds'});
end

function message = calibrationWarning(cfg)
if cfg.calibration.IsDeviceSpecific
    message = "Device-specific calibration flag is set; independent validation is still required.";
else
    message = "UNCALIBRATED RESEARCH OUTPUT - do not interpret curvature or diagnosis clinically.";
end
end

function [stages, seconds] = recordTiming(stages, seconds, stageName, ...
        stageTimer, pipelineTimer)
elapsed = toc(stageTimer);
stages(end + 1, 1) = string(stageName);
seconds(end + 1, 1) = elapsed;
fprintf('[Pipeline]   completed in %.2f s (elapsed %.2f s).\n', ...
    elapsed, toc(pipelineTimer));
end
