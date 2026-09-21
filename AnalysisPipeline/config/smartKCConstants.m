function cfg = smartKCConstants(projectRoot)
%SMARTKCCONSTANTS Central settings registry for the MATLAB SmartKC pipeline.
%   CFG = SMARTKCCONSTANTS(PROJECTROOT) returns all processing, geometry,
%   quality-control and simulation settings. The shipped camera and Placido
%   values reproduce the public Microsoft SmartKC reference configuration;
%   they are not a calibration for a different phone or attachment.

if nargin < 1 || strlength(string(projectRoot)) == 0
    configFolder = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(configFolder);
end

cfg = struct();
cfg.RegistryVersion = "0.14.0";
cfg.ProjectRoot = char(projectRoot);
cfg.ResearchOnly = true;

cfg.paths.Data = fullfile(cfg.ProjectRoot, 'Data');
cfg.paths.Derived = fullfile(cfg.paths.Data, 'Derived');
cfg.paths.Output = fullfile(cfg.paths.Data, 'Output');
cfg.paths.Synthetic = fullfile(cfg.paths.Data, 'Synthetic');
cfg.paths.Model = fullfile(cfg.ProjectRoot, 'models', 'smartkcpp_mire_unet.mat');

cfg.io.InputExtensions = [".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp"];
cfg.io.IgnoreFolderNames = ["Derived", "Output", "Synthetic"];

% Reference phone geometry used in the official SmartKC example command.
% Replace these values with measured/calibrated values for the actual phone.
cfg.camera.SensorSizeMm = [6.4, 4.8];       % [sensor width, sensor height]
cfg.camera.FocalLengthMm = 4.755;
cfg.camera.WorkingDistanceMm = 75.0;
cfg.camera.PrincipalPointPx = [NaN, NaN];   % NaN -> detected Placido centre
cfg.camera.RadialDistortion = [0, 0, 0];

cfg.calibration.IsDeviceSpecific = false;
cfg.calibration.MireIdentityAnchorValidated = false;
cfg.calibration.MireIdentityAnchorNotes = ...
    "Radial order alone cannot prove that the innermost physical mire is present.";
cfg.calibration.ProfileName = "Microsoft SmartKC public reference - unverified for this device";
cfg.calibration.Notes = [
    "Replace camera intrinsics, working distance and Placido geometry before quantitative use."
    "Validate against calibrated spheres and a clinical reference topographer."
    ];

% Public Microsoft ring_distribution.txt geometry: [radius, axial height] mm.
cfg.placido.RingRadiusHeightMm = [ ...
     4.0   0.0
     5.7  10.9
     7.0  19.3
     8.1  25.9
     8.9  31.2
     9.6  35.6
    10.2  39.4
    10.7  42.6
    11.1  45.4
    11.5  47.9
    11.9  50.0
    12.2  52.0
    12.5  53.8
    12.7  55.4
    12.9  56.9
    13.2  58.3
    13.4  59.6
    13.5  60.8
    13.7  61.9
    13.9  62.9
    14.0  63.9
    14.2  64.9
    14.3  65.8
    14.5  66.7
    14.6  67.6
    14.7  68.4
    14.9  69.2
    15.0  70.0
    ];
cfg.placido.ThicknessMm = 2.0;
cfg.placido.ThicknessAdjustmentMm = 0.5;
cfg.placido.MaximumMires = 22;

cfg.preprocessing.CropSizePx = 720;
cfg.preprocessing.MinimumCropSizePx = 480;
cfg.preprocessing.InputMaximumSizePx = 1152;
cfg.preprocessing.CenterSearchFraction = 0.72;
cfg.preprocessing.CenterDetectionMaximumSizePx = 960;
cfg.preprocessing.PupilRadiusFraction = [0.018, 0.09];
cfg.preprocessing.CenterRefineRadiusPx = 10;
cfg.preprocessing.FlatFieldSigmaPx = 32;
cfg.preprocessing.AnalysisRadiusFraction = 0.46;

% Review-only pupil detector adapted from the separate Placido project.
% Defaults scale the Placido 1920-by-1080 prototype settings by the smaller
% image dimension. The pupil result never replaces the reconstruction centre.
cfg.pupil.Enabled = true;
cfg.pupil.SourceFrameMode = "same-ring-image-review-only";
cfg.pupil.SearchRadiusFraction = 0.22;
cfg.pupil.RadiusFraction = [0.075, 0.17];
cfg.pupil.GaussianSigmaFraction = 0.0075;
cfg.pupil.DetectionMaximumSearchSizePx = 192;
cfg.pupil.CircleSensitivity = 0.94;
cfg.pupil.MinimumMetric = 0.30;
cfg.pupil.MaximumCenterOffsetFraction = 0.14;

cfg.segmentation.SmallGaussianSigmaPx = 0.8;
cfg.segmentation.LargeGaussianSigmaPx = 7.0;
cfg.segmentation.ResponseQuantile = 0.66;
cfg.segmentation.AdaptiveSensitivity = 0.52;
cfg.segmentation.MinimumComponentAreaPx = 8;
cfg.segmentation.MaximumGapToBridgePx = 2;
cfg.segmentation.UNetModelFile = cfg.paths.Model;
cfg.segmentation.UNetSourceCommit = ...
    "d9191fac74b0f4902cfe044f8686416b8b14fc1a";
cfg.segmentation.UNetCheckpointSha256 = ...
    "09099547890b215cbfe3727b35fe9f7bb4f955525ec003e1da5b5c86d6ce9e13";
cfg.segmentation.AllowClassicalFallback = true;
cfg.segmentation.ExecutionMode = "auto";

cfg.localization.StartAngleDeg = 0;
cfg.localization.EndAngleDeg = 360;
cfg.localization.AngleStepDeg = 2;
cfg.localization.InnerRadiusPx = 28;
cfg.localization.MaximumRadiusFraction = 0.46;
cfg.localization.MinimumRingSpacingPx = 4;
cfg.localization.MinimumPeakProminence = 0.025;
cfg.localization.MaximumCandidatesPerRay = 28;
% Radial peak sampling starts outside the detected central dark circle.
% Keep this explicit so innermost-mire recovery can be validated per device.
cfg.localization.CentralExclusionScale = 1.08;
% Experimental peak refinement. Keep "none" as the production baseline;
% controlled synthetic comparisons may override this with "quadratic".
cfg.localization.SubpixelMethod = "none";
% The paper uses +/-2 degrees at one-degree sampling. This MATLAB workflow
% samples every 2 degrees and therefore connects two samples on either side.
cfg.localization.GraphRadialTolerancePx = 3.0;
cfg.localization.GraphTangentialHalfWidthDeg = 4.1;
cfg.localization.GraphMinimumComponentSize = 6;
cfg.localization.MaximumAngularGapDeg = 6;

cfg.reconstruction.InitialStepMm = 0.01;
cfg.reconstruction.MinimumStepMm = 1e-7;
cfg.reconstruction.MaximumIterations = 2000;
cfg.reconstruction.MaximumSagMm = 2.0;
cfg.reconstruction.MinimumMiresPerMeridian = 5;
cfg.reconstruction.ClassicMissingPolicy = "radial-linear-extrapolation";
cfg.reconstruction.RobustMissingPolicy = "last-available-inner-mire";

cfg.surface.ZernikeDegree = 8;
cfg.surface.RidgeLambda = 1e-8;
cfg.surface.GridSize = 181;
cfg.surface.MaximumMapRadiusMm = 4.0;
cfg.surface.MinimumPointCount = 80;

cfg.metrics.SimKDiameterMm = 3.0;
cfg.metrics.KeratometricIndex = 1.3375;
cfg.metrics.DioptreFactor = 337.5;
cfg.metrics.MinimumCoverage = 0.55;

cfg.quality.MaximumCenterOffsetFraction = 0.25;
cfg.quality.MaximumSaturationFraction = 0.03;
cfg.quality.MinimumFocusScore = 0.002;
cfg.quality.MinimumMedianMires = 8;
cfg.quality.MinimumReconstructionMeridians = 30;

% Optional post-localization image-shape diagnostic. A partial trace can
% lower its covariance ratio solely because sectors are absent, so only
% sufficiently complete mires enter the primary S07 summary.
cfg.eigenRatio.Enabled = true;
cfg.eigenRatio.Pipeline = "smartkcpp";
cfg.eigenRatio.MinimumPoints = 30;
cfg.eigenRatio.MinimumCoverageFraction = 0.875;
cfg.eigenRatio.MaximumGapDeg = 45;

cfg.visualisation.Visible = "off";
cfg.visualisation.Colormap = turbo(256);
cfg.visualisation.PowerLimitsD = [30, 65];
cfg.visualisation.SaveResolutionDpi = 160;

cfg.simulation.ImageSize = [480, 640];
cfg.simulation.AngleStepDeg = 1;
cfg.simulation.AngularSamples = 360;
cfg.simulation.MinimumInnerMireIdentityCoverage = 0.50;
cfg.simulation.RandomSeed = 73191;
cfg.simulation.BackgroundLevel = 0.62;
cfg.simulation.RingContrast = 0.42;
cfg.simulation.RingWidthPx = 2.0;
cfg.simulation.RingWidthPixels = 2.0;
cfg.simulation.BrightMireContrast = 0.68;
cfg.simulation.DarkMireContrast = 0.34;
cfg.simulation.MaxCornealRadiusMm = 6.5;
cfg.simulation.RootSamples = 96;
cfg.simulation.SurfaceGridSize = 129;
cfg.simulation.GlareStrength = 0.08;
cfg.simulation.PixelScaleFactor = 9.0;
cfg.simulation.NoiseSigma = 0.012;
cfg.simulation.BlurSigma = 0.8;
cfg.simulation.RegularPowerToleranceD = 0.5;
end
