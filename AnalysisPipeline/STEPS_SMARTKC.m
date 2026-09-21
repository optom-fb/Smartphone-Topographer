% STEPS_SMARTKC
% Image-only, dependency-linked SmartKC (classical pathway) analysis.
% Enter an image and inclusive PHYSICAL MIRE range. Each SmartKC radial
% response peak estimates one reflected mire-band centreline. Comment unwanted output
% line with %. Required earlier computations still run automatically in
% memory, but only enabled step images are saved. Image-space Steps 02-07
% also export *_full_frame.png views mapped to the oriented source image.

% Use the same REAL eye image as STEPS_PLACIDO_Only.m so that corresponding
% step figures compare preprocessing pathways without an image confound.
% Synthetic images are reserved for separate algorithm-validation tests.
inputImage = 'D:\MATLAB\Updates\Data\trial_proposal.jpg';
firstRing = 1;
lastRing = 6;
ringRange = [firstRing lastRing];

outputRoot = fullfile(fileparts(mfilename('fullpath')), ...
    'outputs','smartkc_steps');

selectedSteps = [];
%selectedSteps(end+1) = 1;  % STEP 01 - Read and orient the source image.
%selectedSteps(end+1) = 2;  % STEP 02 - Detect centre and create the centred crop.
%selectedSteps(end+1) = 3;  % STEP 03 - Apply flat-field normalization and percentile rescaling.
%selectedSteps(end+1) = 4;  % STEP 04 - Form the classical difference-of-Gaussians dark-mire response.
%selectedSteps(end+1) = 5;  % STEP 05 - Threshold and clean the annular mire segmentation.
%selectedSteps(end+1) = 6;  % STEP 06 - Sample radial profiles and localize subpixel peaks.
%selectedSteps(end+1) = 7;  % STEP 07 - Order and display the requested physical-mire range.
%selectedSteps(end+1) = 20; % STEP 20 - Classify each selected mire as complete-primary or incomplete-diagnostic.
% Steps 20-28 form the SmartKC quality-control and analysis phase.
% the two pathways can be compared image-for-image.
%selectedSteps(end+1) = 21; % STEP 21 - Plot covariance ellipses and eigen ratio for every physical mire.
selectedSteps(end+1) = 22; % STEP 22 - Compute cross-physical-mire centre instability.
%selectedSteps(end+1) = 23; % STEP 23 - Compute harmonic-filtered irregularity.
%selectedSteps(end+1) = 24; % STEP 24 - Plot second-harmonic curves and image axes.
%selectedSteps(end+1) = 25; % STEP 25 - Export a combined per-physical-mire table and averages.
%selectedSteps(end+1) = 26; % STEP 26 - Fit one representative mire ellipse and draw flat/steep axes.
selectedSteps(end+1) = 27; % STEP 27 - Fit all selected mire ellipses with individual flat/steep axes.
selectedSteps(end+1) = 28; % STEP 28 - Show all fitted mire ellipses with mean flat/steep axes only.

addpath(fileparts(mfilename('fullpath')));
smartKCStepResults = generate_smartkc_step_images( ...
    inputImage,ringRange,outputRoot,selectedSteps);
fprintf('\nImage-only output folder:\n%s\n',smartKCStepResults.OutputFolder);
