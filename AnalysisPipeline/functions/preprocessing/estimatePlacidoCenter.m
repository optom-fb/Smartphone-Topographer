function [centerPx, diagnostics] = estimatePlacidoCenter(grayImage, cfg)
%ESTIMATEPLACIDOCENTER Locate the pupil/innermost Placido-circle centre.
%   Coordinates are returned as [x y] in MATLAB image coordinates.

grayImage = im2single(grayImage);
[originalHeight, originalWidth] = size(grayImage);
maximumSizePx = cfg.preprocessing.CenterDetectionMaximumSizePx;
detectionScale = min(1, maximumSizePx / max(originalHeight, originalWidth));
if detectionScale < 1
    workingImage = imresize(grayImage, detectionScale, 'bilinear');
else
    workingImage = grayImage;
end
[height, width] = size(workingImage);
minDim = min(height, width);
searchFraction = cfg.preprocessing.CenterSearchFraction;
searchWidth = max(64, round(width * searchFraction));
searchHeight = max(64, round(height * searchFraction));
x0 = floor((width - searchWidth) / 2) + 1;
y0 = floor((height - searchHeight) / 2) + 1;
searchImage = workingImage(y0:y0+searchHeight-1, ...
    x0:x0+searchWidth-1);

radiusRange = max(8, round(cfg.preprocessing.PupilRadiusFraction * minDim));
if radiusRange(2) <= radiusRange(1)
    radiusRange(2) = radiusRange(1) + 5;
end

smoothed = imgaussfilt(searchImage, 2.0);
[centres, radii, metric] = imfindcircles(smoothed, radiusRange, ...
    'ObjectPolarity', 'dark', 'Sensitivity', 0.95, 'EdgeThreshold', 0.05);

fallbackUsed = false;
if isempty(centres)
    fallbackUsed = true;
    coarse = imgaussfilt(searchImage, max(5, radiusRange(1) / 2));
    [~, linearIndex] = min(coarse(:));
    [candidateY, candidateX] = ind2sub(size(coarse), linearIndex);
    centreLocal = [candidateX, candidateY];
    selectedRadius = mean(radiusRange);
    selectedMetric = NaN;
else
    searchCentre = [size(searchImage, 2), size(searchImage, 1)] / 2;
    distancePenalty = vecnorm(centres - searchCentre, 2, 2) / min(size(searchImage));
    darkness = zeros(size(radii));
    [xx, yy] = meshgrid(1:size(searchImage, 2), 1:size(searchImage, 1));
    for i = 1:numel(radii)
        disc = hypot(xx - centres(i, 1), yy - centres(i, 2)) <= 0.72 * radii(i);
        darkness(i) = 1 - mean(searchImage(disc), 'omitnan');
    end
    score = metric(:) + 0.35 * darkness(:) - 0.55 * distancePenalty(:);
    [~, best] = max(score);
    centreLocal = centres(best, :);
    selectedRadius = radii(best);
    selectedMetric = metric(best);
end

candidate = centreLocal + [x0 - 1, y0 - 1];
[gx, gy] = imgradientxy(imgaussfilt(workingImage, 0.8), 'sobel');
gradientMagnitude = hypot(gx, gy);
refineRadius = max(2, round( ...
    cfg.preprocessing.CenterRefineRadiusPx*detectionScale));
refineStep = max(1, round(2*detectionScale));
offsets = -refineRadius:refineStep:refineRadius;
bestScore = -Inf;
centerPx = candidate;
[xx, yy] = meshgrid(1:width, 1:height);
inner = max(radiusRange(1), 0.55 * selectedRadius);
outer = min(0.34 * minDim, max(4.5 * selectedRadius, inner + 30));
for dx = offsets
    for dy = offsets
        testCenter = candidate + [dx, dy];
        rx = xx - testCenter(1);
        ry = yy - testCenter(2);
        rr = hypot(rx, ry);
        annulus = rr >= inner & rr <= outer & gradientMagnitude > 0;
        if nnz(annulus) < 100
            continue
        end
        ux = rx(annulus) ./ rr(annulus);
        uy = ry(annulus) ./ rr(annulus);
        radial = abs(gx(annulus) .* ux + gy(annulus) .* uy);
        tangential = abs(-gx(annulus) .* uy + gy(annulus) .* ux);
        weights = min(gradientMagnitude(annulus), ...
            prctile(gradientMagnitude(annulus), 90));
        symmetryScore = sum((radial - 0.25 * tangential) .* weights) / sum(weights + eps);
        if symmetryScore > bestScore
            bestScore = symmetryScore;
            centerPx = testCenter;
        end
    end
end

centerPx = [min(max(centerPx(1), 1), width), ...
    min(max(centerPx(2), 1), height)];
centerPx = (centerPx-0.5)/detectionScale+0.5;
initialCenterPx = (candidate-0.5)/detectionScale+0.5;
searchRectangle = ([x0, y0, searchWidth, searchHeight]- ...
    [0.5, 0.5, 0, 0])/detectionScale+[0.5, 0.5, 0, 0];
centerPx = [min(max(centerPx(1), 1), originalWidth), ...
    min(max(centerPx(2), 1), originalHeight)];
diagnostics = struct( ...
    'InitialCenterPx', initialCenterPx, ...
    'SelectedRadiusPx', selectedRadius/detectionScale, ...
    'CircleMetric', selectedMetric, ...
    'RadialSymmetryScore', bestScore, ...
    'FallbackUsed', fallbackUsed, ...
    'SearchRectangle', searchRectangle, ...
    'DetectionScale', detectionScale, ...
    'DetectionImageSizePx', [height, width]);
end
