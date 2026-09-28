function midpoints = getPlacidoMidpoints(cfg)
%GETPLACIDOMIDPOINTS Convert physical ring boundaries to reflective midlines.

model = cfg.placido.RingRadiusHeightMm;
if size(model, 1) < 3 || size(model, 2) ~= 2
    error('SmartKC:InvalidPlacidoGeometry', ...
        'RingRadiusHeightMm must be an N-by-2 matrix with at least 3 rows.');
end

% SmartKC omits the central black boundary and then averages adjacent rows.
model = model(2:end, :);
r = (model(1:end-1, 1) + model(2:end, 1) ...
    - cfg.placido.ThicknessMm + cfg.placido.ThicknessAdjustmentMm) / 2;
z = (model(1:end-1, 2) + model(2:end, 2)) / 2;
midpoints = [r, z];
midpoints = midpoints(1:min(cfg.placido.MaximumMires, size(midpoints, 1)), :);
end
