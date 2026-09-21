function constants = placidoConstants()
% PLACIDOCONSTANTS Single editable settings registry for the Placido project.
%
% Beginner-friendly rule:
%   Change values in this file only when you understand what they control.
%   Change one value at a time, write the old and new values in your lab
%   notes, then re-run the affected steps on the same image/video to compare.
%
% Paths to change this file:
%   D:\MATLAB\placido\config\placidoConstants.m
%   placido/config/placidoConstants.m
%
% This file contains the active user-facing settings. More specialised values
% inside individual helper functions are deliberately not exposed yet: they
% will be centralised only after they have been separately reviewed and tested.

constants = struct();
constants.RegistryVersion = "2026-08-15";

% Step 00 - guided-video frame extraction
constants.step00.inputVideoPath = "";          % empty = newest valid guided AVI
constants.step00.showContactSheet = true;
constants.step00.transitionMarginSeconds = 0.5; % stay away from light commands
constants.step00.solidSettlingSeconds = 1.5;    % wait after solid white-light ON
constants.step00.pupilCandidateCount = 3;
constants.step00.ringCandidateCount = 3;
constants.step00.frameRateFallbackHz = 30;      % only for final-frame clipping

% Step 01 - Placido edge/ring detection
constants.step01.inputImagePath = "";          % empty = recommended newest Step-00 frame
constants.step01.pruneAngleDegrees = 70;
constants.step01.maxMergeDistancePixels = 30;
constants.step01.mergeAngleToleranceDegrees = 30;
constants.step01.minBlobSizePixels = 20;
constants.step01.forceMergeDistancePixels = 4;
constants.step01.minAllowedSubtenseDegrees = 90;
constants.step01.highlightRingCount = 65;
constants.step01.showMergeDiagnostics = true;

% Step 02 - spline fitting and complete/incomplete classification
constants.step02.resultsFile = "";             % empty = newest Step-01 results CSV
constants.step02.ringsToPlot = [3, 6, 10, 14];
constants.step02.maxGapDegrees = 45;            % primary complete-ring gate
constants.step02.method = 'irls';                % 'irls' or 'ransac'
constants.step02.numKnots = 36;
constants.step02.lambda = 'auto';
constants.step02.robustIterations = 5;
constants.step02.angularBins = 180;
constants.step02.minCoverageDegrees = 90;       % warning/support check only
constants.step02.fallbackToArc = true;

% Step 03 - result labels and input selection
constants.step03.resultsFile = "";             % empty = newest Step-01 results CSV
constants.step03.primaryGroupName = "complete_primary";
constants.step03.incompleteGroupName = "incomplete_diagnostic";

% Master runner - automatic pipeline mode
constants.master.mode = "video";               % "video" = Steps 00-03; "image" = Steps 01-03
constants.master.runStep00B = false;            % optional pupil-validation review only

% Step 00B - development-only pupil validation on IR-only frames
constants.step00b.inputFrameManifestPath = ""; % empty = newest manifest
constants.step00b.searchRadiusPixels = 220;
constants.step00b.pupilRadiusRangePixels = [90, 170];
constants.step00b.gaussianSigmaPixels = 8;
constants.step00b.circleSensitivity = 0.94;
constants.step00b.maxCentreOffsetPixels = 140;
end
