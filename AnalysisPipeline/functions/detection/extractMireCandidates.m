function [candidates, polarData] = extractMireCandidates(pre, segmentation, cfg)
%EXTRACTMIRECANDIDATES Find ordered radial response peaks on each meridian.

anglesDeg = (cfg.localization.StartAngleDeg:cfg.localization.AngleStepDeg: ...
    cfg.localization.EndAngleDeg-cfg.localization.AngleStepDeg)';
maxRadius = min(pre.AnalysisRadiusPx, ...
    cfg.localization.MaximumRadiusFraction * min(size(pre.NormalizedGray)));
innerRadius = cfg.localization.InnerRadiusPx;
if isfield(pre, 'CenterDiagnostics') && ...
        isfield(pre.CenterDiagnostics, 'SelectedRadiusPx') && ...
        isfinite(pre.CenterDiagnostics.SelectedRadiusPx)
    % SmartKC discards the central black/pupil segment before numbering
    % physical mires. Starting just outside that boundary prevents a
    % systematic one-ring shift in both real and synthetic images.
    centralExclusionScale = 1.08;
    if isfield(cfg.localization, 'CentralExclusionScale')
        centralExclusionScale = cfg.localization.CentralExclusionScale;
    end
    innerRadius = max(innerRadius, centralExclusionScale * ...
        pre.CenterDiagnostics.SelectedRadiusPx);
end
radiiPx = (ceil(innerRadius):1:floor(maxRadius))';
nAngles = numel(anglesDeg);
profiles = zeros(numel(radiiPx), nAngles, 'single');

NodeId = zeros(0, 1);
AngleIndex = zeros(0, 1);
AngleDeg = zeros(0, 1);
ProvisionalMire = zeros(0, 1);
RadiusPx = zeros(0, 1);
X = zeros(0, 1);
Y = zeros(0, 1);
Score = zeros(0, 1);
WidthPx = zeros(0, 1);
nodeCounter = 0;
subpixelMethod = resolveSubpixelMethod(cfg);

for angleIndex = 1:nAngles
    angle = anglesDeg(angleIndex);
    xq = pre.CenterPx(1) + radiiPx * cosd(angle);
    yq = pre.CenterPx(2) + radiiPx * sind(angle);
    profile = interp2(segmentation.Response, xq, yq, 'linear', 0);
    maskProfile = interp2(single(segmentation.Mask), xq, yq, 'nearest', 0);
    profile = smoothdata(profile, 'gaussian', 5);
    profile = profile .* (0.72 + 0.28 * maskProfile);
    profiles(:, angleIndex) = profile;

    adaptiveProminence = max(cfg.localization.MinimumPeakProminence, ...
        0.20 * iqr(double(profile)));
    minimumHeight = max(0.015, quantile(double(profile), 0.48));
    if max(double(profile)) <= minimumHeight
        peaks = zeros(0, 1);
        locations = zeros(0, 1);
        widths = zeros(0, 1);
        prominences = zeros(0, 1);
    else
        [peaks, locations, widths, prominences] = findpeaks( ...
            double(profile), double(radiiPx), ...
            'MinPeakDistance', cfg.localization.MinimumRingSpacingPx, ...
            'MinPeakProminence', adaptiveProminence, ...
            'MinPeakHeight', minimumHeight);
    end

    if numel(locations) > cfg.localization.MaximumCandidatesPerRay
        [~, byStrength] = sort(prominences, 'descend');
        keep = sort(byStrength(1:cfg.localization.MaximumCandidatesPerRay));
        peaks = peaks(keep);
        locations = locations(keep);
        widths = widths(keep);
        prominences = prominences(keep);
    end
    [locations, radialOrder] = sort(locations);
    peaks = peaks(radialOrder);
    widths = widths(radialOrder);
    prominences = prominences(radialOrder);

    if subpixelMethod == "quadratic"
        locations = refineRadialPeaksQuadratic( ...
            double(profile), double(radiiPx), locations);
    end

    count = numel(locations);
    rows = nodeCounter + (1:count);
    NodeId(rows, 1) = rows;
    AngleIndex(rows, 1) = angleIndex;
    AngleDeg(rows, 1) = angle;
    ProvisionalMire(rows, 1) = (1:count)';
    RadiusPx(rows, 1) = locations;
    X(rows, 1) = pre.CenterPx(1) + locations .* cosd(angle);
    Y(rows, 1) = pre.CenterPx(2) + locations .* sind(angle);
    Score(rows, 1) = prominences + 0.15 * peaks;
    WidthPx(rows, 1) = widths;
    nodeCounter = nodeCounter + count;
end

candidates = table(NodeId, AngleIndex, AngleDeg, ProvisionalMire, RadiusPx, ...
    X, Y, Score, WidthPx);
candidates.LocalizationMethod = repmat(subpixelMethod, ...
    height(candidates), 1);
candidates.MireIndex = candidates.ProvisionalMire;
candidates.ComponentId = zeros(height(candidates), 1);
candidates.IsValid = candidates.MireIndex <= cfg.placido.MaximumMires;
candidates.RejectionReason = repmat("", height(candidates), 1);
candidates.RejectionReason(~candidates.IsValid) = "beyond-maximum-mire-count";

polarData = struct('AnglesDeg', anglesDeg, 'RadiiPx', radiiPx, ...
    'Profiles', profiles, 'MaximumRadiusPx', maxRadius, ...
    'SubpixelMethod', subpixelMethod);
end

function method = resolveSubpixelMethod(cfg)
method = "none";
if isfield(cfg.localization, 'SubpixelMethod') && ...
        strlength(string(cfg.localization.SubpixelMethod)) > 0
    method = string(cfg.localization.SubpixelMethod);
end
if ~ismember(method, ["none", "quadratic"])
    error('SmartKC:Localization:InvalidSubpixelMethod', ...
        'localization.SubpixelMethod must be "none" or "quadratic".');
end
end
