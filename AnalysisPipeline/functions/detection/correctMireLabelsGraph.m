function corrected = correctMireLabelsGraph(candidates, centerPx, cfg)
%CORRECTMIRELABELSGRAPH Apply the SmartKC++ connected-component relabeling.
%   Nodes are joined when they are close in radial and tangential directions.
%   Component modes repair sequential mire-number shifts caused by a broken arc.

corrected = candidates;
if isempty(corrected)
    return
end

n = height(corrected);
edgeSource = zeros(0, 1);
edgeTarget = zeros(0, 1);
uniqueAngles = unique(corrected.AngleIndex)';
step = cfg.localization.AngleStepDeg;
maxStep = max(1, floor(cfg.localization.GraphTangentialHalfWidthDeg / step + 1e-9));
nAngleBins = round(360 / step);

for angleIndex = uniqueAngles
    sourceRows = find(corrected.AngleIndex == angleIndex);
    for delta = 1:maxStep
        neighbourIndex = mod(angleIndex - 1 + delta, nAngleBins) + 1;
        targetRows = find(corrected.AngleIndex == neighbourIndex);
        if isempty(targetRows)
            continue
        end
        for source = sourceRows'
            radialVector = [corrected.X(source), corrected.Y(source)] - centerPx;
            radialVector = radialVector / max(norm(radialVector), eps);
            tangentialVector = [-radialVector(2), radialVector(1)];
            differences = [corrected.X(targetRows)-corrected.X(source), ...
                corrected.Y(targetRows)-corrected.Y(source)];
            radialDistances = abs(differences * radialVector');
            tangentialDistances = abs(differences * tangentialVector');
            allowedTangential = max(1.5, corrected.RadiusPx(source) * ...
                deg2rad(cfg.localization.GraphTangentialHalfWidthDeg));
            matches = targetRows(radialDistances <= cfg.localization.GraphRadialTolerancePx & ...
                tangentialDistances <= allowedTangential);
            if ~isempty(matches)
                edgeSource(end+1:end+numel(matches), 1) = source;
                edgeTarget(end+1:end+numel(matches), 1) = matches;
            end
        end
    end
end

if isempty(edgeSource)
    corrected.IsValid(:) = false;
    corrected.RejectionReason(:) = "no-graph-neighbours";
    return
end

adjacency = cell(n, 1);
for edge = 1:numel(edgeSource)
    a = edgeSource(edge);
    b = edgeTarget(edge);
    adjacency{a}(end+1) = b;
    adjacency{b}(end+1) = a;
end

% Match the released SmartKC++ traversal: a connected segment may contain
% at most one node from a given sampled angle.
components = zeros(n, 1);
nextComponent = 0;
for seed = 1:n
    if components(seed) ~= 0
        continue
    end
    nextComponent = nextComponent + 1;
    stack = seed;
    usedAngles = false(nAngleBins, 1);
    while ~isempty(stack)
        node = stack(end);
        stack(end) = [];
        if components(node) ~= 0 || usedAngles(corrected.AngleIndex(node))
            continue
        end
        components(node) = nextComponent;
        usedAngles(corrected.AngleIndex(node)) = true;
        neighbours = adjacency{node};
        for neighbour = neighbours
            if components(neighbour) == 0 && ...
                    ~usedAngles(corrected.AngleIndex(neighbour)) && ...
                    ~ismember(neighbour, stack)
                stack(end+1) = neighbour; %#ok<AGROW>
            end
        end
    end
end
corrected.ComponentId = components;
componentIds = unique(components);
componentSize = accumarray(components, 1);
medianRadius = accumarray(components, corrected.RadiusPx, [], @median);
[~, componentOrder] = sort(medianRadius(componentIds));
componentIds = componentIds(componentOrder);

small = componentSize(components) < cfg.localization.GraphMinimumComponentSize;
corrected.IsValid(small) = false;
corrected.RejectionReason(small) = "small-connected-component";

for componentId = componentIds'
    subset = find(corrected.ComponentId == componentId & corrected.IsValid);
    if isempty(subset)
        continue
    end
    modeMire = mode(corrected.MireIndex(subset));
    observedMires = unique(corrected.MireIndex(subset));
    for observed = observedMires'
        if observed == modeMire
            continue
        end
        delta = modeMire - observed;
        affectedAngles = unique(corrected.AngleIndex(subset(corrected.MireIndex(subset) == observed)));
        propagate = ismember(corrected.AngleIndex, affectedAngles) & ...
            corrected.MireIndex >= observed;
        corrected.MireIndex(propagate) = corrected.MireIndex(propagate) + delta;
    end
    corrected.MireIndex(subset) = modeMire;
end

outOfRange = corrected.MireIndex < 1 | ...
    corrected.MireIndex > cfg.placido.MaximumMires;
corrected.IsValid(outOfRange) = false;
corrected.RejectionReason(outOfRange) = "corrected-mire-out-of-range";

active = find(corrected.IsValid);
if ~isempty(active)
    keys = [corrected.AngleIndex(active), corrected.MireIndex(active)];
    [~, ~, groups] = unique(keys, 'rows');
    counts = accumarray(groups, 1);
    duplicates = active(counts(groups) > 1);
    corrected.IsValid(duplicates) = false;
    corrected.RejectionReason(duplicates) = "duplicate-angle-mire-after-correction";
end
end
