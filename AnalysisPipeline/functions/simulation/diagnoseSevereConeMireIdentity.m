function [summary, offsets, components, points] = ...
        diagnoseSevereConeMireIdentity(cfg, outputRoot)
%DIAGNOSESEVERECONEMIREIDENTITY Audit raw and graph mire labels vs truth.
%   This diagnostic does not alter graph labels or reconstruction. It runs
%   integer and quadratic peak locations, then separates nearest-ring radial
%   accuracy from assigned same-mire identity accuracy.

arguments
    cfg struct
    outputRoot (1,1) string
end
manifest = readtable(fullfile(cfg.paths.Synthetic, 'manifest.csv'), ...
    'TextType', 'string');
fixture = manifest(manifest.ScenarioName == "keratoconus_severe", :);
if height(fixture) ~= 1
    error('SmartKC:ConeIdentity:FixtureUnavailable', ...
        'Expected exactly one keratoconus_severe fixture.');
end
imagePath = fullfile(cfg.paths.Synthetic, fixture.ImageFile);
truthPath = fullfile(cfg.paths.Synthetic, fixture.GroundTruthFile);
loaded = load(truthPath, 'truth');
[matchedCfg, matched] = configureSyntheticMasterRun(char(imagePath), cfg);
if ~matched
    error('SmartKC:ConeIdentity:FixtureNotMatched', ...
        'Could not activate matched synthetic settings.');
end

modes = ["none", "quadratic"];
summaryRows = cell(0, 1);
pointRows = cell(0, 1);
componentRows = cell(0, 1);
for mode = modes
    modeCfg = matchedCfg;
    modeCfg.localization.SubpixelMethod = mode;
    result = runSmartKCPipeline(char(imagePath), modeCfg, '');
    if result.SmartKCPP.Status ~= "COMPLETED"
        error('SmartKC:ConeIdentity:PipelineFailed', '%s', ...
            result.SmartKCPP.ErrorMessage);
    end
    candidatesByStage = {result.SmartKCPP.RawCandidates, ...
        result.SmartKCPP.Candidates};
    stageNames = ["raw-radial-order", "graph-corrected"];
    for stageIndex = 1:2
        candidates = candidatesByStage{stageIndex};
        [metrics, identity] = evaluateMireLocalizationAgainstTruth( ...
            candidates, loaded.truth, modeCfg.placido.MaximumMires, ...
            modeCfg.localization.GraphRadialTolerancePx);
        assigned = compareMireCandidatesToTruth(candidates, loaded.truth, ...
            result.Preprocessing, modeCfg, 43, fixture.ScenarioName);
        assignedMedian = median( ...
            assigned.CenterCompensatedAbsoluteErrorPx( ...
            assigned.TruthAvailable), 'omitnan');
        identity.LocalizationMethod = repmat(mode, height(identity), 1);
        identity.LabelStage = repmat(stageNames(stageIndex), ...
            height(identity), 1);
        pointRows{end+1, 1} = identity; %#ok<AGROW>
        summaryRows{end+1, 1} = summaryRow(mode, ...
            stageNames(stageIndex), metrics, assignedMedian); %#ok<AGROW>
        if stageIndex == 2
            componentRows{end+1, 1} = componentSummary( ...
                mode, identity); %#ok<AGROW>
        end
    end
end

summary = vertcat(summaryRows{:});
points = vertcat(pointRows{:});
components = vertcat(componentRows{:});
offsets = offsetSummary(points);
ensureFolder(char(outputRoot));
writetable(summary, fullfile(char(outputRoot), ...
    'severe_cone_identity_summary.csv'));
writetable(offsets, fullfile(char(outputRoot), ...
    'severe_cone_label_offsets.csv'));
writetable(components, fullfile(char(outputRoot), ...
    'severe_cone_component_identity.csv'));
writetable(points, fullfile(char(outputRoot), ...
    'severe_cone_identity_points.csv'));
end

function row = summaryRow(mode, stage, metrics, assignedMedian)
LocalizationMethod = mode;
LabelStage = stage;
CandidateCount = metrics.CandidateCount;
MatchedCandidateFraction = metrics.MatchedCandidateFraction;
PhysicalMireIndexAccuracy = metrics.PhysicalMireIndexAccuracy;
DominantMireIndexOffset = metrics.DominantMireIndexOffset;
OffsetAlignedMireIndexAccuracy = metrics.OffsetAlignedMireIndexAccuracy;
MeanAbsoluteAlignedMireIndexError = ...
    metrics.MeanAbsoluteAlignedMireIndexError;
NearestTruthMedianRadialErrorPx = metrics.MedianRadialErrorPx;
AssignedSameMireMedianErrorPx = assignedMedian;
row = table(LocalizationMethod, LabelStage, CandidateCount, ...
    MatchedCandidateFraction, PhysicalMireIndexAccuracy, ...
    DominantMireIndexOffset, OffsetAlignedMireIndexAccuracy, ...
    MeanAbsoluteAlignedMireIndexError, NearestTruthMedianRadialErrorPx, ...
    AssignedSameMireMedianErrorPx);
end

function summary = offsetSummary(points)
matched = points(points.IsMatched, :);
keys = unique(matched(:, {'LocalizationMethod', 'LabelStage', ...
    'LabelOffset'}), 'rows');
Count = zeros(height(keys), 1);
FractionWithinStage = zeros(height(keys), 1);
for row = 1:height(keys)
    sameStage = matched.LocalizationMethod == keys.LocalizationMethod(row) & ...
        matched.LabelStage == keys.LabelStage(row);
    sameOffset = sameStage & matched.LabelOffset == keys.LabelOffset(row);
    Count(row) = nnz(sameOffset);
    FractionWithinStage(row) = Count(row) / nnz(sameStage);
end
summary = [keys, table(Count, FractionWithinStage)];
summary = sortrows(summary, ...
    {'LocalizationMethod', 'LabelStage', 'Count'}, ...
    {'ascend', 'ascend', 'descend'});
end

function summary = componentSummary(mode, identity)
matched = identity(identity.IsMatched & identity.ComponentId > 0, :);
componentIds = unique(matched.ComponentId);
rowCount = numel(componentIds);
LocalizationMethod = repmat(mode, rowCount, 1);
ComponentId = componentIds;
NodeCount = zeros(rowCount, 1);
AssignedMireMode = nan(rowCount, 1);
NearestTruthMireMode = nan(rowCount, 1);
DominantLabelOffset = nan(rowCount, 1);
ExactIdentityFraction = nan(rowCount, 1);
MedianNearestRadialErrorPx = nan(rowCount, 1);
for row = 1:rowCount
    subset = matched(matched.ComponentId == componentIds(row), :);
    NodeCount(row) = height(subset);
    AssignedMireMode(row) = modeValue(subset.AssignedMireIndex);
    NearestTruthMireMode(row) = modeValue(subset.TrueMireIndex);
    DominantLabelOffset(row) = modeValue(subset.LabelOffset);
    ExactIdentityFraction(row) = mean(subset.LabelOffset == 0);
    MedianNearestRadialErrorPx(row) = ...
        median(subset.NearestTruthRadialErrorPx);
end
summary = table(LocalizationMethod, ComponentId, NodeCount, ...
    AssignedMireMode, NearestTruthMireMode, DominantLabelOffset, ...
    ExactIdentityFraction, MedianNearestRadialErrorPx);
summary = sortrows(summary, {'LocalizationMethod', 'AssignedMireMode'});
end

function value = modeValue(values)
value = mode(values(isfinite(values)));
end
