function [image, truth] = simulatePlacidoImage(scenario, cfg)
%SIMULATEPLACIDOIMAGE Generate a calibrated synthetic Placido reflection.
%   [IMAGE, TRUTH] = SIMULATEPLACIDOIMAGE(SCENARIO, CFG) models a rotated
%   biconic cornea with an optional localized Gaussian elevation (cone).
%   For every Placido ring and sampled meridian, the reflection location is
%   obtained by numerically satisfying the meridional specular-reflection
%   equation used by the Arc-Step method. The reflected points are then
%   projected through a pinhole camera and rasterized as dark mire bands on
%   a softly varying corneal/iris background.
%
%   Required SCENARIO fields:
%     Name, RflatMm, RsteepMm, AxisDeg, Q, ConeAmplitudeMm,
%     ConeCenterMm, ConeSigmaMm, BrokenArcFraction, NoiseSigma, BlurSigma
%
%   Required CFG fields:
%     simulation.ImageSize            [height width] pixels
%     simulation.RandomSeed           integer seed
%     camera.SensorSizeMm              [width height] mm
%     camera.FocalLengthMm             focal length in mm
%     camera.WorkingDistanceMm         camera-to-corneal-apex distance, mm
%     placido.RingRadiusHeightMm       N-by-2 [radius height], mm
%
%   Placido heights are measured from the camera toward the cornea, as in
%   the SmartKC ring-distribution files. Coordinates in millimetres use x
%   right, y superior and z away from the camera. Pixel coordinates use x
%   right and y down. Angles are counter-clockwise in physical coordinates.
%
%   This simulator is intended for engineering research and algorithm
%   testing. It is not a validated clinical device or a source of diagnosis.

validateInputs(scenario, cfg);
opts = resolveOptions(cfg);

previousRng = rng;
restoreRng = onCleanup(@() rng(previousRng));
rng(double(cfg.simulation.RandomSeed), 'twister');

imageSize = double(cfg.simulation.ImageSize(:).');
heightPixels = imageSize(1);
widthPixels = imageSize(2);
sensorSizeMm = double(cfg.camera.SensorSizeMm(:).');
focalLengthMm = double(cfg.camera.FocalLengthMm);
workingDistanceMm = double(cfg.camera.WorkingDistanceMm);
ringGeometry = resolveReflectiveRingGeometry(cfg.placido);
numberOfRings = size(ringGeometry, 1);
anglesDeg = (0:(opts.AngularSamples - 1)) .* (360 / opts.AngularSamples);
anglesRad = deg2rad(anglesDeg);
numberOfAngles = numel(anglesDeg);
centerPixels = [(widthPixels + 1) / 2, (heightPixels + 1) / 2];

reflectionRadiusMm = nan(numberOfRings, numberOfAngles);
reflectionPointsMm = nan(numberOfRings, numberOfAngles, 3);
solverResidual = nan(numberOfRings, numberOfAngles);

% Solve smaller source rings first. This gives the root selector a
% physically useful monotonic continuation when a pathological surface
% yields more than one numerical root.
[~, solveOrder] = sort(ringGeometry(:, 1), 'ascend');
for angleIndex = 1:numberOfAngles
    theta = anglesRad(angleIndex);
    previousRadius = NaN;
    for orderIndex = 1:numberOfRings
        ringIndex = solveOrder(orderIndex);
        [radiusMm, residual] = solveReflectionRadius( ...
            ringGeometry(ringIndex, 1), ringGeometry(ringIndex, 2), ...
            theta, scenario, workingDistanceMm, opts.MaxCornealRadiusMm, ...
            opts.RootSamples, previousRadius);
        if isfinite(radiusMm)
            xMm = radiusMm * cos(theta);
            yMm = radiusMm * sin(theta);
            [zMm, ~, ~] = surfaceSagGradient(xMm, yMm, scenario);
            reflectionRadiusMm(ringIndex, angleIndex) = radiusMm;
            reflectionPointsMm(ringIndex, angleIndex, :) = [xMm, yMm, zMm];
            solverResidual(ringIndex, angleIndex) = residual;
            previousRadius = radiusMm;
        end
    end
end

zCameraMm = -workingDistanceMm;
xMm = reflectionPointsMm(:, :, 1);
yMm = reflectionPointsMm(:, :, 2);
zMm = reflectionPointsMm(:, :, 3);
projectionDistanceMm = zMm - zCameraMm;
sensorXmm = focalLengthMm .* xMm ./ projectionDistanceMm;
sensorYmm = focalLengthMm .* yMm ./ projectionDistanceMm;
pointsXPixels = centerPixels(1) + opts.PixelScaleFactor .* ...
    sensorXmm .* widthPixels ./ sensorSizeMm(1);
pointsYPixels = centerPixels(2) - opts.PixelScaleFactor .* ...
    sensorYmm .* heightPixels ./ sensorSizeMm(2);
pointsPixels = cat(3, pointsXPixels, pointsYPixels);
radiiPixels = hypot(pointsXPixels - centerPixels(1), ...
    pointsYPixels - centerPixels(2));
solverValidMask = isfinite(radiiPixels) & pointsXPixels >= 1 & ...
    pointsXPixels <= widthPixels & pointsYPixels >= 1 & ...
    pointsYPixels <= heightPixels;

brokenArcMask = createBrokenArcMask(numberOfRings, numberOfAngles, ...
    double(scenario.BrokenArcFraction));
visibleMask = solverValidMask & ~brokenArcMask;

[rendered, binaryMireMask, mireLabelMap] = ...
    renderMires(pointsPixels, visibleMask, imageSize, opts);
rendered = addGlare(rendered, scenario, opts);
if double(scenario.BlurSigma) > 0
    rendered = gaussianBlur(rendered, double(scenario.BlurSigma));
end
if double(scenario.NoiseSigma) > 0
    rendered = rendered + double(scenario.NoiseSigma) .* randn(imageSize);
end
rendered = min(max(rendered, 0), 1);
image = uint8(round(255 .* rendered));

[surfaceXmm, surfaceYmm] = meshgrid(linspace(-opts.MaxCornealRadiusMm, ...
    opts.MaxCornealRadiusMm, opts.SurfaceGridSize));
[surfaceSagMm, ~, ~] = surfaceSagGradient(surfaceXmm, surfaceYmm, scenario);
surfaceMask = hypot(surfaceXmm, surfaceYmm) <= opts.MaxCornealRadiusMm;
surfaceSagMm(~surfaceMask) = NaN;

truth = struct;
truth.schemaVersion = "1.1";
truth.generator = "simulatePlacidoImage";
truth.coordinateConvention = struct( ...
    'millimetres', "x right, y superior, z away from camera", ...
    'pixels', "[x y], x right and y down", ...
    'angles', "degrees counter-clockwise in physical x-y coordinates");
truth.scenario = scenario;
truth.anglesDeg = anglesDeg;
truth.centerPixels = centerPixels;
truth.radiiPixels = radiiPixels;
truth.pointsPixels = pointsPixels;
truth.reflectionRadiusMm = reflectionRadiusMm;
truth.reflectionPointsMm = reflectionPointsMm;
truth.solverValidMask = solverValidMask;
truth.solverResidual = solverResidual;
truth.brokenArcMask = brokenArcMask;
truth.visibleMask = visibleMask;
truth.segmentation = struct( ...
    'BinaryMireMask', binaryMireMask, ...
    'MireLabelMap', mireLabelMap, ...
    'BackgroundLabel', uint8(0), ...
    'FirstMireLabel', uint8(1), ...
    'NumberOfMires', uint8(numberOfRings), ...
    'MaskDefinition', ...
    "normalized rendered mire response >= 0.5 before glare/noise", ...
    'LabelConvention', ...
    "uint8; 0 background; 1-based inner-to-outer physical mire index");
truth.surface = struct( ...
    'model', "rotated biconic plus localized Gaussian elevation", ...
    'xMm', surfaceXmm, 'yMm', surfaceYmm, 'sagMm', surfaceSagMm, ...
    'validMask', surfaceMask);
truth.calibration = struct( ...
    'imageSize', imageSize, ...
        'sensorSizeMm', sensorSizeMm, ...
        'effectiveSensorSizeMm', sensorSizeMm ./ opts.PixelScaleFactor, ...
        'pixelScaleFactor', opts.PixelScaleFactor, ...
    'pixelPitchMm', [sensorSizeMm(1) / widthPixels, ...
        sensorSizeMm(2) / heightPixels], ...
    'focalLengthMm', focalLengthMm, ...
    'workingDistanceMm', workingDistanceMm, ...
    'ringRadiusHeightMm', ringGeometry, ...
    'randomSeed', double(cfg.simulation.RandomSeed), ...
    'angularSamples', opts.AngularSamples, ...
    'maxCornealRadiusMm', opts.MaxCornealRadiusMm);
truth.derived = struct( ...
    'flatPowerD', 337.5 / double(scenario.RflatMm), ...
    'steepPowerD', 337.5 / double(scenario.RsteepMm), ...
    'cylinderMagnitudeD', abs(337.5 / double(scenario.RsteepMm) - ...
        337.5 / double(scenario.RflatMm)));
truth.artifacts = struct( ...
    'requestedBrokenArcFraction', double(scenario.BrokenArcFraction), ...
    'realizedBrokenArcFraction', nnz(brokenArcMask) / numel(brokenArcMask), ...
    'noiseSigma', double(scenario.NoiseSigma), ...
    'blurSigmaPixels', double(scenario.BlurSigma), ...
    'glareStrength', resolveGlareStrength(scenario, opts));
truth.method = struct( ...
    'reflectionGeometry', "SmartKC Arc-Step meridional angle-bisector equation", ...
    'rootSolver', "bracketed fzero with bounded residual fallback", ...
    'limitation', "Meridional forward tracing does not model skew rays from azimuthal cone gradients.");
end

function ringGeometry = resolveReflectiveRingGeometry(placido)
ringGeometry = double(placido.RingRadiusHeightMm);
if isfield(placido, 'ThicknessMm') && ...
        isfield(placido, 'ThicknessAdjustmentMm') && size(ringGeometry, 1) >= 3
    boundaries = ringGeometry(2:end, :);
    ringGeometry = [ ...
        (boundaries(1:end-1, 1) + boundaries(2:end, 1) ...
        - placido.ThicknessMm + placido.ThicknessAdjustmentMm) / 2, ...
        (boundaries(1:end-1, 2) + boundaries(2:end, 2)) / 2];
end
if isfield(placido, 'MaximumMires')
    ringGeometry = ringGeometry(1:min(placido.MaximumMires, size(ringGeometry, 1)), :);
end
end

function validateInputs(scenario, cfg)
if ~isstruct(scenario) || ~isscalar(scenario)
    error('SmartKC:Simulation:InvalidScenario', ...
        'scenario must be a scalar structure.');
end
requiredScenario = {'Name', 'RflatMm', 'RsteepMm', 'AxisDeg', 'Q', ...
    'ConeAmplitudeMm', 'ConeCenterMm', 'ConeSigmaMm', ...
    'BrokenArcFraction', 'NoiseSigma', 'BlurSigma'};
requireFields(scenario, requiredScenario, 'scenario');
if ~(ischar(scenario.Name) || (isstring(scenario.Name) && isscalar(scenario.Name)))
    error('SmartKC:Simulation:InvalidScenario', ...
        'scenario.Name must be text.');
end
validateFiniteScalar(scenario.RflatMm, 'scenario.RflatMm', true);
validateFiniteScalar(scenario.RsteepMm, 'scenario.RsteepMm', true);
validateFiniteScalar(scenario.AxisDeg, 'scenario.AxisDeg', false);
validateFiniteScalar(scenario.Q, 'scenario.Q', false);
validateFiniteScalar(scenario.ConeAmplitudeMm, ...
    'scenario.ConeAmplitudeMm', false);
if scenario.ConeAmplitudeMm < 0
    error('SmartKC:Simulation:InvalidScenario', ...
        'scenario.ConeAmplitudeMm must be nonnegative.');
end
if ~isnumeric(scenario.ConeCenterMm) || numel(scenario.ConeCenterMm) ~= 2 || ...
        any(~isfinite(scenario.ConeCenterMm), 'all') || ~isreal(scenario.ConeCenterMm)
    error('SmartKC:Simulation:InvalidScenario', ...
        'scenario.ConeCenterMm must contain two finite real values [x y].');
end
validateFiniteScalar(scenario.ConeSigmaMm, 'scenario.ConeSigmaMm', true);
validateFraction(scenario.BrokenArcFraction, 'scenario.BrokenArcFraction');
validateFraction(scenario.NoiseSigma, 'scenario.NoiseSigma');
validateFiniteScalar(scenario.BlurSigma, 'scenario.BlurSigma', false);
if scenario.BlurSigma < 0
    error('SmartKC:Simulation:InvalidScenario', ...
        'scenario.BlurSigma must be nonnegative.');
end

if ~isstruct(cfg) || ~isscalar(cfg)
    error('SmartKC:Simulation:InvalidConfig', 'cfg must be a scalar structure.');
end
requireFields(cfg, {'simulation', 'camera', 'placido'}, 'cfg');
requireFields(cfg.simulation, {'ImageSize', 'RandomSeed'}, 'cfg.simulation');
requireFields(cfg.camera, {'SensorSizeMm', 'FocalLengthMm', ...
    'WorkingDistanceMm'}, 'cfg.camera');
requireFields(cfg.placido, {'RingRadiusHeightMm'}, 'cfg.placido');

imageSize = cfg.simulation.ImageSize;
if ~isnumeric(imageSize) || numel(imageSize) ~= 2 || ~isreal(imageSize) || ...
        any(~isfinite(imageSize), 'all') || any(imageSize < 32) || ...
        any(imageSize ~= round(imageSize))
    error('SmartKC:Simulation:InvalidConfig', ...
        'cfg.simulation.ImageSize must be two integer values >= 32.');
end
validateFiniteScalar(cfg.simulation.RandomSeed, ...
    'cfg.simulation.RandomSeed', false);
if cfg.simulation.RandomSeed < 0 || ...
        cfg.simulation.RandomSeed ~= round(cfg.simulation.RandomSeed)
    error('SmartKC:Simulation:InvalidConfig', ...
        'cfg.simulation.RandomSeed must be a nonnegative integer.');
end
sensorSize = cfg.camera.SensorSizeMm;
if ~isnumeric(sensorSize) || numel(sensorSize) ~= 2 || ~isreal(sensorSize) || ...
        any(~isfinite(sensorSize), 'all') || any(sensorSize <= 0)
    error('SmartKC:Simulation:InvalidConfig', ...
        'cfg.camera.SensorSizeMm must be two positive values [width height].');
end
validateFiniteScalar(cfg.camera.FocalLengthMm, ...
    'cfg.camera.FocalLengthMm', true);
validateFiniteScalar(cfg.camera.WorkingDistanceMm, ...
    'cfg.camera.WorkingDistanceMm', true);
rings = cfg.placido.RingRadiusHeightMm;
if ~isnumeric(rings) || ~ismatrix(rings) || size(rings, 2) ~= 2 || ...
        isempty(rings) || ~isreal(rings) || any(~isfinite(rings), 'all') || ...
        any(rings(:, 1) <= 0) || any(rings(:, 2) < 0)
    error('SmartKC:Simulation:InvalidConfig', ...
        ['cfg.placido.RingRadiusHeightMm must be a finite N-by-2 ' ...
        '[radius height] array with positive radii and nonnegative heights.']);
end
if any(rings(:, 2) >= cfg.camera.WorkingDistanceMm)
    error('SmartKC:Simulation:InvalidConfig', ...
        'Every Placido height must be less than the working distance.');
end
end

function requireFields(value, names, label)
missing = names(~isfield(value, names));
if ~isempty(missing)
    error('SmartKC:Simulation:MissingField', '%s is missing: %s.', ...
        label, strjoin(missing, ', '));
end
end

function validateFiniteScalar(value, label, mustBePositive)
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ~isfinite(value)
    error('SmartKC:Simulation:InvalidValue', '%s must be a finite real scalar.', label);
end
if mustBePositive && value <= 0
    error('SmartKC:Simulation:InvalidValue', '%s must be positive.', label);
end
end

function validateFraction(value, label)
validateFiniteScalar(value, label, false);
if value < 0 || value > 1
    error('SmartKC:Simulation:InvalidValue', '%s must be between 0 and 1.', label);
end
end

function opts = resolveOptions(cfg)
opts = struct;
opts.AngularSamples = getOption(cfg.simulation, 'AngularSamples', 360);
opts.MaxCornealRadiusMm = getOption(cfg.simulation, ...
    'MaxCornealRadiusMm', 6.5);
opts.RootSamples = getOption(cfg.simulation, 'RootSamples', 72);
opts.SurfaceGridSize = getOption(cfg.simulation, 'SurfaceGridSize', 129);
opts.RingWidthPixels = getOption(cfg.simulation, 'RingWidthPixels', 2.2);
opts.BrightMireContrast = getOption(cfg.simulation, ...
    'BrightMireContrast', 0.68);
opts.DarkMireContrast = getOption(cfg.simulation, 'DarkMireContrast', 0.17);
opts.GlareStrength = getOption(cfg.simulation, 'GlareStrength', 0);
opts.GlareCenterPixels = getOption(cfg.simulation, 'GlareCenterPixels', []);
opts.GlareSigmaPixels = getOption(cfg.simulation, 'GlareSigmaPixels', []);
opts.BackgroundLevel = getOption(cfg.simulation, 'BackgroundLevel', 0.62);
opts.PixelScaleFactor = getOption(cfg.simulation, 'PixelScaleFactor', 1.0);

validatePositiveInteger(opts.AngularSamples, 'simulation.AngularSamples', 16);
validateFiniteScalar(opts.MaxCornealRadiusMm, ...
    'simulation.MaxCornealRadiusMm', true);
validatePositiveInteger(opts.RootSamples, 'simulation.RootSamples', 24);
validatePositiveInteger(opts.SurfaceGridSize, 'simulation.SurfaceGridSize', 17);
validateFiniteScalar(opts.RingWidthPixels, 'simulation.RingWidthPixels', true);
validateFraction(opts.BrightMireContrast, 'simulation.BrightMireContrast');
validateFraction(opts.DarkMireContrast, 'simulation.DarkMireContrast');
validateFraction(opts.GlareStrength, 'simulation.GlareStrength');
validateFraction(opts.BackgroundLevel, 'simulation.BackgroundLevel');
validateFiniteScalar(opts.PixelScaleFactor, 'simulation.PixelScaleFactor', true);
if ~isempty(opts.GlareCenterPixels) && ...
        (~isnumeric(opts.GlareCenterPixels) || numel(opts.GlareCenterPixels) ~= 2 || ...
        any(~isfinite(opts.GlareCenterPixels), 'all'))
    error('SmartKC:Simulation:InvalidConfig', ...
        'simulation.GlareCenterPixels must be empty or [x y].');
end
if ~isempty(opts.GlareSigmaPixels)
    validateFiniteScalar(opts.GlareSigmaPixels, ...
        'simulation.GlareSigmaPixels', true);
end
end

function value = getOption(parent, name, defaultValue)
if isfield(parent, name) && ~isempty(parent.(name))
    value = double(parent.(name));
else
    value = defaultValue;
end
end

function validatePositiveInteger(value, label, minimum)
validateFiniteScalar(value, label, true);
if value ~= round(value) || value < minimum
    error('SmartKC:Simulation:InvalidConfig', ...
        '%s must be an integer >= %d.', label, minimum);
end
end

function [radiusMm, finalResidual] = solveReflectionRadius(sourceRadiusMm, ...
        sourceHeightMm, theta, scenario, workingDistanceMm, maximumRadiusMm, ...
        rootSamples, previousRadiusMm)
zCameraMm = -workingDistanceMm;
zSourceMm = sourceHeightMm - workingDistanceMm;
upperRadius = min(maximumRadiusMm, sourceRadiusMm - 1e-5);
lowerRadius = 1e-6;
radiusMm = NaN;
finalResidual = NaN;
if upperRadius <= lowerRadius
    return;
end

residualFunction = @(radius) reflectionResidual(radius, theta, scenario, ...
    sourceRadiusMm, zSourceMm, zCameraMm);
sampleRadii = linspace(lowerRadius, upperRadius, rootSamples);
sampleResiduals = residualFunction(sampleRadii);
candidateRoots = zeros(1, 0);
for index = 1:(numel(sampleRadii) - 1)
    firstValue = sampleResiduals(index);
    secondValue = sampleResiduals(index + 1);
    if ~isfinite(firstValue) || ~isfinite(secondValue)
        continue;
    end
    if abs(firstValue) < 1e-10
        candidateRoots(end + 1) = sampleRadii(index); %#ok<AGROW>
    elseif sign(firstValue) ~= sign(secondValue)
        try
            candidateRoots(end + 1) = fzero(residualFunction, ...
                sampleRadii(index:index + 1)); %#ok<AGROW>
        catch
            % A discontinuity can resemble a sign crossing. It is ignored;
            % the bounded residual fallback below remains available.
        end
    end
end
if isfinite(sampleResiduals(end)) && abs(sampleResiduals(end)) < 1e-10
    candidateRoots(end + 1) = sampleRadii(end);
end

if ~isempty(candidateRoots)
    candidateRoots = sort(candidateRoots(isfinite(candidateRoots)));
    if numel(candidateRoots) > 1
        candidateRoots = candidateRoots([true, diff(candidateRoots) > 1e-5]);
    end
    if isfinite(previousRadiusMm)
        monotonic = candidateRoots >= previousRadiusMm - 0.05;
        if any(monotonic)
            eligible = candidateRoots(monotonic);
            [~, selected] = min(abs(eligible - previousRadiusMm));
            radiusMm = eligible(selected);
        else
            [~, selected] = min(abs(candidateRoots - previousRadiusMm));
            radiusMm = candidateRoots(selected);
        end
    else
        radiusMm = candidateRoots(1);
    end
else
    try
        [fallbackRadius, fallbackResidual] = fminbnd( ...
            @(radius) abs(residualFunction(radius)), lowerRadius, upperRadius);
        if isfinite(fallbackResidual) && fallbackResidual <= 5e-4
            radiusMm = fallbackRadius;
        end
    catch
        radiusMm = NaN;
    end
end
if isfinite(radiusMm)
    finalResidual = abs(residualFunction(radiusMm));
end
end

function residual = reflectionResidual(radiusMm, theta, scenario, ...
        sourceRadiusMm, zSourceMm, zCameraMm)
xMm = radiusMm .* cos(theta);
yMm = radiusMm .* sin(theta);
[zMm, gradientX, gradientY] = surfaceSagGradient(xMm, yMm, scenario);
surfaceSlope = gradientX .* cos(theta) + gradientY .* sin(theta);
cameraSlope = radiusMm ./ (zMm - zCameraMm);
objectSlope = (sourceRadiusMm - radiusMm) ./ (zMm - zSourceMm);
normalizer = sqrt(1 + surfaceSlope .^ 2);
objectCosine = (objectSlope - surfaceSlope) ./ ...
    (sqrt(1 + objectSlope .^ 2) .* normalizer);
cameraCosine = (cameraSlope + surfaceSlope) ./ ...
    (sqrt(1 + cameraSlope .^ 2) .* normalizer);
residual = objectCosine - cameraCosine;
invalid = ~isfinite(zMm) | (zMm <= zSourceMm) | (zMm <= zCameraMm);
residual(invalid) = NaN;
end

function [sagMm, gradientX, gradientY] = surfaceSagGradient(xMm, yMm, scenario)
axisRad = deg2rad(mod(double(scenario.AxisDeg), 180));
cosAxis = cos(axisRad);
sinAxis = sin(axisRad);
uMm = cosAxis .* xMm + sinAxis .* yMm;
vMm = -sinAxis .* xMm + cosAxis .* yMm;
curvatureU = 1 / double(scenario.RflatMm);
curvatureV = 1 / double(scenario.RsteepMm);
q = double(scenario.Q);

numerator = curvatureU .* uMm .^ 2 + curvatureV .* vMm .^ 2;
radicand = 1 - (1 + q) .* (curvatureU ^ 2 .* uMm .^ 2 + ...
    curvatureV ^ 2 .* vMm .^ 2);
valid = radicand > 1e-12;
rootTerm = sqrt(max(radicand, 1e-12));
denominator = 1 + rootTerm;
sagMm = numerator ./ denominator;

derivativeNumeratorU = 2 .* curvatureU .* uMm;
derivativeNumeratorV = 2 .* curvatureV .* vMm;
gradientU = derivativeNumeratorU ./ denominator + ...
    numerator .* (1 + q) .* curvatureU ^ 2 .* uMm ./ ...
    (rootTerm .* denominator .^ 2);
gradientV = derivativeNumeratorV ./ denominator + ...
    numerator .* (1 + q) .* curvatureV ^ 2 .* vMm ./ ...
    (rootTerm .* denominator .^ 2);
gradientX = cosAxis .* gradientU - sinAxis .* gradientV;
gradientY = sinAxis .* gradientU + cosAxis .* gradientV;

coneAmplitude = double(scenario.ConeAmplitudeMm);
if coneAmplitude ~= 0
    coneCenter = double(scenario.ConeCenterMm(:).');
    coneSigma = double(scenario.ConeSigmaMm);
    deltaX = xMm - coneCenter(1);
    deltaY = yMm - coneCenter(2);
    coneElevation = coneAmplitude .* exp(-(deltaX .^ 2 + deltaY .^ 2) ./ ...
        (2 .* coneSigma ^ 2));
    sagMm = sagMm + coneElevation;
    gradientX = gradientX - coneElevation .* deltaX ./ coneSigma ^ 2;
    gradientY = gradientY - coneElevation .* deltaY ./ coneSigma ^ 2;
end
sagMm(~valid) = NaN;
gradientX(~valid) = NaN;
gradientY(~valid) = NaN;
end

function brokenMask = createBrokenArcMask(numberOfRings, numberOfAngles, fraction)
brokenMask = false(numberOfRings, numberOfAngles);
numberToBreak = round(fraction * numberOfAngles);
if numberToBreak == 0
    return;
end
for ringIndex = 1:numberOfRings
    smoothNoise = randn(1, numberOfAngles);
    smoothingPasses = max(3, round(numberOfAngles / 36));
    for passIndex = 1:smoothingPasses
        smoothNoise = (circshift(smoothNoise, 1) + 2 .* smoothNoise + ...
            circshift(smoothNoise, -1)) ./ 4;
    end
    [~, ordering] = sort(smoothNoise, 'ascend');
    brokenMask(ringIndex, ordering(1:numberToBreak)) = true;
end
end

function [rendered, binaryMireMask, mireLabelMap] = ...
        renderMires(pointsPixels, visibleMask, imageSize, opts)
heightPixels = imageSize(1);
widthPixels = imageSize(2);
[columnGrid, rowGrid] = meshgrid(1:widthPixels, 1:heightPixels);
center = [(widthPixels + 1) / 2, (heightPixels + 1) / 2];
normalizedRadius = hypot((columnGrid - center(1)) ./ (0.55 * widthPixels), ...
    (rowGrid - center(2)) ./ (0.55 * heightPixels));
rendered = opts.BackgroundLevel + 0.06 .* exp(-1.5 .* normalizedRadius .^ 2);
rendered = rendered .* (0.94 + 0.06 .* exp(-normalizedRadius .^ 4));

allRadii = hypot(pointsPixels(:, :, 1)-center(1), pointsPixels(:, :, 2)-center(2));
innerRingRadius = min(allRadii(isfinite(allRadii)), [], 'all');
if isempty(innerRingRadius)
    innerRingRadius = 0.06*min(imageSize);
end
pupilRadius = max(12, 0.70*innerRingRadius);
pupil = hypot(columnGrid-center(1), rowGrid-center(2)) <= pupilRadius;
rendered(pupil) = 0.055;

lineSigma = max(0.35, opts.RingWidthPixels / 2.355);
numberOfRings = size(pointsPixels, 1);
maximumResponse = zeros(imageSize, 'single');
mireLabelMap = zeros(imageSize, 'uint8');
for ringIndex = 1:numberOfRings
    curve = drawClosedCurve(squeeze(pointsPixels(ringIndex, :, :)), ...
        visibleMask(ringIndex, :), imageSize);
    curve = gaussianBlur(curve, lineSigma);
    peak = max(curve, [], 'all');
    if peak > 0
        curve = curve ./ peak;
    end
    update = single(curve) > maximumResponse;
    maximumResponse(update) = single(curve(update));
    mireLabelMap(update) = uint8(ringIndex);
    rendered = rendered - opts.DarkMireContrast .* curve;
end
binaryMireMask = maximumResponse >= 0.5;
mireLabelMap(~binaryMireMask) = 0;
end

function layer = drawClosedCurve(points, visible, imageSize)
heightPixels = imageSize(1);
widthPixels = imageSize(2);
layer = zeros(imageSize);
numberOfPoints = size(points, 1);
for pointIndex = 1:numberOfPoints
    nextIndex = mod(pointIndex, numberOfPoints) + 1;
    if ~visible(pointIndex) || ~visible(nextIndex)
        continue;
    end
    firstPoint = points(pointIndex, :);
    secondPoint = points(nextIndex, :);
    if any(~isfinite([firstPoint, secondPoint]))
        continue;
    end
    segmentLength = hypot(secondPoint(1) - firstPoint(1), ...
        secondPoint(2) - firstPoint(2));
    sampleCount = max(1, ceil(2 * segmentLength));
    interpolation = (0:(sampleCount - 1)) ./ sampleCount;
    x = firstPoint(1) + interpolation .* (secondPoint(1) - firstPoint(1));
    y = firstPoint(2) + interpolation .* (secondPoint(2) - firstPoint(2));
    layer = layer + bilinearSplat(x, y, heightPixels, widthPixels);
end
end

function layer = bilinearSplat(x, y, heightPixels, widthPixels)
layer = zeros(heightPixels, widthPixels);
x0 = floor(x);
y0 = floor(y);
fractionX = x - x0;
fractionY = y - y0;
rows = [y0, y0, y0 + 1, y0 + 1];
columns = [x0, x0 + 1, x0, x0 + 1];
weights = [(1 - fractionX) .* (1 - fractionY), ...
    fractionX .* (1 - fractionY), ...
    (1 - fractionX) .* fractionY, fractionX .* fractionY];
inside = rows >= 1 & rows <= heightPixels & columns >= 1 & ...
    columns <= widthPixels & weights > 0;
if ~any(inside)
    return;
end
indices = sub2ind([heightPixels, widthPixels], rows(inside), columns(inside));
accumulated = accumarray(indices(:), weights(inside).', ...
    [heightPixels * widthPixels, 1], @sum, 0);
layer = reshape(accumulated, heightPixels, widthPixels);
end

function output = gaussianBlur(input, sigma)
if sigma <= 0
    output = input;
    return;
end
halfWidth = max(1, ceil(3 * sigma));
coordinate = -halfWidth:halfWidth;
kernel = exp(-(coordinate .^ 2) ./ (2 * sigma ^ 2));
kernel = kernel ./ sum(kernel);
output = conv2(conv2(input, kernel, 'same'), kernel.', 'same');
end

function rendered = addGlare(rendered, scenario, opts)
strength = resolveGlareStrength(scenario, opts);
if strength <= 0
    return;
end
[heightPixels, widthPixels] = size(rendered);
if isfield(scenario, 'GlareCenterPixels') && ...
        ~isempty(scenario.GlareCenterPixels)
    center = double(scenario.GlareCenterPixels(:).');
elseif ~isempty(opts.GlareCenterPixels)
    center = opts.GlareCenterPixels(:).';
else
    center = [0.43 * widthPixels, 0.42 * heightPixels];
end
if isfield(scenario, 'GlareSigmaPixels') && ~isempty(scenario.GlareSigmaPixels)
    sigma = double(scenario.GlareSigmaPixels);
elseif ~isempty(opts.GlareSigmaPixels)
    sigma = opts.GlareSigmaPixels;
else
    sigma = 0.055 * min(heightPixels, widthPixels);
end
[x, y] = meshgrid(1:widthPixels, 1:heightPixels);
rendered = rendered + strength .* exp(-((x - center(1)) .^ 2 + ...
    (y - center(2)) .^ 2) ./ (2 * sigma ^ 2));
end

function strength = resolveGlareStrength(scenario, opts)
if isfield(scenario, 'GlareStrength') && ~isempty(scenario.GlareStrength)
    strength = double(scenario.GlareStrength);
else
    strength = opts.GlareStrength;
end
if ~isscalar(strength) || ~isfinite(strength) || strength < 0 || strength > 1
    error('SmartKC:Simulation:InvalidScenario', ...
        'GlareStrength must be a scalar between 0 and 1.');
end
end
