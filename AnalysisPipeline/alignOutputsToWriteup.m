function alignedFolder = alignOutputsToWriteup(placidoResult, smartkcResult, rootFolder)
%ALIGNOUTPUTSTOWRITEUP Copy generated figures into writeup-aligned folders.
% Raw diagnostic figures remain in their generator folders unchanged.

alignedFolder = char(rootFolder);
analysisFolder = fullfile(alignedFolder,'Analysis');
if ~isfolder(analysisFolder), mkdir(analysisFolder); end
copyMapped(placidoResult.OutputFolder, fullfile(alignedFolder,'Placido_Output','Phase1'), {
    'step_01_acquire_select_frame.png','Method1_Phase1_Step01_Acquire.png';
    'step_02_grayscale.png','Method1_Phase1_Step02_Grayscale.png';
    'step_03_canny_edge_detection.png','Method1_Phase1_Step03_Canny.png';
    'step_04_border_component_cleanup.png','Method1_Phase1_Step04_Cleanup.png';
    'step_06_coarse_centre.png','Method1_Phase1_Step05_CoarseCentre.png';
    'step_07_polar_unwrap.png','Method1_Phase1_Step06_PolarUnwrap.png';
    'step_08_radial_gradient_polarity.png','Method1_Phase1_Step07_Polarity.png';
    'step_09_candidate_ring_groups.png','Method1_Phase1_Step08_ConnectedObjects.png';
    'step_10_candidate_geometry_filter.png','Method1_Phase1_Step09_EnclosureFilter.png';
    'step_11_placido_hub.png','Method1_Phase1_Step10_PlacidoHub.png';
    'step_12_canny_radial_masks.png','Method1_Phase1_Step11_RadialMask.png';
    'step_14_tangent_fragment_merge.png','Method1_Phase1_Step12_FragmentMerge.png';
    'step_15_subtense_gate.png','Method1_Phase1_Step13_SubtenseGate.png';
    'step_16_physical_mire_centrelines.png','Method1_Phase1_Step14_MireCentrelines.png';
    'step_17_angular_binning.png','Method1_Phase1_Step15_Binning.png';
    'step_19_periodic_cubic_spline.png','Method1_Phase1_Step15_SplineFit.png'});
copyMapped(placidoResult.OutputFolder, fullfile(alignedFolder,'Placido_Output','Phase2'), {
    'step_21_eigen_ratio.png','Method1_Phase2_Step01_EigenRatio.png';
    'step_22_mire_centre_instability.png','Method1_Phase2_Step02_CentreInstability.png';
    'step_23_harmonic_filtered_irregularity.png','Method1_Phase2_Step03_Irregularity.png';
    'step_28_all_mire_ellipses_mean_flat_steep.png','Method1_Phase2_Step04_Axes.png'});
copyMapped(char(smartkcResult.OutputFolder), fullfile(alignedFolder,'SmartKC_Output','Phase1'), {
    'step_01_source.png','Method2_Phase1_Step01_ReadOrient.png';
    'step_02_centred_crop.png','Method2_Phase1_Step02_CentreCrop.png';
    'step_03_flat_field_normalized.png','Method2_Phase1_Step03_FlatField.png';
    'step_04_dog_response.png','Method2_Phase1_Step04_DarkResponse.png';
    'step_05_segmentation_mask.png','Method2_Phase1_Step05_Segmentation.png';
    'step_06_radial_peak_localization.png','Method2_Phase1_Step06_RadialPeaks.png';
    'step_20_mire_completeness_quality_gate.png','Method2_Phase1_Step07_CompleteMires.png'});
copyMapped(char(smartkcResult.OutputFolder), fullfile(alignedFolder,'SmartKC_Output','Phase2'), {
    'step_21_eigen_ratio.png','Method2_Phase2_Step01_EigenRatio.png';
    'step_22_centre_instability.png','Method2_Phase2_Step02_CentreInstability.png';
    'step_23_irregularity.png','Method2_Phase2_Step03_Irregularity.png';
    'step_28_all_mire_ellipses_mean_flat_steep.png','Method2_Phase2_Step04_Axes.png'});
end

function copyMapped(sourceFolder,targetFolder,mapping)
if ~isfolder(targetFolder), mkdir(targetFolder); end
for k=1:size(mapping,1)
    src=fullfile(char(sourceFolder),mapping{k,1});
    assert(isfile(src),'Missing figure for writeup: %s',src);
    copyfile(src,fullfile(targetFolder,mapping{k,2}));
end
end
