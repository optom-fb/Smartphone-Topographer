function overviewFile = createSyntheticDatasetOverview(outputRoot, manifest)
%CREATESYNTHETICDATASETOVERVIEW Export a labelled contact sheet of cases.
%   OVERVIEWFILE = CREATESYNTHETICDATASETOVERVIEW(OUTPUTROOT, MANIFEST)
%   writes scenario_overview.png beside the synthetic manifest.

arguments
    outputRoot {mustBeTextScalar}
    manifest table
end

numberOfCases = height(manifest);
if numberOfCases == 0
    error('SmartKC:Simulation:EmptyOverview', ...
        'Cannot create an overview for an empty manifest.');
end

numberOfColumns = min(5, numberOfCases);
numberOfRows = ceil(numberOfCases / numberOfColumns);
figureWidth = 380 * numberOfColumns;
figureHeight = 380 * numberOfRows + 80;
overviewFigure = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, figureWidth, figureHeight]);
cleanup = onCleanup(@() close(overviewFigure));
layout = tiledlayout(overviewFigure, numberOfRows, numberOfColumns, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

for index = 1:numberOfCases
    tile = nexttile(layout);
    imageFile = fullfile(char(outputRoot), ...
        strrep(char(manifest.ImageFile(index)), '/', filesep));
    imshow(imread(imageFile), 'Parent', tile);
    label = displayLabel(manifest(index, :));
    title(tile, label, 'Interpreter', 'none', 'FontSize', 10, ...
        'Color', [0.08, 0.08, 0.08]);
end
sgtitle(layout, ...
    'Synthetic engineering cases - not clinical diagnoses or grades', ...
    'FontWeight', 'bold', 'Color', [0.08, 0.08, 0.08]);

overviewFile = fullfile(char(outputRoot), 'scenario_overview.png');
exportgraphics(overviewFigure, overviewFile, 'Resolution', 180);
end

function label = displayLabel(row)
surfaceClass = string(row.SurfaceClass);
if surfaceClass == "sphere"
    flatPowerD = 337.5 / row.RflatMm;
    label = sprintf('Sphere %.2f D', flatPowerD);
elseif surfaceClass == "regular-astigmatism"
    label = sprintf('%s astigmatism - %s', ...
        upper(char(row.AstigmatismOrientation)), char(row.Severity));
elseif surfaceClass == "keratoconus-like"
    label = sprintf('Keratoconus-like - %s', char(row.Severity));
else
    label = strrep(char(row.ScenarioName), '_', ' ');
end
end
