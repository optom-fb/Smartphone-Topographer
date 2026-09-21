function cropped = cropSyntheticTruthToPreprocessed(truth, pre)
%CROPSYNTHETICTRUTHTOPREPROCESSED Align full-frame truth with pipeline crop.

required = {'segmentation','centerPixels'};
if ~all(isfield(truth, required)) || ...
        ~all(isfield(truth.segmentation, ...
        {'BinaryMireMask','MireLabelMap'}))
    error('SmartKC:Simulation:MissingSegmentationTruth', ...
        'Truth bundle does not contain segmentation mask and label maps.');
end

rectangle = round(pre.CropRectangleFullPx);
x1 = rectangle(1);
y1 = rectangle(2);
x2 = x1 + rectangle(3) - 1;
y2 = y1 + rectangle(4) - 1;
fullMask = truth.segmentation.BinaryMireMask;
fullLabels = truth.segmentation.MireLabelMap;
if x1 < 1 || y1 < 1 || x2 > size(fullMask, 2) || ...
        y2 > size(fullMask, 1)
    error('SmartKC:Simulation:TruthCropOutsideImage', ...
        'Preprocessing crop lies outside the synthetic truth image.');
end

cropped = struct();
cropped.BinaryMireMask = logical(fullMask(y1:y2, x1:x2));
cropped.MireLabelMap = uint8(fullLabels(y1:y2, x1:x2));
cropped.CropRectangleFullPx = rectangle;
cropped.CenterPx = truth.centerPixels - [x1 - 1, y1 - 1];
end
