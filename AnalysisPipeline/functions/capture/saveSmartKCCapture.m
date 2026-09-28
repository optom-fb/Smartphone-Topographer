function record = saveSmartKCCapture(imageData, options)
%SAVESMARTKCCAPTURE Save an image plus an auditable capture-metadata sidecar.

arguments
    imageData {mustBeNumeric, mustBeNonempty}
    options.ProjectRoot (1,1) string
    options.ImageId (1,1) string
    options.PseudoId (1,1) string
    options.Laterality (1,1) string = "unknown"
    options.SourceMode (1,1) string = "external-camera"
    options.CaptureAppVersion (1,1) string = "unversioned"
    options.RegistryVersion (1,1) string = "unknown"
    options.CameraAdaptor (1,1) string = ""
    options.CameraName (1,1) string = ""
    options.CameraDeviceId (1,1) string = ""
    options.CaptureFormat (1,1) string = ""
    options.CalibrationProfile (1,1) string = "unassigned"
    options.WorkingDistanceMm (1,1) double = NaN
    options.CameraSettings (1,1) string = "{}"
    options.OriginalSourcePath (1,1) string = ""
    options.OperatorNotes (1,1) string = ""
end

imageId = normalizeCaptureId(options.ImageId, "Image ID");
pseudoId = normalizeCaptureId(options.PseudoId, "Pseudo-ID");
laterality = lower(strtrim(options.Laterality));
if ~any(laterality == ["right", "left", "unknown"])
    error('SmartKC:InvalidLaterality', ...
        'Laterality must be right, left, or unknown.');
end

captureTime = datetime('now', 'TimeZone', 'UTC');
dateFolder = char(string(captureTime, 'yyyyMMdd'));
outputFolder = fullfile(options.ProjectRoot, 'Data', 'Captured', ...
    char(pseudoId), dateFolder);
ensureFolder(outputFolder);

if strlength(imageId) > 25
    error('SmartKC:CaptureImageIdTooLong', ...
        ['Image ID must use at most 25 filename-safe characters so the ' ...
        'downstream CaseID remains within 32 characters.']);
end
baseStem = imageId + "_" + extractBetween(laterality, 1, 1);
stem = nextAvailableStem(outputFolder, baseStem);
imagePath = fullfile(outputFolder, char(stem + ".png"));
metadataPath = fullfile(outputFolder, char(stem + "_capture.csv"));
imwrite(imageData, imagePath, 'png');

quality = assessSmartKCCapture(imageData);
record = table( ...
    stem, imageId, pseudoId, laterality, captureTime, options.SourceMode, ...
    options.CaptureAppVersion, options.RegistryVersion, ...
    options.CameraAdaptor, options.CameraName, options.CameraDeviceId, ...
    options.CaptureFormat, size(imageData, 2), size(imageData, 1), ...
    options.CalibrationProfile, ...
    options.WorkingDistanceMm, options.CameraSettings, ...
    quality.MeanIntensity, quality.DarkFraction, ...
    quality.SaturatedFraction, quality.FocusScore, quality.Status, ...
    options.OriginalSourcePath, options.OperatorNotes, string(imagePath), ...
    'VariableNames', {'CaptureId', 'ImageId', 'PseudoId', 'Laterality', ...
    'CaptureTimeUtc', 'SourceMode', 'CaptureAppVersion', 'RegistryVersion', ...
    'CameraAdaptor', 'CameraName', ...
    'CameraDeviceId', 'CaptureFormat', 'ImageWidthPx', 'ImageHeightPx', ...
    'CalibrationProfile', 'WorkingDistanceMm', 'CameraSettingsJson', ...
    'MeanIntensity', 'DarkFraction', 'SaturatedFraction', 'FocusScore', ...
    'CaptureQcStatus', 'OriginalSourcePath', 'OperatorNotes', 'ImagePath'});
writetable(record, metadataPath);

record.ImagePath = string(imagePath);
record.MetadataPath = string(metadataPath);
record.QualityMessage = quality.Message;
end

function stem = nextAvailableStem(outputFolder, baseStem)
stem = baseStem;
if isStemAvailable(outputFolder, stem)
    return
end
for captureNumber = 2:9999
    candidate = baseStem + "_" + compose('%02d', captureNumber);
    if isStemAvailable(outputFolder, candidate)
        stem = candidate;
        return
    end
end
error('SmartKC:CaptureNameExhausted', ...
    'No unused capture filename remains for %s.', baseStem);
end

function result = isStemAvailable(outputFolder, stem)
result = ~isfile(fullfile(outputFolder, char(stem + ".png"))) && ...
    ~isfile(fullfile(outputFolder, char(stem + "_capture.csv")));
end
