function plotCompleteMireAxes(axisHandle, variant, pre, cfg, heading)
%PLOTCOMPLETEMIREAXES Plot complete mire traces and harmonic axes in mm.

metrics = variant.EigenRatio.Metrics;
primary = metrics(metrics.IsIncludedInPrimary, :);
hold(axisHandle, 'on');
colours = lines(max(height(primary), 1));
sensorSizeMm = getProcessingSensorSizeMm(pre, cfg);
pitchXmm = sensorSizeMm(1) / pre.OriginalSize(2);
pitchYmm = sensorSizeMm(2) / pre.OriginalSize(1);
for row = 1:height(primary)
    mire = primary.MireIndex(row);
    valid = isfinite(variant.Matrices.X(mire, :)) & ...
        isfinite(variant.Matrices.Y(mire, :));
    xMm = (variant.Matrices.X(mire, valid)-pre.CenterPx(1))*pitchXmm;
    yMm = -(variant.Matrices.Y(mire, valid)-pre.CenterPx(2))*pitchYmm;
    plot(axisHandle, xMm, yMm, '.', 'Color', colours(row, :), ...
        'MarkerSize', 7, 'DisplayName', sprintf('Mire %d', mire));
    center = [primary.CenterXmm(row), primary.CenterYmm(row)];
    majorAngle = primary.MajorRadiusAxisDegCCW(row);
    minorAngle = primary.PerpendicularAxisDegCCW(row);
    majorVector = primary.MajorExtentMm(row)* ...
        [cosd(majorAngle), sind(majorAngle)];
    minorVector = primary.MinorExtentMm(row)* ...
        [cosd(minorAngle), sind(minorAngle)];
    plot(axisHandle, center(1)+[-1; 1]*majorVector(1), ...
        center(2)+[-1; 1]*majorVector(2), '--', ...
        'Color', colours(row, :), 'HandleVisibility', 'off');
    plot(axisHandle, center(1)+[-1; 1]*minorVector(1), ...
        center(2)+[-1; 1]*minorVector(2), '--', ...
        'Color', colours(row, :), 'HandleVisibility', 'off');
end
grid(axisHandle, 'on');
axis(axisHandle, 'equal');
xlabel(axisHandle, 'Sensor x (mm)');
ylabel(axisHandle, 'Sensor y (mm; superior +)');
title(axisHandle, heading);
if height(primary) > 0
    legend(axisHandle, 'Location', 'eastoutside');
end
end
