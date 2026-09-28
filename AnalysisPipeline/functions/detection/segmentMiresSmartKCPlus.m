function segmentation = segmentMiresSmartKCPlus(pre, cfg)
%SEGMENTMIRESSMARTKCPLUS Run validated SmartKC++ U-Net or named fallback.
%   Only a model bundle that passed parity against the pinned official
%   PyTorch checkpoint is reported as the SmartKC++ U-Net path.

modelFile = cfg.segmentation.UNetModelFile;
executionMode = "auto";
if isfield(cfg.segmentation, 'ExecutionMode')
    executionMode = string(cfg.segmentation.ExecutionMode);
end
if executionMode == "robust-classical-synthetic"
    reason = MException('SmartKC:SyntheticClassicalMode', ...
        ['The matched synthetic runner intentionally uses the robust ' ...
        'classical SmartKC++ segmentation regression.']);
    segmentation = fallbackSegmentation(pre, cfg, modelFile, reason);
    segmentation.MethodRequested = "smartkcpp-robust-classical-synthetic";
    return
elseif executionMode ~= "auto"
    error('SmartKC:InvalidSegmentationExecutionMode', ...
        'Unsupported segmentation execution mode: %s.', executionMode);
end
try
    if ~isfile(modelFile)
        error('SmartKC:UNetModelMissing', ...
            'SmartKC++ U-Net model not found: %s', modelFile);
    end
    [network, metadata] = loadValidatedModel(modelFile, cfg);
    cropSize = double(metadata.ModelCropSizePx(:)');
    [grayCrop, placement] = extractCenteredCrop( ...
        pre.Gray, pre.CenterPx, cropSize);
    [labelCrop, ~, ~] = predictSmartKCPPUNet(grayCrop, network, metadata);
    labelMap = placeCrop(labelCrop, size(pre.Gray), placement);
catch exception
    if ~cfg.segmentation.AllowClassicalFallback
        rethrow(exception)
    end
    warning('SmartKC:UNetUnavailable', ...
        'SmartKC++ U-Net unavailable (%s); using the explicit fallback.', ...
        exception.message);
    segmentation = fallbackSegmentation(pre, cfg, modelFile, exception);
    return
end

[height, width] = size(labelMap);
[xx, yy] = meshgrid(1:width, 1:height);
radius = hypot(xx-pre.CenterPx(1), yy-pre.CenterPx(2));
annulus = radius >= cfg.localization.InnerRadiusPx & ...
    radius <= pre.AnalysisRadiusPx;
mask = labelMap ~= metadata.BackgroundClassZeroBased & annulus;
mask = bwareaopen(mask, cfg.segmentation.MinimumComponentAreaPx, 8);
labelMap(~mask) = uint8(metadata.BackgroundClassZeroBased);

segmentation = struct();
segmentation.Mask = mask;
segmentation.LabelMapZeroBased = labelMap;
segmentation.Response = single(mask);
segmentation.MethodRequested = "smartkcpp-unet";
segmentation.MethodActual = "smartkcpp-official-unet-matlab";
segmentation.ModelFile = string(modelFile);
segmentation.ModelValidated = true;
segmentation.ModelSourceCommit = string(metadata.SourceCommit);
segmentation.ModelCheckpointSha256 = string(metadata.CheckpointSha256);
segmentation.ModelFormatVersion = string(metadata.FormatVersion);
segmentation.ModelInputCropRectanglePx = placement.RequestedRectanglePx;
segmentation.UsedFallback = false;
segmentation.FallbackReason = "";
segmentation.Threshold = NaN;
segmentation.ForegroundFraction = mean(mask(annulus));
end

function [network, metadata] = loadValidatedModel(modelFile, cfg)
persistent cachedFile cachedBytes cachedDate cachedNetwork cachedMetadata
modelInfo = dir(modelFile);
sameFile = ~isempty(cachedFile) && string(cachedFile) == string(modelFile) && ...
    cachedBytes == modelInfo.bytes && cachedDate == modelInfo.datenum;
if sameFile
    network = cachedNetwork;
    metadata = cachedMetadata;
    return
end

variableNames = string(who('-file', modelFile));
if ~all(ismember(["network", "metadata"], variableNames))
    error('SmartKC:UNetModelContract', ...
        'Model MAT-file must contain a dlnetwork and validation metadata.');
end
modelData = load(modelFile, 'network', 'metadata');
if ~isa(modelData.network, 'dlnetwork')
    error('SmartKC:UNetModelContract', ...
        'The validated SmartKC++ network must be a MATLAB dlnetwork.');
end
metadata = modelData.metadata;
requiredFields = {'FormatVersion','SourceCommit','CheckpointSha256', ...
    'ModelCropSizePx','NetworkInputSizePx','InputMean','InputStd', ...
    'ClassCount','BackgroundClassZeroBased','ParityValidated'};
if ~all(isfield(metadata, requiredFields)) || ...
        string(metadata.FormatVersion) ~= "SmartKCPP-UNet-MATLAB-v1" || ...
        ~isequal(metadata.ParityValidated, true)
    error('SmartKC:UNetModelNotValidated', ...
        'SmartKC++ U-Net bundle lacks successful parity validation.');
end
if string(metadata.SourceCommit) ~= cfg.segmentation.UNetSourceCommit || ...
        lower(string(metadata.CheckpointSha256)) ~= ...
        lower(cfg.segmentation.UNetCheckpointSha256)
    error('SmartKC:UNetModelProvenance', ...
        'SmartKC++ U-Net commit or checkpoint SHA-256 does not match config.');
end

network = modelData.network;
cachedFile = modelFile;
cachedBytes = modelInfo.bytes;
cachedDate = modelInfo.datenum;
cachedNetwork = network;
cachedMetadata = metadata;
end

function segmentation = fallbackSegmentation(pre, cfg, modelFile, exception)
segmentation = segmentMiresClassical(pre, cfg, "robust");
segmentation.MethodRequested = "smartkcpp-unet";
segmentation.MethodActual = "robust-classical-fallback";
segmentation.ModelFile = string(modelFile);
segmentation.ModelValidated = false;
segmentation.ModelSourceCommit = "";
segmentation.ModelCheckpointSha256 = "";
segmentation.ModelFormatVersion = "";
segmentation.ModelInputCropRectanglePx = [NaN, NaN, NaN, NaN];
segmentation.UsedFallback = true;
segmentation.FallbackReason = string(exception.identifier) + ": " + ...
    string(exception.message);
end

function [crop, placement] = extractCenteredCrop(image, centerPx, cropSize)
image = im2uint8(image);
cropHeight = cropSize(1);
cropWidth = cropSize(2);
x1 = round(centerPx(1)) - floor(cropWidth / 2) + 1;
y1 = round(centerPx(2)) - floor(cropHeight / 2) + 1;
x2 = x1 + cropWidth - 1;
y2 = y1 + cropHeight - 1;

sourceX1 = max(1, x1);
sourceY1 = max(1, y1);
sourceX2 = min(size(image, 2), x2);
sourceY2 = min(size(image, 1), y2);
destinationX1 = sourceX1 - x1 + 1;
destinationY1 = sourceY1 - y1 + 1;
destinationX2 = destinationX1 + sourceX2 - sourceX1;
destinationY2 = destinationY1 + sourceY2 - sourceY1;

crop = zeros(cropHeight, cropWidth, 'uint8');
crop(destinationY1:destinationY2, destinationX1:destinationX2) = ...
    image(sourceY1:sourceY2, sourceX1:sourceX2);
placement = struct();
placement.RequestedRectanglePx = [x1, y1, cropWidth, cropHeight];
placement.SourceX = sourceX1:sourceX2;
placement.SourceY = sourceY1:sourceY2;
placement.DestinationX = destinationX1:destinationX2;
placement.DestinationY = destinationY1:destinationY2;
end

function output = placeCrop(crop, outputSize, placement)
output = zeros(outputSize, 'uint8');
output(placement.SourceY, placement.SourceX) = ...
    crop(placement.DestinationY, placement.DestinationX);
end
