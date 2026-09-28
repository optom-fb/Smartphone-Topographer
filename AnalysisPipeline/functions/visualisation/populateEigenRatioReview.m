function tabs = populateEigenRatioReview(parent, result, cfg)
%POPULATEEIGENRATIOREVIEW Show the full Placido-style S07 analysis.
%   The four inner tabs mirror the neighbouring Placido workflow while
%   presenting only the configured preferred segmentation branch. No Placido
%   project file is called or modified.

tabs = uitabgroup('Parent', parent, 'Units', 'normalized', ...
    'Position', [0, 0, 1, 1]);
axesTab = uitab(tabs, 'Title', '1 - Complete rings: axes');
metricsTab = uitab(tabs, 'Title', '2 - Complete rings: metrics');
incompleteTab = uitab(tabs, 'Title', '3 - Incomplete: diagnostic only');
qualityTab = uitab(tabs, 'Title', '4 - Quality gate');

populateAxesTab(axesTab, result, cfg);
populateMetricsTab(metricsTab, result, cfg);
populateIncompleteTab(incompleteTab, result, cfg);
populateQualityTab(qualityTab, result, cfg);
end

function populateAxesTab(parent, result, cfg)
[variant, displayName] = selectEigenRatioVariant(result, cfg);
addBanner(parent, sprintf(['%s %s | complete traces only; camera-sensor-' ...
    'plane image descriptors, not clinical keratometry axes.'], ...
    displayName, variant.Segmentation.MethodActual));
axisHandle = axes('Parent', parent, 'Position', [0.17, 0.43, 0.66, 0.46]);
plotCompleteMireAxes(axisHandle, variant, result.Preprocessing, cfg, ...
    displayName + ' complete-mire axes');

tableValue = axesTable(variant.EigenRatio.Metrics);
uitable('Parent', parent, 'Units', 'normalized', ...
    'Position', [0.08, 0.04, 0.84, 0.32], 'Data', tableValue, ...
    'RowName', [], 'ColumnWidth', 'auto');
end

function populateMetricsTab(parent, result, cfg)
[variant, displayName] = selectEigenRatioVariant(result, cfg);
metrics = variant.EigenRatio.Metrics;
fields = {'CV_R_percent','Irregularity_percent','HarmonicRMSmm','EigenRatio'};
headings = ["Total radius distortion (CV_R)", ...
    "Harmonic-filtered irregularity", "Second-harmonic RMS", ...
    "Covariance eigen-ratio"];
yLabels = ["CV_R (%)", "Index (%)", "RMS (sensor-plane mm)", ...
    "Minor / major (dimensionless)"];
colours = [0.85 0.33 0.10; 0.13 0.55 0.13; 0.00 0.45 0.74; 0.49 0.18 0.56];
layout = tiledlayout(parent, 2, 2, 'TileSpacing', 'compact', ...
    'Padding', 'compact');
for row = 1:4
    axisHandle = nexttile(layout);
    primary = metrics(metrics.IsIncludedInPrimary, :);
    plotMetric(axisHandle, primary.MireIndex, primary.(fields{row}), ...
        colours(row, :), displayName + " | " + headings(row), yLabels(row));
end
end

function populateIncompleteTab(parent, result, cfg)
[variant, displayName] = selectEigenRatioVariant(result, cfg);
metrics = variant.EigenRatio.Metrics;
addBanner(parent, ['Incomplete traces are excluded from primary means. A ' ...
    'missing sector can lower eigen-ratio without representing corneal shape.']);
axisHandle = axes('Parent', parent, 'Position', [0.18, 0.49, 0.64, 0.39]);
plotIncomplete(axisHandle, metrics, displayName);
uitable('Parent', parent, 'Units', 'normalized', ...
    'Position', [0.08, 0.05, 0.84, 0.34], ...
    'Data', incompleteTable(metrics), ...
    'RowName', [], 'ColumnWidth', 'auto');
end

function populateQualityTab(parent, result, cfg)
[variant, displayName] = selectEigenRatioVariant(result, cfg);
addBanner(parent, ['Traceable inclusion decision for every analysed mire. ' ...
    'Thresholds are engineering defaults and not clinical cutoffs. ']);
uicontrol('Parent', parent, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.025, 0.88, 0.95, 0.035], ...
    'String', sprintf('%s segmentation: %s', displayName, ...
    variant.Segmentation.MethodActual), 'HorizontalAlignment', 'left');
combined = qualityTable(variant.EigenRatio.Metrics);
uitable('Parent', parent, 'Units', 'normalized', ...
    'Position', [0.025, 0.06, 0.95, 0.82], 'Data', combined, ...
    'RowName', [], 'ColumnWidth', 'auto');
end

function plotMetric(axisHandle, x, y, colour, heading, yLabelText)
plot(axisHandle, x, y, '-o', 'LineWidth', 1.6, 'Color', colour, ...
    'MarkerFaceColor', colour);
grid(axisHandle, 'on');
xlabel(axisHandle, 'Mire index');
ylabel(axisHandle, yLabelText);
title(axisHandle, heading);
average = mean(y, 'omitnan');
if isfinite(average)
    yline(axisHandle, average, '--', sprintf('Mean %.3g', average));
end
end

function plotIncomplete(axisHandle, metrics, pipelineName)
incomplete = metrics(~metrics.IsIncludedInPrimary, :);
scatter(axisHandle, 100*incomplete.CoverageFraction, ...
    incomplete.EigenRatio, 45, [0.85 0.33 0.10], 'filled');
grid(axisHandle, 'on');
xlim(axisHandle, [0, 102]);
ylim(axisHandle, [0, 1.05]);
xlabel(axisHandle, 'Observed angular samples (%)');
ylabel(axisHandle, 'Partial-trace eigen-ratio');
title(axisHandle, pipelineName + " incomplete diagnostic");
for row = 1:height(incomplete)
    text(axisHandle, 100*incomplete.CoverageFraction(row)+1, ...
        incomplete.EigenRatio(row), string(incomplete.MireIndex(row)));
end
end

function value = axesTable(metrics)
value = metrics(metrics.IsIncludedInPrimary, {'MireIndex','CoverageFraction', ...
    'MaximumGapDeg','MajorRadiusAxisDegCCW','PerpendicularAxisDegCCW', ...
    'MajorExtentMm','MinorExtentMm','CenterXmm','CenterYmm','CV_R_percent'});
end

function value = incompleteTable(metrics)
value = metrics(~metrics.IsIncludedInPrimary, {'MireIndex','PointCount', ...
    'CoverageFraction','MaximumGapDeg','EigenRatio','HarmonicRMSmm', ...
    'Interpretation'});
end

function value = qualityTable(metrics)
value = metrics(:, {'Pipeline','MireIndex','PointCount','CoverageFraction', ...
    'MaximumGapDeg','IsIncludedInPrimary','AnalysisGroup'});
end

function addBanner(parent, message)
uicontrol('Parent', parent, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.025, 0.92, 0.95, 0.055], 'String', message, ...
    'HorizontalAlignment', 'left', 'FontWeight', 'bold');
end
