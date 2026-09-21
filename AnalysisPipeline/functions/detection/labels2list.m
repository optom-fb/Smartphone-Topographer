function pixelList = labels2list(bwImage)
    % LABELS2LIST Converts a label image into a sorted list of pixel data.
    %
    % INPUT:
    %   bwImage   - A 2D matrix where 0 represents background and 
    %               positive integers represent different object labels.
    %
    % OUTPUT:
    %   pixelList - A table containing columns: [Label, X, Y, LinearIndex]
    %               sorted by increasing label value.

    % 1. Find all pixels that belong to a labeled object (not 0)
    linearIndices = find(bwImage > 0);
    
    % 2. Extract the actual label values for those pixels
    labels = bwImage(linearIndices);
    
    % 3. Convert linear indices to X (column) and Y (row) spatial coordinates
    [Y, X] = ind2sub(size(bwImage), linearIndices);
    
    % 4. Sort everything by increasing label value
    [sortedLabels, sortIdx] = sort(labels, 'ascend');
    
    % Apply the sorting order to the remaining variables
    sortedX = X(sortIdx);
    sortedY = Y(sortIdx);
    sortedLinearIndices = linearIndices(sortIdx);
    
    % 5. Package results into a clean, easy-to-read table
    pixelList = table(sortedLabels, sortedX, sortedY, sortedLinearIndices, ...
        'VariableNames', {'Label', 'X', 'Y', 'LinearIndex'});
end