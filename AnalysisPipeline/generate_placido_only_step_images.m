function result = generate_placido_only_step_images(inputImage, ringRange, outputRoot, selectedSteps, analysisRadiusPx)
%GENERATE_PLACIDO_ONLY_STEP_IMAGES Export one clean PNG per Placido step.
%
% This function is the engine behind STEPS_PLACIDO_Only.m. It implements
% the synchronized 25-stage cornea-to-dedicated-Placido methodology. The
% user-facing output folder contains PNG images only.
%
% Method boundary: grayscale -> fixed Canny [0.10 0.30] -> geometric ring
% processing. No CLAHE, flat-field normalization, adaptive multi-scale
% Canny, learned segmentation or corneal reconstruction is used here.

base = fileparts(mfilename('fullpath'));
placidoFunctions = fullfile(base, 'functions');
if isfolder(placidoFunctions)
    addpath(genpath(placidoFunctions));
end

if nargin < 1 || isempty(inputImage) || strlength(string(inputImage)) == 0
    [fileName, folderName] = uigetfile( ...
        {'*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp','Image files'}, ...
        'Select the Placido image');
    if isequal(fileName, 0)
        error('No input image was selected.');
    end
    inputImage = fullfile(folderName, fileName);
end
inputImage = char(string(inputImage));
if ~isfile(inputImage)
    error('Input image does not exist: %s', inputImage);
end

if nargin < 2 || isempty(ringRange)
    ringRange = [4 10];
end
validateattributes(ringRange, {'numeric'}, {'vector','finite','real','nonempty'}, ...
    mfilename, 'ringRange');
ringRange = ringRange(:).';
if numel(ringRange) ~= 2 || any(ringRange ~= round(ringRange)) || ...
        ringRange(1) < 1 || ringRange(2) < ringRange(1)
    error('ringRange must be two integers [firstRing lastRing] with 1 <= first <= last.');
end

if nargin < 3 || isempty(outputRoot) || strlength(string(outputRoot)) == 0
    outputRoot = fullfile(base, 'outputs', 'placido_only_steps');
end
outputRoot = char(string(outputRoot));
if ~isfolder(outputRoot)
    mkdir(outputRoot);
end

if nargin < 4 || isempty(selectedSteps)
    selectedSteps = 1:28;
end
validateattributes(selectedSteps, {'numeric'}, {'vector','finite','real','nonempty'}, ...
    mfilename, 'selectedSteps');
if any(selectedSteps ~= round(selectedSteps)) || ...
        any(selectedSteps < 1 | selectedSteps > 28) || ...
        numel(unique(selectedSteps)) ~= numel(selectedSteps)
    error('selectedSteps must contain unique integer values from 1 through 28.');
end
selectedSteps = selectedSteps(:).';

if nargin < 5 || isempty(analysisRadiusPx)
    % A physical mire requires two boundary tracks, so its radial demand is
    % approximately twice the legacy per-edge-track estimate.
    requestedAnalysisRadiusPx = 700; % Fixed search field, independent of report range.
else
    validateattributes(analysisRadiusPx, {'numeric'}, ...
        {'scalar','finite','real','positive'}, mfilename, 'analysisRadiusPx');
    requestedAnalysisRadiusPx = round(analysisRadiusPx);
end

[~, sourceBase] = fileparts(inputImage);
safeBase = regexprep(sourceBase, '[^A-Za-z0-9_-]+', '_');
stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
runFolder = fullfile(outputRoot, sprintf('%s_%s', safeBase, stamp));
suffix = 0;
while isfolder(runFolder)
    suffix = suffix + 1;
    runFolder = fullfile(outputRoot, sprintf('%s_%s_%02d', safeBase, stamp, suffix));
end
mkdir(runFolder);

fprintf('PLACIDO_ONLY_STEPS_START\nInput: %s\nOutput: %s\n', inputImage, runFolder);
fprintf('Selected mire range: %d:%d\n',ringRange(1),ringRange(2));
fprintf('Requested analysis radius: %d pixels%s\n',requestedAnalysisRadiusPx, ...
    ternaryText(nargin < 5 || isempty(analysisRadiusPx),' (automatic)',' (manual)'));

% =========================================================================
% Common source objects. The source image is never overwritten.
% =========================================================================
source = imread(inputImage);
% Some camera JPEGs contain a zero EXIF DigitalZoomRatio. MATLAB emits a
% harmless division-by-zero warning while parsing that metadata; orientation
% handling below does not depend on DigitalZoomRatio, so suppress it locally.
warningState = warning;
warning('off','all');
sourceInfo = imfinfo(inputImage);
warning(warningState);
source = applySupportedExifOrientation(source, sourceInfo);
if ndims(source) == 3 && size(source,3) > 3
    source = source(:,:,1:3);
end
if ndims(source) == 3
    grayNative = rgb2gray(source);
else
    grayNative = source;
end
gray = im2double(grayNative);
[heightPx, widthPx] = size(gray);
[X, Y] = meshgrid(1:widthPx, 1:heightPx);

% Allocate neutral placeholders so export selection controls computation as
% well as file creation. An early requested step cannot fail in a later,
% unrelated detector stage.
cannyEdges = false(size(gray));
cleanEdges = false(size(gray));
frameCentre = [NaN NaN]; frameRadius = NaN; frameRoi = false(size(gray));
coarseCentre = [NaN NaN]; polarAnglesDeg = []; polarRadii = []; polarImage = [];
gradientX = []; gradientY = [];
historicalInner = false(size(gray)); historicalOuter = false(size(gray));
historicalLabels = zeros(size(gray));
historicalKeepMask = false(size(gray)); historicalRejectMask = false(size(gray));
placidoCentre = [NaN NaN]; hubCandidateMask = false(size(gray));
placidoRoi = false(size(gray)); dedicatedEdges = false(size(gray));
innerDirectional = false(size(gray)); outerDirectional = false(size(gray));
innerPruned = false(size(gray)); outerPruned = false(size(gray));
removedBranches = false(size(gray)); combinedLabels = zeros(size(gray));
allPoints = table(); componentSummary = table(); finalPoints = table();
boundaryPairSummary = table(); physicalMirePoints = table();
selectedPoints = table(); availableRings = []; requestedRings = ringRange(1):ringRange(2);
fitRingIds = []; fittedTable = table(); fitObjects = {}; fitInfo = {};
shapeMetrics = struct([]);
analysisPoints = table();
workingRadiusPx = NaN; displayHalfSize = 470;

% Stage 03: active original/dedicated Canny settings. No preliminary CLAHE,
% flat-field correction or adaptive multi-scale edge branch is applied.
needsCanny = any(ismember(selectedSteps,[3 4 8 9 10])) || ...
    any(selectedSteps >= 12);
cannyThresholds = [0.10 0.30];
if needsCanny
    cannyEdges = edge(gray, 'Canny', cannyThresholds);
end

% Stage 04: expose the historical border cleanup using the dedicated
% 20-pixel component threshold.
minimumComponentArea = 20;
if any(ismember(selectedSteps,[4 8 9 10]))
    cleanEdges = imclearborder(cannyEdges, 8);
    cleanEdges = bwareaopen(cleanEdges, minimumComponentArea, 8);
end

% Stages 05--10 are locally reconstructed historical cornea states. They
% document development lineage and are not dependencies of Stage 11.
if any(ismember(selectedSteps,5:10))
    frameCentre = [(widthPx + 1)/2, (heightPx + 1)/2];
    frameRadius = floor(min([frameCentre(1)-1, widthPx-frameCentre(1), ...
        frameCentre(2)-1, heightPx-frameCentre(2)]));
    frameRoi = hypot(X-frameCentre(1), Y-frameCentre(2)) <= frameRadius;
end
if any(ismember(selectedSteps,6:10))
    coarseCentre = estimateHistoricalCoarseCentre(gray);
end
if any(selectedSteps == 7)
    coarseRadius = floor(min([coarseCentre(1)-1, widthPx-coarseCentre(1), ...
        coarseCentre(2)-1, heightPx-coarseCentre(2)]));
    coarseRadius = max(1, coarseRadius);
    polarAnglesDeg = 0:359;
    polarRadii = (0:coarseRadius).';
    [polarR, polarTheta] = ndgrid(polarRadii, deg2rad(polarAnglesDeg));
    polarX = coarseCentre(1) + polarR .* cos(polarTheta);
    polarY = coarseCentre(2) + polarR .* sin(polarTheta);
    polarImage = interp2(gray, polarX, polarY, 'linear', NaN);
end
needsGradient = any(ismember(selectedSteps,8:10)) || any(selectedSteps >= 12);
if needsGradient
    [gradientX, gradientY] = imgradientxy(gray, 'sobel');
end
if any(ismember(selectedSteps,8:10))
    coarseTheta = atan2(Y-coarseCentre(2), X-coarseCentre(1));
    coarseRadialGradient = gradientX .* cos(coarseTheta) + ...
        gradientY .* sin(coarseTheta);
    historicalOuter = cleanEdges & coarseRadialGradient >= 0;
    historicalInner = cleanEdges & coarseRadialGradient < 0;
end
if any(ismember(selectedSteps,9:10))
    historicalLabels = bwlabel(historicalOuter | historicalInner, 8);
end
if any(selectedSteps == 10)
    [historicalKeepMask, historicalRejectMask] = ...
        classifyHistoricalComponents(historicalLabels, coarseCentre);
end

% Stages 11--16: current dedicated Placido Step 01 implementation. Each
% nested block stops at the latest requested dependency.
if any(selectedSteps >= 11)
    hubSensitivity = 0.50;
    hubMinimumArea = 500;
    hubMinimumCircularity = 0.65;
    [placidoCentre, hubCandidateMask, placidoRoi, workingRadiusPx] = detectPlacidoHub( ...
        gray, X, Y, requestedAnalysisRadiusPx, hubSensitivity, ...
        hubMinimumArea, hubMinimumCircularity);
    displayHalfSize = workingRadiusPx + 90;
end
if any(selectedSteps >= 12)
    dedicatedEdges = cannyEdges & placidoRoi;
    dedicatedEdges = bwareaopen(dedicatedEdges, minimumComponentArea, 8);
    pruneAngleDeg = 70;
    requireFunction('bwRobustSurgicalPrune');
    basePruned = bwRobustSurgicalPrune( ...
        dedicatedEdges, placidoCentre, pruneAngleDeg);
    placidoTheta = atan2(Y-placidoCentre(2), X-placidoCentre(1));
    placidoRadialGradient = gradientX .* cos(placidoTheta) + ...
        gradientY .* sin(placidoTheta);
    outerDirectional = basePruned & placidoRadialGradient >= 0;
    innerDirectional = basePruned & placidoRadialGradient < 0;
end
if any(selectedSteps >= 13)
    outerPruned = bwRobustSurgicalPrune( ...
        outerDirectional, placidoCentre, pruneAngleDeg);
    innerPruned = bwRobustSurgicalPrune( ...
        innerDirectional, placidoCentre, pruneAngleDeg);
    outerPruned = bwareaopen(outerPruned, minimumComponentArea, 8);
    innerPruned = bwareaopen(innerPruned, minimumComponentArea, 8);
    removedBranches = dedicatedEdges & ~(outerPruned | innerPruned);
end
if any(selectedSteps >= 14)
    maximumMergeDistancePx = 30;
    mergeAngleToleranceDeg = 30;
    forceMergeDistancePx = 4;
    innerLabels = mergeFragmentsSafe(innerPruned, maximumMergeDistancePx, ...
        mergeAngleToleranceDeg, forceMergeDistancePx);
    outerLabels = mergeFragmentsSafe(outerPruned, maximumMergeDistancePx, ...
        mergeAngleToleranceDeg, forceMergeDistancePx);
    innerCombinedLabels = zeros(size(innerLabels));
    outerCombinedLabels = zeros(size(outerLabels));
    innerPositive = innerLabels > 0;
    outerPositive = outerLabels > 0;
    innerCombinedLabels(innerPositive) = 2*innerLabels(innerPositive) - 1;
    outerCombinedLabels(outerPositive) = 2*outerLabels(outerPositive);
    combinedLabels = innerCombinedLabels + outerCombinedLabels;
end
if any(selectedSteps >= 15)
    allPoints = labelImageToPointTable(combinedLabels, placidoCentre);
    minimumSubtenseDeg = 90;
    [componentSummary, finalPoints] = applySubtenseAndOrdering( ...
        allPoints, placidoCentre, minimumSubtenseDeg);
end
if any(selectedSteps >= 16)
    if isempty(finalPoints)
        error(['No curve passed the dedicated %g-degree subtense gate. ' ...
            'Inspect Steps 11--15 or use another input image.'], minimumSubtenseDeg);
    end
    [boundaryPairSummary, physicalMirePoints] = ...
        pairBoundaryTracksIntoMires(finalPoints, placidoCentre);
    if isempty(physicalMirePoints)
        error(['No opposite-polarity boundary pairs had sufficient common angular ' ...
            'support to form a physical Placido mire centreline. Inspect Steps 12--15.']);
    end
    availableRings = unique(physicalMirePoints.RingNumber).';
    if any(~ismember(requestedRings, availableRings))
        missingRings = requestedRings(~ismember(requestedRings, availableRings));
        fprintf(['Placido | Requested reporting-window mire IDs %s are unavailable; ' ...
            'continuing with detected IDs %s. Detection remains independent of ' ...
            'the reporting window.\n'], mat2str(missingRings), ...
            mat2str(intersect(requestedRings,availableRings,'stable')));
    end
    selectedPoints = physicalMirePoints( ...
        ismember(physicalMirePoints.RingNumber, requestedRings), :);
    if isempty(selectedPoints)
        error(['No detected physical Placido mires fall inside the requested ' ...
            'reporting window %s. Available indices are %s.'], ...
            mat2str(requestedRings), mat2str(availableRings));
    end
    fitRingIds = sort(unique(selectedPoints.RingNumber));
end

% Stages 17--24: current dedicated Placido Steps 02 and 03.
if any(selectedSteps >= 17)
    requireFunction('fitAllPlacidoRings');
    [fittedTable, fitObjects, fitInfo] = fitAllPlacidoRings(selectedPoints, ...
        'NumKnots', 36, ...
        'Lambda', 'auto', ...
        'Method', 'irls', ...
        'RobustIter', 5, ...
        'TuningConst', 4.685, ...
        'NumBins', 180, ...
        'MinCoverage', 90, ...
        'MaxGap', 45, ...
        'FallbackToArc', true, ...
        'Verbose', false);
end
if any(selectedSteps >= 21)
    % Downstream shape analysis must consume the fitted Step-19/20 curves,
    % not return to angularly imbalanced raw detector samples.  Periodic
    % mires therefore contribute one uniformly spaced fitted sample per
    % output angle; open arcs retain only their finite supported samples.
    analysisPoints = table(fittedTable.RingNumber,fittedTable.Theta, ...
        fittedTable.R_fit,'VariableNames',{'RingNumber','T','R'});
    analysisPoints = analysisPoints(all(isfinite(analysisPoints{:,{'T','R'}}),2),:);
    shapeMetrics = calculateShapeMetrics(analysisPoints, fitRingIds, fitInfo);
end

S = struct();
S.source = source;
S.gray = gray;
S.cannyEdges = cannyEdges;
S.cleanEdges = cleanEdges;
S.frameCentre = frameCentre;
S.frameRadius = frameRadius;
S.frameRoi = frameRoi;
S.coarseCentre = coarseCentre;
S.polarAnglesDeg = polarAnglesDeg;
S.polarRadii = polarRadii;
S.polarImage = polarImage;
S.historicalInner = historicalInner;
S.historicalOuter = historicalOuter;
S.historicalLabels = historicalLabels;
S.historicalKeepMask = historicalKeepMask;
S.historicalRejectMask = historicalRejectMask;
S.placidoCentre = placidoCentre;
S.hubCandidateMask = hubCandidateMask;
S.placidoRoi = placidoRoi;
S.dedicatedEdges = dedicatedEdges;
S.innerDirectional = innerDirectional;
S.outerDirectional = outerDirectional;
S.innerPruned = innerPruned;
S.outerPruned = outerPruned;
S.removedBranches = removedBranches;
S.combinedLabels = combinedLabels;
S.allPoints = allPoints;
S.componentSummary = componentSummary;
S.finalPoints = finalPoints;
S.boundaryPairSummary = boundaryPairSummary;
S.physicalMirePoints = physicalMirePoints;
S.selectedPoints = selectedPoints;
S.analysisPoints = analysisPoints;
S.requestedRings = requestedRings;
S.fitRingIds = fitRingIds;
S.fittedTable = fittedTable;
S.fitObjects = fitObjects;
S.fitInfo = fitInfo;
S.shapeMetrics = shapeMetrics;
S.workingRadiusPx = workingRadiusPx;
S.displayHalfSize = displayHalfSize;

stepSlugs = { ...
    'acquire_select_frame', ...
    'grayscale', ...
    'canny_edge_detection', ...
    'border_component_cleanup', ...
    'circular_field_of_view', ...
    'coarse_centre', ...
    'polar_unwrap', ...
    'radial_gradient_polarity', ...
    'candidate_ring_groups', ...
    'candidate_geometry_filter', ...
    'placido_hub', ...
    'canny_radial_masks', ...
    'radial_branch_pruning', ...
    'tangent_fragment_merge', ...
    'subtense_gate', ...
    'physical_mire_centrelines', ...
    'angular_binning', ...
    'periodic_arc_decision', ...
    'periodic_cubic_spline', ...
    'irls_outlier_weighting', ...
    'eigen_ratio', ...
    'mire_centre_instability', ...
    'harmonic_filtered_irregularity', ...
    'principal_image_axis', ...
    'combined_per_mire_summary', ...
    'representative_mire_ellipse_flat_steep', ...
    'all_mire_ellipses_individual_flat_steep', ...
    'all_mire_ellipses_mean_flat_steep'};

outputFiles = strings(numel(selectedSteps),1);
fullFrameFiles = strings(0,1);
for index = 1:numel(selectedSteps)
    step = selectedSteps(index);
    outputPath = fullfile(runFolder, sprintf('step_%02d_%s.png', ...
        step, stepSlugs{step}));
    renderPlacidoOnlyStep(step, S, outputPath);
    outputFiles(index) = string(outputPath);
    reportWriteupStep('Placido',step);
    if ismember(step,[11 12 13 14 15 16 19])
        fullFramePath = fullfile(runFolder,sprintf( ...
            'step_%02d_%s_full_frame.png',step,stepSlugs{step}));
        renderPlacidoFullFrameStep(step,S,fullFramePath);
        fullFrameFiles(end+1,1) = string(fullFramePath); %#ok<AGROW>
    end
end

result = struct();
result.InputImage = inputImage;
result.OutputFolder = runFolder;
result.SelectedSteps = selectedSteps;
result.RingRange = ringRange;
result.AvailablePhysicalMires = availableRings;
result.BoundaryPairSummary = boundaryPairSummary;
result.AnalysisRadiusPx = workingRadiusPx;
result.OutputFiles = outputFiles;
result.FullFrameOutputFiles = fullFrameFiles;
% Fit every detected centreline separately from the requested report range.
[allFit,~,allInfo] = fitAllPlacidoRings(physicalMirePoints, ...
    'NumKnots',36,'Lambda','auto','Method','irls','RobustIter',5, ...
    'TuningConst',4.685,'NumBins',180,'MinCoverage',90,'MaxGap',45, ...
    'FallbackToArc',true,'Verbose',false);
allPoints = table(allFit.RingNumber,allFit.Theta,allFit.R_fit, ...
    'VariableNames',{'RingNumber','T','R'});
allPoints = allPoints(all(isfinite(allPoints{:,:}),2),:);
result.AllMetrics = calculateShapeMetrics(allPoints,sort(unique(physicalMirePoints.RingNumber)),allInfo);
result.AllPoints = allPoints;
result.DetectedPoints = physicalMirePoints;

fprintf(['PLACIDO_ONLY_STEPS_COMPLETE\nGenerated %d image(s), including full-frame variants. ' ...
    'The output folder contains PNG files only.\n'], ...
    numel(outputFiles)+numel(fullFrameFiles));
end

% =========================================================================
% Processing helpers
% =========================================================================

function centre = estimateHistoricalCoarseCentre(gray)
% Reproduce the intent of coarse_center.m using an efficient box mean.
[h, w] = size(gray);
sideLength = min(h, w);
support = max(3, round(sideLength/10));
if mod(support,2) == 0
    support = support + 1;
end
smoothed = imboxfilt(gray, support, 'Padding', 'replicate');
margin = floor(support/2);
valid = smoothed;
if h > 2*margin && w > 2*margin
    valid([1:margin, h-margin+1:h], :) = Inf;
    valid(:, [1:margin, w-margin+1:w]) = Inf;
end
[~, linearIndex] = min(valid(:));
[row, column] = ind2sub(size(valid), linearIndex);
centre = [column row];
end

function oriented = applySupportedExifOrientation(source, info)
% Match the displayed frame for the supported rotation-only EXIF cases.
oriented = source;
if isempty(info) || ~isfield(info,'Orientation') || isempty(info.Orientation)
    return;
end
switch info.Orientation
    case 3
        oriented = rot90(source,2);
    case 6
        oriented = rot90(source,-1);
    case 8
        oriented = rot90(source,1);
end
end

function [centre, candidateMask, roiMask, actualWorkingRadius] = detectPlacidoHub( ...
        gray, X, Y, requestedWorkingRadius, sensitivity, minimumArea, minimumCircularity)
% The original adaptive-region test remains the documented fallback, but a
% dark circular hub proposal is evaluated first.  This corrects a real
% failure mode of the historical findCenterGlow implementation: if no
% eligible region is found it silently selects component 1, which can be an
% eyelid or border object.  The proposal is evaluated on a bounded preview
% so a 4K frame remains practical in MATLAB.
[heightPx, widthPx] = size(gray);
scale = min(1, 480/max(heightPx,widthPx));
preview = gray;
if scale < 1
    preview = imresize(gray, scale, 'bilinear');
end
preview = imgaussfilt(preview, 2.0, 'Padding', 'symmetric');
[previewHeight, previewWidth] = size(preview);
previewMin = min(previewHeight, previewWidth);
radiusRange = [max(8,round(0.018*previewMin)), ...
    max(12,round(0.16*previewMin))];
radiusRange(2) = max(radiusRange(2), radiusRange(1)+5);

try
    [circleCentres, circleRadii, circleStrength] = imfindcircles( ...
        preview, radiusRange, 'ObjectPolarity','dark', ...
        'Sensitivity',0.92, 'EdgeThreshold',0.05, 'Method','TwoStage');
catch
    circleCentres = zeros(0,2);
    circleRadii = zeros(0,1);
    circleStrength = zeros(0,1);
end

candidateMask = false(size(gray));
if ~isempty(circleCentres)
    previewCentre = [(previewWidth+1)/2, (previewHeight+1)/2];
    proximity = 1-min(1,vecnorm(circleCentres-previewCentre,2,2) / ...
        (0.5*previewMin));
    darkness = zeros(size(circleStrength));
    for candidate = 1:size(circleCentres,1)
        centreCandidate = circleCentres(candidate,:);
        radiusCandidate = circleRadii(candidate);
        x1 = max(1,round(centreCandidate(1)-radiusCandidate));
        x2 = min(previewWidth,round(centreCandidate(1)+radiusCandidate));
        y1 = max(1,round(centreCandidate(2)-radiusCandidate));
        y2 = min(previewHeight,round(centreCandidate(2)+radiusCandidate));
        darkness(candidate) = mean(preview(y1:y2,x1:x2),'all');
    end
    darkness = 1-mat2gray(darkness);
    score = 0.70*mat2gray(circleStrength) + 0.20*darkness + 0.10*proximity;
    [~, bestCandidate] = max(score);
    centre = circleCentres(bestCandidate,:)/scale;
    selectedRadius = circleRadii(bestCandidate)/scale;
    candidateMask = hypot(X-centre(1),Y-centre(2)) <= selectedRadius;
else
    % Faithful fallback to the dedicated adaptive hub-region rule, with an
    % explicit failure rather than returning an arbitrary first component.
    binary = imbinarize(gray, 'adaptive', 'Sensitivity', sensitivity);
    filled = imfill(binary, 'holes');
    stats = regionprops(filled, gray, 'Area', 'Circularity', ...
        'Centroid', 'MeanIntensity', 'PixelIdxList');
    if isempty(stats)
        error('Placido hub detection found no connected candidate structures.');
    end
    eligible = find([stats.Area] > minimumArea & ...
        [stats.Circularity] > minimumCircularity);
    if isempty(eligible)
        error(['Placido hub detection found no candidate satisfying Area > %g ' ...
            'and Circularity > %.2f.'], minimumArea, minimumCircularity);
    end
    imageCentre = [(widthPx+1)/2, (heightPx+1)/2];
    centroids = vertcat(stats(eligible).Centroid);
    areas = [stats(eligible).Area].';
    circularities = [stats(eligible).Circularity].';
    intensities = [stats(eligible).MeanIntensity].';
    proximity = 1-min(1,vecnorm(centroids-imageCentre,2,2) / ...
        (0.5*min(heightPx,widthPx)));
    score = 0.35*mat2gray(areas) + 0.30*mat2gray(circularities) + ...
        0.25*(1-mat2gray(intensities)) + 0.10*proximity;
    [~, bestEligible] = max(score);
    centre = centroids(bestEligible,:);
    candidateMask(stats(eligible(bestEligible)).PixelIdxList) = true;
end
safeRadius = floor(min([centre(1)-1,size(gray,2)-centre(1), ...
    centre(2)-1,size(gray,1)-centre(2)]));
actualWorkingRadius = max(1,min(requestedWorkingRadius,safeRadius));
roiMask = hypot(X-centre(1), Y-centre(2)) <= actualWorkingRadius;
end

function value = ternaryText(condition, trueValue, falseValue)
if condition, value = trueValue; else, value = falseValue; end
end

function [keepMask, rejectMask] = classifyHistoricalComponents(labels, centre)
components = regionprops(labels, 'PixelIdxList', 'Area');
keepMask = false(size(labels));
rejectMask = false(size(labels));
for k = 1:numel(components)
    indices = components(k).PixelIdxList;
    [row, column] = ind2sub(size(labels), indices);
    keep = false;
    if numel(indices) >= 3
        try
            hull = convhull(double(column), double(row), 'Simplify', true);
            keep = inpolygon(centre(1), centre(2), column(hull), row(hull));
        catch
            keep = false;
        end
    end
    if keep
        keepMask(indices) = true;
    else
        rejectMask(indices) = true;
    end
end
end

function finalLabels = mergeFragmentsSafe(mask, maxDistance, angleTolerance, forceDistance)
% Memory-safe implementation of the dedicated endpoint/tangent merge rule.
connected = bwconncomp(mask, 8);
stats = regionprops(connected, 'PixelList', 'PixelIdxList');
n = numel(stats);
finalLabels = zeros(size(mask));
if n == 0
    return;
end

endpointsImage = bwmorph(mask, 'endpoints');
[endpointY, endpointX] = find(endpointsImage);
allEndpoints = [endpointX endpointY];
lookback = 30;
tips = cell(n,1);
tangents = cell(n,1);
for component = 1:n
    pixels = double(stats(component).PixelList);
    isTip = ismember(allEndpoints, pixels, 'rows');
    componentTips = double(allEndpoints(isTip,:));
    if isempty(componentTips)
        % Avoid the original full pairwise-distance matrix for closed curves.
        seed = pixels(1,:);
        [~, a] = max(sum((pixels-seed).^2,2));
        [~, b] = max(sum((pixels-pixels(a,:)).^2,2));
        componentTips = [pixels(a,:); pixels(b,:)];
    end
    componentTangents = zeros(size(componentTips));
    for tipIndex = 1:size(componentTips,1)
        delta = pixels-componentTips(tipIndex,:);
        [~, order] = sort(sum(delta.^2,2), 'ascend');
        innerIndex = order(min(lookback, numel(order)));
        vector = componentTips(tipIndex,:) - pixels(innerIndex,:);
        componentTangents(tipIndex,:) = vector ./ (norm(vector)+eps);
    end
    tips{component} = componentTips;
    tangents{component} = componentTangents;
end

source = zeros(0,1);
target = zeros(0,1);
for i = 1:n
    for j = i+1:n
        merge = false;
        for a = 1:size(tips{i},1)
            for b = 1:size(tips{j},1)
                bridge = tips{j}(b,:) - tips{i}(a,:);
                distance = norm(bridge);
                if distance > maxDistance
                    continue;
                end
                direction = bridge/(distance+eps);
                angleA = acosd(max(-1,min(1,dot(tangents{i}(a,:), direction))));
                angleB = acosd(max(-1,min(1,dot(tangents{j}(b,:), -direction))));
                if distance <= forceDistance || ...
                        (angleA < angleTolerance && angleB < angleTolerance)
                    merge = true;
                    break;
                end
            end
            if merge, break; end
        end
        if merge
            source(end+1,1) = i; %#ok<AGROW>
            target(end+1,1) = j; %#ok<AGROW>
        end
    end
end

if isempty(source)
    mapping = 1:n;
else
    mapping = conncomp(graph(source, target, [], n));
end
for component = 1:n
    finalLabels(stats(component).PixelIdxList) = mapping(component);
end
end

function points = labelImageToPointTable(labels, centre)
indices = find(labels > 0);
[Y, X] = ind2sub(size(labels), indices);
Label = double(labels(indices));
X = double(X);
Y = double(Y);
T = mod(atan2(Y-centre(2), X-centre(1)), 2*pi);
R = hypot(X-centre(1), Y-centre(2));
points = table(Label, X, Y, T, R);
points = sortrows(points, {'Label','T'});
end

function [summary, finalPoints] = applySubtenseAndOrdering(points, centre, minimumSubtense)
if isempty(points)
    summary = table();
    finalPoints = table();
    return;
end
requireFunction('getSubtenseRobust');
labels = unique(points.Label);
n = numel(labels);
MeanRadiusPx = nan(n,1);
SubtenseDeg = nan(n,1);
EnclosesCentre = false(n,1);
Accepted = false(n,1);
for k = 1:n
    rows = points.Label == labels(k);
    MeanRadiusPx(k) = mean(points.R(rows), 'omitnan');
    [SubtenseDeg(k), EnclosesCentre(k)] = getSubtenseRobust( ...
        points.X(rows), points.Y(rows), centre);
    Accepted(k) = SubtenseDeg(k) >= minimumSubtense;
end
summary = table(labels, MeanRadiusPx, SubtenseDeg, EnclosesCentre, Accepted, ...
    'VariableNames', {'Label','MeanRadiusPx','SubtenseDeg','EnclosesCentre','Accepted'});

acceptedSummary = sortrows(summary(summary.Accepted,:), 'MeanRadiusPx');
finalPoints = points(ismember(points.Label, acceptedSummary.Label),:);
if isempty(finalPoints)
    return;
end
finalPoints.RingNumber = zeros(height(finalPoints),1);
for ring = 1:height(acceptedSummary)
    finalPoints.RingNumber(finalPoints.Label == acceptedSummary.Label(ring)) = ring;
end
finalPoints.T_deg = rad2deg(finalPoints.T);
finalPoints = sortrows(finalPoints, {'RingNumber','T'});
end

function [pairSummary, mirePoints] = pairBoundaryTracksIntoMires(boundaryPoints, centre)
% Pair consecutive opposite-polarity edge tracks and form one mire centreline.
% Odd source labels came from the negative-radial-gradient mask and even
% labels from the positive-radial-gradient mask.  Pairing is performed only
% between radially adjacent tracks of opposite polarity; a missing or extra
% boundary is therefore reported as unpaired instead of silently shifting
% every subsequent physical mire identity.
trackIds = unique(boundaryPoints.RingNumber).';
n = numel(trackIds);
meanRadius = nan(n,1); polarity = nan(n,1);
for k = 1:n
    rows = boundaryPoints.RingNumber == trackIds(k);
    meanRadius(k) = median(boundaryPoints.R(rows),'omitnan');
    sourceLabels = boundaryPoints.Label(rows);
    polarity(k) = mode(mod(sourceLabels,2)); % 1=negative/inner mask, 0=positive/outer mask
end
[meanRadius,order] = sort(meanRadius);
trackIds = trackIds(order); polarity = polarity(order);

InnerBoundaryTrack = zeros(0,1); OuterBoundaryTrack = zeros(0,1);
InnerMeanRadiusPx = zeros(0,1); OuterMeanRadiusPx = zeros(0,1);
MeanWidthPx = zeros(0,1); CommonAngleCount = zeros(0,1);
CoverageDeg = zeros(0,1); MireIndex = zeros(0,1);
mirePoints = table(); k = 1; mire = 0;
while k < n
    if polarity(k) == polarity(k+1)
        k = k + 1;
        continue;
    end
    innerTrack = trackIds(k); outerTrack = trackIds(k+1);
    innerRows = boundaryPoints.RingNumber == innerTrack;
    outerRows = boundaryPoints.RingNumber == outerTrack;
    innerProfile = angularMedianProfile(boundaryPoints.T(innerRows),boundaryPoints.R(innerRows));
    outerProfile = angularMedianProfile(boundaryPoints.T(outerRows),boundaryPoints.R(outerRows));
    common = isfinite(innerProfile) & isfinite(outerProfile) & outerProfile > innerProfile;
    commonCount = sum(common);
    if commonCount >= 30
        mire = mire + 1;
        theta = deg2rad(find(common)-1);
        radius = 0.5*(innerProfile(common)+outerProfile(common));
        width = outerProfile(common)-innerProfile(common);
        X = centre(1)+radius.*cos(theta); Y = centre(2)+radius.*sin(theta);
        Label = repmat(mire,numel(theta),1); RingNumber = Label;
        T = theta; R = radius; T_deg = rad2deg(theta);
        InnerTrack = repmat(innerTrack,numel(theta),1);
        OuterTrack = repmat(outerTrack,numel(theta),1);
        WidthPx = width;
        block = table(Label,X,Y,T,R,RingNumber,T_deg,InnerTrack,OuterTrack,WidthPx);
        mirePoints = [mirePoints; block]; %#ok<AGROW>
        MireIndex(end+1,1)=mire; %#ok<AGROW>
        InnerBoundaryTrack(end+1,1)=innerTrack; %#ok<AGROW>
        OuterBoundaryTrack(end+1,1)=outerTrack; %#ok<AGROW>
        InnerMeanRadiusPx(end+1,1)=meanRadius(k); %#ok<AGROW>
        OuterMeanRadiusPx(end+1,1)=meanRadius(k+1); %#ok<AGROW>
        MeanWidthPx(end+1,1)=mean(width,'omitnan'); %#ok<AGROW>
        CommonAngleCount(end+1,1)=commonCount; %#ok<AGROW>
        CoverageDeg(end+1,1)=commonCount; %#ok<AGROW>
    end
    k = k + 2;
end
pairSummary = table(MireIndex,InnerBoundaryTrack,OuterBoundaryTrack, ...
    InnerMeanRadiusPx,OuterMeanRadiusPx,MeanWidthPx,CommonAngleCount,CoverageDeg);
if ~isempty(mirePoints)
    mirePoints = sortrows(mirePoints,{'RingNumber','T'});
end
end

function profile = angularMedianProfile(theta,radius)
% One robust radius per integer-degree bin; gaps remain missing.
bin = mod(round(rad2deg(theta)),360)+1;
profile = accumarray(bin(:),radius(:),[360 1],@median,NaN);
end

function metrics = calculateShapeMetrics(points, ringIds, fitInfo)
template = struct('Ring',0,'IsCompletePrimary',false,'CoverageDeg',NaN, ...
    'MaximumGapDeg',NaN,'EigenRatio',NaN, ...
    'TrackingCentroid',[NaN NaN],'Eigenvectors',nan(2), ...
    'MajorExtentPx',NaN,'MinorExtentPx',NaN, ...
    'CV_R_Pct',NaN,'IrregularityPct',NaN,'EllipseRmsPx',NaN, ...
    'HarmonicRmsPx',NaN, ...
    'FlatRawDeg',NaN,'SteepRawDeg',NaN,'ImageAxisDeg',NaN, ...
    'PerpendicularAxisDeg',NaN,'HarmonicAmplitudePx',NaN, ...
    'HarmonicMajorRadiusPx',NaN,'HarmonicMinorRadiusPx',NaN, ...
    'RawHarmonicCoefficients',nan(3,1), ...
    'CenteredAnglesRad',zeros(0,1),'CenteredRadiiPx',zeros(0,1), ...
    'CenteredHarmonicFitPx',zeros(0,1),'IrregularResidualPx',zeros(0,1), ...
    'CenteredHarmonicCoefficients',nan(3,1));
metrics = repmat(template, numel(ringIds), 1);
requireFunction('getHarmonicAstigmatism');
for k = 1:numel(ringIds)
    ring = ringIds(k);
    rows = points.RingNumber == ring;
    theta = points.T(rows);
    radius = points.R(rows);
    info = fitInfo{k};
    metrics(k).Ring = ring;
    metrics(k).CoverageDeg = info.coverage_deg;
    metrics(k).MaximumGapDeg = info.max_gap_deg;
    metrics(k).IsCompletePrimary = info.is_closed && ...
        strcmpi(info.spline_type, 'periodic');

    if numel(radius) >= 3
        % Common comparison frame used by both pathways: X increases to the
        % image right and Y increases superiorly (opposite image-row growth).
        trackingX = radius .* cos(theta);
        trackingY = -radius .* sin(theta);
        centre = [mean(trackingX) mean(trackingY)];
        covariance = cov([trackingX trackingY]);
        [vectors, values] = eig(covariance, 'vector');
        [values, order] = sort(real(values), 'descend');
        vectors = real(vectors(:,order));
        metrics(k).TrackingCentroid = centre;
        metrics(k).Eigenvectors = vectors;
        if values(1) > 0
            metrics(k).MajorExtentPx = sqrt(2*values(1));
            metrics(k).MinorExtentPx = sqrt(2*max(values(2),0));
            metrics(k).EigenRatio = metrics(k).MinorExtentPx / ...
                metrics(k).MajorExtentPx;
            % Shared convention: the covariance major eigenvector (long
            % ellipse semiaxis) is the flat image axis; the orthogonal
            % minor eigenvector (short semiaxis) is the steep image axis.
            metrics(k).ImageAxisDeg = mod(atan2d(vectors(2,1),vectors(1,1)),180);
            metrics(k).PerpendicularAxisDeg = mod(metrics(k).ImageAxisDeg+90,180);
        end
        [flatRaw, steepRaw, harmonicRms, majorRadius, minorRadius] = ...
            getHarmonicAstigmatism(rad2deg(theta), radius);
        metrics(k).FlatRawDeg = flatRaw;
        metrics(k).SteepRawDeg = steepRaw;
        metrics(k).HarmonicRmsPx = harmonicRms;
        metrics(k).HarmonicAmplitudePx = (majorRadius-minorRadius)/2;
        metrics(k).HarmonicMajorRadiusPx = majorRadius;
        metrics(k).HarmonicMinorRadiusPx = minorRadius;
        rawBasis = [ones(size(theta)),cos(2*theta),sin(2*theta)];
        metrics(k).RawHarmonicCoefficients = rawBasis \ radius;
        metrics(k).CV_R_Pct = 100*std(radius)/max(mean(radius),eps);

        centredX = trackingX-centre(1);
        centredY = trackingY-centre(2);
        centredAngles = atan2(centredY,centredX);
        centredRadii = hypot(centredX,centredY);
        centredBasis = [ones(size(centredAngles)), ...
            cos(2*centredAngles), sin(2*centredAngles)];
        centredCoefficients = centredBasis \ centredRadii;
        centredFit = centredBasis*centredCoefficients;
        irregularResidual = centredRadii-centredFit;
        [ellipseRms,ellipseIrregularity] = ...
            calculateHealthExEllipseIrregularity(trackingX,trackingY);
        metrics(k).EllipseRmsPx = ellipseRms;
        metrics(k).IrregularityPct = ellipseIrregularity;
        metrics(k).CenteredAnglesRad = centredAngles;
        metrics(k).CenteredRadiiPx = centredRadii;
        metrics(k).CenteredHarmonicFitPx = centredFit;
        metrics(k).IrregularResidualPx = irregularResidual;
        metrics(k).CenteredHarmonicCoefficients = centredCoefficients;
    end
end
end

function [rmseValue,irregularityPct] = calculateHealthExEllipseIrregularity(x,y)
% Unified explicit-ellipse radial RMSE irregularity definition.
% fit an explicit ellipse, calculate radial RMSE, then normalize by mean R.
rmseValue=NaN; irregularityPct=NaN;
if numel(x)<5 || exist('fit_ellipse','file')~=2 || ...
        exist('get_optometric_axes','file')~=2
    return;
end
try
    params=fit_ellipse(x(:),y(:));
    if isempty(params), return; end
    opto=get_optometric_axes(params);
    radius=hypot(x(:),y(:));
    theta=atan2(y(:),x(:));
    a=opto.major_radius; b=opto.minor_radius;
    phi=deg2rad(opto.major_axis_deg);
    ideal=(a*b)./sqrt((b*cos(theta-phi)).^2+(a*sin(theta-phi)).^2);
    residual=radius-ideal;
    rmseValue=sqrt(mean(residual.^2));
    irregularityPct=100*rmseValue/max(mean(radius),eps);
catch
    rmseValue=NaN; irregularityPct=NaN;
end
end

function requireFunction(name)
if exist(name, 'file') ~= 2
    error(['Required original Placido helper %s.m was not found. Keep the ' ...
        'D:\\MATLAB\\placido project beside the Updates folder.'], name);
end
end

% =========================================================================
% Image-only renderers
% =========================================================================

function renderPlacidoOnlyStep(step, S, outputPath)
switch step
    case 1
        writeBoundedImage(S.source, outputPath);
    case 2
        writeBoundedImage(S.gray, outputPath);
    case 3
        writeBoundedImage(S.cannyEdges, outputPath);
    case 4
        writeBoundedImage(S.cleanEdges, outputPath);
    case 5
        image = greyToRgb(S.gray);
        image(repmat(~S.frameRoi,1,1,3)) = 0;
        writeBoundedImage(image, outputPath);
    case 6
        [fig, ax] = imageAxes(S.gray);
        plot(ax, S.coarseCentre(1), S.coarseCentre(2), 'y+', ...
            'MarkerSize', 18, 'LineWidth', 2.2);
        exportAndClose(fig, ax, outputPath);
    case 7
        fig = figure('Visible','off','Color','w','Position',[100 100 1050 720]);
        ax = axes(fig);
        imagesc(ax, S.polarAnglesDeg, S.polarRadii, S.polarImage);
        axis(ax,'xy'); axis(ax,'tight'); colormap(ax,gray(256));
        xlabel(ax,'Angle (degrees)'); ylabel(ax,'Radius (pixels)');
        exportAndClose(fig, ax, outputPath);
    case 8
        image = masksOnBlack(size(S.gray), ...
            {S.historicalInner,S.historicalOuter}, {[1 0.18 0.12],[0.10 0.85 0.35]});
        writeBoundedImage(image, outputPath);
    case 9
        writeBoundedImage(colourLabels(S.historicalLabels), outputPath);
    case 10
        image = blendMasks(greyToRgb(S.gray), ...
            {S.historicalRejectMask,S.historicalKeepMask}, ...
            {[0.12 0.42 1.00],[1.00 0.18 0.12]}, [0.90 0.95]);
        writeBoundedImage(image, outputPath);
    case 11
        [fig, ax] = imageAxes(S.gray);
        [hubY,hubX] = find(bwperim(S.hubCandidateMask,8));
        plot(ax,hubX,hubY,'.','Color',[1.00 0.72 0.08], ...
            'MarkerSize',5,'DisplayName','Detected hub boundary');
        roiTheta = linspace(0,2*pi,720);
        plot(ax,S.placidoCentre(1)+S.workingRadiusPx*cos(roiTheta), ...
            S.placidoCentre(2)+S.workingRadiusPx*sin(roiTheta),'--', ...
            'Color',[0.10 0.90 0.90],'LineWidth',1.5, ...
            'DisplayName',sprintf('%d pixel analysis ROI',S.workingRadiusPx));
        plot(ax, S.placidoCentre(1), S.placidoCentre(2), 'r+', ...
            'MarkerSize',18,'LineWidth',2.2,'DisplayName','Placido centre');
        zoomImageAxes(ax, size(S.gray), S.placidoCentre, S.displayHalfSize);
        legend(ax,'Location','northwest','Color','w','TextColor','k');
        exportAndClose(fig, ax, outputPath);
    case 12
        image = blendMasks(greyToRgb(S.gray), ...
            {S.innerDirectional,S.outerDirectional}, ...
            {[1.00 0.12 0.12],[0.10 0.90 0.35]}, [0.92 0.92]);
        writeBoundedImage(cropAroundCentre(image,S.placidoCentre,S.displayHalfSize), outputPath);
    case 13
        image = blendMasks(greyToRgb(S.gray), ...
            {S.removedBranches,S.innerPruned,S.outerPruned}, ...
            {[0.95 0.10 0.85],[1.00 0.12 0.12],[0.10 0.90 0.35]}, ...
            [0.82 0.95 0.95]);
        writeBoundedImage(cropAroundCentre(image,S.placidoCentre,S.displayHalfSize), outputPath);
    case 14
        ringImage = colourLabels(S.combinedLabels);
        writeBoundedImage(cropAroundCentre(ringImage,S.placidoCentre,S.displayHalfSize), ...
            outputPath);
    case 15
        acceptedLabels = S.componentSummary.Label(S.componentSummary.Accepted);
        accepted = ismember(S.allPoints.Label, acceptedLabels);
        [fig, ax] = imageAxes(S.gray);
        scatter(ax, S.allPoints.X(~accepted), S.allPoints.Y(~accepted), 3, ...
            [0.10 0.42 1.00], 'filled');
        scatter(ax, S.allPoints.X(accepted), S.allPoints.Y(accepted), 3, ...
            [1.00 0.18 0.12], 'filled');
        zoomImageAxes(ax, size(S.gray), S.placidoCentre, S.displayHalfSize);
        exportAndClose(fig, ax, outputPath);
    case 16
        [fig, ax] = imageAxes(S.gray);
        plotRingPointSets(ax, S.selectedPoints, S.requestedRings, true);
        zoomImageAxes(ax, size(S.gray), S.placidoCentre, S.displayHalfSize);
        exportAndClose(fig, ax, outputPath);
    case 17
        [fig, ax] = plotAxes();
        colours = lines(max(1,numel(S.fitRingIds)));
        for k = 1:numel(S.fitRingIds)
            info = S.fitInfo{k};
            plot(ax, rad2deg(info.bin_t), info.bin_r, '.', ...
                'Color', colours(k,:), 'MarkerSize', 9, ...
                'DisplayName', sprintf('Mire %d',S.fitRingIds(k)));
        end
        xlabel(ax,'Angle (degrees)'); ylabel(ax,'Median radius (pixels)');
        xlim(ax,[0 360]); grid(ax,'on');
        addCompactLegend(ax, numel(S.fitRingIds));
        exportAndClose(fig, ax, outputPath);
    case 18
        [fig, ax] = plotAxes();
        gaps = cellfun(@(x) x.max_gap_deg, S.fitInfo);
        bars = bar(ax, S.fitRingIds, gaps, 'FaceColor','flat');
        bars.CData = repmat([0.82 0.24 0.16],numel(gaps),1);
        bars.CData(gaps < 45,:) = repmat([0.12 0.62 0.38],sum(gaps < 45),1);
        yline(ax,45,'--','45 degree closure threshold','LineWidth',1.4, ...
            'Color',[0.90 0.90 0.90],'HandleVisibility','off');
        for k = 1:numel(gaps)
            text(ax,S.fitRingIds(k),gaps(k)+1, ...
                sprintf('%.1f deg\n%s',gaps(k),S.fitInfo{k}.spline_type), ...
                'HorizontalAlignment','center','VerticalAlignment','bottom', ...
                'FontSize',8,'Color',[0.94 0.94 0.94]);
        end
        upperGapLimit = max(50,10*ceil((max(gaps)+5)/10));
        xticks(ax,S.fitRingIds); ylim(ax,[0 upperGapLimit]);
        xlabel(ax,'Physical mire index'); ylabel(ax,'Maximum gap (degrees)');
        grid(ax,'on');
        exportAndClose(fig, ax, outputPath);
    case 19
        [fig, ax] = imageAxes(S.gray);
        colours = lines(max(1,numel(S.fitRingIds)));
        for k = 1:numel(S.fitRingIds)
            rows = S.fittedTable.RingNumber == S.fitRingIds(k);
            theta = S.fittedTable.Theta(rows);
            radius = S.fittedTable.R_fit(rows);
            style = '-';
            if strcmpi(S.fitInfo{k}.spline_type,'arc'), style = '--'; end
            if strcmpi(S.fitInfo{k}.spline_type,'periodic') && ~isempty(theta)
                thetaPlot = vertcat(theta,theta(1)+2*pi);
                radiusPlot = vertcat(radius,radius(1));
            else
                thetaPlot = theta;
                radiusPlot = radius;
            end
            plot(ax, S.placidoCentre(1)+radiusPlot.*cos(thetaPlot), ...
                S.placidoCentre(2)+radiusPlot.*sin(thetaPlot), style, ...
                'Color',colours(k,:), 'LineWidth',1.5);
        end
        zoomImageAxes(ax, size(S.gray), S.placidoCentre, S.displayHalfSize);
        exportAndClose(fig, ax, outputPath);
    case 20
        [fig, ax] = plotAxes();
        colours = lines(max(1,numel(S.fitRingIds)));
        for k = 1:numel(S.fitRingIds)
            ringRows = S.selectedPoints.RingNumber == S.fitRingIds(k);
            angles = mod(S.selectedPoints.T(ringRows),2*pi);
            residuals = S.fitInfo{k}.residuals;
            outliers = S.fitInfo{k}.outlier_mask;
            n = min([numel(angles),numel(residuals),numel(outliers)]);
            angles = angles(1:n);
            residuals = residuals(1:n);
            outliers = outliers(1:n);
            [angles,order] = sort(angles);
            residuals = residuals(order);
            outliers = outliers(order);
            scatter(ax,rad2deg(angles),residuals,7,colours(k,:),'filled', ...
                'MarkerFaceAlpha',0.30, ...
                'DisplayName',sprintf('Mire %d',S.fitRingIds(k)));
            scatter(ax,rad2deg(angles(outliers)),residuals(outliers),15, ...
                [0.85 0.12 0.12],'filled','HandleVisibility','off');
        end
        yline(ax,0,'-','Color',[0.90 0.90 0.90], ...
            'HandleVisibility','off');
        xlim(ax,[0 360]); grid(ax,'on');
        xlabel(ax,'Angle (degrees)'); ylabel(ax,'IRLS residual (pixels)');
        addCompactLegend(ax, numel(S.fitRingIds));
        exportAndClose(fig, ax, outputPath);
    case 21
        fig = descriptorFigure('Covariance eigen-ratio');
        layout = tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
        axGeometry = nexttile(layout); styleDescriptorAxes(axGeometry);
        colours = lines(max(1,numel(S.shapeMetrics)));
        ellipseTheta = linspace(0,2*pi,720);
        for k = 1:numel(S.shapeMetrics)
            metric = S.shapeMetrics(k);
            rows = S.analysisPoints.RingNumber == metric.Ring;
            trackingX = S.analysisPoints.R(rows).*sin(S.analysisPoints.T(rows));
            trackingY = S.analysisPoints.R(rows).*cos(S.analysisPoints.T(rows));
            scatter(axGeometry,trackingX,trackingY,5,colours(k,:),'filled', ...
                'MarkerFaceAlpha',0.28,'HandleVisibility','off');
            if isfinite(metric.EigenRatio)
                ellipse = metric.TrackingCentroid.' + metric.Eigenvectors * ...
                    [metric.MajorExtentPx*cos(ellipseTheta); ...
                     metric.MinorExtentPx*sin(ellipseTheta)];
                lineStyle = '-';
                if ~metric.IsCompletePrimary, lineStyle = ':'; end
                plot(axGeometry,ellipse(1,:),ellipse(2,:),lineStyle, ...
                    'Color',colours(k,:),'LineWidth',1.6, ...
                    'DisplayName',sprintf('Mire %d',metric.Ring));
                labelFraction = (k-1)/max(1,numel(S.shapeMetrics));
                labelIndex = 1 + round(labelFraction*(numel(ellipseTheta)-1));
                text(axGeometry,ellipse(1,labelIndex),ellipse(2,labelIndex), ...
                    sprintf(' M%d',metric.Ring),'Color',colours(k,:), ...
                    'FontSize',8,'FontWeight','bold');
            end
        end
        axis(axGeometry,'equal'); grid(axGeometry,'on');
        xlabel(axGeometry,'Tracking X (pixels)'); ylabel(axGeometry,'Tracking Y (pixels)');
        title(axGeometry,'Point clouds and covariance ellipses');

        axMetric = nexttile(layout); styleDescriptorAxes(axMetric);
        plotDescriptorMetric(axMetric,S.shapeMetrics,'EigenRatio', ...
            'Eigen-ratio, L_{minor}/L_{major}',[0 1.05]);
        title(axMetric,'sqrt(lambda_{min}/lambda_{max}) = L_{minor}/L_{major}');
        exportFigureAndClose(fig,outputPath);
    case 22
        fig = descriptorFigure('Physical-mire centre instability');
        layout = tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
        metrics = S.shapeMetrics;
        centres = vertcat(metrics.TrackingCentroid);
        valid = all(isfinite(centres),2);
        primary = [metrics.IsCompletePrimary].' & valid;
        referenceRows = primary;
        if ~any(referenceRows), referenceRows = valid; end
        referenceCentre = mean(centres(referenceRows,:),1,'omitnan');
        deviations = hypot(centres(:,1)-referenceCentre(1), ...
            centres(:,2)-referenceCentre(2));
        spread = sqrt(std(centres(referenceRows,1))^2 + ...
            std(centres(referenceRows,2))^2);

        axCentres = nexttile(layout); styleDescriptorAxes(axCentres);
        colours = lines(max(1,numel(metrics)));
        for k = 1:numel(metrics)
            if ~valid(k), continue; end
            plot(axCentres,[referenceCentre(1) centres(k,1)], ...
                [referenceCentre(2) centres(k,2)],':','Color',colours(k,:), ...
                'HandleVisibility','off');
            scatter(axCentres,centres(k,1),centres(k,2),55,colours(k,:), ...
                'filled','DisplayName',sprintf('Mire %d',metrics(k).Ring));
            text(axCentres,centres(k,1),centres(k,2),sprintf('  M%d',metrics(k).Ring), ...
                'Color',colours(k,:),'FontWeight','bold','FontSize',9);
        end
        plot(axCentres,referenceCentre(1),referenceCentre(2),'k+', ...
            'MarkerSize',16,'LineWidth',2.0,'HandleVisibility','off');
        axis(axCentres,'equal'); grid(axCentres,'on');
        xlabel(axCentres,'Mire-centre X (source-image pixels)');
        ylabel(axCentres,'Mire-centre Y (source-image pixels)');
        title(axCentres,'Per-mire centroids and selected-range mean');

        axInstability = nexttile(layout); styleDescriptorAxes(axInstability);
        rings = [metrics.Ring].';
        plot(axInstability,rings,deviations,'o-','Color',[0.12 0.63 0.38], ...
            'MarkerFaceColor',[0.12 0.63 0.38],'LineWidth',1.7);
        xticks(axInstability,rings); grid(axInstability,'on');
        xlabel(axInstability,'Physical mire index');
        ylabel(axInstability,'Distance from mean centre (source-image pixels)');
        yline(axInstability,mean(deviations(referenceRows),'omitnan'),'--k', ...
            sprintf('Mean %.3f',mean(deviations(referenceRows),'omitnan')));
        title(axInstability,sprintf( ...
            'Single-frame cross-mire centre spread = %.3f pixels',spread));
        markDiagnosticRings(axInstability,metrics,deviations);
        exportFigureAndClose(fig,outputPath);
    case 23
        fig = descriptorFigure('Ellipse-RMSE irregularity');
        metrics = S.shapeMetrics;
        axIrregularity = axes(fig); styleDescriptorAxes(axIrregularity);
        plotDescriptorMetric(axIrregularity,metrics,'IrregularityPct', ...
            'Ellipse-RMSE irregularity (%)',[]);
        title(axIrregularity,'Per-mire ellipse-RMSE irregularity');
        exportFigureAndClose(fig,outputPath);
    case 24
        fig = descriptorFigure('Principal second-harmonic image axes');
        layout = tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
        metrics = S.shapeMetrics;
        colours = lines(max(1,numel(metrics)));
        axAxes = nexttile(layout); styleDescriptorAxes(axAxes);
        tPlot = linspace(0,2*pi,720).';
        for k = 1:numel(metrics)
            metric = metrics(k);
            if ~all(isfinite(metric.TrackingCentroid)) || ...
                    ~isfinite(metric.FlatRawDeg)
                continue;
            end
            coefficients = metric.RawHarmonicCoefficients;
            radialFit = [ones(size(tPlot)),cos(2*tPlot),sin(2*tPlot)]*coefficients;
            cx = 0; cy = 0;
            lineStyle = '-';
            if ~metric.IsCompletePrimary, lineStyle = ':'; end
            plot(axAxes,cx+radialFit.*sin(tPlot),cy+radialFit.*cos(tPlot), ...
                lineStyle,'Color',colours(k,:),'LineWidth',1.4, ...
                'DisplayName',sprintf('Mire %d',metric.Ring));
            majorDirection = [sind(metric.FlatRawDeg),cosd(metric.FlatRawDeg)];
            minorDirection = [sind(metric.SteepRawDeg),cosd(metric.SteepRawDeg)];
            plot(axAxes,cx+[-metric.HarmonicMajorRadiusPx metric.HarmonicMajorRadiusPx]*majorDirection(1), ...
                cy+[-metric.HarmonicMajorRadiusPx metric.HarmonicMajorRadiusPx]*majorDirection(2), ...
                '--','Color',colours(k,:),'LineWidth',0.9,'HandleVisibility','off');
            plot(axAxes,cx+[-metric.HarmonicMinorRadiusPx metric.HarmonicMinorRadiusPx]*minorDirection(1), ...
                cy+[-metric.HarmonicMinorRadiusPx metric.HarmonicMinorRadiusPx]*minorDirection(2), ...
                ':','Color',colours(k,:),'LineWidth',0.8,'HandleVisibility','off');
            labelFraction = (k-1)/max(1,numel(metrics));
            labelIndex = 1 + round(labelFraction*(numel(tPlot)-1));
            text(axAxes,cx+radialFit(labelIndex)*sin(tPlot(labelIndex)), ...
                cy+radialFit(labelIndex)*cos(tPlot(labelIndex)), ...
                sprintf(' M%d',metric.Ring),'Color',colours(k,:), ...
                'FontWeight','bold','FontSize',8);
        end
        axis(axAxes,'equal'); grid(axAxes,'on');
        xlabel(axAxes,'Tracking X (pixels)'); ylabel(axAxes,'Tracking Y (pixels)');
        title(axAxes,'Fitted curves and orthogonal image axes');
        addCompactLegend(axAxes,numel(metrics));

        axAngle = nexttile(layout); styleDescriptorAxes(axAngle);
        rings = [metrics.Ring].';
        imageAxis = [metrics.ImageAxisDeg].';
        perpendicular = [metrics.PerpendicularAxisDeg].';
        plot(axAngle,rings,imageAxis,'o','Color',[0.12 0.72 0.93], ...
            'MarkerFaceColor',[0.12 0.72 0.93],'LineWidth',1.5, ...
            'DisplayName','Principal image axis');
        plot(axAngle,rings,perpendicular,'s','Color',[1.00 0.62 0.16], ...
            'MarkerFaceColor',[1.00 0.62 0.16],'LineWidth',1.3, ...
            'DisplayName','Orthogonal image axis');
        xticks(axAngle,rings); yticks(axAngle,0:30:180); ylim(axAngle,[0 180]);
        grid(axAngle,'on'); xlabel(axAngle,'Physical mire index');
        ylabel(axAngle,'Axis orientation (degrees; 0 to <180)');
        title(axAngle,'Image-space orientation (not keratometry)');
        legend(axAngle,'Location','best');
        exportFigureAndClose(fig,outputPath);
    case 25
        renderCombinedRingSummary(S,outputPath);
    case 26
        renderPlacidoEllipseViews(S,outputPath,"single");
    case 27
        renderPlacidoEllipseViews(S,outputPath,"individual");
    case 28
        renderPlacidoEllipseViews(S,outputPath,"mean");
    otherwise
        error('Unsupported Placido-only step: %d', step);
end
end

function renderPlacidoEllipseViews(S,outputPath,mode)
metrics=S.shapeMetrics; colours=lines(max(1,numel(metrics)));
fig=figure('Visible','off','Color','w','Position',[50 50 1300 1000]);
ax=axes(fig); styleDescriptorAxes(ax); hold(ax,'on'); t=linspace(0,2*pi,720);
indices=1:numel(metrics);
if mode=="single", indices=1; end
maxLength=0;
for k=indices
    m=metrics(k); rows=S.analysisPoints.RingNumber==m.Ring;
    x=S.analysisPoints.R(rows).*cos(S.analysisPoints.T(rows));
    y=-S.analysisPoints.R(rows).*sin(S.analysisPoints.T(rows));
    scatter(ax,x,y,4,[.68 .68 .68],'filled','MarkerFaceAlpha',.22,'HandleVisibility','off');
    if any(~isfinite([m.MajorExtentPx m.MinorExtentPx])) || any(~isfinite(m.TrackingCentroid)), continue; end
    e=m.TrackingCentroid.'+m.Eigenvectors*[m.MajorExtentPx*cos(t);m.MinorExtentPx*sin(t)];
    plot(ax,e(1,:),e(2,:),'--','Color',colours(k,:),'LineWidth',2.8, ...
        'DisplayName',sprintf('Mire %d covariance ellipse',m.Ring));
    maxLength=max(maxLength,m.MajorExtentPx);
    if mode~="mean"
        drawPlacidoAxisPair(ax,m.TrackingCentroid,m.ImageAxisDeg,m.MajorExtentPx, ...
            colours(k,:),mode=="single");
    end
end
if mode=="mean"
    valid=[metrics.ImageAxisDeg].'; valid=valid(isfinite(valid));
    [meanFlat,~]=axialStatistics(valid); centres=vertcat(metrics.TrackingCentroid);
    meanCentre=mean(centres(all(isfinite(centres),2),:),1,'omitnan');
    drawPlacidoAxisPair(ax,meanCentre,meanFlat,maxLength,[.05 .35 .80],true);
    title(ax,sprintf('All fitted physical-mire ellipses; mean flat %.2f deg and steep %.2f deg', ...
        meanFlat,mod(meanFlat+90,180)));
elseif mode=="single"
    title(ax,sprintf('Representative physical mire %d: fitted ellipse with flat and steep axes',metrics(indices).Ring));
else
    title(ax,'All selected physical mires: covariance ellipses with individual flat and steep axes');
end
axis(ax,'equal'); grid(ax,'on');
xlabel(ax,'Tracking X (source-image pixels)');
ylabel(ax,'Tracking Y (source-image pixels)');
lgd=legend(ax,'Location','bestoutside');
set(lgd,'Color','w','TextColor','k','EdgeColor',[.35 .35 .35]);
exportFigureAndClose(fig,outputPath);
end

function drawPlacidoAxisPair(ax,centre,flatImageDeg,lengthPx,colour,showLegend)
flat=[cosd(flatImageDeg) sind(flatImageDeg)]; steep=[cosd(flatImageDeg+90) sind(flatImageDeg+90)];
flatName='Flat axis'; steepName='Steep axis';
if ~showLegend, flatName=''; steepName=''; end
h1=plot(ax,centre(1)+[-lengthPx lengthPx]*flat(1),centre(2)+[-lengthPx lengthPx]*flat(2), ...
    '--','Color',colour,'LineWidth',1.5,'DisplayName',flatName);
h2=plot(ax,centre(1)+[-lengthPx lengthPx]*steep(1),centre(2)+[-lengthPx lengthPx]*steep(2), ...
    ':','Color',[.18 .18 .18],'LineWidth',1.7,'DisplayName',steepName);
if ~showLegend, set([h1 h2],'HandleVisibility','off'); end
if showLegend
    flatValue=mod(flatImageDeg,180); steepValue=mod(flatValue+90,180);
    text(ax,centre(1)+.72*lengthPx*flat(1),centre(2)+.72*lengthPx*flat(2), ...
        sprintf(' Flat %.2f deg',flatValue),'Color',colour,'FontWeight','bold','BackgroundColor','w');
    text(ax,centre(1)+.72*lengthPx*steep(1),centre(2)+.72*lengthPx*steep(2), ...
        sprintf(' Steep %.2f deg',steepValue),'Color',[.12 .12 .12],'FontWeight','bold','BackgroundColor','w');
end
end

function renderCombinedRingSummary(S,outputPath)
% One publication-ready dashboard containing the per-mire descriptors and
% their selected-range summaries. Angles use axial (180-degree periodic)
% statistics rather than an invalid arithmetic average across 0/180.
metrics = S.shapeMetrics;
n = numel(metrics);
figHeight = max(900,min(1900,520+42*n));
fig = figure('Visible','off','Color','w', ...
    'Position',[40 40 1900 figHeight],'Name','Placido per-mire summary');
axPlot = axes(fig,'Position',[0.045 0.10 0.40 0.80]);
styleDescriptorAxes(axPlot);
colours = lines(max(1,n));
tPlot = linspace(0,2*pi,720).';
for k = 1:n
    m = metrics(k);
    if any(~isfinite(m.RawHarmonicCoefficients)), continue; end
    radialFit = [ones(size(tPlot)),cos(2*tPlot),sin(2*tPlot)] * ...
        m.RawHarmonicCoefficients;
    plot(axPlot,radialFit.*sin(tPlot),radialFit.*cos(tPlot),'-', ...
        'Color',colours(k,:),'LineWidth',1.35, ...
        'DisplayName',sprintf('Mire %d',m.Ring));
    majorDirection = [sind(m.FlatRawDeg),cosd(m.FlatRawDeg)];
    axisLength = m.HarmonicMajorRadiusPx;
    plot(axPlot,[-axisLength axisLength]*majorDirection(1), ...
        [-axisLength axisLength]*majorDirection(2),'--', ...
        'Color',colours(k,:),'LineWidth',0.85,'HandleVisibility','off');
end
axis(axPlot,'equal'); grid(axPlot,'on');
xlabel(axPlot,'Tracking X (pixels)'); ylabel(axPlot,'Tracking Y (pixels)');
title(axPlot,'Second-harmonic curves and principal axes');
addCompactLegend(axPlot,n);

axText = axes(fig,'Position',[0.47 0.07 0.51 0.84],'Color','w');
axis(axText,[0 1 0 1]); axis(axText,'off');
centres = vertcat(metrics.TrackingCentroid);
valid = all(isfinite(centres),2);
primary = [metrics.IsCompletePrimary].' & valid;
summaryRows = primary;
if ~any(summaryRows), summaryRows = valid; end
referenceCentre = mean(centres(summaryRows,:),1,'omitnan');
deviation = hypot(centres(:,1)-referenceCentre(1),centres(:,2)-referenceCentre(2));
spread = sqrt(std(centres(summaryRows,1),0,'omitnan')^2 + ...
    std(centres(summaryRows,2),0,'omitnan')^2);

header = sprintf('%-5s %7s %8s %8s %8s %9s %8s %8s', ...
    'Mire','ER','Ctr X','Ctr Y','dCtr','Irreg%','Axis','Orth');
linesText = strings(n+7,1);
    linesText(1) = "PER-PHYSICAL-MIRE QUANTITATIVE OUTPUT";
linesText(2) = header;
linesText(3) = repmat('-',1,strlength(header));
for k = 1:n
    m = metrics(k);
    linesText(k+3) = sprintf('%-5d %7.4f %8.2f %8.2f %8.2f %9.3f %8.2f %8.2f', ...
        m.Ring,m.EigenRatio,m.TrackingCentroid(1),m.TrackingCentroid(2), ...
        deviation(k),m.IrregularityPct,m.ImageAxisDeg,m.PerpendicularAxisDeg);
end
er = [metrics.EigenRatio].'; irr = [metrics.IrregularityPct].';
axisValues = [metrics.ImageAxisDeg].';
[axisMean,axisStd] = axialStatistics(axisValues(summaryRows));
linesText(n+4) = repmat('-',1,strlength(header));
linesText(n+5) = sprintf('MEAN  %7.4f %8.2f %8.2f %8.2f %9.3f %8.2f %8.2f', ...
    mean(er(summaryRows),'omitnan'),mean(centres(summaryRows,1),'omitnan'), ...
    mean(centres(summaryRows,2),'omitnan'),mean(deviation(summaryRows),'omitnan'), ...
    mean(irr(summaryRows),'omitnan'),axisMean,mod(axisMean+90,180));
linesText(n+6) = sprintf('SD    %7.4f %8.2f %8.2f %8.2f %9.3f %8.2f %8s', ...
    std(er(summaryRows),0,'omitnan'),std(centres(summaryRows,1),0,'omitnan'), ...
    std(centres(summaryRows,2),0,'omitnan'),std(deviation(summaryRows),0,'omitnan'), ...
    std(irr(summaryRows),0,'omitnan'),axisStd,'--');
linesText(n+7) = sprintf('Cross-mire centre instability = %.3f pixels',spread);
fontSize = max(6.5,min(10.5,12-0.18*n));
text(axText,0.025,0.97,strjoin(linesText,newline),'Color','k', ...
    'FontName','Consolas','FontSize',fontSize,'VerticalAlignment','top', ...
    'Interpreter','none');
title(axText,sprintf('Selected physical mires %d:%d | axial angle statistics', ...
    metrics(1).Ring,metrics(end).Ring),'Color','k','FontWeight','bold');
exportFigureAndClose(fig,outputPath);
end

function [meanAngle,standardDeviation] = axialStatistics(angles)
angles = angles(isfinite(angles));
if isempty(angles)
    meanAngle = NaN; standardDeviation = NaN; return;
end
c = mean(cosd(2*angles)); s = mean(sind(2*angles));
meanAngle = mod(0.5*atan2d(s,c),180);
resultant = max(eps,min(1,hypot(c,s)));
standardDeviation = 0.5*rad2deg(sqrt(max(0,-2*log(resultant))));
end

function renderPlacidoFullFrameStep(step,S,outputPath)
% Export the same native-coordinate overlay without the presentation crop.
switch step
    case 11
        [fig,ax]=imageAxes(S.gray); [hubY,hubX]=find(bwperim(S.hubCandidateMask,8));
        plot(ax,hubX,hubY,'.','Color',[1 .72 .08],'MarkerSize',5);
        t=linspace(0,2*pi,720);
        plot(ax,S.placidoCentre(1)+S.workingRadiusPx*cos(t), ...
            S.placidoCentre(2)+S.workingRadiusPx*sin(t),'--', ...
            'Color',[.1 .9 .9],'LineWidth',1.5);
        plot(ax,S.placidoCentre(1),S.placidoCentre(2),'r+', ...
            'MarkerSize',18,'LineWidth',2.2); exportAndClose(fig,ax,outputPath);
    case 12
        image=blendMasks(greyToRgb(S.gray), ...
            {S.innerDirectional,S.outerDirectional}, ...
            {[1 .12 .12],[.1 .9 .35]},[.92 .92]); writeBoundedImage(image,outputPath);
    case 13
        image=blendMasks(greyToRgb(S.gray), ...
            {S.removedBranches,S.innerPruned,S.outerPruned}, ...
            {[.95 .1 .85],[1 .12 .12],[.1 .9 .35]},[.82 .95 .95]);
        writeBoundedImage(image,outputPath);
    case 14
        writeBoundedImage(colourLabels(S.combinedLabels),outputPath);
    case 15
        acceptedLabels=S.componentSummary.Label(S.componentSummary.Accepted);
        accepted=ismember(S.allPoints.Label,acceptedLabels); [fig,ax]=imageAxes(S.gray);
        scatter(ax,S.allPoints.X(~accepted),S.allPoints.Y(~accepted),3,[.1 .42 1],'filled');
        scatter(ax,S.allPoints.X(accepted),S.allPoints.Y(accepted),3,[1 .18 .12],'filled');
        exportAndClose(fig,ax,outputPath);
    case 16
        [fig,ax]=imageAxes(S.gray); plotRingPointSets(ax,S.selectedPoints,S.requestedRings,true);
        exportAndClose(fig,ax,outputPath);
    case 19
        [fig,ax]=imageAxes(S.gray); colours=lines(max(1,numel(S.fitRingIds)));
        for k=1:numel(S.fitRingIds)
            rows=S.fittedTable.RingNumber==S.fitRingIds(k);
            theta=S.fittedTable.Theta(rows); radius=S.fittedTable.R_fit(rows); style='-';
            if strcmpi(S.fitInfo{k}.spline_type,'arc'), style='--'; end
            thetaPlot=theta; radiusPlot=radius;
            if strcmpi(S.fitInfo{k}.spline_type,'periodic') && ~isempty(theta)
                thetaPlot=[theta;theta(1)+2*pi]; radiusPlot=[radius;radius(1)];
            end
            plot(ax,S.placidoCentre(1)+radiusPlot.*cos(thetaPlot), ...
                S.placidoCentre(2)+radiusPlot.*sin(thetaPlot),style, ...
                'Color',colours(k,:),'LineWidth',1.5);
        end
        exportAndClose(fig,ax,outputPath);
    otherwise
        error('No Placido full-frame renderer for Step %d.',step);
end
end

function [fig, ax] = imageAxes(image)
fig = figure('Visible','off','Color','w','Position',[100 100 1000 850]);
ax = axes(fig,'Position',[0 0 1 1]);
imshow(image,[],'Parent',ax);
axis(ax,'image'); axis(ax,'off'); hold(ax,'on');
end

function fig = descriptorFigure(name)
fig = figure('Visible','off','Color','w','Name',name, ...
    'Position',[100 100 1400 720]);
end

function styleDescriptorAxes(ax)
set(ax,'Color','w', ...
    'XColor','k','YColor','k', ...
    'GridColor',[0.72 0.72 0.72],'GridAlpha',0.45, ...
    'MinorGridAlpha',0.20,'FontSize',10,'LineWidth',0.8);
hold(ax,'on'); box(ax,'on');
ax.Title.Color = [0 0 0];
ax.XLabel.Color = [0 0 0];
ax.YLabel.Color = [0 0 0];
end

function plotDescriptorMetric(ax,metrics,fieldName,yLabelText,yLimits)
rings = [metrics.Ring].';
values = arrayfun(@(metric) metric.(fieldName),metrics);
values = values(:);
primary = [metrics.IsCompletePrimary].' & isfinite(values);
diagnostic = ~[metrics.IsCompletePrimary].' & isfinite(values);
if any(primary)
    plot(ax,rings(primary),values(primary),'o-','Color',[0.18 0.78 0.46], ...
        'MarkerFaceColor',[0.18 0.78 0.46],'LineWidth',1.7, ...
        'DisplayName','Complete-primary');
    primaryMean = mean(values(primary),'omitnan');
    yline(ax,primaryMean,'--','Color',[0.82 0.84 0.88], ...
        'LineWidth',1.1,'Label',sprintf('primary mean %.3g',primaryMean), ...
        'LabelHorizontalAlignment','left','HandleVisibility','off');
end
if any(diagnostic)
    plot(ax,rings(diagnostic),values(diagnostic),'x:','Color',[1.00 0.62 0.16], ...
        'MarkerSize',8,'LineWidth',1.3,'DisplayName','Incomplete diagnostic');
end
xticks(ax,rings); grid(ax,'on'); xlabel(ax,'Physical mire index');
ylabel(ax,yLabelText);
if ~isempty(yLimits), ylim(ax,yLimits); end
if any(primary) || any(diagnostic)
    legend(ax,'Location','best','Color','w','TextColor','k');
end
end

function markDiagnosticRings(ax,metrics,values)
rings = [metrics.Ring].';
diagnostic = ~[metrics.IsCompletePrimary].' & isfinite(values);
if any(diagnostic)
    plot(ax,rings(diagnostic),values(diagnostic),'x','Color',[1.00 0.62 0.16], ...
        'MarkerSize',9,'LineWidth',1.5,'DisplayName','Incomplete diagnostic');
    legend(ax,'Location','best','Color','w','TextColor','k');
end
end

function [fig, ax] = plotAxes()
dark = [0.055 0.060 0.070];
fig = figure('Visible','off','Color',dark,'Position',[100 100 1050 720]);
ax = axes(fig,'Position',[0.10 0.11 0.84 0.82]);
set(ax,'Color',dark,'XColor',[0.94 0.94 0.94], ...
    'YColor',[0.94 0.94 0.94],'GridColor',[0.55 0.58 0.62], ...
    'GridAlpha',0.35,'FontSize',10,'LineWidth',0.8);
hold(ax,'on'); box(ax,'on');
end

function exportAndClose(fig, ax, path)
exportgraphics(ax, path, 'Resolution', 220, 'BackgroundColor', fig.Color);
close(fig);
end

function exportFigureAndClose(fig,path)
exportgraphics(fig,path,'Resolution',220,'BackgroundColor',fig.Color);
close(fig);
end

function plotRingPointSets(ax, points, ringIds, writeLabels)
colours = lines(max(1,numel(ringIds)));
for k = 1:numel(ringIds)
    rows = points.RingNumber == ringIds(k);
    plot(ax,points.X(rows),points.Y(rows),'.','Color',colours(k,:), ...
        'MarkerSize',5,'DisplayName',sprintf('Mire %d',ringIds(k)));
    if writeLabels && any(rows)
        candidateIndices = find(rows);
        targetAngle = mod(2*pi*(k-1)/max(1,numel(ringIds)) + pi/12,2*pi);
        angularDistance = abs(angle(exp(1i*(points.T(rows)-targetAngle))));
        [~,localIndex] = min(angularDistance);
        idx = candidateIndices(localIndex);
        text(ax,points.X(idx),points.Y(idx),sprintf(' %d',ringIds(k)), ...
            'Color',colours(k,:),'FontSize',8,'FontWeight','bold', ...
            'BackgroundColor','w','Margin',1);
    end
end
end

function cropped = cropAroundCentre(image, centre, halfSize)
height = size(image,1);
width = size(image,2);
x1 = max(1,floor(centre(1)-halfSize));
x2 = min(width,ceil(centre(1)+halfSize));
y1 = max(1,floor(centre(2)-halfSize));
y2 = min(height,ceil(centre(2)+halfSize));
cropped = image(y1:y2,x1:x2,:);
end

function zoomImageAxes(ax, imageSize, centre, halfSize)
height = imageSize(1);
width = imageSize(2);
xlim(ax,[max(0.5,centre(1)-halfSize), ...
    min(width+0.5,centre(1)+halfSize)]);
ylim(ax,[max(0.5,centre(2)-halfSize), ...
    min(height+0.5,centre(2)+halfSize)]);
end

function addCompactLegend(ax, count)
if count <= 18
    item = legend(ax,'Location','eastoutside');
    item.Color = 'white';
    item.TextColor = 'black';
    if count > 10
        item.NumColumns = 2;
    end
end
end

function image = colourLabels(labels)
n = max(labels(:));
if n < 1
    image = zeros([size(labels),3],'uint8');
    return;
end
image = label2rgb(labels, lines(n), [0 0 0], 'noshuffle');
end

function image = masksOnBlack(imageSize, masks, colours)
image = zeros([imageSize,3]);
for k = 1:numel(masks)
    for channel = 1:3
        layer = image(:,:,channel);
        layer(masks{k}) = colours{k}(channel);
        image(:,:,channel) = layer;
    end
end
end

function image = blendMasks(image, masks, colours, alpha)
image = im2double(image);
for k = 1:numel(masks)
    mask = logical(masks{k});
    for channel = 1:3
        layer = image(:,:,channel);
        layer(mask) = (1-alpha(k))*layer(mask) + alpha(k)*colours{k}(channel);
        image(:,:,channel) = layer;
    end
end
end

function rgb = greyToRgb(gray)
gray = im2double(gray);
rgb = repmat(gray,1,1,3);
end

function writeBoundedImage(image, path)
if islogical(image)
    image = uint8(image)*255;
elseif isa(image,'double') || isa(image,'single')
    image = im2uint8(mat2gray(image));
end
maximumDimension = 1800;
scale = min(1, maximumDimension/max(size(image,1),size(image,2)));
if scale < 1
    image = imresize(image, scale, 'bilinear');
end
imwrite(image, path);
end
