function scenarios = syntheticSphereScenarios(powersD)
%SYNTHETICSPHERESCENARIOS Build true-sphere fixtures from K values.
%   SCENARIOS = SYNTHETICSPHERESCENARIOS(POWERSD) uses the keratometric
%   convention radius(mm) = 337.5 / K(D). Every returned surface has Q = 0.

arguments
    powersD (1,:) double {mustBeFinite, mustBePositive} = 42:46
end
if numel(unique(powersD)) ~= numel(powersD)
    error('SmartKC:Simulation:DuplicateSpherePower', ...
        'Sphere powers must be unique.');
end

defaults = defaultSyntheticScenarios();
base = defaults(1);
scenarios = repmat(base, 1, numel(powersD));
for index = 1:numel(powersD)
    powerD = powersD(index);
    scenarios(index).Name = "sphere_" + powerToken(powerD) + "D";
    scenarios(index).SurfaceClass = "sphere";
    scenarios(index).Severity = "reference-series";
    scenarios(index).AstigmatismOrientation = "none";
    scenarios(index).RflatMm = 337.5 / powerD;
    scenarios(index).RsteepMm = 337.5 / powerD;
    scenarios(index).AxisDeg = 0;
    scenarios(index).Q = 0;
    scenarios(index).ConeAmplitudeMm = 0;
    scenarios(index).ConeCenterMm = [0, 0];
    scenarios(index).BrokenArcFraction = 0;
    scenarios(index).GlareStrength = 0;
end
end

function token = powerToken(powerD)
token = string(compose('%.2f', powerD));
token = regexprep(token, '0+$', '');
token = regexprep(token, '\.$', '');
token = replace(token, '.', 'p');
end
