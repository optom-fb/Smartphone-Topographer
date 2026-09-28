function pupil = detectPupilPlacidoStyle(image, expectedCenterFullPx, cfg)
%DETECTPUPILPLACIDOSTYLE Cautiously detect a dark pupil-like circle.
%   This is a path-independent adaptation of the review-only detector in the
%   neighbouring Placido project. It is intended for audit, not for changing
%   the Placido centre or reconstruction geometry.

arguments
    image
    expectedCenterFullPx (1,2) double
    cfg struct
end

gray = im2gray(image);
[imageHeight, imageWidth] = size(gray);
minimumDimension = min(imageHeight, imageWidth);
searchRadiusPx = max(1, round( ...
    cfg.pupil.SearchRadiusFraction*minimumDimension));
radiusRangePx = max(2, round(cfg.pupil.RadiusFraction*minimumDimension));
gaussianSigmaPx = max(0, ...
    cfg.pupil.GaussianSigmaFraction*minimumDimension);
maximumOffsetPx = max(1, ...
    cfg.pupil.MaximumCenterOffsetFraction*minimumDimension);

if radiusRangePx(1) >= radiusRangePx(2)
    error('SmartKC:InvalidPupilRadiusRange', ...
        'The scaled pupil radius range must have increasing bounds.');
end
if expectedCenterFullPx(1) < 1 || expectedCenterFullPx(1) > imageWidth || ...
        expectedCenterFullPx(2) < 1 || expectedCenterFullPx(2) > imageHeight
    error('SmartKC:InvalidPupilExpectedCenter', ...
        'The expected pupil centre must lie inside the source image.');
end

xStart = max(1, round(expectedCenterFullPx(1)-searchRadiusPx));
xEnd = min(imageWidth, round(expectedCenterFullPx(1)+searchRadiusPx));
yStart = max(1, round(expectedCenterFullPx(2)-searchRadiusPx));
yEnd = min(imageHeight, round(expectedCenterFullPx(2)+searchRadiusPx));
searchRegion = gray(yStart:yEnd, xStart:xEnd);
detectionScale = min(1, cfg.pupil.DetectionMaximumSearchSizePx/ ...
    max(size(searchRegion)));
if detectionScale < 1
    detectionRegion = imresize(searchRegion, detectionScale, 'bilinear');
else
    detectionRegion = searchRegion;
end
detectionRadiusRangePx = max(2, round(radiusRangePx*detectionScale));
detectionSigmaPx = gaussianSigmaPx*detectionScale;
smoothed = imgaussfilt(detectionRegion, detectionSigmaPx);
[localCenters, detectionRadiiPx, metrics] = imfindcircles(smoothed, ...
    detectionRadiusRangePx, ...
    'ObjectPolarity', 'dark', 'Sensitivity', cfg.pupil.CircleSensitivity, ...
    'Method', 'TwoStage');
if isempty(localCenters)
    fullCenters = zeros(0, 2);
    radiiPx = zeros(0, 1);
else
    localCenters = (localCenters-0.5)/detectionScale+0.5;
    fullCenters = localCenters+[xStart-1, yStart-1];
    radiiPx = detectionRadiiPx/detectionScale;
end
centerDistancesPx = hypot(fullCenters(:, 1)-expectedCenterFullPx(1), ...
    fullCenters(:, 2)-expectedCenterFullPx(2));
if isempty(metrics)
    normalizedMetrics = zeros(0, 1);
else
    normalizedMetrics = metrics/max(metrics);
end
proximityScores = max(0, 1-centerDistancesPx/maximumOffsetPx);
scores = 0.70*normalizedMetrics+0.30*proximityScores;
candidates = table(fullCenters(:, 1), fullCenters(:, 2), radiiPx, ...
    metrics, centerDistancesPx, scores, 'VariableNames', ...
    {'CenterXFullPx','CenterYFullPx','RadiusPx','Metric', ...
    'DistanceFromExpectedCenterPx','Score'});

pupil = emptyPupil(expectedCenterFullPx, ...
    [xStart, yStart, xEnd, yEnd], candidates, cfg);
pupil.DetectionScale = detectionScale;
if isempty(candidates)
    pupil.FailureReason = "No dark circular candidates were found.";
    return
end
[~, bestIndex] = max(candidates.Score);
best = candidates(bestIndex, :);
if best.DistanceFromExpectedCenterPx > maximumOffsetPx
    pupil.FailureReason = sprintf( ...
        'Best candidate is %.1f px from the expected centre (limit %.1f px).', ...
        best.DistanceFromExpectedCenterPx, maximumOffsetPx);
    return
end
if best.Metric < cfg.pupil.MinimumMetric
    pupil.FailureReason = sprintf( ...
        'Best candidate metric %.3f is below the minimum %.3f.', ...
        best.Metric, cfg.pupil.MinimumMetric);
    return
end

pupil.CenterFullPx = [best.CenterXFullPx, best.CenterYFullPx];
pupil.RadiusPx = best.RadiusPx;
pupil.DiameterPx = 2*best.RadiusPx;
pupil.Metric = best.Metric;
pupil.Score = best.Score;
pupil.OffsetFromPlacidoCenterPx = pupil.CenterFullPx-expectedCenterFullPx;
pupil.OffsetMagnitudePx = norm(pupil.OffsetFromPlacidoCenterPx);
pupil.IsValid = true;
pupil.FailureReason = "";
end

function pupil = emptyPupil(expectedCenter, searchRegion, candidates, cfg)
pupil = struct();
pupil.Enabled = true;
pupil.Method = "placido-dark-circle-review";
pupil.SourceFrameMode = string(cfg.pupil.SourceFrameMode);
pupil.IsValid = false;
pupil.CenterFullPx = [NaN, NaN];
pupil.CenterPx = [NaN, NaN];
pupil.RadiusPx = NaN;
pupil.DiameterPx = NaN;
pupil.Metric = NaN;
pupil.Score = NaN;
pupil.ExpectedCenterFullPx = expectedCenter;
pupil.OffsetFromPlacidoCenterPx = [NaN, NaN];
pupil.OffsetMagnitudePx = NaN;
pupil.SearchRegionFullPx = searchRegion;
pupil.DetectionScale = NaN;
pupil.Candidates = candidates;
pupil.FailureReason = "";
pupil.Warning = "Review-only circle estimate. Ring-on images can obscure " + ...
    "the pupil; do not use as a clinical pupil measurement.";
end
