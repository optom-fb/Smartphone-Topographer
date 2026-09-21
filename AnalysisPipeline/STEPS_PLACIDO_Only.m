% STEPS_PLACIDO_ONLY
% Synchronized Placido/cornea image-processing figure generator.
%
% This is the launcher to use beside the synchronized methodology chapter.
% The step number, title, order and output filename match the chapter.
%
% IMPORTANT METHOD BOUNDARY
%   - Uses the original cornea and dedicated Placido image-domain method.
%   - Uses grayscale followed by fixed Canny thresholds [0.10 0.30].
%   - Does NOT use CLAHE, flat-field correction, adaptive multi-scale Canny,
%     learned segmentation, Zernike analysis or simulated keratometry.
%   - Writes the original analysis-view PNG for every enabled step.
%   - Image-space Steps 11-16 and 19 also receive a *_full_frame.png view.
%     Plots and tables remain single outputs because a full frame does not apply.
%   - No CSV, MAT, JSON or contact-sheet file is written to the result folder.
%
% HOW TO USE
%   1. Enter the full image path.
%   2. Enter the inclusive PHYSICAL MIRE range using firstRing/lastRing.
%      Each mire is one midpoint curve formed from a paired inner and outer
%      Canny boundary. The eigen analysis is performed on that midpoint.
%   3. Put '%' at the beginning of an unwanted selectedSteps line.
%   4. Press Run.

% -------------------------------------------------------------------------
% USER INPUTS
% -------------------------------------------------------------------------
inputImage = 'D:\MATLAB\Updates\Data\trial_proposal.jpg';

firstRing = 1;
lastRing = 6;
ringRange = [firstRing lastRing];

% Empty = automatically enlarge the Placido analysis radius for lastRing.
% Alternatively enter a radius in pixels (for example 700). The radius is
% always clipped safely at the nearest image boundary around the found hub.
analysisRadiusPx = [];

% A new image-only subfolder is created for each run.
outputRoot = fullfile(fileparts(mfilename('fullpath')), ...
    'outputs', 'placido_only_steps');

% -------------------------------------------------------------------------
% SYNCHRONIZED PLACIDO/CORNEA METHODOLOGY STEPS
% Comment an unwanted line by putting '%' at its beginning.
% -------------------------------------------------------------------------
selectedSteps = [];
%selectedSteps(end+1) = 1;  % STEP 01 - Acquire and orient the source frame.
%selectedSteps(end+1) = 2;  % STEP 02 - Convert the frame to grayscale.
%selectedSteps(end+1) = 3;  % STEP 03 - Detect intensity transitions using fixed Canny thresholds.
%selectedSteps(end+1) = 4;  % STEP 04 - Remove border connected and very small edge components.
%selectedSteps(end+1) = 5;  % STEP 05 - Apply the historical circular field of view.
%selectedSteps(end+1) = 6;  % STEP 06 - Estimate the historical coarse centre.
%selectedSteps(end+1) = 7;  % STEP 07 - Unwrap the image into polar coordinates.
%selectedSteps(end+1) = 8;  % STEP 08 - Separate edges by radial gradient polarity.
%selectedSteps(end+1) = 9;  % STEP 09 - Group historical edge points into connected candidates.
%selectedSteps(end+1) = 10; % STEP 10 - Filter historical candidates by enclosure geometry.
%selectedSteps(end+1) = 11; % STEP 11 - Recover the dedicated Placido hub and working ROI.
%selectedSteps(end+1) = 12; % STEP 12 - Apply the dedicated Canny ROI and radial orientation masks.
%selectedSteps(end+1) = 13; % STEP 13 - Prune branches inconsistent with ring geometry.
%selectedSteps(end+1) = 14; % STEP 14 - Merge compatible ring fragments using endpoint distance and tangent direction.
%selectedSteps(end+1) = 15; % STEP 15 - Reject curves with insufficient angular subtense.
%selectedSteps(end+1) = 16; % STEP 16 - Pair inner/outer boundaries and construct physical-mire centrelines.
%selectedSteps(end+1) = 17; % STEP 17 - Bin each selected curve on a fixed angular grid.
%selectedSteps(end+1) = 18; % STEP 18 - Choose periodic or open arc fitting from the largest angular gap.
%selectedSteps(end+1) = 19; % STEP 19 - Fit a cubic B spline in periodic or open arc mode.
%selectedSteps(end+1) = 20; % STEP 20 - Downweight spline outliers using Tukey bisquare IRLS.
%selectedSteps(end+1) = 21; % STEP 21 - Compute covariance eigen ratio for each selected physical mire.
selectedSteps(end+1) = 22; % STEP 22 - Quantify cross-mire centre instability.
%selectedSteps(end+1) = 23; % STEP 23 - Compute harmonic filtered radial irregularity.
%selectedSteps(end+1) = 24; % STEP 24 - Determine the principal second harmonic image axes.
%selectedSteps(end+1) = 25; % STEP 25 - Summarise every selected physical mire and range averages.
%selectedSteps(end+1) = 26; % STEP 26 - Fit one representative mire ellipse and draw flat/steep axes.
selectedSteps(end+1) = 27; % STEP 27 - Fit all selected mire ellipses with individual flat/steep axes.
selectedSteps(end+1) = 28; % STEP 28 - Show all fitted mire ellipses with mean flat/steep axes only.

% -------------------------------------------------------------------------
% EXECUTION: no editing is normally required below this line.
% -------------------------------------------------------------------------
addpath(fileparts(mfilename('fullpath')));
placidoOnlyResults = generate_placido_only_step_images( ...
    inputImage, ringRange, outputRoot, selectedSteps, analysisRadiusPx);

fprintf('\nImage-only output folder:\n%s\n', placidoOnlyResults.OutputFolder);
