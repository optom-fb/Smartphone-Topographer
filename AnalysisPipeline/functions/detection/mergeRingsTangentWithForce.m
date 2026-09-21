function [finalLabels, numFinalRings] = mergeRingsTangentWithForce(bw, maxDist, angleTol, forceMergeDist, doDisplay)
    % mergeRingsTangentWithForce 
    % Logic:
    %   1. d <= forceMergeDist           -> Merge (Magenta)
    %   2. d <= maxDist & angles < tol   -> Merge (Green)
    %   3. d <= maxDist & angles > tol   -> Reject (Red)

    if nargin < 5, doDisplay = false; end
    if nargin < 4, forceMergeDist = 3; end % Default: merge 3px gaps regardless of angle
    if nargin < 3, angleTol = 30; end
    if nargin < 2, maxDist = 25; end

    [rows, cols] = size(bw);
    L = bwlabel(bw, 8);
    stats = regionprops(L, 'PixelList', 'PixelIdxList');
    numBlobs = numel(stats);
    
    % Find morphological endpoints
    endpointsImg = bwmorph(bw, 'endpoints');
    [epY, epX] = find(endpointsImg);
    allEndpoints = [epX, epY];

    % Step 1: Pre-calculate Tips and Tangents
    lookback = 30; 
    blobData = struct('tips', [], 'tangents', []);
    for i = 1:numBlobs
        pixels = stats(i).PixelList;
        isMyTip = ismember(allEndpoints, pixels, 'rows');
        myTips = allEndpoints(isMyTip, :);
        if size(myTips, 1) < 1
            dists = pdist2(pixels, pixels);
            [~, idx] = max(dists(:));
            [r, c] = ind2sub(size(dists), idx);
            myTips = [pixels(r, :); pixels(c, :)];
        end
        blobData(i).tips = myTips;
        for t = 1:size(myTips, 1)
            tipPos = myTips(t, :);
            dToTip = sqrt(sum((pixels - tipPos).^2, 2));
            [~, sortIdx] = sort(dToTip);
            innerIdx = min(lookback, size(pixels,1));
            p_inner = pixels(sortIdx(innerIdx), :);
            v = tipPos - p_inner; 
            blobData(i).tangents(t, :) = v / (norm(v) + eps);
        end
    end

    % Step 2: Visualization Setup
    if doDisplay
        figure('Color', 'w');
        imshow(imdilate(bw, ones(2,2))); hold on;
        title(['Magenta: Force Merge | Green: Tangent Merge | Red: Reject']);
    end

    % Step 3: Proximity Testing
    s = []; t = [];
    visualLimit = maxDist * 1.5;

    for i = 1:numBlobs
        for j = (i+1):numBlobs
            merged = false;
            tipsI = blobData(i).tips; tipsJ = blobData(j).tips;
            tansI = blobData(i).tangents; tansJ = blobData(j).tangents;
            
            for ti = 1:size(tipsI, 1)
                for tj = 1:size(tipsJ, 1)
                    pI = tipsI(ti, :); pJ = tipsJ(tj, :);
                    dist = norm(pI - pJ);
                    if dist > visualLimit, continue; end
                    
                    % Vectors & Angles
                    bridgeVecIJ = (pJ - pI) / (dist + eps);
                    vI = tansI(ti, :); vJ = tansJ(tj, :);
                    theta1 = acosd(max(-1, min(1, dot(vI, bridgeVecIJ))));
                    theta2 = acosd(max(-1, min(1, dot(vJ, -bridgeVecIJ))));
                    
                    % Conditionals
                    isForceMerge = dist <= forceMergeDist;
                    isTangentMerge = (dist <= maxDist) && (theta1 < angleTol && theta2 < angleTol);
                    
                    if doDisplay
                        mid = (pI + pJ)/2;
                        if isForceMerge
                            col = [1 0 1]; style = '-'; % Magenta
                        elseif isTangentMerge
                            col = [0 0.8 0]; style = '-'; % Green
                        elseif dist <= maxDist
                            col = [1 0 0]; style = '--'; % Red
                        else
                            col = [0.5 0.5 0.5]; style = ':'; % Gray
                        end
                        
                        plot([pI(1), pJ(1)], [pI(2), pJ(2)], style, 'Color', col, 'LineWidth', 1.5);
                        quiver(pI(1), pI(2), vI(1)*8, vI(2)*8, 0, 'b', 'MaxHeadSize', 2);
                        quiver(pJ(1), pJ(2), vJ(1)*8, vJ(2)*8, 0, 'b', 'MaxHeadSize', 2);
                        
                        msg = sprintf('d=%.1f\n%d°,%d°', dist, round(theta1), round(theta2));
                        text(mid(1), mid(2), msg, 'Color', col, 'FontSize', 7, 'FontWeight', 'bold', ...
                            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
                    end
                    
                    if isForceMerge || isTangentMerge
                        merged = true;
                    end
                end
            end
            if merged
                s = [s, i]; t = [t, j];
            end
        end
    end

    % Step 4: Graph Theory Consolidation
    if isempty(s)
        mapping = 1:numBlobs;
    else
        G = graph(s, t, [], numBlobs);
        mapping = conncomp(G);
    end
    
    % Step 5: Final Output
    finalLabels = zeros(rows, cols);
    for i = 1:numBlobs
        finalLabels(stats(i).PixelIdxList) = mapping(i);
    end
    numFinalRings = max(mapping);
    if doDisplay, hold off; end
end