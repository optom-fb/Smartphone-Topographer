function [labelMap500, logits512, labelMap512, networkInput512] = ...
        predictSmartKCPPUNet( ...
        grayInput500, network, metadata)
%PREDICTSMARTKCPPUNET Run the pinned official preprocessing and U-Net.

arguments
    grayInput500
    network dlnetwork
    metadata struct
end

expectedCrop = double(metadata.ModelCropSizePx(:)');
if ~isequal(size(grayInput500, 1:2), expectedCrop)
    error('SmartKC:UNetCropSize', ...
        'SmartKC++ U-Net input must be %d-by-%d pixels.', expectedCrop);
end

if ~isa(grayInput500, 'uint8')
    grayInput500 = im2uint8(grayInput500);
end
networkSize = double(metadata.NetworkInputSizePx(:)');
resized = resizePillowBilinearUint8(grayInput500, networkSize);
rgb = repmat(im2single(resized), 1, 1, 3);
for channel = 1:3
    rgb(:, :, channel) = (rgb(:, :, channel) - metadata.InputMean(channel)) ./ ...
        metadata.InputStd(channel);
end

dlInput = dlarray(rgb, 'SSCB');
networkInput512 = rgb;
logits512 = extractdata(predict(network, dlInput));
if ndims(logits512) == 4
    logits512 = logits512(:, :, :, 1);
end
[~, oneBased] = max(logits512, [], 3);
labelMap512 = uint8(oneBased - 1);
labelMap500 = resizePillowNearest(labelMap512, expectedCrop);
end
