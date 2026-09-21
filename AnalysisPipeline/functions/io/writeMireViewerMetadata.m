function metadataPath = writeMireViewerMetadata(result, outputFolder, cfg)
%WRITEMIREVIEWERMETADATA Export the geometry needed for a crop overlay.
%   Scientific mire coordinates remain in millimetres in the S03 CSVs.
%   Pixel dimensions in this companion JSON are visualization metadata only.

arguments
    result (1,1) struct
    outputFolder {mustBeTextScalar}
    cfg (1,1) struct
end

pre = result.Preprocessing;
sensorSizeMm = getProcessingSensorSizeMm(pre, cfg);
calibrationStatus = "UNCALIBRATED_REFERENCE_GEOMETRY";
if result.Calibration.IsDeviceSpecific
    calibrationStatus = "DEVICE_PROFILE_SET_REQUIRES_VALIDATION";
end

metadata = struct();
metadata.schemaVersion = "SmartKC-MireViewer-v1";
metadata.caseId = string(result.CaseId);
metadata.cropImageFile = "S01_crop.png";
metadata.cropCenterPx = double(pre.CenterPx(:).');            % [x, y]
metadata.cropSizePx = double(size(pre.Gray, [1, 2]));         % [height, width]
metadata.processingFullSizePx = double(pre.OriginalSize(:).'); % [height, width]
metadata.processingSensorSizeMm = double(sensorSizeMm(:).');   % [width, height]
metadata.spatialUnit = "mm";
metadata.coordinateFrame = ...
    "camera-sensor-plane; origin=detected-centre; x=right; y=superior";
metadata.calibrationStatus = calibrationStatus;
metadata.registryVersion = string(cfg.RegistryVersion);
[metadata.exifOrientation, missingExif] = fieldOrDefault( ...
    pre, 'ExifOrientation', 1);
[metadata.inputResizeScale, missingResizeScale] = fieldOrDefault( ...
    pre, 'InputResizeScale', 1);
metadata.compatibilityStatus = "CURRENT_PREPROCESSING_FIELDS";
if missingExif || missingResizeScale
    metadata.compatibilityStatus = ...
        "LEGACY_DEFAULTS_EXIF_ORIENTATION_1_INPUT_RESIZE_SCALE_1";
end

ensureFolder(outputFolder);
metadataPath = fullfile(outputFolder, 'S03_mire_viewer_metadata.json');
jsonText = jsonencode(metadata, PrettyPrint=true);
fileId = fopen(metadataPath, 'w', 'n', 'UTF-8');
if fileId < 0
    error('SmartKC:MireViewerMetadataWriteFailed', ...
        'Could not open mire-viewer metadata for writing: %s.', metadataPath);
end
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, '%s\n', jsonText);
end

function [value, usedDefault] = fieldOrDefault(structure, fieldName, defaultValue)
usedDefault = ~isfield(structure, fieldName) || ...
    isempty(structure.(fieldName));
if usedDefault
    value = double(defaultValue);
else
    value = double(structure.(fieldName));
end
end
