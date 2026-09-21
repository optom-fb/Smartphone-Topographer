function [projectRoot, cfg] = initializeSmartKCProject(callerFile)
%INITIALIZESMARTKCPROJECT Add project code folders and load configuration.

arguments
    callerFile (1,:) char = mfilename('fullpath')
end

callerFolder = fileparts(callerFile);
if endsWith(callerFolder, [filesep 'scripts']) || ...
        endsWith(callerFolder, [filesep 'tests'])
    projectRoot = fileparts(callerFolder);
else
    probe = callerFolder;
    while ~isempty(probe) && ~isfolder(fullfile(probe, 'config'))
        parent = fileparts(probe);
        if strcmp(parent, probe)
            break
        end
        probe = parent;
    end
    projectRoot = probe;
end

if ~isfolder(fullfile(projectRoot, 'config'))
    error('SmartKC:ProjectRootNotFound', ...
        'Could not locate the SmartKC project root from %s.', callerFile);
end

addpath(fullfile(projectRoot, 'config'));
addpath(genpath(fullfile(projectRoot, 'functions')));
cfg = smartKCConstants(projectRoot);
end
