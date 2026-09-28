function output = resizePillowNearest(input, outputSize)
%RESIZEPILLOWNEAREST Match Pillow nearest-neighbour resize coordinates.

arguments
    input (:,:)
    outputSize (1,2) double {mustBeInteger, mustBePositive}
end

[inputHeight, inputWidth] = size(input);
y = min(floor(((0:outputSize(1)-1) + 0.5) * ...
    inputHeight / outputSize(1)), inputHeight - 1) + 1;
x = min(floor(((0:outputSize(2)-1) + 0.5) * ...
    inputWidth / outputSize(2)), inputWidth - 1) + 1;
output = input(y, x);
end
