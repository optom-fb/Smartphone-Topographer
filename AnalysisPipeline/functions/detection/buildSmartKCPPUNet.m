function [network, metadata] = buildSmartKCPPUNet(weightsFile)
%BUILDSMARTKCPPUNET Build the pinned SmartKC++ U-Net from converted weights.

arguments
    weightsFile (1,:) char
end

if ~isfile(weightsFile)
    error('SmartKC:UNetWeightsMissing', ...
        'Converted SmartKC++ U-Net weights not found: %s', weightsFile);
end

weights = load(weightsFile);
requiredFormat = "SmartKCPP-UNet-weights-v1";
if ~isfield(weights, 'FormatVersion') || ...
        string(weights.FormatVersion) ~= requiredFormat
    error('SmartKC:UNetWeightsFormat', ...
        'Unsupported SmartKC++ U-Net weight-bundle format.');
end

inputSize = double(weights.NetworkInputSizePx(:)');
classCount = double(weights.ClassCount(1));
graph = layerGraph(imageInputLayer([inputSize, 3], ...
    'Normalization', 'none', 'Name', 'input'));
previous = "input";
skipNames = strings(1, 4);
downWidths = [32, 64, 128, 256, 512];

for level = 0:4
    torchPrefix = sprintf('unet.down_path.%d.block', level);
    matlabPrefix = sprintf('down%d', level);
    block = convolutionBlock(weights, torchPrefix, matlabPrefix, ...
        downWidths(level + 1));
    graph = addLayers(graph, block);
    graph = connectLayers(graph, previous, matlabPrefix + "_conv1");
    previous = matlabPrefix + "_bn2";
    if level < 4
        skipNames(level + 1) = previous;
        poolName = matlabPrefix + "_pool";
        pool = maxPooling2dLayer(2, 'Stride', 2, 'Name', poolName);
        graph = addLayers(graph, pool);
        graph = connectLayers(graph, previous, poolName);
        previous = poolName;
    end
end

upWidths = [256, 128, 64, 32];
for level = 0:3
    torchPrefix = sprintf('unet.up_path.%d', level);
    matlabPrefix = sprintf('up%d', level);
    resizeName = matlabPrefix + "_resize";
    resize = resize2dLayer('Scale', [2, 2], 'Method', 'bilinear', ...
        'GeometricTransformMode', 'half-pixel', 'Name', resizeName);
    graph = addLayers(graph, resize);
    graph = connectLayers(graph, previous, resizeName);

    upConvName = matlabPrefix + "_project";
    upConv = convolutionLayer(weights, torchPrefix + ".up.1", ...
        upWidths(level + 1), 1, upConvName);
    graph = addLayers(graph, upConv);
    graph = connectLayers(graph, resizeName, upConvName);

    concatName = matlabPrefix + "_concat";
    concat = depthConcatenationLayer(2, 'Name', concatName);
    graph = addLayers(graph, concat);
    graph = connectLayers(graph, upConvName, concatName + "/in1");
    graph = connectLayers(graph, skipNames(4 - level), concatName + "/in2");

    block = convolutionBlock(weights, torchPrefix + ".conv_block.block", ...
        matlabPrefix, upWidths(level + 1));
    graph = addLayers(graph, block);
    graph = connectLayers(graph, concatName, matlabPrefix + "_conv1");
    previous = matlabPrefix + "_bn2";
end

outputLayer = convolutionLayer(weights, 'unet.last', classCount, 1, 'logits');
graph = addLayers(graph, outputLayer);
graph = connectLayers(graph, previous, 'logits');
network = dlnetwork(graph);

metadata = struct();
metadata.FormatVersion = "SmartKCPP-UNet-MATLAB-v1";
metadata.SourceRepository = string(weights.SourceRepository);
metadata.SourceCommit = string(weights.SourceCommit);
metadata.CheckpointSha256 = lower(string(weights.CheckpointSha256));
metadata.CheckpointSizeBytes = double(weights.CheckpointSizeBytes(1));
metadata.NetworkInputSizePx = inputSize;
metadata.ModelCropSizePx = double(weights.ModelCropSizePx(:)');
metadata.InputMean = single(weights.InputMean(:)');
metadata.InputStd = single(weights.InputStd(:)');
metadata.ClassCount = classCount;
metadata.BackgroundClassZeroBased = ...
    double(weights.BackgroundClassZeroBased(1));
metadata.ConversionPyTorchVersion = string(weights.PyTorchVersion);
metadata.ResizeMethod = "bilinear-half-pixel";
metadata.LabelResizeMethod = "nearest-half-pixel";
metadata.ParityValidated = false;
end

function layers = convolutionBlock(weights, torchPrefix, matlabPrefix, channels)
layers = [
    convolutionLayer(weights, torchPrefix + ".0", channels, 3, ...
        matlabPrefix + "_conv1")
    reluLayer('Name', matlabPrefix + "_relu1")
    normalizationLayer(weights, torchPrefix + ".2", ...
        matlabPrefix + "_bn1")
    convolutionLayer(weights, torchPrefix + ".3", channels, 3, ...
        matlabPrefix + "_conv2")
    reluLayer('Name', matlabPrefix + "_relu2")
    normalizationLayer(weights, torchPrefix + ".5", ...
        matlabPrefix + "_bn2")
    ];
end

function layer = convolutionLayer(weights, torchPrefix, channels, ...
        filterSize, layerName)
torchWeights = tensor(weights, torchPrefix + ".weight");
matlabWeights = permute(single(torchWeights), [3, 4, 2, 1]);
bias = reshape(single(tensor(weights, torchPrefix + ".bias")), 1, 1, []);
layer = convolution2dLayer(filterSize, channels, 'Padding', 'same', ...
    'Weights', matlabWeights, 'Bias', bias, 'Name', layerName);
end

function layer = normalizationLayer(weights, torchPrefix, layerName)
scale = reshape(single(tensor(weights, torchPrefix + ".weight")), 1, 1, []);
offset = reshape(single(tensor(weights, torchPrefix + ".bias")), 1, 1, []);
trainedMean = reshape(single(tensor(weights, ...
    torchPrefix + ".running_mean")), 1, 1, []);
trainedVariance = reshape(single(tensor(weights, ...
    torchPrefix + ".running_var")), 1, 1, []);
layer = batchNormalizationLayer('Epsilon', 1e-5, 'Scale', scale, ...
    'Offset', offset, 'TrainedMean', trainedMean, ...
    'TrainedVariance', trainedVariance, 'Name', layerName);
end

function value = tensor(weights, torchName)
fieldName = "tensor__" + replace(string(torchName), ".", "_");
if ~isfield(weights, fieldName)
    error('SmartKC:UNetTensorMissing', ...
        'Converted U-Net tensor is missing: %s', torchName);
end
value = weights.(fieldName);
end
