function [image, metadata] = readImageWithExifOrientation(imagePath)
%READIMAGEWITHEXIFORIENTATION Decode an image and apply EXIF orientation.

arguments
    imagePath (1,:) char
end

image = imread(imagePath);
information = imageInformationWithoutOptionalMetadataWarnings(imagePath);
orientation = exifOrientation(information(1));
rawSize = size(image, 1:2);
image = applyExifOrientation(image, orientation);
metadata = struct( ...
    'ExifOrientation', orientation, ...
    'ExifOrientationApplied', orientation ~= 1, ...
    'RawSourceSizePx', rawSize, ...
    'OrientedSourceSizePx', size(image, 1:2));
end

function information = imageInformationWithoutOptionalMetadataWarnings(imagePath)
warningState = warning;
restoreWarnings = onCleanup(@() warning(warningState));
warning('off', 'all');
information = imfinfo(imagePath);
end

function orientation = exifOrientation(information)
orientation = 1;
if isfield(information, 'Orientation') && ...
        isnumeric(information.Orientation) && isscalar(information.Orientation)
    orientation = double(information.Orientation);
elseif isfield(information, 'DigitalCamera') && ...
        isstruct(information.DigitalCamera) && ...
        isfield(information.DigitalCamera, 'Orientation')
    orientation = double(information.DigitalCamera.Orientation);
elseif isfield(information, 'UnknownTags') && ...
        ~isempty(information.UnknownTags)
    tags = information.UnknownTags;
    tagIndex = find([tags.ID] == 274, 1);
    if ~isempty(tagIndex)
        orientation = double(tags(tagIndex).Value(1));
    end
end
if ~ismember(orientation, 1:8)
    orientation = 1;
end
end
