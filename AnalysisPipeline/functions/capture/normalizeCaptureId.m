function value = normalizeCaptureId(value, fieldName)
%NORMALIZECAPTUREID Convert an operator label to a safe filename component.

arguments
    value {mustBeTextScalar}
    fieldName {mustBeTextScalar} = "value"
end

value = lower(strtrim(string(value)));
value = regexprep(value, '[^a-z0-9_-]+', '_');
value = regexprep(value, '^[_-]+|[_-]+$', '');
if strlength(value) > 32
    value = extractBefore(value, 33);
end

if strlength(value) == 0
    error('SmartKC:InvalidCaptureId', ...
        '%s must contain at least one letter or number.', fieldName);
end
end
