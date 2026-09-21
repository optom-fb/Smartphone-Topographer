function bwClean = bwRobustSurgicalPrune(bw, center, angleThresh)
    % center: [cx, cy]
    % angleThresh: Stop pruning if local angle > angleThresh (default 40)
    
    if nargin < 3, angleThresh = 40; end
    lookahead = 5;      % How many pixels ahead to look for direction
    stopPatience = 3;   % Must see tangential trend for 3 steps to stop

    skel = bwskel(bw > 0);
    [rows, cols] = size(bw);
    cx = center(1); cy = center(2);
    
    endpoints = bwmorph(skel, 'endpoints');
    [ey, ex] = find(endpoints);
    pixelsToRemove = false(rows, cols);
    
    for i = 1:length(ex)
        % 1. Trace the entire segment once to get an ordered list of pixels
        % (Using a simple neighbor-following trace)
        path = traceSkeletonPath(skel, [ex(i), ey(i)]);
        if size(path, 1) < 5, continue; end
        
        % 2. Walk the path with a windowed direction check
        numPruned = 0;
        consecutiveTangential = 0;
        
        for k = 1 : (size(path, 1) - lookahead)
            currP = path(k, :);
            aheadP = path(k + lookahead, :);
            
            % Direction Vector (smoothed over the 'lookahead' window)
            vPath = [aheadP(1) - currP(1), aheadP(2) - currP(2)];
            % Radial Vector
            vRadial = [currP(1) - cx, currP(2) - cy];
            
            % Angle between path and radius
            dotProd = dot(vPath, vRadial) / (norm(vPath) * norm(vRadial));
            angleDeg = acosd(max(min(abs(dotProd), 1), -1));
            
            if angleDeg < angleThresh
                % Still radial
                numPruned = k;
                consecutiveTangential = 0;
            else
                % Potential limit reached
                consecutiveTangential = consecutiveTangential + 1;
                if consecutiveTangential >= stopPatience
                    break; % Trend confirmed: we are now following the ring
                end
            end
        end
        
        % Mark pixels for removal
        if numPruned > 0
            for j = 1:numPruned
                pixelsToRemove(path(j,2), path(j,1)) = true;
            end
        end
    end
    
    % Apply to original image
    pruneMask = imdilate(pixelsToRemove, strel('disk', 2));
    bwClean = bw & ~pruneMask;
end

function path = traceSkeletonPath(skel, startNode)
    % Helper to turn a skeleton branch into an ordered list of [x, y]
    path = startNode;
    curr = startNode;
    skelCopy = skel;
    while true
        skelCopy(curr(2), curr(1)) = 0; % Mark visited
        [ny, nx] = find(skelCopy(max(1,curr(2)-1):min(end,curr(2)+1), ...
                                 max(1,curr(1)-1):min(end,curr(1)+1)), 1);
        if isempty(ny), break; end
        curr = [nx + curr(1) - 2, ny + curr(2) - 2];
        path = [path; curr];
    end
end