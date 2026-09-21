function sweep = evaluateSevereConeInnerRadiusSweep(cfg, scales, outputCsv)
%EVALUATESEVERECONEINNERRADIUSSWEEP Test central exclusion vs mire identity.
%   Quadratic peak refinement is held fixed. This diagnostic changes only
%   the factor applied to the detected central dark-circle radius.

arguments
    cfg struct
    scales (1,:) double {mustBeFinite, mustBePositive}
    outputCsv (1,1) string = ""
end
if numel(unique(scales)) ~= numel(scales)
    error('SmartKC:ConeIdentity:DuplicateScale', ...
        'Central exclusion scales must be unique.');
end
manifest = readtable(fullfile(cfg.paths.Synthetic, 'manifest.csv'), ...
    'TextType', 'string');
fixture = manifest(manifest.ScenarioName == "keratoconus_severe", :);
if height(fixture) ~= 1
    error('SmartKC:ConeIdentity:FixtureUnavailable', ...
        'Expected exactly one keratoconus_severe fixture.');
end
imagePath = fullfile(cfg.paths.Synthetic, fixture.ImageFile);
loaded = load(fullfile(cfg.paths.Synthetic, fixture.GroundTruthFile), 'truth');
[matchedCfg, matched] = configureSyntheticMasterRun(char(imagePath), cfg);
if ~matched
    error('SmartKC:ConeIdentity:FixtureNotMatched', ...
        'Could not activate matched synthetic settings.');
end

rowCount = numel(scales);
CentralExclusionScale = scales(:);
SelectedCentralRadiusPx = nan(rowCount, 1);
EffectiveInnerRadiusPx = nan(rowCount, 1);
TruthFirstMireMedianRadiusPx = nan(rowCount, 1);
TruthFirstMireMinimumRadiusPx = nan(rowCount, 1);
TruthFirstMireMaximumRadiusPx = nan(rowCount, 1);
FirstAssignedMireMedianRadiusPx = nan(rowCount, 1);
MedianMiresPerAngle = nan(rowCount, 1);
DominantMireIndexOffset = nan(rowCount, 1);
OffsetAlignedMireIndexAccuracy = nan(rowCount, 1);
PhysicalMireIndexAccuracy = nan(rowCount, 1);
NearestTruthMedianRadialErrorPx = nan(rowCount, 1);
AssignedSameMireMedianErrorPx = nan(rowCount, 1);
Status = strings(rowCount, 1);
ErrorMessage = strings(rowCount, 1);

truthFirst = loaded.truth.radiiPixels(1, ...
    loaded.truth.visibleMask(1, :) & ...
    isfinite(loaded.truth.radiiPixels(1, :)));
for row = 1:rowCount
    runCfg = matchedCfg;
    runCfg.localization.SubpixelMethod = "quadratic";
    runCfg.localization.CentralExclusionScale = scales(row);
    try
        result = runSmartKCPipeline(char(imagePath), runCfg, '');
        if result.SmartKCPP.Status ~= "COMPLETED"
            error('SmartKC:ConeIdentity:PipelineFailed', '%s', ...
                result.SmartKCPP.ErrorMessage);
        end
        selectedRadius = ...
            result.Preprocessing.CenterDiagnostics.SelectedRadiusPx;
        SelectedCentralRadiusPx(row) = selectedRadius;
        EffectiveInnerRadiusPx(row) = max(runCfg.localization.InnerRadiusPx, ...
            scales(row) * selectedRadius);
        TruthFirstMireMedianRadiusPx(row) = median(truthFirst);
        TruthFirstMireMinimumRadiusPx(row) = min(truthFirst);
        TruthFirstMireMaximumRadiusPx(row) = max(truthFirst);
        active = result.SmartKCPP.Candidates( ...
            result.SmartKCPP.Candidates.IsValid, :);
        first = active.RadiusPx(active.MireIndex == 1);
        FirstAssignedMireMedianRadiusPx(row) = median(first, 'omitnan');
        MedianMiresPerAngle(row) = ...
            result.SmartKCPP.Quality.MedianMiresPerAngle;
        [metrics, ~] = evaluateMireLocalizationAgainstTruth( ...
            result.SmartKCPP.Candidates, loaded.truth, ...
            runCfg.placido.MaximumMires, ...
            runCfg.localization.GraphRadialTolerancePx);
        DominantMireIndexOffset(row) = metrics.DominantMireIndexOffset;
        OffsetAlignedMireIndexAccuracy(row) = ...
            metrics.OffsetAlignedMireIndexAccuracy;
        PhysicalMireIndexAccuracy(row) = metrics.PhysicalMireIndexAccuracy;
        NearestTruthMedianRadialErrorPx(row) = metrics.MedianRadialErrorPx;
        assigned = compareMireCandidatesToTruth( ...
            result.SmartKCPP.Candidates, loaded.truth, ...
            result.Preprocessing, runCfg, 43, fixture.ScenarioName);
        AssignedSameMireMedianErrorPx(row) = median( ...
            assigned.CenterCompensatedAbsoluteErrorPx( ...
            assigned.TruthAvailable), 'omitnan');
        Status(row) = "COMPLETED";
    catch exception
        Status(row) = "FAILED";
        ErrorMessage(row) = string(exception.message);
    end
    fprintf('[Cone inner-radius sweep] %.3f | %s | offset %.0f\n', ...
        scales(row), Status(row), DominantMireIndexOffset(row));
end

sweep = table(CentralExclusionScale, SelectedCentralRadiusPx, ...
    EffectiveInnerRadiusPx, TruthFirstMireMedianRadiusPx, ...
    TruthFirstMireMinimumRadiusPx, TruthFirstMireMaximumRadiusPx, ...
    FirstAssignedMireMedianRadiusPx, MedianMiresPerAngle, ...
    DominantMireIndexOffset, OffsetAlignedMireIndexAccuracy, ...
    PhysicalMireIndexAccuracy, NearestTruthMedianRadialErrorPx, ...
    AssignedSameMireMedianErrorPx, Status, ErrorMessage);
if strlength(outputCsv) > 0
    ensureFolder(fileparts(char(outputCsv)));
    writetable(sweep, char(outputCsv));
end
end
