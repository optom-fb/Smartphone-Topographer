function showStepReview(stepNumber, cfg)
%SHOWSTEPREVIEW Display the table and visual artifact for a numbered step.

arguments
    stepNumber (1,1) double {mustBeInteger, mustBeInRange(stepNumber, 0, 7)}
    cfg struct
end

close(findall(groot, 'Type', 'figure', 'Tag', 'SmartKCStepReview'));
fprintf('\n========== STEP %02d REVIEW ==========\n', stepNumber);

switch stepNumber
    case 0
        reviewStep00(cfg);
    case 1
        reviewStep01(cfg);
    case 2
        reviewStep02(cfg);
    case 3
        reviewStep03(cfg);
    case 4
        reviewReconstructionStep(cfg, 4, "SmartKC");
    case 5
        reviewReconstructionStep(cfg, 5, "SmartKC++");
    case 6
        reviewStep06(cfg);
    case 7
        reviewStep07(cfg);
end
drawnow;
end

function reviewStep00(cfg)
paths = smartKCPaths(cfg);
manifestPath = paths.Manifests.S00;
manifest = readManifest(manifestPath);
displayColumns(manifest, {'CaseId','ImageId','WidthPx','HeightPx','Channels', ...
    'BitDepth','DecodeOK','Message'});
fprintf('Input manifest: %s\n', manifestPath);
end

function reviewStep01(cfg)
paths = smartKCPaths(cfg);
manifestPath = paths.Manifests.S01;
manifest = readManifest(manifestPath);
displayColumns(manifest, {'CaseId','IsAcceptedForSegmentation','FocusScore', ...
    'SaturationFraction','CenterXFullPx','CenterYFullPx','PupilIsValid', ...
    'PupilDetectionStatus','PupilScore','PupilCenterOffsetSensorMm', ...
    'PupilEquivalentSensorDiameterMm','PreprocessMessage'});

row = firstExistingPath(manifest, 'PreprocessedMat');
if isempty(row)
    fprintf('No Step-01 preview is available. See: %s\n', manifestPath);
    return
end
loaded = load(char(manifest.PreprocessedMat(row)), 'pre');
pre = loaded.pre;
fig = newReviewFigure('SmartKC Step 01 - preprocessing', [70, 100, 1500, 560]);
layout = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile(layout);
[sourceImage, ~] = readImageWithExifOrientation(char(pre.SourcePath));
plotPupilReviewOverlay(gca, sourceImage, pre, "full");
title('Full image: red Placido, yellow pupil', ...
    'Color', [0.12, 0.12, 0.12]);
nexttile(layout);
plotPupilReviewOverlay(gca, pre.RGB, pre, "crop");
title("Pupil " + pre.Pupil.DetectionStatus, 'Interpreter', 'none', ...
    'Color', [0.12, 0.12, 0.12]);
nexttile(layout);
imshow(pre.NormalizedGray, []);
title('Normalized analysis image', 'Color', [0.12, 0.12, 0.12]);
fprintf('Preprocessed bundle: %s\n', manifest.PreprocessedMat(row));
end

function reviewStep02(cfg)
paths = smartKCPaths(cfg);
manifestPath = paths.Manifests.S02;
manifest = readManifest(manifestPath);
displayColumns(manifest, {'CaseId','SmartKCPPMethod','SegmentationMessage'});

row = firstExistingPath(manifest, 'SegmentationMat');
if isempty(row)
    fprintf('No Step-02 preview is available. See: %s\n', manifestPath);
    return
end
preData = load(char(manifest.PreprocessedMat(row)), 'pre');
segData = load(char(manifest.SegmentationMat(row)));
fig = newReviewFigure('SmartKC Step 02 - segmentation', [70, 100, 1500, 540]);
layout = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile(layout);
imshow(preData.pre.RGB);
title('Centred crop', 'Color', [0.12, 0.12, 0.12]);
nexttile(layout);
imshow(segData.smartKCSegmentation.Mask);
title('SmartKC mask', 'Color', [0.12, 0.12, 0.12]);
nexttile(layout);
imshow(segData.smartKCPPSegmentation.Mask);
title("SmartKC++ mask | " + segData.smartKCPPSegmentation.MethodActual, ...
    'Interpreter', 'none', 'Color', [0.12, 0.12, 0.12]);
fprintf('Segmentation bundle: %s\n', manifest.SegmentationMat(row));
end

function reviewStep03(cfg)
paths = smartKCPaths(cfg);
manifestPath = paths.Manifests.S03;
manifest = readManifest(manifestPath);
displayColumns(manifest, {'CaseId','MedianSmartKCMires', ...
    'MedianSmartKCPPMires','LocalizationMessage'});

row = firstExistingPath(manifest, 'MirePointsMat');
if isempty(row)
    fprintf('No Step-03 preview is available. See: %s\n', manifestPath);
    return
end
preData = load(char(manifest.PreprocessedMat(row)), 'pre');
mireData = load(char(manifest.MirePointsMat(row)), ...
    'smartKCCandidates', 'smartKCPPCandidates');
fig = newReviewFigure('SmartKC Step 03 - mire localization', [70, 100, 1300, 600]);
layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile(layout);
showMireOverlay(preData.pre.RGB, mireData.smartKCCandidates);
title('SmartKC radial labels', 'Color', [0.12, 0.12, 0.12]);
nexttile(layout);
showMireOverlay(preData.pre.RGB, mireData.smartKCPPCandidates);
title('SmartKC++ graph-corrected labels', 'Color', [0.12, 0.12, 0.12]);
fprintf('Mire-point bundle: %s\n', manifest.MirePointsMat(row));
end

function reviewReconstructionStep(cfg, stepNumber, label)
if stepNumber == 4
    manifestField = 'S04';
    pathColumn = 'SmartKCReconstructionMat';
    statusColumn = 'SmartKCStatus';
else
    manifestField = 'S05';
    pathColumn = 'SmartKCPPReconstructionMat';
    statusColumn = 'SmartKCPPStatus';
end
paths = smartKCPaths(cfg);
manifestPath = paths.Manifests.(manifestField);
manifest = readManifest(manifestPath);
displayColumns(manifest, {'CaseId', pathColumn, statusColumn});

row = firstExistingPath(manifest, pathColumn);
if isempty(row)
    fprintf('%s reconstruction did not pass. The status above is the output.\n', label);
    fprintf('Manifest: %s\n', manifestPath);
    return
end
loaded = load(char(manifest.(pathColumn)(row)), 'surface', 'metrics');
fig = newReviewFigure("SmartKC Step " + stepNumber + " - " + label, ...
    [100, 100, 1100, 560]);
layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
showPowerMap(nexttile(layout), loaded.surface, 'AxialPowerD', ...
    label + " axial power", cfg);
showPowerMap(nexttile(layout), loaded.surface, 'TangentialPowerD', ...
    label + " tangential power", cfg);
fprintf('%s result: steep %.2f D, flat %.2f D.\n', label, ...
    loaded.metrics.SimKSteepD, loaded.metrics.SimKFlatD);
end

function reviewStep06(cfg)
paths = smartKCPaths(cfg);
manifestPath = paths.Manifests.S06;
manifest = readManifest(manifestPath);
displayColumns(manifest, {'CaseId','OutputFolder','ExportMessage'});
for row = 1:height(manifest)
    casePaths = smartKCPaths(cfg, manifest.CaseId(row));
    summaryPath = casePaths.S06SummaryCsv;
    reviewPath = casePaths.S06ReviewPng;
    if isfile(summaryPath)
        summary = readtable(summaryPath, 'TextType', 'string');
        displayColumns(summary, {'Pipeline','Status','SegmentationMethod', ...
            'SimKSteepD','SimKFlatD','CylinderD','CalibrationStatus','ErrorMessage'});
        fprintf('Final summary: %s\n', summaryPath);
    end
    if isfile(reviewPath)
        fig = newReviewFigure('SmartKC Step 06 - final review', ...
            [40, 80, 1600, 760]);
        axisHandle = axes('Parent', fig);
        imshow(imread(reviewPath), 'Parent', axisHandle);
        title(axisHandle, 'Final paired audit review', ...
            'Color', [0.12, 0.12, 0.12]);
        fprintf('Final review image: %s\n', reviewPath);
        return
    end
end
fprintf('No Step-06 review image was found. See: %s\n', cfg.paths.Output);
end

function reviewStep07(cfg)
paths = smartKCPaths(cfg);
manifestPath = paths.Manifests.S07;
manifest = readManifest(manifestPath);
displayColumns(manifest, {'CaseId','S07EigenRatioCsv', ...
    'EigenRatioMessage'});
for row = 1:height(manifest)
    csvPath = string(manifest.S07EigenRatioCsv(row));
    resultPath = string(manifest.S06ResultMat(row));
    if strlength(csvPath) > 0 && isfile(csvPath)
        metrics = readtable(csvPath, 'TextType', 'string');
        primary = metrics(logical(metrics.IsIncludedInPrimary), :);
        displayColumns(primary, {'Pipeline','MireIndex','CoverageFraction', ...
            'MaximumGapDeg','EigenRatio','HarmonicRMSmm'});
        fprintf('Eigen-ratio metrics: %s\n', csvPath);
    end
    if strlength(resultPath) > 0 && isfile(resultPath)
        loaded = load(resultPath, 'result');
        fig = newReviewFigure('SmartKC Step 07 - SmartKC++ ring analysis', ...
            [50, 80, 1500, 780]);
        populateEigenRatioReview(fig, loaded.result, cfg);
        return
    end
end
fprintf('No Step-07 result MAT was found. See: %s\n', cfg.paths.Output);
end

function manifest = readManifest(path)
if ~isfile(path)
    error('SmartKC:ReviewManifestMissing', 'Review manifest not found: %s', path);
end
manifest = readtable(path, 'TextType', 'string');
end

function displayColumns(value, requested)
available = requested(ismember(requested, value.Properties.VariableNames));
if isempty(available)
    disp(value);
else
    disp(value(:, available));
end
end

function row = firstExistingPath(manifest, columnName)
row = [];
if ~ismember(columnName, manifest.Properties.VariableNames)
    return
end
for index = 1:height(manifest)
    value = string(manifest.(columnName)(index));
    if strlength(value) > 0 && isfile(value)
        row = index;
        return
    end
end
end

function fig = newReviewFigure(name, position)
fig = figure('Name', char(name), 'NumberTitle', 'off', 'Color', 'w', ...
    'Tag', 'SmartKCStepReview', 'Position', position);
end

function showMireOverlay(rgb, points)
imshow(rgb);
hold on
active = points(points.IsValid, :);
if ~isempty(active)
    scatter(active.X, active.Y, 7, active.MireIndex, 'filled');
    colormap(gca, turbo(24));
end
end

function showPowerMap(axisHandle, surface, fieldName, heading, cfg)
imagesc(axisHandle, surface.Xmm(1, :), surface.Ymm(:, 1), surface.(fieldName));
axis(axisHandle, 'image', 'xy');
colormap(axisHandle, cfg.visualisation.Colormap);
clim(axisHandle, cfg.visualisation.PowerLimitsD);
colorbar(axisHandle);
xlabel(axisHandle, 'x (mm)');
ylabel(axisHandle, 'y (mm; superior +)');
title(axisHandle, heading, 'Color', [0.12, 0.12, 0.12]);
end
