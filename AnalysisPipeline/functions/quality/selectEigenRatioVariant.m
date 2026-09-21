function [variant, displayName] = selectEigenRatioVariant(result, cfg)
%SELECTEIGENRATIOVARIANT Return the configured S07 mire-analysis branch.

pipeline = lower(string(cfg.eigenRatio.Pipeline));
switch pipeline
    case "smartkcpp"
        variant = result.SmartKCPP;
        displayName = "SmartKC++";
    case "smartkc"
        variant = result.SmartKC;
        displayName = "SmartKC";
    otherwise
        error('SmartKC:InvalidEigenRatioPipeline', ...
            'Unsupported S07 pipeline: %s.', pipeline);
end
if ~variant.EigenRatio.Enabled
    error('SmartKC:EigenRatioVariantNotCalculated', ...
        'S07 was not calculated for the configured pipeline %s.', pipeline);
end
end
