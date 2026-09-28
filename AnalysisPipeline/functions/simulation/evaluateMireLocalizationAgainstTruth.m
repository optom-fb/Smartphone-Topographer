function [metrics, details] = evaluateMireLocalizationAgainstTruth(candidates, truth, ...
        maximumMires, radialTolerancePx)
%EVALUATEMIRELOCALIZATIONAGAINSTTRUTH Score detected mire identities/radii.

arguments
    candidates table
    truth struct
    maximumMires (1,1) double {mustBeInteger, mustBePositive}
    radialTolerancePx (1,1) double {mustBePositive} = 3
end

active = candidates(candidates.IsValid, :);
CandidateRow = find(candidates.IsValid);
matched = false(height(active), 1);
trueMire = nan(height(active), 1);
radialError = nan(height(active), 1);
for row = 1:height(active)
    % Candidate angles follow image coordinates (positive clockwise after
    % the image-y inversion); simulator truth uses physical CCW azimuth.
    truthAngleDeg = mod(-active.AngleDeg(row), 360);
    angularDifference = abs(mod(truth.anglesDeg-truthAngleDeg+180, ...
        360)-180);
    [~, angleIndex] = min(angularDifference);
    available = truth.visibleMask(:, angleIndex) & ...
        (1:size(truth.visibleMask, 1))' <= maximumMires & ...
        isfinite(truth.radiiPixels(:, angleIndex));
    ringIndices = find(available);
    if isempty(ringIndices)
        continue
    end
    errors = abs(truth.radiiPixels(ringIndices, angleIndex) - ...
        active.RadiusPx(row));
    [minimumError, nearest] = min(errors);
    if minimumError <= radialTolerancePx
        matched(row) = true;
        trueMire(row) = ringIndices(nearest);
        radialError(row) = minimumError;
    end
end

metrics = struct();
metrics.CandidateCount = height(active);
metrics.MatchedCandidateCount = nnz(matched);
metrics.MatchedCandidateFraction = safeDivide(nnz(matched), height(active));
if any(matched)
    signedOffset = trueMire(matched)-active.MireIndex(matched);
    dominantOffset = mode(signedOffset);
    metrics.PhysicalMireIndexAccuracy = mean(signedOffset == 0);
    metrics.MeanAbsolutePhysicalMireIndexError = mean(abs(signedOffset));
    metrics.DominantMireIndexOffset = dominantOffset;
    metrics.OffsetAlignedMireIndexAccuracy = ...
        mean(signedOffset == dominantOffset);
    metrics.MeanAbsoluteAlignedMireIndexError = ...
        mean(abs(signedOffset-dominantOffset));
    metrics.MedianRadialErrorPx = median(radialError(matched));
else
    metrics.PhysicalMireIndexAccuracy = NaN;
    metrics.MeanAbsolutePhysicalMireIndexError = NaN;
    metrics.DominantMireIndexOffset = NaN;
    metrics.OffsetAlignedMireIndexAccuracy = NaN;
    metrics.MeanAbsoluteAlignedMireIndexError = NaN;
    metrics.MedianRadialErrorPx = NaN;
end
metrics.RadialMatchTolerancePx = radialTolerancePx;

AssignedMireIndex = double(active.MireIndex);
TrueMireIndex = trueMire;
LabelOffset = TrueMireIndex - AssignedMireIndex;
NearestTruthRadialErrorPx = radialError;
ImageAngleDeg = double(active.AngleDeg);
TruthAngleDeg = mod(-ImageAngleDeg, 360);
IsMatched = matched;
if ismember('ComponentId', active.Properties.VariableNames)
    ComponentId = double(active.ComponentId);
else
    ComponentId = zeros(height(active), 1);
end
details = table(CandidateRow, ComponentId, ImageAngleDeg, TruthAngleDeg, ...
    AssignedMireIndex, TrueMireIndex, LabelOffset, ...
    NearestTruthRadialErrorPx, IsMatched);
end

function value = safeDivide(numerator, denominator)
if denominator == 0
    value = NaN;
else
    value = numerator / denominator;
end
end
