function report = validateSmartKCPPUNetParity(network, metadata, fixtureFile)
%VALIDATESMARTKCPPUNETPARITY Compare MATLAB inference with official PyTorch.

arguments
    network dlnetwork
    metadata struct
    fixtureFile (1,:) char
end

if ~isfile(fixtureFile)
    error('SmartKC:UNetParityFixtureMissing', ...
        'SmartKC++ U-Net parity fixture not found: %s', fixtureFile);
end
fixture = load(fixtureFile);
if string(fixture.SourceCommit) ~= string(metadata.SourceCommit) || ...
        lower(string(fixture.CheckpointSha256)) ~= ...
        lower(string(metadata.CheckpointSha256))
    error('SmartKC:UNetParityProvenanceMismatch', ...
        'Parity fixture and converted network provenance do not match.');
end

[labels500, logits512, labels512, networkInput512] = predictSmartKCPPUNet( ...
    fixture.GrayInput500Uint8, network, metadata);
reference512 = uint8(fixture.LabelMap512ZeroBased);
reference500 = uint8(fixture.LabelMap500ZeroBased);
agreement512 = mean(labels512(:) == reference512(:));
agreement500 = mean(labels500(:) == reference500(:));

locations = double(fixture.ProbeYXZeroBased) + 1;
probeLogits = zeros(size(locations, 1), metadata.ClassCount, 'single');
for index = 1:size(locations, 1)
    probeLogits(index, :) = reshape(logits512( ...
        locations(index, 1), locations(index, 2), :), 1, []);
end
referenceProbeLogits = single(fixture.ProbeLogits);
maximumProbeLogitError = max(abs( ...
    probeLogits(:) - referenceProbeLogits(:)));
referenceNetworkInput = single(fixture.NetworkInput512);
networkInputDifference = abs(networkInput512 - referenceNetworkInput);

report = struct();
report.SourceCommit = string(metadata.SourceCommit);
report.CheckpointSha256 = string(metadata.CheckpointSha256);
report.ReferencePyTorchVersion = string(fixture.ReferencePyTorchVersion);
report.ReferenceTorchvisionVersion = ...
    string(fixture.ReferenceTorchvisionVersion);
report.ReferencePillowVersion = string(fixture.ReferencePillowVersion);
report.LabelAgreement512 = agreement512;
report.LabelAgreement500 = agreement500;
report.MaximumProbeLogitAbsoluteError = double(maximumProbeLogitError);
report.MaximumNetworkInputAbsoluteError = ...
    double(max(networkInputDifference(:)));
report.MeanNetworkInputAbsoluteError = ...
    double(mean(networkInputDifference(:)));
report.MinimumRequiredLabelAgreement = 0.9999;
report.MaximumAllowedProbeLogitError = 1e-3;
report.Passed = agreement512 >= report.MinimumRequiredLabelAgreement && ...
    agreement500 >= report.MinimumRequiredLabelAgreement && ...
    maximumProbeLogitError <= report.MaximumAllowedProbeLogitError && ...
    report.MaximumNetworkInputAbsoluteError == 0;
end
