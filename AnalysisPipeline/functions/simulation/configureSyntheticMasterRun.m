function [cfg, isSynthetic, truthPath] = ...
        configureSyntheticMasterRun(imagePath, cfg)
%CONFIGURESYNTHETICMASTERRUN Apply matched settings to a tracked fixture.
%   Real images are returned unchanged. A file is recognized only when it
%   has a same-stem truth MAT in the sibling GroundTruth directory and that
%   MAT identifies the project's simulator.

arguments
    imagePath (1,:) char
    cfg struct
end

isSynthetic = false;
truthPath = "";
[imageFolder, stem] = fileparts(imagePath);
[syntheticRoot, imageFolderName] = fileparts(imageFolder);
candidateTruthPath = fullfile(syntheticRoot, 'GroundTruth', [stem, '.mat']);
if ~strcmp(imageFolderName, 'Images') || ~isfile(candidateTruthPath)
    return
end

loaded = load(candidateTruthPath, 'truth');
if ~isfield(loaded, 'truth') || ~isfield(loaded.truth, 'generator') || ...
        string(loaded.truth.generator) ~= "simulatePlacidoImage" || ...
        ~isfield(loaded.truth, 'calibration') || ...
        ~isfield(loaded.truth.calibration, 'effectiveSensorSizeMm')
    return
end

cfg.camera.SensorSizeMm = ...
    double(loaded.truth.calibration.effectiveSensorSizeMm);
cfg.calibration.IsDeviceSpecific = true;
cfg.calibration.MireIdentityAnchorValidated = false;
cfg.calibration.MireIdentityAnchorNotes = ...
    "Matched geometry does not guarantee observability of physical mire 1.";
cfg.calibration.ProfileName = "Matched deterministic synthetic fixture";
cfg.calibration.Notes = [
    "Synthetic truth geometry; never use this profile for a real image."
    "Robust classical segmentation selected for synthetic regression."
    ];
cfg.localization.InnerRadiusPx = 4;
cfg.preprocessing.PupilRadiusFraction = [0.018, 0.04];
cfg.segmentation.ExecutionMode = "robust-classical-synthetic";
isSynthetic = true;
truthPath = string(candidateTruthPath);
end
