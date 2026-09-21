function completed = prepareClassicRadii(radii)
%PREPARECLASSICRADII Reproduce SmartKC's pre-Arc-Step gap filling.
%   Missing samples and angular outliers are filled on circular mire traces,
%   making every retained ring contiguous before the classic Arc-Step method.

completed = radii;
nAngles = size(radii, 2);
for mire = 1:size(radii, 1)
    row = radii(mire, :);
    if nnz(isfinite(row)) < max(8, round(0.10 * nAngles))
        completed(mire, :) = NaN;
        continue
    end
    tripled = [row, row, row];
    tripled = fillmissing(tripled, 'linear', 'EndValues', 'nearest');
    localMedian = movmedian(tripled, 25, 'omitmissing');
    residual = abs(tripled - localMedian);
    localMad = movmedian(residual, 51, 'omitmissing');
    outlier = residual > max(2.5, 4.5 * localMad);
    tripled(outlier) = localMedian(outlier);
    tripled = movmedian(tripled, 5, 'omitmissing');
    completed(mire, :) = tripled(nAngles+1:2*nAngles);
end

lastUsable = find(any(isfinite(completed), 2), 1, 'last');
if isempty(lastUsable)
    completed(:) = NaN;
else
    completed(lastUsable+1:end, :) = NaN;
end
end
