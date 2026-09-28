function matrices = mirePointsToMatrices(points, anglesDeg, maximumMires)
%MIREPOINTSTOMATRICES Convert a point table into mire-by-angle arrays.

nAngles = numel(anglesDeg);
radii = nan(maximumMires, nAngles);
x = nan(maximumMires, nAngles);
y = nan(maximumMires, nAngles);
scores = nan(maximumMires, nAngles);

active = points(points.IsValid, :);
for row = 1:height(active)
    mire = active.MireIndex(row);
    angleIndex = active.AngleIndex(row);
    if mire < 1 || mire > maximumMires || angleIndex < 1 || angleIndex > nAngles
        continue
    end
    if isnan(radii(mire, angleIndex)) || active.Score(row) > scores(mire, angleIndex)
        radii(mire, angleIndex) = active.RadiusPx(row);
        x(mire, angleIndex) = active.X(row);
        y(mire, angleIndex) = active.Y(row);
        scores(mire, angleIndex) = active.Score(row);
    end
end

matrices = struct('RadiiPx', radii, 'X', x, 'Y', y, 'Scores', scores, ...
    'AnglesDeg', anglesDeg(:)', 'CoverageByMire', mean(isfinite(radii), 2), ...
    'MireCountByAngle', sum(isfinite(radii), 1));
end
