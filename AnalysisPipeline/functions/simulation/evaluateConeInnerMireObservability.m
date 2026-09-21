function observability = evaluateConeInnerMireObservability(cfg, outputCsv)
%EVALUATECONEINNERMIREOBSERVABILITY Audit truth response for inner mires.
%   Runs the three cone stress fixtures with quadratic peaks and measures
%   response/mask support at exact truth points for physical mires 1--3.

arguments
    cfg struct
    outputCsv (1,1) string = ""
end
manifest = readtable(fullfile(cfg.paths.Synthetic, 'manifest.csv'), ...
    'TextType', 'string');
fixtures = manifest(manifest.SurfaceClass == "keratoconus-like", :);
rows = cell(0, 1);
for fixtureIndex = 1:height(fixtures)
    fixture = fixtures(fixtureIndex, :);
    imagePath = fullfile(cfg.paths.Synthetic, fixture.ImageFile);
    loaded = load(fullfile(cfg.paths.Synthetic, ...
        fixture.GroundTruthFile), 'truth');
    [runCfg, matched] = configureSyntheticMasterRun(char(imagePath), cfg);
    if ~matched
        error('SmartKC:ConeObservability:FixtureNotMatched', ...
            'Could not match %s.', fixture.ScenarioName);
    end
    runCfg.localization.SubpixelMethod = "quadratic";
    result = runSmartKCPipeline(char(imagePath), runCfg, '');
    if result.SmartKCPP.Status ~= "COMPLETED"
        error('SmartKC:ConeObservability:PipelineFailed', '%s', ...
            result.SmartKCPP.ErrorMessage);
    end
    [~, identity] = evaluateMireLocalizationAgainstTruth( ...
        result.SmartKCPP.Candidates, loaded.truth, ...
        runCfg.placido.MaximumMires, ...
        runCfg.localization.GraphRadialTolerancePx);
    rows{end+1, 1} = innerMireRows(fixture.ScenarioName, ...
        loaded.truth, result, identity, runCfg); %#ok<AGROW>
end
observability = vertcat(rows{:});
if strlength(outputCsv) > 0
    ensureFolder(fileparts(char(outputCsv)));
    writetable(observability, char(outputCsv));
end
end

function rows = innerMireRows(scenarioName, truth, result, identity, cfg)
mireIndices = (1:3)';
rowCount = numel(mireIndices);
ScenarioName = repmat(scenarioName, rowCount, 1);
PhysicalMireIndex = mireIndices;
TruthMedianRadiusPx = nan(rowCount, 1);
TruthMinimumRadiusPx = nan(rowCount, 1);
TruthMaximumRadiusPx = nan(rowCount, 1);
FractionTruthBeyondInnerRadius = nan(rowCount, 1);
MedianSegmentationResponse = nan(rowCount, 1);
P10SegmentationResponse = nan(rowCount, 1);
TruthPointMaskHitFraction = nan(rowCount, 1);
CandidateAngleCoverageFraction = nan(rowCount, 1);
MedianNearestCandidateErrorPx = nan(rowCount, 1);

cropOrigin = double(result.Preprocessing.CropRectangleFullPx(1:2));
center = double(result.Preprocessing.CenterPx);
selectedRadius = ...
    result.Preprocessing.CenterDiagnostics.SelectedRadiusPx;
effectiveInnerRadius = max(cfg.localization.InnerRadiusPx, ...
    cfg.localization.CentralExclusionScale * selectedRadius);
response = result.SmartKCPP.Segmentation.Response;
mask = result.SmartKCPP.Segmentation.Mask;
for row = 1:rowCount
    mire = mireIndices(row);
    xFull = reshape(truth.pointsPixels(mire, :, 1), [], 1);
    yFull = reshape(truth.pointsPixels(mire, :, 2), [], 1);
    visible = reshape(truth.visibleMask(mire, :), [], 1);
    truthRadiusAll = reshape(truth.radiiPixels(mire, :), [], 1);
    if numel(xFull) ~= numel(visible) || numel(xFull) ~= numel(truthRadiusAll)
        error('SmartKC:ConeObservability:TruthSizeMismatch', ...
            'Truth point, visibility, and radius arrays must have equal length.');
    end
    xCrop = xFull - cropOrigin(1) + 1;
    yCrop = yFull - cropOrigin(2) + 1;
    valid = visible & isfinite(xCrop) & isfinite(yCrop) & ...
        xCrop >= 1 & xCrop <= size(response, 2) & ...
        yCrop >= 1 & yCrop <= size(response, 1);
    radial = hypot(xCrop-center(1), yCrop-center(2));
    truthRadius = truthRadiusAll(valid);
    TruthMedianRadiusPx(row) = median(truthRadius);
    TruthMinimumRadiusPx(row) = min(truthRadius);
    TruthMaximumRadiusPx(row) = max(truthRadius);
    FractionTruthBeyondInnerRadius(row) = ...
        mean(radial(valid) >= effectiveInnerRadius);
    responseAtTruth = interp2(response, xCrop(valid), yCrop(valid), ...
        'linear', 0);
    maskAtTruth = interp2(single(mask), xCrop(valid), yCrop(valid), ...
        'nearest', 0);
    MedianSegmentationResponse(row) = median(responseAtTruth);
    P10SegmentationResponse(row) = prctile(responseAtTruth, 10);
    TruthPointMaskHitFraction(row) = mean(maskAtTruth > 0.5);
    matched = identity.IsMatched & identity.TrueMireIndex == mire;
    CandidateAngleCoverageFraction(row) = ...
        nnz(matched) / numel(result.SmartKCPP.Polar.AnglesDeg);
    MedianNearestCandidateErrorPx(row) = median( ...
        identity.NearestTruthRadialErrorPx(matched), 'omitnan');
end
rows = table(ScenarioName, PhysicalMireIndex, TruthMedianRadiusPx, ...
    TruthMinimumRadiusPx, TruthMaximumRadiusPx, ...
    FractionTruthBeyondInnerRadius, MedianSegmentationResponse, ...
    P10SegmentationResponse, TruthPointMaskHitFraction, ...
    CandidateAngleCoverageFraction, MedianNearestCandidateErrorPx);
end
