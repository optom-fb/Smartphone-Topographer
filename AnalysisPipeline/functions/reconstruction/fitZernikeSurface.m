function surface = fitZernikeSurface(reconstruction, cfg)
%FITZERNIKEURFACE Fit a real Zernike surface and derive curvature maps.
%   Missing SmartKC++ mires are extrapolated only here, using all available
%   two-dimensional neighbours as described by Ganatra et al. (2025).

if isempty(reconstruction.Points) || height(reconstruction.Points) < cfg.surface.MinimumPointCount
    error('SmartKC:InsufficientSurfacePoints', ...
        'Only %d reconstructed points are available; at least %d are required.', ...
        height(reconstruction.Points), cfg.surface.MinimumPointCount);
end

points = reconstruction.Points;
valid = isfinite(points.Xmm) & isfinite(points.Ymm) & isfinite(points.SagMm) & ...
    points.SagMm >= -0.2 & points.SagMm <= cfg.reconstruction.MaximumSagMm;
if ismember('Converged', points.Properties.VariableNames)
    valid = valid & points.Converged;
end
validPointCount = nnz(valid);
if validPointCount < cfg.surface.MinimumPointCount
    error('SmartKC:InsufficientValidSurfacePoints', ...
        ['Only %d of %d reconstructed points are converged and inside the ' ...
         'valid sag range; at least %d are required. Check mire labels and calibration.'], ...
        validPointCount, height(points), cfg.surface.MinimumPointCount);
end
x = points.Xmm(valid);
y = points.Ymm(valid);
z = points.SagMm(valid);

radius = hypot(x, y);
fitRadiusMm = min(cfg.surface.MaximumMapRadiusMm, max(radius));
if fitRadiusMm <= 0
    error('SmartKC:DegenerateSurface', 'Reconstructed points have zero radial extent.');
end
rho = radius / fitRadiusMm;
inside = rho <= 1;
x = x(inside);
y = y(inside);
z = z(inside);
rho = rho(inside);
theta = atan2(y, x);
insidePointCount = numel(z);
if insidePointCount < cfg.surface.MinimumPointCount
    error('SmartKC:InsufficientValidSurfacePoints', ...
        ['Only %d valid points fall inside the %.2f mm fitting radius; ' ...
         'at least %d are required. Check mire labels and calibration.'], ...
        insidePointCount, fitRadiusMm, cfg.surface.MinimumPointCount);
end
z(end+1, 1) = 0;
rho(end+1, 1) = 0;
theta(end+1, 1) = 0;

[design, modes] = realZernikeBasis(rho, theta, cfg.surface.ZernikeDegree);
lambda = cfg.surface.RidgeLambda;
penalty = sqrt(lambda) * eye(size(design, 2));
weights = ones(size(z));
coefficients = zeros(size(design, 2), 1);
for iteration = 1:4
    weightedDesign = design .* sqrt(weights);
    weightedZ = z .* sqrt(weights);
    coefficients = [weightedDesign; penalty] \ ...
        [weightedZ; zeros(size(penalty, 1), 1)];
    residuals = z-design*coefficients;
    scale = 1.4826 * median(abs(residuals-median(residuals))) + eps;
    huber = 1.345 * scale;
    weights = min(1, huber ./ max(abs(residuals), eps));
end

gridAxis = linspace(-fitRadiusMm, fitRadiusMm, cfg.surface.GridSize);
[xGrid, yGrid] = meshgrid(gridAxis, gridAxis);
rhoGrid = hypot(xGrid, yGrid) / fitRadiusMm;
thetaGrid = atan2(yGrid, xGrid);
gridDesign = realZernikeBasis(rhoGrid(:), thetaGrid(:), cfg.surface.ZernikeDegree);
zFull = reshape(gridDesign*coefficients, size(xGrid));
discMask = rhoGrid <= 1;

spacing = gridAxis(2)-gridAxis(1);
[zx, zy] = gradient(zFull, spacing, spacing);
[zxx, zxyA] = gradient(zx, spacing, spacing);
[zxyB, zyy] = gradient(zy, spacing, spacing);
zxy = 0.5*(zxyA+zxyB);
angle = atan2(yGrid, xGrid);
cosAngle = cos(angle);
sinAngle = sin(angle);
radialSlope = zx.*cosAngle + zy.*sinAngle;
radialSecond = zxx.*cosAngle.^2 + 2*zxy.*sinAngle.*cosAngle + ...
    zyy.*sinAngle.^2;
tangentialCurvature = abs(radialSecond) ./ (1+radialSlope.^2).^(3/2);
tangentialPowerD = cfg.metrics.DioptreFactor*tangentialCurvature;
axialPowerAnalyticD = cfg.metrics.DioptreFactor*abs(radialSlope) ./ ...
    max(hypot(xGrid, yGrid).*sqrt(1+radialSlope.^2), eps);
centerIndex = ceil(size(xGrid, 1)/2);
axialPowerAnalyticD(centerIndex, centerIndex) = ...
    tangentialPowerD(centerIndex, centerIndex);
axialPowerD = radialAveragePower(tangentialPowerD, xGrid, yGrid, discMask);

zGrid = zFull;
zGrid(~discMask) = NaN;
tangentialPowerD(~discMask) = NaN;
axialPowerAnalyticD(~discMask) = NaN;
axialPowerD(~discMask) = NaN;

fitted = design*coefficients;
fitResiduals = z-fitted;
surface = struct();
surface.Variant = reconstruction.Variant;
surface.Xmm = xGrid;
surface.Ymm = yGrid;
surface.SagMm = zGrid;
surface.Mask = discMask;
surface.TangentialPowerD = tangentialPowerD;
surface.AxialPowerAnalyticD = axialPowerAnalyticD;
surface.AxialPowerD = axialPowerD;
surface.Coefficients = coefficients;
surface.Modes = modes;
surface.FitRadiusMm = fitRadiusMm;
surface.FitPointCount = numel(z);
surface.MeasuredFitPointCount = insidePointCount;
surface.FitRMSEum = 1000*sqrt(mean(fitResiduals.^2));
surface.FitMedianAbsoluteResidualUm = 1000*median(abs(fitResiduals));
surface.FitResidualsMm = fitResiduals;
surface.RegistryVersion = string(cfg.RegistryVersion);
end

function axialPower = radialAveragePower(tangentialPower, xGrid, yGrid, mask)
axisValues = xGrid(1, :);
axialPower = nan(size(tangentialPower));
valid = find(mask);
numberOfSamples = 64;
fractions = linspace(0, 1, numberOfSamples);
for index = 1:numel(valid)
    linearIndex = valid(index);
    targetX = xGrid(linearIndex);
    targetY = yGrid(linearIndex);
    values = interp2(axisValues, axisValues, tangentialPower, ...
        targetX*fractions, targetY*fractions, 'linear');
    axialPower(linearIndex) = mean(values, 'omitnan');
end
end

function [basis, modes] = realZernikeBasis(rho, theta, maximumDegree)
rho = rho(:);
theta = theta(:);
modeN = zeros(0, 1);
modeM = zeros(0, 1);
columns = cell(0, 1);
for n = 0:maximumDegree
    for m = -n:2:n
        absoluteM = abs(m);
        radial = zeros(size(rho));
        for s = 0:(n-absoluteM)/2
            coefficient = (-1)^s * factorial(n-s) / ...
                (factorial(s)*factorial((n+absoluteM)/2-s)* ...
                 factorial((n-absoluteM)/2-s));
            radial = radial + coefficient*rho.^(n-2*s);
        end
        if m < 0
            angular = sin(absoluteM*theta);
        elseif m > 0
            angular = cos(m*theta);
        else
            angular = ones(size(theta));
        end
        columns{end+1, 1} = radial.*angular; %#ok<AGROW>
        modeN(end+1, 1) = n; %#ok<AGROW>
        modeM(end+1, 1) = m; %#ok<AGROW>
    end
end
basis = horzcat(columns{:});
modes = table(modeN, modeM, 'VariableNames', {'RadialDegree','AzimuthalFrequency'});
end
