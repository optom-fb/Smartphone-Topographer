function [folder, name] = placidoCaptureLocation(projectRoot, backend, subfolder, name)
% Resolve capture folders without allowing an absolute or parent path.
backend = validatestring(backend, {'phone', 'external'});
subfolder = strtrim(string(subfolder));
subfolder = replace(subfolder, '/', filesep);
if contains(subfolder, '..') || startsWith(subfolder, filesep) || ...
        contains(subfolder, ':') || contains(subfolder, ["<", ">", '"', "|", "?", "*"])
    error('Placido:Folder', 'Use a relative output subfolder, e.g. Test, without parent paths.');
end
name = regexprep(strtrim(string(name)), '[<>:"/\\|?*]', '_');
name = regexprep(name, '\s+', '_');
if strlength(name) == 0
    error('Placido:Filename', 'Enter a filename beginning, e.g. eye.');
end
if strcmp(backend, 'phone'), channel = 'Smart_Phone'; else, channel = 'EXT_Camera'; end
folder = fullfile(projectRoot, 'Data', 'GUI Data', channel, char(subfolder));
name = char(name);
end
