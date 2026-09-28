function pre = preprocessPlacidoImage(imagePath, cfg)
%PREPROCESSPLACIDOIMAGE Decode, centre, crop and normalize a mire image.

arguments
    imagePath (1,:) char
    cfg struct
end

if ~isfile(imagePath)
    error('SmartKC:InputNotFound', 'Input image not found: %s', imagePath);
end

[raw, sourceMetadata] = readImageWithExifOrientation(imagePath);
if ismatrix(raw)
    rgb = repmat(raw, 1, 1, 3);
elseif size(raw, 3) >= 3
    rgb = raw(:, :, 1:3);
else
    error('SmartKC:UnsupportedImage', 'Unsupported channel count in %s.', imagePath);
end
[sourceHeight, sourceWidth, ~] = size(rgb);
processingSensorSizeMm = double(cfg.camera.SensorSizeMm(:).');
if ismember(sourceMetadata.ExifOrientation, 5:8)
    processingSensorSizeMm = processingSensorSizeMm([2, 1]);
end
inputResizeScale = min(1, cfg.preprocessing.InputMaximumSizePx / ...
    max(sourceHeight, sourceWidth));
if inputResizeScale < 1
    rgb = imresize(rgb, inputResizeScale, 'bilinear');
end
rgbSingle = im2single(rgb);
grayFull = rgb2gray(rgbSingle);
[centerFullPx, centerDiagnostics] = estimatePlacidoCenter(grayFull, cfg);
[height, width] = size(grayFull);
if cfg.pupil.Enabled
    try
        pupil = detectPupilPlacidoStyle(rgb, centerFullPx, cfg);
    catch exception
        pupil = failedPupil(string(exception.message), cfg);
    end
else
    pupil = failedPupil("Disabled in configuration.", cfg);
    pupil.Enabled = false;
    pupil.DetectionStatus = "DISABLED";
end

cropSize = min([cfg.preprocessing.CropSizePx, height, width]);
cropSize = max(min(cfg.preprocessing.MinimumCropSizePx, min(height, width)), cropSize);
cropSize = 2 * floor(cropSize / 2);
half = cropSize / 2;
x1 = round(centerFullPx(1)) - half + 1;
y1 = round(centerFullPx(2)) - half + 1;
x1 = min(max(x1, 1), width - cropSize + 1);
y1 = min(max(y1, 1), height - cropSize + 1);
x2 = x1 + cropSize - 1;
y2 = y1 + cropSize - 1;

rgbCrop = rgbSingle(y1:y2, x1:x2, :);
grayCrop = grayFull(y1:y2, x1:x2);
centerPx = centerFullPx - [x1 - 1, y1 - 1];
pupilCfg = cfg;
pupilCfg.camera.SensorSizeMm = processingSensorSizeMm;
pupil = addPupilCoordinateFrames(pupil, [x1, y1], ...
    [height, width], centerFullPx, pupilCfg);

background = imgaussfilt(grayCrop, cfg.preprocessing.FlatFieldSigmaPx, ...
    'FilterSize', 2 * ceil(2 * cfg.preprocessing.FlatFieldSigmaPx) + 1);
normalized = grayCrop ./ max(background, 0.05);
validRadius = min([centerPx(1)-1, centerPx(2)-1, ...
    cropSize-centerPx(1), cropSize-centerPx(2)]);
validRadius = max(10, cfg.preprocessing.AnalysisRadiusFraction * 2 * validRadius);
[xx, yy] = meshgrid(1:cropSize, 1:cropSize);
roi = hypot(xx-centerPx(1), yy-centerPx(2)) <= validRadius;
limits = prctile(normalized(roi), [1, 99]);
normalized = rescale(normalized, 0, 1, 'InputMin', limits(1), 'InputMax', limits(2));

gradientMagnitude = imgradient(imgaussfilt(normalized, 0.7));
saturationMask = any(rgbCrop >= 0.999, 3);
focusScore = median(gradientMagnitude(roi), 'omitnan');
saturationFraction = mean(saturationMask(roi), 'omitnan');
frameCenter = [width, height] / 2;
centerOffsetFraction = norm(centerFullPx-frameCenter) / min(width, height);
quality = struct();
quality.FocusScore = focusScore;
quality.SaturationFraction = saturationFraction;
quality.CenterOffsetFraction = centerOffsetFraction;
quality.PassesFocus = focusScore >= cfg.quality.MinimumFocusScore;
quality.PassesSaturation = saturationFraction <= cfg.quality.MaximumSaturationFraction;
quality.PassesCentering = centerOffsetFraction <= cfg.quality.MaximumCenterOffsetFraction;
quality.IsAcceptedForSegmentation = quality.PassesFocus && quality.PassesSaturation;

[~, imageId, extension] = fileparts(imagePath);
pre = struct();
pre.ImageId = string(imageId);
pre.CaseId = deriveCaseId(imagePath);
pre.SourcePath = string(imagePath);
pre.Extension = string(extension);
pre.SourceOriginalSize = [sourceHeight, sourceWidth];
pre.RawSourceSize = sourceMetadata.RawSourceSizePx;
pre.ExifOrientation = sourceMetadata.ExifOrientation;
pre.ExifOrientationApplied = sourceMetadata.ExifOrientationApplied;
pre.OriginalSize = [height, width];
pre.InputResizeScale = inputResizeScale;
pre.ProcessingSensorSizeMm = processingSensorSizeMm;
pre.RGB = rgbCrop;
pre.Gray = grayCrop;
pre.NormalizedGray = normalized;
pre.CenterFullPx = centerFullPx;
pre.CenterSourcePx = processingPointToSource(centerFullPx, ...
    inputResizeScale);
pre.CenterPx = centerPx;
pre.CropRectangleFullPx = [x1, y1, cropSize, cropSize];
pre.CropRectangleSourcePx = processingRectangleToSource( ...
    pre.CropRectangleFullPx, inputResizeScale);
pre.AnalysisRadiusPx = validRadius;
pre.CenterDiagnostics = centerDiagnostics;
pre.Pupil = pupil;
pre.Quality = quality;
pre.RegistryVersion = string(cfg.RegistryVersion);
end

function sourcePoint = processingPointToSource(processingPoint, scale)
sourcePoint = (processingPoint-0.5)/scale+0.5;
end

function sourceRectangle = processingRectangleToSource(rectangle, scale)
sourceRectangle = [processingPointToSource(rectangle(1:2), scale), ...
    rectangle(3:4)/scale];
end

function pupil = failedPupil(message, cfg)
pupil = struct('Enabled', logical(cfg.pupil.Enabled), ...
    'Method', "placido-dark-circle-review", ...
    'SourceFrameMode', string(cfg.pupil.SourceFrameMode), ...
    'IsValid', false, 'CenterFullPx', [NaN, NaN], ...
    'CenterPx', [NaN, NaN], 'RadiusPx', NaN, 'DiameterPx', NaN, ...
    'Metric', NaN, 'Score', NaN, 'ExpectedCenterFullPx', [NaN, NaN], ...
    'OffsetFromPlacidoCenterPx', [NaN, NaN], ...
    'OffsetMagnitudePx', NaN, 'SearchRegionFullPx', [NaN, NaN, NaN, NaN], ...
    'DetectionScale', NaN, 'Candidates', table(), ...
    'FailureReason', string(message), ...
    'Warning', "Review-only pupil estimate; not a clinical measurement.", ...
    'DetectionStatus', "ERROR");
end
