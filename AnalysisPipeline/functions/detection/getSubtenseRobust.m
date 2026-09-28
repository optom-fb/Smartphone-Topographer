function [subtense, isLongArc] = getSubtenseRobust(X, Y, centerPoint)
    % 1. Safety check: Need at least 3 non-collinear points for a proper hull
    % If points are effectively a line, convhull still works but returns 2 pts.
    try
        k = convhull(X, Y, 'Simplify', true);
    catch
        % If convhull fails (e.g., all points identical), 
        % treat as a single point/line.
        k = [1; length(X)]; 
    end
    
    hullX = X(k);
    hullY = Y(k);
    
    % 2. Check if center is inside silhouette
    % Note: If data is perfectly collinear, this is almost always false.
    isLongArc = inpolygon(centerPoint(1), centerPoint(2), hullX, hullY);
    
    % 3. Calculate angles of hull vertices relative to center
    hullAngles = atan2d(hullY - centerPoint(2), hullX - centerPoint(1));
    
    % Unique is important here: if hull is a line, we only want the two tips
    hullAngles = sort(mod(unique(hullAngles), 360));
    
    if numel(hullAngles) < 2
        subtense = 0;
        return;
    end
    
    % 4. Find the gaps
    gaps = [diff(hullAngles); (hullAngles(1) + 360) - hullAngles(end)];
    maxGap = max(gaps);
    
    % The subtense is the "filled" part of the circle
    subtense = 360 - maxGap;
end