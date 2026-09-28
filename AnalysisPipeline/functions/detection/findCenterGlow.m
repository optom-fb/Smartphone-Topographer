function [center, bwFilled] = findCenterGlow(I)
% FINDCENTERGLOW (Rewritten for Enhanced/CLAHE Images)
% Finds the center of the Placido disk by locating the geometric 
% hub of the concentric ring structures.

    % 1. Ensure grayscale and double format
    if size(I, 3) == 3
        I = rgb2gray(I);
    end
    I = im2double(I);

    % 2. Clean up local artifacts and isolate ring edges
    % Instead of top-hatting a glow, we binarize the sharp mires directly
    bw_rings = imbinarize(I, 'adaptive', 'Sensitivity', 0.5);
    
    % 3. Fill the innermost ring completely to create a solid central core
    % This turns the center ring structure into a reliable solid circular mask
    bwFilled = imfill(bw_rings, 'holes');
    
    % 4. Find the properties of all connected structures
    stats = regionprops(bwFilled, 'Area', 'Circularity', 'Centroid', 'BoundingBox');
    
    if isempty(stats)
        error('Could not find any structures. Check image contrast.');
    end

    % 5. Filter for the true center:
    % The corneal ring hub will be highly circular (>0.75) and 
    % located near the middle region of the image matrix frame.
    [h, w] = size(I);
    imgCenter = [w/2, h/2];
    
    validIdx = [];
    minDist = Inf;
    bestIdx = 1;
    
    for k = 1:length(stats)
        % Check if the shape is reasonably circular
        if stats(k).Circularity > 0.65 && stats(k).Area > 500
            % Measure distance from the literal image center to avoid eyelash edges
            distFromImgCenter = sqrt(sum((stats(k).Centroid - imgCenter).^2));
            if distFromImgCenter < minDist
                minDist = distFromImgCenter;
                bestIdx = k;
            end
        end
    end
    
    % Extract the coordinates of our best central concentric hub match
    center = stats(bestIdx).Centroid;
    
    % 6. Recreate the precise working cornea boundary mask (cm) for the next steps
    % Generates a clean circular boundary centered on our found hub coordinates
    [X, Y] = meshgrid(1:w, 1:h);
    bwFilled = (X - center(1)).^2 + (Y - center(2)).^2 <= 380^2; 

end
