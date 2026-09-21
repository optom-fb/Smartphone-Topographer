function [caseSummary, mireSummary, pointDetails, relationship] = ...
        evaluateSphereLocalizationBaseline(powersD, cfg, outputRoot)
%EVALUATESPHERELOCALIZATIONBASELINE Measure current mire error against truth.
%   Uses the tracked standard-resolution SphereSeries fixtures and the
%   unchanged matched SmartKC++ pipeline. No localization parameter or
%   reconstruction calculation is modified by this evaluator.

arguments
    powersD (1,:) double {mustBeFinite, mustBePositive}
    cfg struct
    outputRoot (1,1) string
end
if numel(unique(powersD)) ~= numel(powersD)
    error('SmartKC:LocalizationBaseline:DuplicatePower', ...
        'Sphere powers must be unique.');
end

sphereRoot = fullfile(cfg.paths.Synthetic, 'SphereSeries');
manifestPath = fullfile(sphereRoot, 'manifest.csv');
if ~isfile(manifestPath)
    error('SmartKC:LocalizationBaseline:MissingSphereSeries', ...
        'Generate the tracked sphere series first: %s.', manifestPath);
end
manifest = readtable(manifestPath, 'TextType', 'string');
manifestK = 337.5 ./ manifest.RflatMm;
ensureFolder(char(outputRoot));

pointTables = cell(numel(powersD), 1);
summaryRows = cell(numel(powersD), 1);
for index = 1:numel(powersD)
    powerD = powersD(index);
    match = find(abs(manifestK - powerD) <= 1e-10, 1);
    if isempty(match)
        error('SmartKC:LocalizationBaseline:PowerNotFound', ...
            'No tracked sphere fixture matches %.6g D.', powerD);
    end
    imagePath = fullfile(sphereRoot, manifest.ImageFile(match));
    truthPath = fullfile(sphereRoot, manifest.GroundTruthFile(match));
    loaded = load(truthPath, 'truth');
    [caseCfg, isSynthetic] = configureSyntheticMasterRun(char(imagePath), cfg);
    if ~isSynthetic
        error('SmartKC:LocalizationBaseline:FixtureNotMatched', ...
            'Could not activate matched synthetic settings for %s.', imagePath);
    end
    result = runSmartKCPipeline(char(imagePath), caseCfg, '');
    if result.SmartKCPP.Status ~= "COMPLETED"
        error('SmartKC:LocalizationBaseline:PipelineFailed', '%s', ...
            result.SmartKCPP.ErrorMessage);
    end
    details = compareMireCandidatesToTruth( ...
        result.SmartKCPP.Candidates, loaded.truth, result.Preprocessing, ...
        caseCfg, powerD, manifest.ScenarioName(match));
    pointTables{index} = details;
    centerOffsetPx = result.Preprocessing.CenterFullPx - ...
        loaded.truth.centerPixels;
    summaryRows{index} = summarizeCase(details, result.SmartKCPP, powerD, ...
        centerOffsetPx);
    fprintf('[Localization baseline] %.2f D | %d truth comparisons\n', ...
        powerD, nnz(details.TruthAvailable));
end

pointDetails = vertcat(pointTables{:});
caseSummary = vertcat(summaryRows{:});
mireSummary = summarizeMires(pointDetails);
relationship = summarizeRelationship(caseSummary);
writetable(pointDetails, fullfile(char(outputRoot), ...
    'sphere_localization_points.csv'));
writetable(caseSummary, fullfile(char(outputRoot), ...
    'sphere_localization_case_summary.csv'));
writetable(mireSummary, fullfile(char(outputRoot), ...
    'sphere_localization_mire_summary.csv'));
writetable(relationship, fullfile(char(outputRoot), ...
    'sphere_localization_k_relationship.csv'));
end

function summary = summarizeCase(details, variant, powerD, centerOffsetPx)
valid = details.TruthAvailable & ...
    isfinite(details.EndToEndSignedErrorPx) & ...
    isfinite(details.CenterCompensatedSignedErrorPx);
endSignedPx = details.EndToEndSignedErrorPx(valid);
endAbsolutePx = details.EndToEndAbsoluteErrorPx(valid);
endSignedMm = details.EndToEndSignedErrorSensorMm(valid);
endAbsoluteMm = details.EndToEndAbsoluteErrorSensorMm(valid);
compensatedSignedPx = details.CenterCompensatedSignedErrorPx(valid);
compensatedAbsolutePx = details.CenterCompensatedAbsoluteErrorPx(valid);
compensatedSignedMm = details.CenterCompensatedSignedErrorSensorMm(valid);
compensatedAbsoluteMm = ...
    details.CenterCompensatedAbsoluteErrorSensorMm(valid);
RecoveredSteepD = variant.Metrics.SimKSteepD;
RecoveredFlatD = variant.Metrics.SimKFlatD;
SteepErrorD = RecoveredSteepD - powerD;
FlatErrorD = RecoveredFlatD - powerD;
MeanKErrorD = mean([SteepErrorD, FlatErrorD]);
MaximumAbsoluteKErrorD = max(abs([SteepErrorD, FlatErrorD]));
SphereK_D = powerD;
ComparedPointCount = nnz(valid);
MedianMiresPerAngle = variant.Quality.MedianMiresPerAngle;
CenterOffsetXpx = centerOffsetPx(1);
CenterOffsetYpx = centerOffsetPx(2);
CenterOffsetMagnitudePx = norm(centerOffsetPx);
MeanEndToEndSignedErrorPx = mean(endSignedPx, 'omitnan');
MedianEndToEndAbsoluteErrorPx = median(endAbsolutePx, 'omitnan');
P95EndToEndAbsoluteErrorPx = prctile(endAbsolutePx, 95);
MaximumEndToEndAbsoluteErrorPx = max(endAbsolutePx, [], 'omitnan');
MeanEndToEndSignedErrorSensorMm = mean(endSignedMm, 'omitnan');
MedianEndToEndAbsoluteErrorSensorMm = median(endAbsoluteMm, 'omitnan');
P95EndToEndAbsoluteErrorSensorMm = prctile(endAbsoluteMm, 95);
MeanCenterCompensatedSignedErrorPx = ...
    mean(compensatedSignedPx, 'omitnan');
MedianCenterCompensatedAbsoluteErrorPx = ...
    median(compensatedAbsolutePx, 'omitnan');
P95CenterCompensatedAbsoluteErrorPx = ...
    prctile(compensatedAbsolutePx, 95);
MaximumCenterCompensatedAbsoluteErrorPx = ...
    max(compensatedAbsolutePx, [], 'omitnan');
MeanCenterCompensatedSignedErrorSensorMm = ...
    mean(compensatedSignedMm, 'omitnan');
MedianCenterCompensatedAbsoluteErrorSensorMm = ...
    median(compensatedAbsoluteMm, 'omitnan');
P95CenterCompensatedAbsoluteErrorSensorMm = ...
    prctile(compensatedAbsoluteMm, 95);
ResidualCylinderD = variant.Metrics.CylinderD;
summary = table(SphereK_D, ComparedPointCount, MedianMiresPerAngle, ...
    CenterOffsetXpx, CenterOffsetYpx, CenterOffsetMagnitudePx, ...
    MeanEndToEndSignedErrorPx, MedianEndToEndAbsoluteErrorPx, ...
    P95EndToEndAbsoluteErrorPx, MaximumEndToEndAbsoluteErrorPx, ...
    MeanEndToEndSignedErrorSensorMm, ...
    MedianEndToEndAbsoluteErrorSensorMm, ...
    P95EndToEndAbsoluteErrorSensorMm, ...
    MeanCenterCompensatedSignedErrorPx, ...
    MedianCenterCompensatedAbsoluteErrorPx, ...
    P95CenterCompensatedAbsoluteErrorPx, ...
    MaximumCenterCompensatedAbsoluteErrorPx, ...
    MeanCenterCompensatedSignedErrorSensorMm, ...
    MedianCenterCompensatedAbsoluteErrorSensorMm, ...
    P95CenterCompensatedAbsoluteErrorSensorMm, ...
    RecoveredSteepD, RecoveredFlatD, SteepErrorD, FlatErrorD, ...
    MeanKErrorD, MaximumAbsoluteKErrorD, ResidualCylinderD);
end

function summary = summarizeMires(points)
mires = unique(points.MireIndex(points.TruthAvailable));
rowCount = numel(mires);
MireIndex = mires;
ComparedPointCount = zeros(rowCount, 1);
MeanCenterCompensatedSignedErrorPx = nan(rowCount, 1);
MedianEndToEndAbsoluteErrorPx = nan(rowCount, 1);
P95EndToEndAbsoluteErrorPx = nan(rowCount, 1);
MedianCenterCompensatedAbsoluteErrorPx = nan(rowCount, 1);
P95CenterCompensatedAbsoluteErrorPx = nan(rowCount, 1);
for row = 1:rowCount
    selected = points.TruthAvailable & points.MireIndex == mires(row);
    signedError = points.CenterCompensatedSignedErrorPx(selected);
    endAbsoluteError = points.EndToEndAbsoluteErrorPx(selected);
    compensatedAbsoluteError = ...
        points.CenterCompensatedAbsoluteErrorPx(selected);
    ComparedPointCount(row) = nnz(selected);
    MeanCenterCompensatedSignedErrorPx(row) = ...
        mean(signedError, 'omitnan');
    MedianEndToEndAbsoluteErrorPx(row) = ...
        median(endAbsoluteError, 'omitnan');
    P95EndToEndAbsoluteErrorPx(row) = prctile(endAbsoluteError, 95);
    MedianCenterCompensatedAbsoluteErrorPx(row) = ...
        median(compensatedAbsoluteError, 'omitnan');
    P95CenterCompensatedAbsoluteErrorPx(row) = ...
        prctile(compensatedAbsoluteError, 95);
end
summary = table(MireIndex, ComparedPointCount, ...
    MeanCenterCompensatedSignedErrorPx, ...
    MedianEndToEndAbsoluteErrorPx, P95EndToEndAbsoluteErrorPx, ...
    MedianCenterCompensatedAbsoluteErrorPx, ...
    P95CenterCompensatedAbsoluteErrorPx);
end

function relationship = summarizeRelationship(caseSummary)
Predictor = ["MeanEndToEndSignedErrorPx"; ...
    "MeanCenterCompensatedSignedErrorPx"; "CenterOffsetMagnitudePx"];
values = {caseSummary.MeanEndToEndSignedErrorPx; ...
    caseSummary.MeanCenterCompensatedSignedErrorPx; ...
    caseSummary.CenterOffsetMagnitudePx};
ComparedSphereCount = zeros(3, 1);
PearsonCorrelation = nan(3, 1);
SlopeDPerUnit = nan(3, 1);
InterceptD = nan(3, 1);
for row = 1:3
    predictor = values{row};
    valid = isfinite(predictor) & isfinite(caseSummary.MeanKErrorD);
    ComparedSphereCount(row) = nnz(valid);
    if nnz(valid) < 3
        continue
    end
    PearsonCorrelation(row) = corr(predictor(valid), ...
        caseSummary.MeanKErrorD(valid));
    coefficients = polyfit(predictor(valid), ...
        caseSummary.MeanKErrorD(valid), 1);
    SlopeDPerUnit(row) = coefficients(1);
    InterceptD(row) = coefficients(2);
end
relationship = table(Predictor, ComparedSphereCount, ...
    PearsonCorrelation, SlopeDPerUnit, InterceptD);
end
