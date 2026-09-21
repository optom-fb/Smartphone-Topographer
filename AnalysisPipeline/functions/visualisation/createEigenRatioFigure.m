function figureHandle = createEigenRatioFigure(result, cfg)
%CREATEEIGENRATIOFIGURE Export the S07 complete-ring metric summary.

figureHandle = figure('Visible', cfg.visualisation.Visible, 'Color', 'w', ...
    'Position', [200, 50, 900, 1050]);
layout = tiledlayout(figureHandle, 4, 1, 'TileSpacing', 'compact', ...
    'Padding', 'loose');
[variant, displayName] = selectEigenRatioVariant(result, cfg);
metrics = variant.EigenRatio.Metrics;
fields = {'CV_R_percent','Irregularity_percent','HarmonicRMSmm','EigenRatio'};
headings = ["Total radius distortion (CV_R)", ...
    "Harmonic-filtered irregularity", "Second-harmonic RMS", ...
    "Covariance eigen-ratio"];
yLabels = ["CV_R (%)", "Index (%)", "RMS (sensor-plane mm)", ...
    "Minor / major (dimensionless)"];
colours = [0.85 0.33 0.10; 0.13 0.55 0.13; 0.00 0.45 0.74; 0.49 0.18 0.56];

for row = 1:4
    axisHandle = nexttile(layout);
    primary = metrics(metrics.IsIncludedInPrimary, :);
    plotMetric(axisHandle, primary.MireIndex, primary.(fields{row}), ...
        colours(row, :), displayName + " | " + headings(row), yLabels(row));
end
title(layout, ["S07 complete-mire shape metrics | " + result.CaseId; ...
    displayName + " " + variant.Segmentation.MethodActual + ...
    " | incomplete traces excluded; image-space QC only"], ...
    'Interpreter', 'none', 'FontWeight', 'bold');
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
