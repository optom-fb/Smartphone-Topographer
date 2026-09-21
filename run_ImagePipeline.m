function run_ImagePipeline
%RUN_IMAGEPIPELINE Run the paired Placido and classical SmartKC image demo.
% Edit the three settings below, then run this file from MATLAB.
% Results are research-only image descriptors; calibration is not supplied.

root = fileparts(mfilename('fullpath'));
analysisRoot = fullfile(root,'AnalysisPipeline');
addpath(analysisRoot);
addpath(fullfile(analysisRoot,'config'));
addpath(genpath(fullfile(analysisRoot,'functions')));
dataRoot = fullfile(root,'Data');
if ~isfolder(dataRoot), mkdir(dataRoot); end

%% USER SETTINGS
INPUT_IMAGE_NAME = 'trial1.jpg'; % default demonstration image in Data
FIRST_MIRE = 1;              % first mire included in the final comparison
LAST_MIRE = 15;              % last mire included in the final comparison

if isempty(INPUT_IMAGE_NAME)
    [name,folder] = uigetfile({'*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp','Image files'}, ...
        'Select a sample image from Data');
    if isequal(name,0), return; end
    imagePath = fullfile(folder,name);
else
    imagePath = fullfile(dataRoot,INPUT_IMAGE_NAME);
    if ~isfile(imagePath)
        error('Image not found in Data: %s',imagePath);
    end
    [~,name,ext] = fileparts(imagePath); name = [name ext];
end
validateattributes([FIRST_MIRE LAST_MIRE],{'numeric'},{'finite','integer','positive'});
if LAST_MIRE < FIRST_MIRE, error('LAST_MIRE must be >= FIRST_MIRE.'); end
timestamp=char(datetime('now','Format','yyyyMMdd_HHmmss'));
runFolder = fullfile(root,'Output',[erase(name,{'.png','.jpg','.jpeg','.tif','.tiff','.bmp'}),'_',timestamp]);
if ~isfolder(runFolder), mkdir(runFolder); end
mireRange = [FIRST_MIRE LAST_MIRE];
% Raw render stages are temporary; only writeup-aligned outputs are published.
scratch = tempname; mkdir(scratch);
scratchCleanup = onCleanup(@() rmdir(scratch,'s'));
placidoFolder = fullfile(scratch,'Placido');
smartkcFolder = fullfile(scratch,'SmartKC');
fprintf('Running Placido image pipeline...\n');
placido = generate_placido_only_step_images(imagePath,mireRange,placidoFolder,1:28);
fprintf('Running classical SmartKC image pipeline...\n');
smartkc = generate_smartkc_step_images(imagePath,mireRange,smartkcFolder,[1:7 20:28]);
alignOutputsToWriteup(placido,smartkc,runFolder);
placido.OutputFolder=fullfile(runFolder,'Placido_Output');
smartkc.OutputFolder=fullfile(runFolder,'SmartKC_Output');
placido.OutputFiles=[]; placido.FullFrameOutputFiles=[];
smartkc.OutputFiles=[]; smartkc.FullFrameOutputFiles=[];
save(fullfile(runFolder,'Analysis','paired_results.mat'),'placido','smartkc','imagePath','mireRange');
presentPairedResults(placido,smartkc,mireRange,fullfile(runFolder,'Analysis'));
fprintf('Complete. Results saved under %s\n',runFolder);
fprintf('Figures, values tables and complete-only summaries are saved in Analysis.\n');
end
