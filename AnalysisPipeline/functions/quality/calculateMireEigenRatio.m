function analysis = calculateMireEigenRatio(matrices, pre, cfg, pipelineName)
%CALCULATEMIREEIGENRATIO Calculate per-mire image-shape diagnostics.
%   Spatial outputs use camera-sensor-plane millimetres. EigenRatio is the
%   dimensionless minor/major covariance extent ratio. Only sufficiently
%   complete traces enter the primary summary; incomplete traces remain in
%   the returned table as diagnostic rows.

arguments
    matrices struct
    pre struct
    cfg struct
    pipelineName (1,1) string
end

anglesDeg = matrices.AnglesDeg(:)';
nAngles = numel(anglesDeg);
sensorSizeMm = getProcessingSensorSizeMm(pre, cfg);
pitchXmm = sensorSizeMm(1) / pre.OriginalSize(2);
pitchYmm = sensorSizeMm(2) / pre.OriginalSize(1);
nMires = size(matrices.X, 1);

rows = cell(nMires, 20);
rowCount = 0;
for mireIndex = 1:nMires
    valid = isfinite(matrices.X(mireIndex, :)) & ...
        isfinite(matrices.Y(mireIndex, :));
    pointCount = nnz(valid);
    if pointCount < 3
        continue
    end

    observedAngles = anglesDeg(valid);
    xMm = (matrices.X(mireIndex, valid)-pre.CenterPx(1)) * pitchXmm;
    yMm = -(matrices.Y(mireIndex, valid)-pre.CenterPx(2)) * pitchYmm;
    coverageFraction = pointCount / nAngles;
    maximumGapDeg = circularMaximumGap(observedAngles);
    isComplete = pointCount >= cfg.eigenRatio.MinimumPoints && ...
        coverageFraction >= cfg.eigenRatio.MinimumCoverageFraction && ...
        maximumGapDeg <= cfg.eigenRatio.MaximumGapDeg;

    centerXmm = mean(xMm);
    centerYmm = mean(yMm);
    centeredX = xMm-centerXmm;
    centeredY = yMm-centerYmm;
    covariance = cov([centeredX(:), centeredY(:)]);
    [vectors, values] = eig(covariance, 'vector');
    [latent, order] = sort(real(values), 'descend');
    vectors = real(vectors(:, order));
    majorExtentMm = sqrt(2*max(latent(1), 0));
    minorExtentMm = sqrt(2*max(latent(2), 0));
    eigenRatio = minorExtentMm / majorExtentMm;
    majorAxisDegCCW = mod(atan2d(vectors(2, 1), vectors(1, 1)), 180);

    polarAngle = atan2(centeredY, centeredX);
    radialMm = hypot(centeredX, centeredY);
    design = [ones(pointCount, 1), cos(2*polarAngle(:)), ...
        sin(2*polarAngle(:))];
    harmonicCoefficients = design \ radialMm(:);
    fittedRadiusMm = design * harmonicCoefficients;
    harmonicAmplitudeMm = hypot(harmonicCoefficients(2), ...
        harmonicCoefficients(3));
    if harmonicAmplitudeMm > eps(max(mean(radialMm), 1))
        majorRadiusAxisDegCCW = mod(0.5*atan2d( ...
            harmonicCoefficients(3), harmonicCoefficients(2)), 180);
        perpendicularAxisDegCCW = mod(majorRadiusAxisDegCCW+90, 180);
    else
        majorRadiusAxisDegCCW = NaN;
        perpendicularAxisDegCCW = NaN;
    end
    harmonicRMSmm = sqrt(mean((radialMm(:)-fittedRadiusMm).^2));
    cvRPercent = 100*std(radialMm)/mean(radialMm);
    irregularRadiusMm = radialMm(:)-fittedRadiusMm+mean(radialMm);
    irregularityPercent = 100*std(irregularRadiusMm)/mean(radialMm);

    if isComplete
        group = "complete-primary";
        interpretation = "Included in primary complete-mire summary";
    else
        group = "incomplete-diagnostic";
        interpretation = "Excluded from primary summary: incomplete trace; " + ...
            "eigen-ratio may be biased by missing sectors";
    end
    rowCount = rowCount+1;
    rows(rowCount, :) = {pipelineName, mireIndex, pointCount, ...
        coverageFraction, 360*coverageFraction, maximumGapDeg, isComplete, ...
        group, centerXmm, centerYmm, majorExtentMm, minorExtentMm, ...
        majorRadiusAxisDegCCW, perpendicularAxisDegCCW, majorAxisDegCCW, ...
        cvRPercent, irregularityPercent, harmonicRMSmm, eigenRatio, ...
        interpretation};
end
rows = rows(1:rowCount, :);

metrics = emptyMetricsTable();
if ~isempty(rows)
    metrics = cell2table(rows, 'VariableNames', ...
        metrics.Properties.VariableNames);
    metrics.Pipeline = string(metrics.Pipeline);
    metrics.AnalysisGroup = string(metrics.AnalysisGroup);
    metrics.Interpretation = string(metrics.Interpretation);
end

primary = metrics(metrics.IsIncludedInPrimary, :);
analysis = struct();
analysis.Enabled = true;
analysis.Method = "covariance-minor-major-ratio";
analysis.CoordinateFrame = ...
    "camera-sensor-plane; origin=detected-centre; x=right; y=superior";
analysis.SpatialUnit = "mm";
analysis.EigenRatioUnit = "dimensionless";
analysis.Metrics = metrics;
analysis.PrimaryMireCount = height(primary);
analysis.IncompleteMireCount = height(metrics)-height(primary);
analysis.MeanEigenRatio = mean(primary.EigenRatio, 'omitnan');
analysis.MedianEigenRatio = median(primary.EigenRatio, 'omitnan');
analysis.Warning = "Image-shape/QC descriptor only; not corneal power, " + ...
    "a validated keratoconus index, or a clinical diagnosis.";
end

function maximumGapDeg = circularMaximumGap(anglesDeg)
anglesDeg = sort(unique(mod(anglesDeg(:), 360)));
if isempty(anglesDeg)
    maximumGapDeg = 360;
    return
end
gaps = diff([anglesDeg; anglesDeg(1)+360]);
maximumGapDeg = max(gaps);
end

function metrics = emptyMetricsTable()
metrics = table('Size', [0, 20], ...
    'VariableTypes', {'string','double','double','double','double','double', ...
    'logical','string','double','double','double','double','double','double', ...
    'double','double','double','double','double','string'}, ...
    'VariableNames', {'Pipeline','MireIndex','PointCount','CoverageFraction', ...
    'ObservedAngleEquivalentDeg','MaximumGapDeg','IsIncludedInPrimary', ...
    'AnalysisGroup','CenterXmm','CenterYmm','MajorExtentMm','MinorExtentMm', ...
    'MajorRadiusAxisDegCCW','PerpendicularAxisDegCCW', ...
    'CovarianceMajorAxisDegCCW','CV_R_percent','Irregularity_percent', ...
    'HarmonicRMSmm','EigenRatio','Interpretation'});
end
