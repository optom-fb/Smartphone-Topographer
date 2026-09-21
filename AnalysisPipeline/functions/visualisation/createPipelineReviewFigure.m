function figureHandle = createPipelineReviewFigure(result, cfg, parent)
%CREATEPIPELINEREVIEWFIGURE Create a paired visual-QC summary.

if nargin < 3 || isempty(parent)
    figureHandle = figure('Visible', cfg.visualisation.Visible, ...
        'Color', 'w', 'Position', [40, 40, 1800, 1050]);
    layoutParent = figureHandle;
else
    figureHandle = ancestor(parent, 'figure');
    layoutParent = parent;
end
layout = tiledlayout(layoutParent, 2, 4, 'TileSpacing', 'compact', ...
    'Padding', 'loose');
if result.Calibration.IsDeviceSpecific
    calibrationBanner = "PROFILE SET; VALIDATE";
else
    calibrationBanner = "UNCALIBRATED";
end

nexttile(layout);
plotPupilReviewOverlay(gca, result.Preprocessing.RGB, ...
    result.Preprocessing, "crop");
title("Centre + pupil review | " + calibrationBanner + " | " + ...
    result.Preprocessing.Pupil.DetectionStatus, 'FontSize', 10, ...
    'Interpreter', 'none', ...
    'Color', [0.12, 0.12, 0.12]);

nexttile(layout);
imshow(result.SmartKC.Segmentation.Mask);
title(sprintf('SmartKC mask (%s)', result.SmartKC.Segmentation.MethodActual), ...
    'Interpreter', 'none', 'Color', [0.12, 0.12, 0.12]);

nexttile(layout);
showMirePoints(result.Preprocessing.RGB, result.SmartKC.Candidates);
title(sprintf('SmartKC radial labels | median %.0f mires', ...
    median(result.SmartKC.Matrices.MireCountByAngle)), ...
    'Color', [0.12, 0.12, 0.12]);

nexttile(layout);
showMirePoints(result.Preprocessing.RGB, result.SmartKCPP.Candidates);
title(sprintf('SmartKC++ graph labels | %s | median %.0f mires', ...
    displayMethod(result.SmartKCPP.Segmentation.MethodActual), ...
    median(result.SmartKCPP.Matrices.MireCountByAngle)), ...
    'Interpreter', 'none', 'Color', [0.12, 0.12, 0.12]);

nexttile(layout);
showMap(result.SmartKC, 'AxialPowerD', cfg, 'SmartKC axial power');

nexttile(layout);
showMap(result.SmartKC, 'TangentialPowerD', cfg, 'SmartKC tangential power');

nexttile(layout);
showMap(result.SmartKCPP, 'AxialPowerD', cfg, 'SmartKC++ axial power');

nexttile(layout);
showMap(result.SmartKCPP, 'TangentialPowerD', cfg, 'SmartKC++ tangential power');
end

function label = displayMethod(method)
method = string(method);
if method == "smartkcpp-official-unet-matlab"
    label = "official U-Net";
else
    label = method;
end
end

function showMirePoints(rgb, points)
imshow(rgb);
hold on
active = points(points.IsValid, :);
if ~isempty(active)
    scatter(active.X, active.Y, 5, active.MireIndex, 'filled');
    colormap(gca, turbo(24));
end
end

function showMap(variant, fieldName, cfg, heading)
if ~cfg.calibration.IsDeviceSpecific
    axis([0, 1, 0, 1]);
    axis off
    text(0.5, 0.62, 'MAP WITHHELD', 'HorizontalAlignment', 'center', ...
        'FontWeight', 'bold', 'Color', [0.72, 0, 0], 'FontSize', 12);
    text(0.5, 0.42, {'Device/attachment calibration is not set.', ...
        'Review segmentation and mire labels only.'}, ...
        'HorizontalAlignment', 'center', 'Color', [0.22, 0.22, 0.22], ...
        'FontSize', 8);
    title(heading + " | uncalibrated", 'FontSize', 10, ...
        'Color', [0.12, 0.12, 0.12]);
    return
end
if variant.Status ~= "COMPLETED"
    axis([0, 1, 0, 1]);
    axis off
    text(0.05, 0.84, "RECONSTRUCTION BLOCKED", 'FontWeight', 'bold', ...
        'Color', [0.72, 0, 0], 'FontSize', 10);
    text(0.05, 0.70, wrapMessage(variant.ErrorMessage, 42), ...
        'Interpreter', 'none', 'VerticalAlignment', 'top', ...
        'Color', [0.22, 0.22, 0.22], 'FontSize', 8);
    title(heading, 'FontSize', 10, 'Color', [0.12, 0.12, 0.12]);
    return
end
surface = variant.Surface;
imagesc(surface.Xmm(1, :), surface.Ymm(:, 1), surface.(fieldName));
axis image xy
colormap(gca, cfg.visualisation.Colormap);
clim(cfg.visualisation.PowerLimitsD);
colorbar
xlabel('x (mm)', 'Color', [0.18, 0.18, 0.18]);
ylabel('y (mm; superior +)', 'Color', [0.18, 0.18, 0.18]);
metrics = variant.Metrics;
title(sprintf('%s | %.2f / %.2f D @ %.0f deg', heading, ...
    metrics.SimKSteepD, metrics.SimKFlatD, metrics.SimKSteepAxisDeg), ...
    'Color', [0.12, 0.12, 0.12]);
end

function wrapped = wrapMessage(message, maximumCharacters)
words = split(strtrim(string(message)));
lines = strings(0, 1);
current = "";
for i = 1:numel(words)
    proposal = strtrim(current + " " + words(i));
    if strlength(proposal) > maximumCharacters && strlength(current) > 0
        lines(end+1, 1) = current; %#ok<AGROW>
        current = words(i);
    else
        current = proposal;
    end
end
if strlength(current) > 0
    lines(end+1, 1) = current;
end
wrapped = strjoin(lines, newline);
end
