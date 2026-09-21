function refinedLocations = refineRadialPeaksQuadratic(profile, radiiPx, ...
        locations)
%REFINERADIALPEAKSQUADRATIC Fit a three-sample parabola at each radial peak.
%   Only strict concave local maxima with a finite vertex within one sample
%   are refined. Boundary, flat, non-concave, or invalid peaks retain their
%   original locations.

arguments
    profile (:,1) double
    radiiPx (:,1) double
    locations (:,1) double
end
if numel(profile) ~= numel(radiiPx)
    error('SmartKC:Localization:ProfileSizeMismatch', ...
        'profile and radiiPx must have the same number of samples.');
end
if numel(radiiPx) > 1 && any(abs(diff(radiiPx) - diff(radiiPx(1:2))) > 1e-9)
    error('SmartKC:Localization:NonuniformRadialSamples', ...
        'Quadratic refinement requires uniformly spaced radial samples.');
end

refinedLocations = locations;
if numel(radiiPx) < 3 || isempty(locations)
    return
end
sampleStep = radiiPx(2) - radiiPx(1);
for row = 1:numel(locations)
    [distance, index] = min(abs(radiiPx - locations(row)));
    if distance > 0.51 * abs(sampleStep) || index <= 1 || ...
            index >= numel(profile)
        continue
    end
    left = profile(index - 1);
    centre = profile(index);
    right = profile(index + 1);
    denominator = left - 2 * centre + right;
    if ~all(isfinite([left, centre, right])) || denominator >= -eps || ...
            centre < left || centre < right
        continue
    end
    fractionalOffset = 0.5 * (left - right) / denominator;
    if ~isfinite(fractionalOffset) || abs(fractionalOffset) > 1
        continue
    end
    refinedLocations(row) = radiiPx(index) + fractionalOffset * sampleStep;
end
end
