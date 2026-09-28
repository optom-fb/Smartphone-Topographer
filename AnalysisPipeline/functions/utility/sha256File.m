function hash = sha256File(filePath)
%SHA256FILE Return a lower-case SHA-256 digest for a file.

arguments
    filePath (1,:) char
end

if ~isfile(filePath)
    error('SmartKC:HashInputMissing', 'File not found: %s', filePath);
end

if contains(filePath, '"')
    error('SmartKC:UnsupportedHashPath', ...
        'File paths containing a double quote are not supported.');
end
quotedPath = ['"' filePath '"'];
if ispc
    command = sprintf('certutil -hashfile %s SHA256', quotedPath);
elseif ismac
    command = sprintf('shasum -a 256 %s', quotedPath);
else
    command = sprintf('sha256sum %s', quotedPath);
end
[status, output] = system(command);
if status ~= 0
    error('SmartKC:HashCommandFailed', ...
        'Unable to calculate SHA-256 for %s.\n%s', filePath, output);
end
candidates = regexp(output, '(?i)(?:[0-9a-f]{2}\s*){32}', 'match');
hash = "";
for index = 1:numel(candidates)
    current = lower(string(regexprep(candidates{index}, '\s', '')));
    if strlength(current) == 64
        hash = current;
        break
    end
end
if strlength(hash) ~= 64
    error('SmartKC:HashParseFailed', ...
        'Could not parse the SHA-256 command output for %s.', filePath);
end
end
