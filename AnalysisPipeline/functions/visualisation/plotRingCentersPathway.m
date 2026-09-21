function plotRingCentersPathway(finalTbl, xc, yc)
    % Extracts the true geometric center of each detected ring using 
    % an algebraic least-squares circle fit (robust to incomplete/cut-off rings).
    
    rings = unique(finalTbl.RingNumber);
    numRings = length(rings);
    
    if numRings < 2
        warning('Not enough rings detected to plot a pathway.');
        return;
    end
    
    centersX = zeros(numRings, 1);
    centersY = zeros(numRings, 1);
    
    for i = 1:numRings
        ringData = finalTbl(finalTbl.RingNumber == rings(i), :);
        X = ringData.X;
        Y = ringData.Y;
        
        % We need at least 3 points to fit a circle
        if length(X) >= 3
            % Algebraic least-squares circle fit formulation:
            % 2*x*xc + 2*y*yc + C = x^2 + y^2
            A = [2*X, 2*Y, ones(size(X))];
            B = X.^2 + Y.^2;
            
            % Solve linear system via least squares
            P = A \ B;
            fit_xc = P(1);
            fit_yc = P(2);
            
            % Sanity Check: If the fitted center drifts too far from the 
            % global center glow (e.g. > 40 pixels) due to noise, fallback gracefully.
            if norm([fit_xc - xc, fit_yc - yc]) < 40
                centersX(i) = fit_xc;
                centersY(i) = fit_yc;
            else
                centersX(i) = xc;
                centersY(i) = yc;
            end
        else
            centersX(i) = xc;
            centersY(i) = yc;
        end
    end
    
    % Plot the pathway connecting the geometric centers (Cyan line)
    plot(centersX, centersY, 'c-', 'LineWidth', 2.5);
    
    % Plot individual ring center markers (Yellow dots)
    plot(centersX, centersY, 'yo', 'MarkerFaceColor', 'y', 'MarkerSize', 5);
    
    % Label the first ring center for orientation
    text(centersX(1), centersY(1), ' Ring 1 Center', 'Color', 'yellow', 'FontSize', 9, 'FontWeight', 'bold');
end