function reconstruction = arcStepReconstruct(matrices, pre, cfg, variant)
%ARCSTEPRECONSTRUCT Reconstruct meridional corneal points with Arc-Step.
%   VARIANT="smartkc" first fills every retained mire trace. VARIANT=
%   "smartkcpp" skips absent mires and continues from the last available
%   inner point, leaving two-dimensional extrapolation to the surface fit.

arguments
    matrices struct
    pre struct
    cfg struct
    variant (1,1) string {mustBeMember(variant, ["smartkc", "smartkcpp"])}
end

radii = matrices.RadiiPx;
if variant == "smartkc"
    radiiForArc = prepareClassicRadii(radii);
    missingPolicy = cfg.reconstruction.ClassicMissingPolicy;
else
    radiiForArc = radii;
    missingPolicy = cfg.reconstruction.RobustMissingPolicy;
end

midpoints = getPlacidoMidpoints(cfg);
maximumMires = min([size(radiiForArc, 1), size(midpoints, 1), ...
    cfg.placido.MaximumMires]);
radiiForArc = radiiForArc(1:maximumMires, :);
anglesDeg = matrices.AnglesDeg(:)';
nAngles = numel(anglesDeg);
if size(radiiForArc, 2) ~= nAngles
    error('SmartKC:ArcStepDimensionMismatch', ...
        'Radii columns must match the number of sampled angles.');
end

sensorSizeMm = getProcessingSensorSizeMm(pre, cfg);
sensorWidth = sensorSizeMm(1);
sensorHeight = sensorSizeMm(2);
imageWidth = pre.OriginalSize(2);
imageHeight = pre.OriginalSize(1);
focalLength = cfg.camera.FocalLengthMm;
workingDistance = cfg.camera.WorkingDistanceMm;

allRows = cell(nAngles, 1);
meridianSummary = repmat(struct('AngleDeg', NaN, 'AvailableMires', 0, ...
    'ReconstructedMires', 0, 'ConvergedFraction', 0, 'Status', ""), nAngles, 1);

for angleIndex = 1:nAngles
    angle = anglesDeg(angleIndex);
    currentRadii = radiiForArc(:, angleIndex);
    available = find(isfinite(currentRadii));
    meridianSummary(angleIndex).AngleDeg = angle;
    meridianSummary(angleIndex).AvailableMires = numel(available);
    if numel(available) < cfg.reconstruction.MinimumMiresPerMeridian || ...
            ~ismember(1, available)
        meridianSummary(angleIndex).Status = "insufficient-inner-mires";
        continue
    end

    xPixel = abs(currentRadii(available) * cosd(angle));
    yPixel = abs(currentRadii(available) * sind(angle));
    k = hypot(xPixel * sensorWidth / imageWidth, ...
        yPixel * sensorHeight / imageHeight) / focalLength;

    oppositeAngle = mod(angle + 180, 360);
    [oppositeDistance, oppositeIndex] = min(abs(wrapTo180(anglesDeg-oppositeAngle)));
    firstK = k(available == 1);
    if isempty(firstK)
        meridianSummary(angleIndex).Status = "missing-first-mire";
        continue
    end
    if oppositeDistance <= 0.51 * cfg.localization.AngleStepDeg && ...
            isfinite(radiiForArc(1, oppositeIndex))
        oppositeRadius = radiiForArc(1, oppositeIndex);
        oppositeK = hypot(abs(oppositeRadius*cosd(oppositeAngle))*sensorWidth/imageWidth, ...
            abs(oppositeRadius*sind(oppositeAngle))*sensorHeight/imageHeight) / focalLength;
        centralK = mean([firstK, oppositeK]);
    else
        centralK = firstK;
    end

    [surface, status] = constructMeridian(available, k, centralK, ...
        midpoints, workingDistance, cfg.reconstruction);
    meridianSummary(angleIndex).Status = status;
    if isempty(surface)
        continue
    end
    surface.AngleDeg(:) = angle;
    surface.AngleIndex(:) = angleIndex;
    surface.Xmm = surface.RadialMm .* cosd(angle);
    surface.Ymm = -surface.RadialMm .* sind(angle); % clinical plots: superior is +y
    allRows{angleIndex} = surface;
    meridianSummary(angleIndex).ReconstructedMires = height(surface);
    meridianSummary(angleIndex).ConvergedFraction = mean(surface.Converged);
end

nonempty = ~cellfun(@isempty, allRows);
if any(nonempty)
    points = vertcat(allRows{nonempty});
else
    points = table();
end
summary = struct2table(meridianSummary);

reconstruction = struct();
reconstruction.Variant = variant;
reconstruction.MissingPolicy = missingPolicy;
reconstruction.Points = points;
reconstruction.MeridianSummary = summary;
reconstruction.RadiiInputPx = radii;
reconstruction.RadiiUsedPx = radiiForArc;
reconstruction.AnglesDeg = anglesDeg;
reconstruction.PlacidoMidpointsMm = midpoints;
reconstruction.CalibrationProfile = cfg.calibration.ProfileName;
reconstruction.IsDeviceCalibrated = cfg.calibration.IsDeviceSpecific;
end

function [surface, status] = constructMeridian(ringIndices, kValues, centralK, ...
        midpoints, workingDistance, settings)
keys = [0; ringIndices(:)];
kByKey = [centralK; kValues(:)];
oyByKey = [midpoints(1, 1); midpoints(ringIndices, 1)];
ozByKey = [midpoints(1, 2)-workingDistance; ...
    midpoints(ringIndices, 2)-workingDistance];
p = -workingDistance;

rows = zeros(numel(keys)-1, 7);
rowCount = 0;
zOld = 0;
yOld = 0;
slopeOld = 0;
quadraticOld = 0;
status = "ok";
centralSag = NaN;

for position = 1:numel(keys)
    key = keys(position);
    k = kByKey(position);
    oy = oyByKey(position);
    oz = ozByKey(position);
    step = settings.InitialStepMm;
    if key > 0 && position == 2
        % The reference Arc-Step uses the artificial central solution only
        % to establish apex quadratic curvature. The first physical mire
        % is then stepped from the apex state, not from the artificial
        % central-ray endpoint.
        zOld = 0;
        yOld = 0;
        slopeOld = 0;
        z = centralSag;
    else
        z = zOld;
    end
    residual = Inf;
    slope = slopeOld;
    cubic = 0;
    y = (-p+z) * k;
    converged = false;

    for iteration = 1:settings.MaximumIterations
        y = (-p+z) * k;
        if key == 0
            if abs(y) < eps
                status = "degenerate-central-ray";
                surface = table();
                return
            end
            quadraticTrial = 2*z/y^2;
            cubic = 0;
            deltaY = y;
        else
            deltaY = y-yOld;
            if abs(deltaY) < 1e-10
                status = "degenerate-mire-spacing";
                surface = table();
                return
            end
            quadraticTrial = quadraticOld;
            cubic = 6*(z-zOld-slopeOld*deltaY-0.5*quadraticOld*deltaY^2) / deltaY^3;
        end
        slope = slopeOld + quadraticTrial*deltaY + 0.5*cubic*deltaY^2;
        objectSlope = (oy-y) / (-oz+z);
        cosObject = (objectSlope-slope) / sqrt((1+objectSlope^2)*(1+slope^2));
        cosCamera = (k+slope) / sqrt((1+k^2)*(1+slope^2));
        residual = cosObject-cosCamera;
        if residual*step < 0
            step = -step/3;
        end
        z = z+step;
        if abs(step) <= settings.MinimumStepMm
            converged = true;
            break
        end
    end

    if key == 0
        quadraticOld = quadraticTrial;
        centralSag = z;
    else
        quadraticOld = quadraticOld+cubic*(y-yOld);
    end
    zOld = z;
    yOld = y;
    slopeOld = slope;

    if key > 0
        rowCount = rowCount+1;
        curvature = abs(quadraticOld)/(1+slope^2)^(3/2);
        rows(rowCount, :) = [key, y, z, curvature, residual, iteration, converged];
    end
end

rows = rows(1:rowCount, :);
surface = array2table(rows, 'VariableNames', ...
    {'MireIndex','RadialMm','SagMm','MeridionalCurvaturePerMm', ...
     'ReflectionResidual','Iterations','Converged'});
surface.MireIndex = round(surface.MireIndex);
surface.Iterations = round(surface.Iterations);
surface.Converged = logical(surface.Converged);
surface = surface(isfinite(surface.SagMm) & ...
    surface.SagMm < settings.MaximumSagMm & surface.RadialMm > 0, :);
end
