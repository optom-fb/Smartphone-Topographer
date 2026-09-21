function comparison = compareSyntheticSubpixelRegression(cfg, outputCsv)
%COMPARESYNTHETICSUBPIXELREGRESSION Compare integer and quadratic peaks.
%   Runs the tracked ten-case synthetic dataset with both localization modes.
%   Quantitative cases are checked against matched dense truth-surface 3 mm
%   SimK. Nominal apical powers remain descriptive only. Cone cases remain
%   completion and localization stress tests without a SimK accuracy claim.

arguments
    cfg struct
    outputCsv (1,1) string = ""
end

manifestPath = fullfile(cfg.paths.Synthetic, 'manifest.csv');
manifest = readtable(manifestPath, 'TextType', 'string');
rowCount = height(manifest);
ScenarioName = manifest.ScenarioName;
SurfaceClass = manifest.SurfaceClass;
BaselineStatus = strings(rowCount, 1);
QuadraticStatus = strings(rowCount, 1);
BaselineMires = nan(rowCount, 1);
QuadraticMires = nan(rowCount, 1);
MireChange = nan(rowCount, 1);
BaselineMedianEdgeErrorPx = nan(rowCount, 1);
QuadraticMedianEdgeErrorPx = nan(rowCount, 1);
MedianEdgeErrorChangePx = nan(rowCount, 1);
BaselineSteepD = nan(rowCount, 1);
QuadraticSteepD = nan(rowCount, 1);
BaselineFlatD = nan(rowCount, 1);
QuadraticFlatD = nan(rowCount, 1);
BaselineCylinderD = nan(rowCount, 1);
QuadraticCylinderD = nan(rowCount, 1);
TruthReferenceSteepD = nan(rowCount, 1);
TruthReferenceFlatD = nan(rowCount, 1);
TruthReferenceCylinderD = nan(rowCount, 1);
TruthReferenceSteepAxisDeg = nan(rowCount, 1);
BaselineMaximumNominalKErrorD = nan(rowCount, 1);
QuadraticMaximumNominalKErrorD = nan(rowCount, 1);
MaximumNominalKErrorChangeD = nan(rowCount, 1);
BaselineMaximumTruthKErrorD = nan(rowCount, 1);
QuadraticMaximumTruthKErrorD = nan(rowCount, 1);
MaximumTruthKErrorChangeD = nan(rowCount, 1);
SteepAxisChangeDeg = nan(rowCount, 1);
FirstPhysicalMireCandidateCoverageFraction = nan(rowCount, 1);
MireIdentityComparisonEligibility = strings(rowCount, 1);
AccuracyScope = strings(rowCount, 1);
RegressionCheck = strings(rowCount, 1);
ErrorMessage = strings(rowCount, 1);

for row = 1:rowCount
    imagePath = fullfile(cfg.paths.Synthetic, manifest.ImageFile(row));
    truthPath = fullfile(cfg.paths.Synthetic, manifest.GroundTruthFile(row));
    loaded = load(truthPath, 'truth');
    [matchedCfg, matched] = configureSyntheticMasterRun(char(imagePath), cfg);
    if ~matched
        error('SmartKC:SubpixelRegression:FixtureNotMatched', ...
            'Could not activate matched settings for %s.', imagePath);
    end
    try
        baselineCfg = matchedCfg;
        baselineCfg.localization.SubpixelMethod = "none";
        baseline = runSmartKCPipeline(char(imagePath), baselineCfg, '');
        quadraticCfg = matchedCfg;
        quadraticCfg.localization.SubpixelMethod = "quadratic";
        quadratic = runSmartKCPipeline(char(imagePath), quadraticCfg, '');
        BaselineStatus(row) = baseline.SmartKCPP.Status;
        QuadraticStatus(row) = quadratic.SmartKCPP.Status;
        if baseline.SmartKCPP.Status ~= "COMPLETED" || ...
                quadratic.SmartKCPP.Status ~= "COMPLETED"
            error('SmartKC:SubpixelRegression:PipelineFailed', ...
                'Baseline: %s | Quadratic: %s', ...
                baseline.SmartKCPP.ErrorMessage, ...
                quadratic.SmartKCPP.ErrorMessage);
        end
        BaselineMires(row) = baseline.SmartKCPP.Quality.MedianMiresPerAngle;
        QuadraticMires(row) = quadratic.SmartKCPP.Quality.MedianMiresPerAngle;
        MireChange(row) = QuadraticMires(row) - BaselineMires(row);
        nominalMeanD = mean([337.5 / manifest.RflatMm(row), ...
            337.5 / manifest.RsteepMm(row)]);
        baselineDetails = compareMireCandidatesToTruth( ...
            baseline.SmartKCPP.Candidates, loaded.truth, ...
            baseline.Preprocessing, baselineCfg, nominalMeanD, ...
            ScenarioName(row));
        quadraticDetails = compareMireCandidatesToTruth( ...
            quadratic.SmartKCPP.Candidates, loaded.truth, ...
            quadratic.Preprocessing, quadraticCfg, nominalMeanD, ...
            ScenarioName(row));
        BaselineMedianEdgeErrorPx(row) = median( ...
            baselineDetails.CenterCompensatedAbsoluteErrorPx( ...
            baselineDetails.TruthAvailable), 'omitnan');
        QuadraticMedianEdgeErrorPx(row) = median( ...
            quadraticDetails.CenterCompensatedAbsoluteErrorPx( ...
            quadraticDetails.TruthAvailable), 'omitnan');
        MedianEdgeErrorChangePx(row) = QuadraticMedianEdgeErrorPx(row) - ...
            BaselineMedianEdgeErrorPx(row);
        BaselineSteepD(row) = baseline.SmartKCPP.Metrics.SimKSteepD;
        QuadraticSteepD(row) = quadratic.SmartKCPP.Metrics.SimKSteepD;
        BaselineFlatD(row) = baseline.SmartKCPP.Metrics.SimKFlatD;
        QuadraticFlatD(row) = quadratic.SmartKCPP.Metrics.SimKFlatD;
        BaselineCylinderD(row) = baseline.SmartKCPP.Metrics.CylinderD;
        QuadraticCylinderD(row) = quadratic.SmartKCPP.Metrics.CylinderD;
        SteepAxisChangeDeg(row) = axialDifference( ...
            quadratic.SmartKCPP.Metrics.SimKSteepAxisDeg, ...
            baseline.SmartKCPP.Metrics.SimKSteepAxisDeg);

        quantitative = SurfaceClass(row) == "sphere" || ...
            SurfaceClass(row) == "regular-astigmatism";
        if quantitative
            AccuracyScope(row) = "MATCHED_TRUTH_3MM_SIMK_REGRESSION";
            nominalSteepD = 337.5 / manifest.RsteepMm(row);
            nominalFlatD = 337.5 / manifest.RflatMm(row);
            BaselineMaximumNominalKErrorD(row) = max(abs([ ...
                BaselineSteepD(row) - nominalSteepD, ...
                BaselineFlatD(row) - nominalFlatD]));
            QuadraticMaximumNominalKErrorD(row) = max(abs([ ...
                QuadraticSteepD(row) - nominalSteepD, ...
                QuadraticFlatD(row) - nominalFlatD]));
            MaximumNominalKErrorChangeD(row) = ...
                QuadraticMaximumNominalKErrorD(row) - ...
                BaselineMaximumNominalKErrorD(row);
            truthMetrics = computeSyntheticTruthSimK(loaded.truth, matchedCfg);
            TruthReferenceSteepD(row) = truthMetrics.SimKSteepD;
            TruthReferenceFlatD(row) = truthMetrics.SimKFlatD;
            TruthReferenceCylinderD(row) = truthMetrics.CylinderD;
            TruthReferenceSteepAxisDeg(row) = ...
                truthMetrics.SimKSteepAxisDeg;
            BaselineMaximumTruthKErrorD(row) = max(abs([ ...
                BaselineSteepD(row) - truthMetrics.SimKSteepD, ...
                BaselineFlatD(row) - truthMetrics.SimKFlatD]));
            QuadraticMaximumTruthKErrorD(row) = max(abs([ ...
                QuadraticSteepD(row) - truthMetrics.SimKSteepD, ...
                QuadraticFlatD(row) - truthMetrics.SimKFlatD]));
            MaximumTruthKErrorChangeD(row) = ...
                QuadraticMaximumTruthKErrorD(row) - ...
                BaselineMaximumTruthKErrorD(row);
            passed = QuadraticMaximumTruthKErrorD(row) <= ...
                cfg.simulation.RegularPowerToleranceD && ...
                MaximumTruthKErrorChangeD(row) <= 0.05 && ...
                MireChange(row) >= 0;
            MireIdentityComparisonEligibility(row) = "ELIGIBLE";
            if passed
                RegressionCheck(row) = "PASS";
            else
                RegressionCheck(row) = "FAIL";
            end
        else
            [~, identity] = evaluateMireLocalizationAgainstTruth( ...
                quadratic.SmartKCPP.Candidates, loaded.truth, ...
                quadraticCfg.placido.MaximumMires, ...
                quadraticCfg.localization.GraphRadialTolerancePx);
            firstMireMatches = identity.IsMatched & ...
                identity.TrueMireIndex == 1;
            FirstPhysicalMireCandidateCoverageFraction(row) = ...
                nnz(firstMireMatches) / ...
                numel(quadratic.SmartKCPP.Polar.AnglesDeg);
            if FirstPhysicalMireCandidateCoverageFraction(row) < ...
                    cfg.simulation.MinimumInnerMireIdentityCoverage
                AccuracyScope(row) = ...
                    "CONE_UNANCHORED_IDENTITY_STRESS_TEST";
                MireIdentityComparisonEligibility(row) = ...
                    "NOT_APPLICABLE_INNER_MIRE_UNOBSERVABLE";
                RegressionCheck(row) = "NOT_APPLICABLE";
            else
                AccuracyScope(row) = "CONE_LOCALIZATION_STRESS_TEST";
                MireIdentityComparisonEligibility(row) = "ELIGIBLE";
                passed = MireChange(row) >= 0 && ...
                    MedianEdgeErrorChangePx(row) <= 0.02;
                if passed
                    RegressionCheck(row) = "PASS";
                else
                    RegressionCheck(row) = "FAIL";
                end
            end
        end
    catch exception
        RegressionCheck(row) = "FAIL";
        ErrorMessage(row) = string(exception.message);
    end
    fprintf('[Subpixel regression] %s | %s\n', ...
        ScenarioName(row), RegressionCheck(row));
end

comparison = table(ScenarioName, SurfaceClass, BaselineStatus, ...
    QuadraticStatus, BaselineMires, QuadraticMires, MireChange, ...
    BaselineMedianEdgeErrorPx, QuadraticMedianEdgeErrorPx, ...
    MedianEdgeErrorChangePx, BaselineSteepD, QuadraticSteepD, ...
    BaselineFlatD, QuadraticFlatD, BaselineCylinderD, ...
    QuadraticCylinderD, TruthReferenceSteepD, TruthReferenceFlatD, ...
    TruthReferenceCylinderD, TruthReferenceSteepAxisDeg, ...
    BaselineMaximumNominalKErrorD, ...
    QuadraticMaximumNominalKErrorD, MaximumNominalKErrorChangeD, ...
    BaselineMaximumTruthKErrorD, QuadraticMaximumTruthKErrorD, ...
    MaximumTruthKErrorChangeD, ...
    SteepAxisChangeDeg, FirstPhysicalMireCandidateCoverageFraction, ...
    MireIdentityComparisonEligibility, AccuracyScope, RegressionCheck, ...
    ErrorMessage);
if strlength(outputCsv) > 0
    ensureFolder(fileparts(char(outputCsv)));
    writetable(comparison, char(outputCsv));
end
end

function difference = axialDifference(firstDeg, secondDeg)
difference = abs(mod(firstDeg - secondDeg + 90, 180) - 90);
end
