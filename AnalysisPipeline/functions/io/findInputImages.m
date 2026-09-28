function files = findInputImages(dataRoot, cfg)
%FINDINPUTIMAGES Recursively list source images, excluding derived folders.

arguments
    dataRoot (1,:) char
    cfg struct
end

if ~isfolder(dataRoot)
    files = strings(0, 1);
    return
end

listing = dir(fullfile(dataRoot, '**', '*'));
listing = listing(~[listing.isdir]);
files = strings(0, 1);
for i = 1:numel(listing)
    path = string(fullfile(listing(i).folder, listing(i).name));
    [~, ~, ext] = fileparts(path);
    if ~any(strcmpi(ext, cfg.io.InputExtensions))
        continue
    end
    relative = erase(path, string(dataRoot) + filesep);
    parts = split(relative, filesep);
    if any(ismember(lower(parts), lower(cfg.io.IgnoreFolderNames)))
        continue
    end
    files(end+1, 1) = path; %#ok<AGROW>
end
files = sort(files);
end
