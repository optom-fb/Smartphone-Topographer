function extraction = extractSmartKCGuidedVideoFrames( ...
        videoPath, timingCsvPath, outputFolder, showContactSheet)
%EXTRACTSMARTKCGUIDEDVIDEOFRAMES Select pupil/ring candidates from guided AVI.
%   Labels follow recorded Arduino command times. They do not prove that the
%   physical illumination changed, so the saved contact sheet must be reviewed.

arguments
    videoPath {mustBeTextScalar}
    timingCsvPath {mustBeTextScalar}
    outputFolder {mustBeTextScalar}
    showContactSheet (1,1) logical = true
end
videoPath = char(videoPath);
timingCsvPath = char(timingCsvPath);
outputFolder = char(outputFolder);
if ~isfile(videoPath)
    error('SmartKC:GuidedVideoMissing', 'Video not found: %s', videoPath);
end
if ~isfile(timingCsvPath)
    error('SmartKC:GuidedTimingMissing', ...
        'Matching timing CSV not found: %s', timingCsvPath);
end
ensureFolder(outputFolder);

timing = readtable(timingCsvPath, 'TextType', 'string');
required = {'Event', 'ActualTimeSeconds', 'ArduinoCommand'};
if ~all(ismember(required, timing.Properties.VariableNames))
    error('SmartKC:InvalidGuidedTiming', ...
        'Timing CSV does not contain the required guided-video columns.');
end

reader = VideoReader(videoPath);
settings = struct('TransitionMarginSeconds', 0.5, ...
    'SolidSettlingSeconds', 1.5, 'PupilCandidateCount', 3, ...
    'RingCandidateCount', 3, 'FrameRateFallbackHz', 30);
plan = buildFramePlan(timing, reader.Duration, settings);

frameCount = height(plan);
frames = cell(frameCount, 1);
frameNumbers = zeros(frameCount, 1);
frameTimes = zeros(frameCount, 1);
paths = strings(frameCount, 1);
for index = 1:frameCount
    [frame, frameNumber] = readFrameNearTime( ...
        reader, plan.RequestedTimeSeconds(index));
    actualTime = (frameNumber - 1) / reader.FrameRate;
    outputName = sprintf('%02d_%s_f%05d_t%06.3f.png', index, ...
        plan.SampleName(index), frameNumber, actualTime);
    paths(index) = string(fullfile(outputFolder, outputName));
    imwrite(frame, paths(index));
    frames{index} = frame;
    frameNumbers(index) = frameNumber;
    frameTimes(index) = actualTime;
end

manifest = plan;
manifest.SourceVideoPath = repmat(string(videoPath), frameCount, 1);
manifest.TimingCsvPath = repmat(string(timingCsvPath), frameCount, 1);
manifest.FrameNumber = frameNumbers;
manifest.FrameTimeSeconds = frameTimes;
manifest.OutputImagePath = paths;
[~, videoStem] = fileparts(videoPath);
manifestPath = fullfile(outputFolder, [videoStem '_frame_manifest.csv']);
writetable(manifest, manifestPath);

recommendedIndex = find(manifest.RecommendedForPipeline, 1, 'first');
if isempty(recommendedIndex)
    error('SmartKC:NoRecommendedGuidedFrame', ...
        'The frame-selection plan produced no recommended ring frame.');
end

contactSheetPath = "";
if showContactSheet
    contactSheetPath = string(fullfile(outputFolder, ...
        [videoStem '_frame_contact_sheet.png']));
    createContactSheet(frames, manifest, videoStem, contactSheetPath);
end

extraction = struct();
extraction.Manifest = manifest;
extraction.ManifestPath = string(manifestPath);
extraction.ContactSheetPath = contactSheetPath;
extraction.RecommendedRingImagePath = paths(recommendedIndex);
extraction.RecommendedRingFrame = frames{recommendedIndex};
extraction.PupilCandidatePaths = paths( ...
    manifest.FramePurpose == "pupil_candidate");
end

function plan = buildFramePlan(timing, videoDuration, settings)
recordStart = eventTime(timing, 'record_start_ir_only');
solidOn = eventTime(timing, 'solid_placido_on');
firstBlockOff = eventTime(timing, 'block_1_placido_off');
recordEnd = eventTime(timing, 'record_end_placido_off');

irStart = recordStart + settings.TransitionMarginSeconds;
irEnd = solidOn - settings.TransitionMarginSeconds;
solidStart = solidOn + settings.SolidSettlingSeconds;
solidEnd = firstBlockOff - settings.TransitionMarginSeconds;
if irEnd <= irStart || solidEnd <= solidStart
    error('SmartKC:GuidedIntervalsTooShort', ...
        'The recorded illumination intervals are too short for frame selection.');
end

plan = table('Size', [0 6], ...
    'VariableTypes', {'string','string','double','double','logical','string'}, ...
    'VariableNames', {'SampleName','FramePurpose','BlockNumber', ...
    'RequestedTimeSeconds','RecommendedForPipeline','SelectionReason'});

targets = linspace(irStart, irEnd, settings.PupilCandidateCount);
for index = 1:numel(targets)
    plan = appendRow(plan, sprintf('pupil_ir_%02d', index), ...
        'pupil_candidate', 0, targets(index), false, ...
        'IR-only interval away from the solid-light transition.');
end

targets = linspace(solidStart, solidEnd, settings.RingCandidateCount);
for index = 1:numel(targets)
    plan = appendRow(plan, sprintf('ring_solid_%02d', index), ...
        'ring_candidate', 0, targets(index), false, ...
        'Settled solid Placido interval.');
end
ringRows = find(startsWith(plan.SampleName, "ring_solid_"));
plan.RecommendedForPipeline(ringRows(ceil(numel(ringRows) / 2))) = true;

blocks = blockNumbers(timing);
for index = 1:numel(blocks)
    block = blocks(index);
    off = eventTime(timing, sprintf('block_%d_placido_off', block));
    on = eventTime(timing, sprintf('block_%d_placido_on', block));
    if index < numel(blocks)
        nextOff = eventTime(timing, ...
            sprintf('block_%d_placido_off', blocks(index + 1)));
    else
        nextOff = recordEnd;
    end
    plan = appendRow(plan, sprintf('pair_%02d_off', block), ...
        'paired_pupil_candidate', block, (off + on) / 2, false, ...
        'Midpoint of a commanded OFF block.');
    plan = appendRow(plan, sprintf('pair_%02d_on', block), ...
        'paired_ring_candidate', block, (on + nextOff) / 2, false, ...
        'Midpoint of the adjacent commanded ON block.');
end

plan.RequestedTimeSeconds = min(plan.RequestedTimeSeconds, ...
    max(0, videoDuration - 1 / settings.FrameRateFallbackHz));
end

function result = appendRow(result, name, purpose, block, time, recommended, reason)
result(end+1, :) = {string(name), string(purpose), block, time, ...
    recommended, string(reason)};
end

function value = eventTime(timing, eventName)
row = find(timing.Event == string(eventName), 1, 'first');
if isempty(row) || ~isfinite(timing.ActualTimeSeconds(row))
    error('SmartKC:GuidedEventMissing', ...
        'Required event "%s" is missing or invalid.', eventName);
end
value = timing.ActualTimeSeconds(row);
end

function result = blockNumbers(timing)
result = zeros(height(timing), 1);
count = 0;
for index = 1:height(timing)
    tokens = regexp(timing.Event(index), ...
        '^block_(\d+)_placido_off$', 'tokens', 'once');
    if ~isempty(tokens)
        count = count + 1;
        result(count) = str2double(tokens{1});
    end
end
result = unique(result(1:count), 'sorted');
if isempty(result)
    error('SmartKC:GuidedBlocksMissing', ...
        'No paired OFF/ON timing blocks were found.');
end
end

function [frame, frameNumber] = readFrameNearTime(reader, targetTime)
frameNumber = max(1, round(targetTime * reader.FrameRate) + 1);
while frameNumber >= 1
    try
        frame = read(reader, frameNumber);
        return
    catch ME
        if frameNumber == 1
            rethrow(ME);
        end
        frameNumber = frameNumber - 1;
    end
end
end

function createContactSheet(frames, manifest, videoStem, outputPath)
figureHandle = figure('Name', 'SmartKC++ guided-video frame review', ...
    'Color', 'white', 'Visible', 'off', 'Position', [70 70 1500 900]);
cleanup = onCleanup(@() close(figureHandle));
columns = 4;
rows = ceil(numel(frames) / columns);
layout = tiledlayout(figureHandle, rows, columns, ...
    'TileSpacing', 'compact', 'Padding', 'compact');
title(layout, "Selected frames: " + string(videoStem), 'Interpreter', 'none');
for index = 1:numel(frames)
    axisHandle = nexttile(layout);
    imshow(frames{index}, 'Parent', axisHandle);
    title(axisHandle, sprintf('%s | %.3f s', manifest.SampleName(index), ...
        manifest.FrameTimeSeconds(index)), 'Interpreter', 'none', ...
        'FontSize', 8);
end
exportgraphics(figureHandle, outputPath, 'Resolution', 160);
end
