function metrics = computeSimK(surface, cfg)
%COMPUTESIMK Compute SmartKC-style orthogonal simulated keratometry.

radius = cfg.metrics.SimKDiameterMm/2;
sampleRadii = linspace(-radius, radius, 81);
angles = (0:179)';
meanPower = nan(size(angles));
axisValues = surface.Xmm(1, :);
for i = 1:numel(angles)
    xq = sampleRadii*cosd(angles(i));
    yq = sampleRadii*sind(angles(i));
    values = interp2(axisValues, axisValues, surface.AxialPowerD, xq, yq, 'linear');
    if mean(isfinite(values)) >= cfg.metrics.MinimumCoverage
        meanPower(i) = mean(values, 'omitnan');
    end
end

if ~any(isfinite(meanPower))
    error('SmartKC:SimKUnavailable', 'No meridian has enough axial-map coverage for Sim-K.');
end
[flatPower, flatIndex] = min(meanPower, [], 'omitnan');
flatAxisDeg = angles(flatIndex);
steepAxisDeg = mod(flatAxisDeg+90, 180);
steepPower = meanPower(steepAxisDeg+1);

metrics = struct();
metrics.SimKSteepD = steepPower;
metrics.SimKFlatD = flatPower;
metrics.SimKSteepAxisDeg = steepAxisDeg;
metrics.SimKFlatAxisDeg = flatAxisDeg;
metrics.MeanKD = mean([steepPower, flatPower]);
metrics.CylinderD = steepPower-flatPower;
metrics.MeridianAnglesDeg = angles;
metrics.MeanAxialPowerByMeridianD = meanPower;
metrics.CalibrationStatus = "UNCALIBRATED_RESEARCH_OUTPUT";
metrics.IsDeviceCalibrated = cfg.calibration.IsDeviceSpecific;
end
