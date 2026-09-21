function segmentation = segmentMiresClassical(pre, cfg, mode)
%SEGMENTMIRESCLASSICAL Segment dark Placido bands using local enhancement.
%   MODE="smartkc" uses a direct band-pass/adaptive threshold. MODE="robust"
%   adds a morphological dark-line response and more conservative cleanup.

arguments
    pre struct
    cfg struct
    mode (1,1) string {mustBeMember(mode, ["smartkc", "robust"])} = "smartkc"
end

gray = im2single(pre.NormalizedGray);
small = imgaussfilt(gray, cfg.segmentation.SmallGaussianSigmaPx);
large = imgaussfilt(gray, cfg.segmentation.LargeGaussianSigmaPx);
response = max(large - small, 0);

if mode == "robust"
    radius = max(2, round(cfg.segmentation.LargeGaussianSigmaPx / 2));
    bottomHat = imbothat(gray, strel('disk', radius, 0));
    bottomHat = mat2gray(bottomHat);
    response = 0.68 * mat2gray(response) + 0.32 * bottomHat;
else
    response = mat2gray(response);
end

[height, width] = size(gray);
[xx, yy] = meshgrid(1:width, 1:height);
rr = hypot(xx-pre.CenterPx(1), yy-pre.CenterPx(2));
annulus = rr >= cfg.localization.InnerRadiusPx & rr <= pre.AnalysisRadiusPx;
values = response(annulus);
globalThreshold = quantile(values, cfg.segmentation.ResponseQuantile);
adaptiveThreshold = adaptthresh(response, cfg.segmentation.AdaptiveSensitivity, ...
    'ForegroundPolarity', 'bright', 'NeighborhoodSize', 2*floor(min(size(gray))/16)+1);
mask = response > max(globalThreshold * 0.72, adaptiveThreshold);
mask = mask & annulus;

if mode == "robust"
    mask = imclose(mask, strel('disk', cfg.segmentation.MaximumGapToBridgePx, 0));
end
mask = bwareaopen(mask, cfg.segmentation.MinimumComponentAreaPx, 8);
mask = bwmorph(mask, 'clean');

segmentation = struct();
segmentation.Mask = mask;
segmentation.Response = response;
segmentation.MethodRequested = mode;
segmentation.MethodActual = "classical-" + mode;
segmentation.ModelFile = "";
segmentation.UsedFallback = false;
segmentation.Threshold = globalThreshold;
segmentation.ForegroundFraction = mean(mask(annulus));
end
