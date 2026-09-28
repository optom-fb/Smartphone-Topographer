function resultsFile = getLatestPlacidoResultsFile(projectRoot, resultsFileName)
%GETLATESTPLACIDORESULTSFILE Return a chosen or most-recent detector CSV.
%
% Leave resultsFileName empty to use the newest *_results.csv file in
% Data\Output. Provide a filename, for example 'Trial_results.csv', only
% when you deliberately want to analyse an older result.

    outputFolder = fullfile(projectRoot, 'Data', 'Output');

    if nargin >= 2 && strlength(string(resultsFileName)) > 0
        resultsFile = fullfile(outputFolder, resultsFileName);
    else
        resultFiles = dir(fullfile(outputFolder, '**', '*_results.csv'));
        if isempty(resultFiles)
            error(['No detector results were found in: %s\n' ...
                   'Run step01_detect_placido_rings.m first.'], outputFolder);
        end

        [~, newestIndex] = max([resultFiles.datenum]);
        resultsFile = fullfile(resultFiles(newestIndex).folder, ...
            resultFiles(newestIndex).name);
    end

    if ~isfile(resultsFile)
        error('Results file not found: %s', resultsFile);
    end

    fprintf('Using results file: %s\n', resultsFile);
end
