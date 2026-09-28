function caseId = deriveCaseId(sourcePath)
%DERIVECASEID Create a short, cross-platform CaseID from a source filename.
%   The source stem is lower-cased, whitespace/punctuation becomes an
%   underscore, and unsafe or overly long identifiers are rejected.

if ~(ischar(sourcePath) || (isstring(sourcePath) && isscalar(sourcePath)))
    error('SmartKC:InvalidCaseIdSource', ...
        'sourcePath must be a character vector or scalar string.');
end
[~, sourceStem, ~] = fileparts(char(sourcePath));
caseId = lower(string(sourceStem));
caseId = regexprep(caseId, '[^a-z0-9_-]+', '_');
caseId = regexprep(caseId, '^[_-]+|[_-]+$', '');

if strlength(caseId) == 0
    error('SmartKC:InvalidCaseId', ...
        'The source filename does not contain a usable CaseID.');
end
if strlength(caseId) > 32
    error('SmartKC:CaseIdTooLong', ...
        ['CaseID "%s" is %d characters; rename the source using at most ' ...
         '32 anonymized letters, numbers, underscores, or hyphens.'], ...
        caseId, strlength(caseId));
end

reserved = ["con","prn","aux","nul", ...
    "com1","com2","com3","com4","com5","com6","com7","com8","com9", ...
    "lpt1","lpt2","lpt3","lpt4","lpt5","lpt6","lpt7","lpt8","lpt9"];
if any(caseId == reserved)
    error('SmartKC:ReservedCaseId', ...
        'CaseID "%s" is reserved on Windows; rename the source image.', caseId);
end
end
