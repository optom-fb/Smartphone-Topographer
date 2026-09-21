function figureHandle = showPipelineTabs(result, cfg)
%SHOWPIPELINETABS Display one image's complete S00-S07 review in tabs.

close(findall(groot, 'Type', 'figure', 'Tag', 'SmartKCPipelineTabs'));
figureHandle = figure('Name', char("SmartKC pipeline - " + result.CaseId), ...
    'NumberTitle', 'off', 'Color', 'white', ...
    'Tag', 'SmartKCPipelineTabs', 'Position', [40, 60, 1500, 820]);
tabs = uitabgroup(figureHandle);

tab = uitab(tabs, 'Title', 'S00 Input');
tab.BackgroundColor = [1, 1, 1];
axisHandle = axes('Parent', tab);
[sourceImage, ~] = readImageWithExifOrientation(char(result.SourcePath));
imshow(sourceImage, 'Parent', axisHandle);
title(axisHandle, "Input | " + result.CaseId, 'Interpreter', 'none', ...
    'Color', [0.08, 0.08, 0.08]);

tab = uitab(tabs, 'Title', 'S01 Preprocess');
tab.BackgroundColor = [1, 1, 1];
layout = tiledlayout(tab, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
axisHandle = nexttile(layout);
plotPupilReviewOverlay(axisHandle, sourceImage, ...
    result.Preprocessing, "full");
title(axisHandle, 'Full image: red Placido, yellow pupil', ...
    'Color', [0.08, 0.08, 0.08]);
axisHandle = nexttile(layout);
plotPupilReviewOverlay(axisHandle, result.Preprocessing.RGB, ...
    result.Preprocessing, "crop");
title(axisHandle, "Pupil " + result.Preprocessing.Pupil.DetectionStatus, ...
    'Interpreter', 'none', 'Color', [0.08, 0.08, 0.08]);
axisHandle = nexttile(layout);
imshow(result.Preprocessing.NormalizedGray, [], 'Parent', axisHandle);
title(axisHandle, 'Normalized image', 'Color', [0.08, 0.08, 0.08]);

tab = uitab(tabs, 'Title', 'S02 Segmentation');
tab.BackgroundColor = [1, 1, 1];
layout = tiledlayout(tab, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
axisHandle = nexttile(layout);
imshow(result.Preprocessing.RGB, 'Parent', axisHandle);
title(axisHandle, 'Analysis crop', 'Color', [0.08, 0.08, 0.08]);
axisHandle = nexttile(layout);
imshow(result.SmartKC.Segmentation.Mask, 'Parent', axisHandle);
title(axisHandle, "SmartKC | " + result.SmartKC.Segmentation.MethodActual, ...
    'Interpreter', 'none', 'Color', [0.08, 0.08, 0.08]);
axisHandle = nexttile(layout);
imshow(result.SmartKCPP.Segmentation.Mask, 'Parent', axisHandle);
title(axisHandle, "SmartKC++ | " + ...
    result.SmartKCPP.Segmentation.MethodActual, ...
    'Interpreter', 'none', 'Color', [0.08, 0.08, 0.08]);

tab = uitab(tabs, 'Title', 'S03 Mire labels');
tab.BackgroundColor = [1, 1, 1];
layout = tiledlayout(tab, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
showCandidates(nexttile(layout), result.Preprocessing.RGB, ...
    result.SmartKC.Candidates, 'SmartKC radial labels');
showCandidates(nexttile(layout), result.Preprocessing.RGB, ...
    result.SmartKCPP.Candidates, 'SmartKC++ graph-corrected labels');

addReconstructionTab(tabs, 'S04 SmartKC maps', result.SmartKC, cfg);
addReconstructionTab(tabs, 'S05 SmartKC++ maps', result.SmartKCPP, cfg);

tab = uitab(tabs, 'Title', 'S06 Final review');
tab.BackgroundColor = [1, 1, 1];
createPipelineReviewFigure(result, cfg, tab);

if cfg.eigenRatio.Enabled
    tab = uitab(tabs, 'Title', 'S07 SmartKC++ ring analysis');
    tab.BackgroundColor = [1, 1, 1];
    populateEigenRatioReview(tab, result, cfg);
end
end

function showCandidates(axisHandle, rgb, candidates, heading)
imshow(rgb, 'Parent', axisHandle);
hold(axisHandle, 'on');
active = candidates(candidates.IsValid, :);
if ~isempty(active)
    scatter(axisHandle, active.X, active.Y, 7, active.MireIndex, 'filled');
    colormap(axisHandle, turbo(24));
end
title(axisHandle, heading, 'Color', [0.08, 0.08, 0.08]);
end

function addReconstructionTab(tabs, titleText, variant, cfg)
tab = uitab(tabs, 'Title', titleText);
tab.BackgroundColor = [1, 1, 1];
layout = tiledlayout(tab, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
showMap(nexttile(layout), variant, 'AxialPowerD', 'Axial power', cfg);
showMap(nexttile(layout), variant, 'TangentialPowerD', ...
    'Tangential power', cfg);
end

function showMap(axisHandle, variant, fieldName, heading, cfg)
if ~cfg.calibration.IsDeviceSpecific
    showUncalibratedMapNotice(axisHandle, heading);
    return
end
if variant.Status ~= "COMPLETED"
    axis(axisHandle, [0, 1, 0, 1]);
    axis(axisHandle, 'off');
    text(axisHandle, 0.05, 0.82, 'RECONSTRUCTION BLOCKED', ...
        'FontWeight', 'bold', 'Color', [0.72, 0, 0]);
    text(axisHandle, 0.05, 0.68, variant.ErrorMessage, ...
        'Interpreter', 'none', 'VerticalAlignment', 'top', ...
        'Color', [0.18, 0.18, 0.18]);
    title(axisHandle, heading, 'Color', [0.08, 0.08, 0.08]);
    return
end

surface = variant.Surface;
imagesc(axisHandle, surface.Xmm(1, :), surface.Ymm(:, 1), ...
    surface.(fieldName));
axis(axisHandle, 'image', 'xy');
colormap(axisHandle, cfg.visualisation.Colormap);
clim(axisHandle, cfg.visualisation.PowerLimitsD);
colorbar(axisHandle);
xlabel(axisHandle, 'x (mm)');
ylabel(axisHandle, 'y (mm; superior +)');
title(axisHandle, sprintf('%s | %.2f / %.2f D @ %.0f deg', heading, ...
    variant.Metrics.SimKSteepD, variant.Metrics.SimKFlatD, ...
    variant.Metrics.SimKSteepAxisDeg), 'Color', [0.08, 0.08, 0.08]);
end

function showUncalibratedMapNotice(axisHandle, heading)
axis(axisHandle, [0, 1, 0, 1]);
axis(axisHandle, 'off');
text(axisHandle, 0.5, 0.62, 'MAP WITHHELD', ...
    'HorizontalAlignment', 'center', 'FontWeight', 'bold', ...
    'FontSize', 14, 'Color', [0.72, 0, 0]);
text(axisHandle, 0.5, 0.43, ...
    {'Device/attachment calibration is not set.', ...
     'Review segmentation and mire labels only.'}, ...
    'HorizontalAlignment', 'center', 'Color', [0.18, 0.18, 0.18]);
title(axisHandle, heading + " | uncalibrated", ...
    'Color', [0.08, 0.08, 0.08]);
end
