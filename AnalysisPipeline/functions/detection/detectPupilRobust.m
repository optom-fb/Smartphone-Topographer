function pupil = detectPupilRobust(I, expectedCenter, options)
%DETECTPUPILROBUST Detect a dark pupil near an expected corneal centre.
%
%   pupil = detectPupilRobust(I, expectedCenter) searches for a dark,
%   pupil-like circle near expectedCenter, which is normally the Placido or
%   corneal centre returned by findCenterGlow.
%
%   This first-stage detector is deliberately cautious. If it cannot find a
%   sufficiently strong, nearby candidate, pupil.IsValid is false and no pupil
%   position is guessed.
%
%   Optional name-value settings:
%     SearchRadius       Half-width of the search region in pixels (default 180)
%     PupilRadiusRange   Expected pupil-radius range in pixels (default [40 105])
%     GaussianSigma      Blur before circle detection (default 6)
%     Sensitivity        imfindcircles sensitivity (default 0.88)
%     MinMetric          Minimum Hough-circle confidence (default 0.30)
%     MaxCenterOffset    Maximum distance from expected centre (default 72)
%     ShowDiagnostic     Display an overlay for visual checking (default false)
%
%   The returned structure contains the selected candidate, all candidates,
%   the search region, confidence values, and an IsValid flag.

arguments
    I
    expectedCenter (1,2) double
    options.SearchRadius (1,1) double {mustBePositive} = 180
    options.PupilRadiusRange (1,2) double {mustBePositive} = [40 105]
    options.GaussianSigma (1,1) double {mustBeNonnegative} = 6
    options.Sensitivity (1,1) double {mustBeGreaterThanOrEqual(options.Sensitivity, 0), mustBeLessThanOrEqual(options.Sensitivity, 1)} = 0.88
    options.MinMetric (1,1) double {mustBeNonnegative} = 0.30
    options.MaxCenterOffset (1,1) double {mustBePositive} = 72
    options.ShowDiagnostic (1,1) logical = false
end

if options.PupilRadiusRange(1) >= options.PupilRadiusRange(2)
    error('PupilRadiusRange must contain [minimum maximum] radii.');
end

grayImage = im2gray(I);
[imageHeight, imageWidth] = size(grayImage);

if expectedCenter(1) < 1 || expectedCenter(1) > imageWidth || ...
        expectedCenter(2) < 1 || expectedCenter(2) > imageHeight
    error('expectedCenter must be inside the input image.');
end

% Crop around the corneal/ring centre rather than around the camera frame.
xStart = max(1, round(expectedCenter(1) - options.SearchRadius));
xEnd   = min(imageWidth, round(expectedCenter(1) + options.SearchRadius));
yStart = max(1, round(expectedCenter(2) - options.SearchRadius));
yEnd   = min(imageHeight, round(expectedCenter(2) + options.SearchRadius));

searchRegion = grayImage(yStart:yEnd, xStart:xEnd);
smoothedRegion = imgaussfilt(searchRegion, options.GaussianSigma);

[localCenters, radii, metrics] = imfindcircles(smoothedRegion, ...
    options.PupilRadiusRange, ...
    'ObjectPolarity', 'dark', ...
    'Sensitivity', options.Sensitivity, ...
    'Method', 'TwoStage');

% imfindcircles returns an empty 0-by-0 array when it finds no candidates.
% Preserve the expected two-column centre shape so a no-candidate image is a
% valid, reportable outcome rather than a size-mismatch error below.
if isempty(localCenters)
    fullCenters = zeros(0, 2);
else
    fullCenters = localCenters + [xStart - 1, yStart - 1];
end
centerDistances = hypot(fullCenters(:,1) - expectedCenter(1), ...
    fullCenters(:,2) - expectedCenter(2));

if isempty(metrics)
    normalizedMetrics = zeros(0, 1);
else
    normalizedMetrics = metrics ./ max(metrics);
end

proximityScores = max(0, 1 - centerDistances ./ options.MaxCenterOffset);
scores = 0.70 .* normalizedMetrics + 0.30 .* proximityScores;

candidates = table(fullCenters(:,1), fullCenters(:,2), radii, metrics, ...
    centerDistances, scores, ...
    'VariableNames', {'CenterX', 'CenterY', 'Radius', 'Metric', ...
    'DistanceFromExpectedCenter', 'Score'});

pupil = struct();
pupil.Center = [NaN, NaN];
pupil.Radius = NaN;
pupil.Diameter = NaN;
pupil.Metric = NaN;
pupil.Score = NaN;
pupil.IsValid = false;
pupil.ExpectedCenter = expectedCenter;
pupil.SearchRegion = [xStart, yStart, xEnd, yEnd];
pupil.Candidates = candidates;
pupil.FailureReason = '';

if isempty(candidates)
    pupil.FailureReason = 'No dark circular candidates were found.';
else
    [~, bestIndex] = max(candidates.Score);
    bestCandidate = candidates(bestIndex, :);

    isNearExpectedCenter = ...
        bestCandidate.DistanceFromExpectedCenter <= options.MaxCenterOffset;
    hasSufficientMetric = bestCandidate.Metric >= options.MinMetric;

    if isNearExpectedCenter && hasSufficientMetric
        pupil.Center = [bestCandidate.CenterX, bestCandidate.CenterY];
        pupil.Radius = bestCandidate.Radius;
        pupil.Diameter = 2 * bestCandidate.Radius;
        pupil.Metric = bestCandidate.Metric;
        pupil.Score = bestCandidate.Score;
        pupil.IsValid = true;
    elseif ~isNearExpectedCenter
        pupil.FailureReason = sprintf( ...
            'Best candidate is %.1f px from the expected centre (limit %.1f px).', ...
            bestCandidate.DistanceFromExpectedCenter, options.MaxCenterOffset);
    else
        pupil.FailureReason = sprintf( ...
            'Best candidate metric %.3f is below the minimum %.3f.', ...
            bestCandidate.Metric, options.MinMetric);
    end
end

if options.ShowDiagnostic
    localShowDiagnostic(I, pupil);
end
end

function localShowDiagnostic(I, pupil)
%LOCALSHOWDIAGNOSTIC Display the search area and selected pupil candidate.

diagnosticFigure = figure( ...
    'Name', 'Pupil detection diagnostic', 'Color', 'w', ...
    'Position', [70 70 1550 900]);
diagnosticFigure.WindowState = 'maximized';
imshow(I);
hold on;

hSearchRegion = rectangle('Position', [pupil.SearchRegion(1), pupil.SearchRegion(2), ...
    pupil.SearchRegion(3) - pupil.SearchRegion(1), ...
    pupil.SearchRegion(4) - pupil.SearchRegion(2)], ...
    'EdgeColor', [0.2 0.6 1], 'LineStyle', '--', 'LineWidth', 1.5);
hExpectedCenter = plot(pupil.ExpectedCenter(1), pupil.ExpectedCenter(2), 'b+', ...
    'LineWidth', 2, 'MarkerSize', 12);

if pupil.IsValid
    hPupilBoundary = viscircles(pupil.Center, pupil.Radius, ...
        'Color', 'y', 'LineWidth', 2);
    hPupilCenter = plot(pupil.Center(1), pupil.Center(2), 'y+', ...
        'LineWidth', 2, 'MarkerSize', 12);
    title(sprintf('Pupil detected: diameter %.1f px, metric %.2f', ...
        pupil.Diameter, pupil.Metric));
else
    title(sprintf('Pupil not accepted: %s', pupil.FailureReason), ...
        'Color', [0.85 0.2 0.2]);
end

% Legend is intentionally omitted: viscircles objects cannot be included in
% a MATLAB legend on all releases. Blue marks the search/expected centre;
% yellow marks the accepted pupil candidate.
hold off;
end
