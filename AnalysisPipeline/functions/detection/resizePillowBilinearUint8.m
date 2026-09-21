function output = resizePillowBilinearUint8(input, outputSize)
%RESIZEPILLOWBILINEARUINT8 Match Pillow bilinear resizing for uint8 images.
%   Pillow performs separable interpolation and rounds to uint8 after both
%   the horizontal and vertical passes. MATLAB imresize rounds after the
%   combined interpolation, which can change U-Net logits near class ties.

arguments
    input (:,:) uint8
    outputSize (1,2) double {mustBeInteger, mustBePositive}
end

[inputHeight, inputWidth] = size(input);
outputHeight = outputSize(1);
outputWidth = outputSize(2);

[x0, x1, xWeight] = sampleCoordinates(inputWidth, outputWidth);
horizontal = (1 - xWeight) .* single(input(:, x0)) + ...
    xWeight .* single(input(:, x1));
horizontal = uint8(floor(horizontal + 0.5));

[y0, y1, yWeight] = sampleCoordinates(inputHeight, outputHeight);
verticalWeight = yWeight(:);
output = (1 - verticalWeight) .* single(horizontal(y0, :)) + ...
    verticalWeight .* single(horizontal(y1, :));
output = uint8(floor(output + 0.5));
end

function [lowerIndex, upperIndex, weight] = sampleCoordinates( ...
        inputLength, outputLength)
position = ((0:outputLength-1) + 0.5) * inputLength / outputLength - 0.5;
position = min(max(position, 0), inputLength - 1);
lowerZeroBased = floor(position);
upperZeroBased = min(lowerZeroBased + 1, inputLength - 1);
weight = single(position - lowerZeroBased);
lowerIndex = lowerZeroBased + 1;
upperIndex = upperZeroBased + 1;
end
