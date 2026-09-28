function manifest = generateSyntheticPlacidoDataset(outputRoot, cfg, scenarios)
%GENERATESYNTHETICPLACIDODATASET Write images, truth MAT files and a manifest.
%   MANIFEST = GENERATESYNTHETICPLACIDODATASET(OUTPUTROOT, CFG, SCENARIOS)
%   writes Images/*.png, GroundTruth/*.mat, exact mask/label PNGs, and
%   manifest.csv. SCENARIOS is a
%   structure array accepted by SIMULATEPLACIDOIMAGE. If it is omitted or
%   empty, DEFAULTSYNTHETICSCENARIOS is used. Each case gets a deterministic
%   seed cfg.simulation.RandomSeed + case index - 1.
%
%   Existing files with the same generated names are replaced. This output
%   is for engineering research and must not be treated as clinical data.

if nargin < 3 || isempty(scenarios)
    scenarios = defaultSyntheticScenarios();
end
if ~(ischar(outputRoot) || (isstring(outputRoot) && isscalar(outputRoot)))
    error('SmartKC:Simulation:InvalidOutputRoot', ...
        'outputRoot must be a character vector or scalar string.');
end
if ~isstruct(scenarios) || isempty(scenarios)
    error('SmartKC:Simulation:InvalidScenarios', ...
        'scenarios must be a nonempty structure array.');
end
outputRoot = char(outputRoot);
imageDirectory = fullfile(outputRoot, 'Images');
truthDirectory = fullfile(outputRoot, 'GroundTruth');
maskDirectory = fullfile(outputRoot, 'GroundTruthMasks');
labelDirectory = fullfile(outputRoot, 'GroundTruthLabels');
createDirectory(outputRoot);
createDirectory(imageDirectory);
createDirectory(truthDirectory);
createDirectory(maskDirectory);
createDirectory(labelDirectory);

numberOfCases = numel(scenarios);
caseIndex = (1:numberOfCases).';
scenarioName = strings(numberOfCases, 1);
surfaceClass = strings(numberOfCases, 1);
severity = strings(numberOfCases, 1);
astigmatismOrientation = strings(numberOfCases, 1);
imageFile = strings(numberOfCases, 1);
groundTruthFile = strings(numberOfCases, 1);
groundTruthMaskFile = strings(numberOfCases, 1);
groundTruthLabelFile = strings(numberOfCases, 1);
randomSeed = zeros(numberOfCases, 1);
rFlatMm = zeros(numberOfCases, 1);
rSteepMm = zeros(numberOfCases, 1);
axisDeg = zeros(numberOfCases, 1);
q = zeros(numberOfCases, 1);
cylinderMagnitudeD = zeros(numberOfCases, 1);
coneAmplitudeMm = zeros(numberOfCases, 1);
coneCenterXmm = zeros(numberOfCases, 1);
coneCenterYmm = zeros(numberOfCases, 1);
coneSigmaMm = zeros(numberOfCases, 1);
brokenArcFraction = zeros(numberOfCases, 1);
glareStrength = zeros(numberOfCases, 1);
noiseSigma = zeros(numberOfCases, 1);
blurSigma = zeros(numberOfCases, 1);

for index = 1:numberOfCases
    cfgForCase = cfg;
    cfgForCase.simulation.RandomSeed = double(cfg.simulation.RandomSeed) + index - 1;
    [generatedImage, truth] = simulatePlacidoImage(scenarios(index), cfgForCase);
    safeName = sanitizeName(scenarios(index).Name);
    stem = sprintf('%02d_%s', index, safeName);
    imageName = [stem, '.png'];
    truthName = [stem, '.mat'];
    maskName = [stem, '_mask.png'];
    labelName = [stem, '_labels.png'];
    imwrite(generatedImage, fullfile(imageDirectory, imageName));
    save(fullfile(truthDirectory, truthName), 'truth', '-v7');
    imwrite(truth.segmentation.BinaryMireMask, ...
        fullfile(maskDirectory, maskName));
    imwrite(truth.segmentation.MireLabelMap, ...
        fullfile(labelDirectory, labelName));

    scenarioName(index) = string(scenarios(index).Name);
    surfaceClass(index) = scenarioText(scenarios(index), ...
        'SurfaceClass', "unspecified");
    severity(index) = scenarioText(scenarios(index), ...
        'Severity', "unspecified");
    astigmatismOrientation(index) = scenarioText(scenarios(index), ...
        'AstigmatismOrientation', "unspecified");
    imageFile(index) = "Images/" + string(imageName);
    groundTruthFile(index) = "GroundTruth/" + string(truthName);
    groundTruthMaskFile(index) = "GroundTruthMasks/" + string(maskName);
    groundTruthLabelFile(index) = "GroundTruthLabels/" + string(labelName);
    randomSeed(index) = cfgForCase.simulation.RandomSeed;
    rFlatMm(index) = scenarios(index).RflatMm;
    rSteepMm(index) = scenarios(index).RsteepMm;
    axisDeg(index) = scenarios(index).AxisDeg;
    q(index) = scenarios(index).Q;
    cylinderMagnitudeD(index) = truth.derived.cylinderMagnitudeD;
    coneAmplitudeMm(index) = scenarios(index).ConeAmplitudeMm;
    coneCenter = double(scenarios(index).ConeCenterMm(:).');
    coneCenterXmm(index) = coneCenter(1);
    coneCenterYmm(index) = coneCenter(2);
    coneSigmaMm(index) = scenarios(index).ConeSigmaMm;
    brokenArcFraction(index) = scenarios(index).BrokenArcFraction;
    glareStrength(index) = scenarioNumeric(scenarios(index), ...
        'GlareStrength', cfg.simulation.GlareStrength);
    noiseSigma(index) = scenarios(index).NoiseSigma;
    blurSigma(index) = scenarios(index).BlurSigma;
end

axisConvention = repmat("flat-meridian-degrees", numberOfCases, 1);
manifest = table(caseIndex, scenarioName, surfaceClass, severity, ...
    astigmatismOrientation, imageFile, groundTruthFile, ...
    groundTruthMaskFile, groundTruthLabelFile, ...
    randomSeed, rFlatMm, rSteepMm, axisDeg, q, cylinderMagnitudeD, ...
    coneAmplitudeMm, coneCenterXmm, coneCenterYmm, coneSigmaMm, ...
    brokenArcFraction, glareStrength, noiseSigma, blurSigma, axisConvention, ...
    'VariableNames', {'CaseIndex', 'ScenarioName', 'SurfaceClass', ...
    'Severity', 'AstigmatismOrientation', 'ImageFile', 'GroundTruthFile', ...
    'GroundTruthMaskFile', 'GroundTruthLabelFile', ...
    'RandomSeed', 'RflatMm', 'RsteepMm', 'AxisDeg', ...
    'Q', 'CylinderMagnitudeD', 'ConeAmplitudeMm', 'ConeCenterXmm', ...
    'ConeCenterYmm', 'ConeSigmaMm', 'BrokenArcFraction', 'GlareStrength', ...
    'NoiseSigma', 'BlurSigma', 'AxisConvention'});
writetable(manifest, fullfile(outputRoot, 'manifest.csv'));
end

function createDirectory(path)
if ~isfolder(path)
    [created, message] = mkdir(path);
    if ~created
        error('SmartKC:Simulation:CreateDirectoryFailed', ...
            'Could not create %s: %s', path, message);
    end
end
end

function safeName = sanitizeName(name)
safeName = lower(char(string(name)));
safeName = regexprep(safeName, '[^a-z0-9]+', '_');
safeName = regexprep(safeName, '^_+|_+$', '');
if isempty(safeName)
    safeName = 'scenario';
end
end

function value = scenarioText(scenario, fieldName, fallback)
if isfield(scenario, fieldName) && strlength(string(scenario.(fieldName))) > 0
    value = string(scenario.(fieldName));
else
    value = fallback;
end
end

function value = scenarioNumeric(scenario, fieldName, fallback)
if isfield(scenario, fieldName) && ~isempty(scenario.(fieldName))
    value = double(scenario.(fieldName));
else
    value = double(fallback);
end
end
