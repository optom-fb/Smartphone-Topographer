function [metrics, surface] = computeSyntheticTruthSimK(truth, cfg)
%COMPUTESYNTHETICTRUTHSIMK Compute matched 3 mm SimK from dense truth sag.
%   The simulator's physical y-positive-superior coordinates are mirrored
%   into the reconstruction convention before the ordinary Zernike and
%   SimK functions are applied. Nominal apical K is intentionally not used.

arguments
    truth struct
    cfg struct
end
required = {'xMm', 'yMm', 'sagMm'};
if ~isfield(truth, 'surface') || ...
        any(~isfield(truth.surface, required))
    error('SmartKC:SyntheticTruthSimK:MissingSurface', ...
        'truth.surface must contain xMm, yMm, and sagMm.');
end
x = truth.surface.xMm;
y = -truth.surface.yMm;
z = truth.surface.sagMm;
valid = isfinite(z) & hypot(x, y) <= cfg.surface.MaximumMapRadiusMm;
points = table(x(valid), y(valid), z(valid), true(nnz(valid), 1), ...
    'VariableNames', {'Xmm', 'Ymm', 'SagMm', 'Converged'});
reconstruction = struct('Variant', "truth-reference", 'Points', points);
surface = fitZernikeSurface(reconstruction, cfg);
metrics = computeSimK(surface, cfg);
end
