function plotCleanSegmentsNoJumps(T, highlighted, useRings)
    % plotCleanSegmentsNoJumps
    % Breaks the line using NaNs if the distance between sequential 
    % sorted points exceeds a normal step threshold.

    arguments
        T                   % Required input
        highlighted = [];  % Optional input, defaults to empty matrix
        useRings = false;
    end

    if (~useRings)
        uniqueLabels = unique(T.Label);
        whichField = 'Label';
    else
        uniqueLabels = unique(T.RingNumber);    
        whichField = 'RingNumber';
    end

    numLabels = numel(uniqueLabels);
    colors = lines(numLabels); 

    % figure('Color', 'w');
    hold on; grid on;
    
    for i = 1:numLabels
        currentLabel = uniqueLabels(i);

        subT = T(T.(whichField) == currentLabel, :);

        if height(subT) < 2
            plot(subT.X, subT.Y, '.', 'Color', colors(i,:));
            continue;
        end

        pts = [subT.X, subT.Y];
        numPts = size(pts, 1);

        % 1. Find the true endpoints of the segment (furthest pair) [1]
        X_diff = pts(:,1) - pts(:,1)';
        Y_diff = pts(:,2) - pts(:,2)';
        distSq = X_diff.^2 + Y_diff.^2; 
        
        [~, maxValIdx] = max(distSq(:));
        [startIdx, ~] = ind2sub(size(distSq), maxValIdx);

        % 2. Run Nearest Neighbor sorting [1]
        sortedIdx = zeros(numPts, 1);
        visited = false(numPts, 1);
        
        currIdx = startIdx;
        sortedIdx(1) = currIdx;
        visited(currIdx) = true;
        
        for k = 2:numPts
            lastPt = pts(currIdx, :);
            dists = sum((pts - lastPt).^2, 2);
            dists(visited) = Inf; 
            
            [~, nextIdx] = min(dists);
            sortedIdx(k) = nextIdx;
            visited(nextIdx) = true;
            currIdx = nextIdx;
        end
        
        % Use the sorted order
        x = pts(sortedIdx, 1);
        y = pts(sortedIdx, 2);
        col = colors(i, :);

        % 3. Calculate step distances to identify "jumps"
        stepDists = sqrt(diff(x).^2 + diff(y).^2);
        
        % Establish a threshold for a "jump". 
        % For pixel-based data, adjacent steps are roughly 1 to 1.4 pixels.
        % We scale this threshold dynamically to support non-pixel coordinates too.
        medStep = median(stepDists);
        if isempty(medStep) || isnan(medStep) || medStep < 1e-5
            maxLineGap = 2.5; 
        else
            maxLineGap = max(2.5, 2.5 * medStep);
        end
        
        % Find where the jumps occur
        jumpIdx = find(stepDists > maxLineGap);
        
        x_plot = double(x);
        y_plot = double(y);
        
        % 4. Insert NaNs to break the line at those jump points
        if ~isempty(jumpIdx)
            newX = [];
            newY = [];
            lastIdx = 1;
            for j = 1:numel(jumpIdx)
                idx = jumpIdx(j);
                newX = [newX; x_plot(lastIdx:idx); NaN];
                newY = [newY; y_plot(lastIdx:idx); NaN];
                lastIdx = idx + 1;
            end
            newX = [newX; x_plot(lastIdx:end)];
            newY = [newY; y_plot(lastIdx:end)];
            x_plot = newX;
            y_plot = newY;
        end

        % 5. Plot the broken path
        % Points after the NaN will show up as markers, but won't have line connections

        if ismember(currentLabel, highlighted)
            lineWidth = 3;
        else
            lineWidth = 1;
        end

        plot(x_plot, y_plot, '.-', 'Color', col, 'MarkerSize', 6, 'LineWidth', lineWidth);
        

        % 6. Place the text label at the end of the *main continuous* branch 
        % (i.e., right before the first jump happens)
        if ~isempty(jumpIdx)
            labelIdx = jumpIdx(1);
        else
            labelIdx = numPts;
        end
        
        text(x(labelIdx), y(labelIdx), num2str(currentLabel), ...
            'FontSize', 8, ...
            'FontWeight', 'bold', ...
            'Color', 'w', ...
            'BackgroundColor', col, ...
            'Margin', 0.5, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle');
    end
    
    xlabel('X'); ylabel('Y');
    title('Segments with Automatic Jump Prevention');
    hold off;
end