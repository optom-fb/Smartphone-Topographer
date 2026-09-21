function report = checkPlatformCompatibility(projectRoot)
%CHECKPLATFORMCOMPATIBILITY Audit runtime and path portability prerequisites.
%   REPORT = CHECKPLATFORMCOMPATIBILITY(PROJECTROOT) returns one row per
%   Windows/macOS/Linux portability check without changing project files.

if nargin < 1 || strlength(string(projectRoot)) == 0
    utilityFolder = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(fileparts(utilityFolder));
end
projectRoot = char(projectRoot);

checkName = strings(0, 1);
passed = false(0, 1);
details = strings(0, 1);

if ispc
    platformName = "Windows";
elseif ismac
    platformName = "macOS";
elseif isunix
    platformName = "Linux/Unix";
else
    platformName = "unsupported";
end
addCheck("Supported operating system", platformName ~= "unsupported", ...
    platformName + " | filesep=" + string(filesep));

addCheck("MATLAB release", ~isMATLABReleaseOlderThan("R2022b"), ...
    string(version('-release')) + " (R2022b or newer required)");
addCheck("Project root", isfolder(projectRoot), string(projectRoot));

requiredFolders = {'config','functions','scripts','tests','CaptureGUI','Data'};
missingFolders = requiredFolders(~cellfun(@(name) ...
    isfolder(fullfile(projectRoot, name)), requiredFolders));
addCheck("Required project folders", isempty(missingFolders), ...
    missingDetail(missingFolders));

requiredFunctions = {'imfindcircles','imgaussfilt','imbothat','findpeaks', ...
    'prctile','dlnetwork'};
missingFunctions = requiredFunctions(cellfun(@(name) exist(name, 'file') == 0, ...
    requiredFunctions));
addCheck("Required toolbox functions", isempty(missingFunctions), ...
    missingDetail(missingFunctions));

licenseFeatures = {'image_toolbox','signal_toolbox','statistics_toolbox', ...
    'neural_network_toolbox'};
licenseNames = {'Image Processing Toolbox','Signal Processing Toolbox', ...
    'Statistics and Machine Learning Toolbox','Deep Learning Toolbox'};
missingLicenses = licenseNames(~cellfun(@(feature) ...
    license('test', feature), licenseFeatures));
addCheck("Required toolbox licences", isempty(missingLicenses), ...
    missingDetail(missingLicenses));

matlabFiles = dir(fullfile(projectRoot, '*.m'));
sourceFolders = {'config','functions','scripts','tests','CaptureGUI'};
for folderIndex = 1:numel(sourceFolders)
    matlabFiles = [matlabFiles; dir(fullfile(projectRoot, ...
        sourceFolders{folderIndex}, '**', '*.m'))]; %#ok<AGROW>
end
relativePaths = strings(numel(matlabFiles), 1);
hardCodedFiles = strings(0, 1);
osCommandFiles = strings(0, 1);
checkerPath = string([mfilename('fullpath') '.m']);
approvedSystemPaths = [
    "functions" + filesep + "utility" + filesep + "sha256File.m"
    "scripts" + filesep + "setup_smartkcpp_unet.m"
    ];
for index = 1:numel(matlabFiles)
    fullPath = fullfile(matlabFiles(index).folder, matlabFiles(index).name);
    relativePaths(index) = erase(string(fullPath), string(projectRoot) + filesep);
    if string(fullPath) == checkerPath
        continue
    end
    source = fileread(fullPath);
    windowsDrivePattern = '(?<![A-Za-z0-9])[A-Za-z]:[\\/]';
    hasWindowsDrive = ~isempty(regexp(source, windowsDrivePattern, 'once'));
    if hasWindowsDrive
        hardCodedFiles(end+1, 1) = relativePaths(index); %#ok<AGROW>
    end
    osCommandPattern = [ ...
        '(?m)(^\s*!|(?<![A-Za-z0-9_])' ...
        '(system|dos|unix|winopen)\s*\()'];
    if ~isempty(regexp(source, osCommandPattern, 'once')) && ...
            ~ismember(relativePaths(index), approvedSystemPaths)
        osCommandFiles(end+1, 1) = relativePaths(index); %#ok<AGROW>
    end
end
addCheck("No hard-coded drive paths in MATLAB code", isempty(hardCodedFiles), ...
    missingDetail(cellstr(hardCodedFiles)));
addCheck("No unapproved external OS commands", isempty(osCommandFiles), ...
    missingDetail(cellstr(osCommandFiles)));

lowerPaths = lower(relativePaths);
hasCaseCollision = numel(unique(lowerPaths)) ~= numel(lowerPaths);
addCheck("No case-colliding MATLAB paths", ~hasCaseCollision, ...
    "Required for case-sensitive Linux filesystems");

report = table(checkName, passed, details, ...
    'VariableNames', {'Check','Passed','Details'});

    function addCheck(name, result, message)
        checkName(end+1, 1) = string(name);
        passed(end+1, 1) = logical(result);
        details(end+1, 1) = string(message);
    end
end

function detail = missingDetail(missing)
if isempty(missing)
    detail = "OK";
else
    detail = "Missing or flagged: " + strjoin(string(missing), ", ");
end
end
