function metrics = computeBinarySegmentationMetrics(predictedMask, ...
        truthMask, evaluationMask)
%COMPUTEBINARYSEGMENTATIONMETRICS Compare a mire mask with synthetic truth.

arguments
    predictedMask (:,:) {mustBeNumericOrLogical}
    truthMask (:,:) {mustBeNumericOrLogical}
    evaluationMask (:,:) {mustBeNumericOrLogical} = true(size(truthMask))
end

if ~isequal(size(predictedMask), size(truthMask), size(evaluationMask))
    error('SmartKC:Simulation:SegmentationMetricSizeMismatch', ...
        'Predicted, truth, and evaluation masks must have equal sizes.');
end
predicted = logical(predictedMask) & logical(evaluationMask);
truth = logical(truthMask) & logical(evaluationMask);
domain = logical(evaluationMask);

truePositive = nnz(predicted & truth);
falsePositive = nnz(predicted & ~truth & domain);
falseNegative = nnz(~predicted & truth & domain);
trueNegative = nnz(~predicted & ~truth & domain);

metrics = struct();
metrics.TruePositivePixels = truePositive;
metrics.FalsePositivePixels = falsePositive;
metrics.FalseNegativePixels = falseNegative;
metrics.TrueNegativePixels = trueNegative;
metrics.Dice = safeDivide(2 * truePositive, ...
    2 * truePositive + falsePositive + falseNegative);
metrics.IoU = safeDivide(truePositive, ...
    truePositive + falsePositive + falseNegative);
metrics.Precision = safeDivide(truePositive, truePositive + falsePositive);
metrics.Recall = safeDivide(truePositive, truePositive + falseNegative);
metrics.Specificity = safeDivide(trueNegative, trueNegative + falsePositive);
metrics.PredictedForegroundFraction = safeDivide(nnz(predicted), nnz(domain));
metrics.TruthForegroundFraction = safeDivide(nnz(truth), nnz(domain));
end

function value = safeDivide(numerator, denominator)
if denominator == 0
    value = NaN;
else
    value = numerator / denominator;
end
end
