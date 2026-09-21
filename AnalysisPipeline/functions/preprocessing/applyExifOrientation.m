function oriented = applyExifOrientation(image, orientation)
%APPLYEXIFORIENTATION Transform raw pixels into the displayed orientation.

arguments
    image
    orientation (1,1) double {mustBeInteger, mustBeInRange(orientation, 1, 8)}
end

switch orientation
    case 1
        oriented = image;
    case 2
        oriented = fliplr(image);
    case 3
        oriented = rot90(image, 2);
    case 4
        oriented = flipud(image);
    case 5
        oriented = permute(image, [2, 1, 3]);
    case 6
        oriented = rot90(image, -1);
    case 7
        oriented = rot90(permute(image, [2, 1, 3]), 2);
    case 8
        oriented = rot90(image, 1);
end
end
