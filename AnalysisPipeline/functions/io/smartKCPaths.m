function paths = smartKCPaths(cfg, caseId)
%SMARTKCPATHS Central S00-S07 manifest and per-case output naming registry.

paths.Manifests = struct( ...
    'S00', fullfile(cfg.paths.Derived, 'S00_manifest.csv'), ...
    'S01', fullfile(cfg.paths.Derived, 'S01_manifest.csv'), ...
    'S02', fullfile(cfg.paths.Derived, 'S02_manifest.csv'), ...
    'S03', fullfile(cfg.paths.Derived, 'S03_manifest.csv'), ...
    'S04', fullfile(cfg.paths.Derived, 'S04_manifest.csv'), ...
    'S05', fullfile(cfg.paths.Derived, 'S05_manifest.csv'), ...
    'S06', fullfile(cfg.paths.Derived, 'S06_manifest.csv'), ...
    'S07', fullfile(cfg.paths.Derived, 'S07_manifest.csv'));

if nargin < 2 || strlength(string(caseId)) == 0
    return
end
caseId = string(caseId);
if ~isscalar(caseId) || isempty(regexp(caseId, '^[a-z0-9][a-z0-9_-]{0,31}$', 'once'))
    error('SmartKC:InvalidCaseId', ...
        'CaseID must be a canonical 1-32 character lower-case identifier.');
end

paths.CaseId = caseId;
paths.DerivedCaseFolder = fullfile(cfg.paths.Derived, char(caseId));
paths.OutputCaseFolder = fullfile(cfg.paths.Output, char(caseId));

paths.S01PreprocessMat = fullfile(paths.DerivedCaseFolder, 'S01_preprocess.mat');
paths.S01CropPng = fullfile(paths.DerivedCaseFolder, 'S01_crop.png');
paths.S02SegmentationMat = fullfile(paths.DerivedCaseFolder, 'S02_segmentation.mat');
paths.S02SmartKCMaskPng = fullfile(paths.DerivedCaseFolder, 'S02_skc_mask.png');
paths.S02SmartKCPPMaskPng = fullfile(paths.DerivedCaseFolder, 'S02_skcpp_mask.png');
paths.S03MiresMat = fullfile(paths.DerivedCaseFolder, 'S03_mires.mat');
paths.S03SmartKCMiresCsv = fullfile(paths.DerivedCaseFolder, 'S03_skc_mires.csv');
paths.S03SmartKCPPMiresCsv = fullfile(paths.DerivedCaseFolder, 'S03_skcpp_mires.csv');
paths.S04SmartKCReconstructionMat = fullfile(paths.DerivedCaseFolder, ...
    'S04_skc_reconstruction.mat');
paths.S05SmartKCPPReconstructionMat = fullfile(paths.DerivedCaseFolder, ...
    'S05_skcpp_reconstruction.mat');

paths.S01OutputCropPng = fullfile(paths.OutputCaseFolder, 'S01_crop.png');
paths.S01OutputNormalizedPng = fullfile(paths.OutputCaseFolder, 'S01_normalized.png');
paths.S01PupilCsv = fullfile(paths.OutputCaseFolder, 'S01_pupil.csv');
paths.S01PupilReviewPng = fullfile(paths.OutputCaseFolder, ...
    'S01_pupil_review.png');
paths.S02OutputSmartKCMaskPng = fullfile(paths.OutputCaseFolder, 'S02_skc_mask.png');
paths.S02OutputSmartKCPPMaskPng = fullfile(paths.OutputCaseFolder, 'S02_skcpp_mask.png');
paths.S03OutputSmartKCMiresCsv = fullfile(paths.OutputCaseFolder, 'S03_skc_mires.csv');
paths.S03OutputSmartKCPPMiresCsv = fullfile(paths.OutputCaseFolder, 'S03_skcpp_mires.csv');
paths.S03MireViewerMetadataJson = fullfile(paths.OutputCaseFolder, ...
    'S03_mire_viewer_metadata.json');
paths.S04OutputSmartKCSurfaceCsv = fullfile(paths.OutputCaseFolder, 'S04_skc_surface.csv');
paths.S05OutputSmartKCPPSurfaceCsv = fullfile(paths.OutputCaseFolder, 'S05_skcpp_surface.csv');
paths.S06SummaryCsv = fullfile(paths.OutputCaseFolder, 'S06_summary.csv');
paths.S06ResultMat = fullfile(paths.OutputCaseFolder, 'S06_result.mat');
paths.S06ReviewPng = fullfile(paths.OutputCaseFolder, 'S06_review.png');
paths.S07EigenRatioCsv = fullfile(paths.OutputCaseFolder, 'S07_eigen_ratio.csv');
paths.S07EigenRatioPng = fullfile(paths.OutputCaseFolder, 'S07_eigen_ratio.png');
paths.S07AxesPng = fullfile(paths.OutputCaseFolder, 'S07_axes.png');
end
