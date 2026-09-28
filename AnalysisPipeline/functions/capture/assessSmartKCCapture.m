function quality = assessSmartKCCapture(imageData)
%ASSESSSMARTKCCAPTURE Provide immediate non-clinical image-capture checks.

arguments
    imageData {mustBeNumeric, mustBeNonempty}
end

if ndims(imageData) == 3
    gray = im2gray(imageData);
else
    gray = imageData;
end
gray = im2single(gray);

laplacianKernel = [0 1 0; 1 -4 1; 0 1 0];
laplacianResponse = imfilter(gray, laplacianKernel, 'replicate');

quality = struct();
quality.MeanIntensity = mean(gray, 'all', 'omitnan');
quality.DarkFraction = mean(gray <= 0.005, 'all');
quality.SaturatedFraction = mean(gray >= 0.995, 'all');
quality.FocusScore = var(laplacianResponse(:), 'omitnan');
quality.ImageHeightPx = size(gray, 1);
quality.ImageWidthPx = size(gray, 2);

issues = strings(0, 1);
if quality.SaturatedFraction > 0.03
    issues(end+1, 1) = "high saturation";
end
if quality.DarkFraction > 0.20
    issues(end+1, 1) = "large clipped-dark area";
end
if quality.FocusScore < 2e-4
    issues(end+1, 1) = "possible blur";
end
if quality.MeanIntensity < 0.08 || quality.MeanIntensity > 0.92
    issues(end+1, 1) = "extreme overall brightness";
end

quality.IsAcceptedForReview = isempty(issues);
if quality.IsAcceptedForReview
    quality.Status = "REVIEW_READY";
    quality.Message = "Basic capture checks passed; inspect mire focus and completeness.";
else
    quality.Status = "REVIEW_REQUIRED";
    quality.Message = "Check " + strjoin(issues, ", ") + ".";
end
end
