function ensureFolder(folderPath)
%ENSUREFOLDER Create a folder when it does not already exist.
if ~isfolder(folderPath)
    mkdir(folderPath);
end
end
