function manifest = buildInputManifest(imagePaths, cfg)
%BUILDINPUTMANIFEST Decode images and record provenance/basic input QC.

imagePaths = string(imagePaths(:));
n = numel(imagePaths);
SourcePath = imagePaths;
ImageId = strings(n, 1);
CaseId = strings(n, 1);
WidthPx = nan(n, 1);
HeightPx = nan(n, 1);
Channels = nan(n, 1);
BitDepth = nan(n, 1);
DecodeOK = false(n, 1);
Message = strings(n, 1);

for i = 1:n
    [~, ImageId(i), ~] = fileparts(SourcePath(i));
    CaseId(i) = deriveCaseId(SourcePath(i));
    try
        info = imfinfo(SourcePath(i));
        WidthPx(i) = info.Width;
        HeightPx(i) = info.Height;
        BitDepth(i) = info.BitDepth;
        image = imread(SourcePath(i));
        Channels(i) = size(image, 3);
        DecodeOK(i) = true;
        Message(i) = "OK";
    catch exception
        Message(i) = string(exception.message);
    end
end

if n > 0
    [uniqueCaseIds, ~, groups] = unique(CaseId);
    counts = accumarray(groups, 1);
    duplicates = uniqueCaseIds(counts > 1);
    if ~isempty(duplicates)
        error('SmartKC:DuplicateCaseId', ...
            ['Duplicate CaseID(s) after filename normalization: %s. ' ...
             'Rename the source images so every short anonymized stem is unique.'], ...
            strjoin(duplicates, ', '));
    end
end

RegistryVersion = repmat(string(cfg.RegistryVersion), n, 1);
manifest = table(CaseId, ImageId, SourcePath, WidthPx, HeightPx, Channels, BitDepth, ...
    DecodeOK, RegistryVersion, Message);
end
