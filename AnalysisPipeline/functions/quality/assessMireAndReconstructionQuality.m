function quality = assessMireAndReconstructionQuality(matrices, reconstruction, surface, cfg)
%ASSESSMIREANDRECONSTRUCTIONQUALITY Summarize auditable stage-level QC.

quality = struct();
quality.MedianMiresPerAngle = median(matrices.MireCountByAngle);
quality.MinimumMiresPerAngle = min(matrices.MireCountByAngle);
quality.AngularCoverageFraction = mean(matrices.MireCountByAngle >= ...
    cfg.reconstruction.MinimumMiresPerMeridian);
quality.MireCoverageByRing = matrices.CoverageByMire;
quality.ReconstructedMeridians = nnz(reconstruction.MeridianSummary.ReconstructedMires > 0);
quality.ConvergedMeridianFraction = mean( ...
    reconstruction.MeridianSummary.ConvergedFraction( ...
    reconstruction.MeridianSummary.ReconstructedMires > 0), 'omitnan');
quality.SurfaceFitRMSEum = surface.FitRMSEum;
quality.MireIdentityAnchorValidated = ...
    cfg.calibration.MireIdentityAnchorValidated;
if quality.MireIdentityAnchorValidated
    quality.MireIdentityAnchorStatus = "VALIDATED_DEVICE_ANCHOR";
else
    quality.MireIdentityAnchorStatus = "UNVERIFIED_RADIAL_ORDER";
end
quality.MireIdentityAnchorNotes = cfg.calibration.MireIdentityAnchorNotes;
quality.PassesMireCount = quality.MedianMiresPerAngle >= cfg.quality.MinimumMedianMires;
quality.PassesMeridianCount = quality.ReconstructedMeridians >= ...
    cfg.quality.MinimumReconstructionMeridians;
quality.PassesCoverage = quality.AngularCoverageFraction >= cfg.metrics.MinimumCoverage;
quality.IsAcceptedForResearchReview = quality.PassesMireCount && ...
    quality.PassesMeridianCount && quality.PassesCoverage;
quality.IsAcceptedForClinicalUse = false;
quality.ClinicalUseReason = "Research pipeline is not clinically validated.";
end
