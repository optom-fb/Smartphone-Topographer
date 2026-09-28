function run_LaptopCaptureGUI(source)
%RUN_LAPTOPCAPTUREGUI Launch the portable Placido acquisition GUI.
%   run_LaptopCaptureGUI       Opens external-camera mode.
%   run_LaptopCaptureGUI('phone') Opens CameraRecorder smartphone mode.
%
% The GUI is an acquisition tool. It does not run the image-processing
% pipeline automatically; review and then run run_ImagePipeline separately.

root = fileparts(mfilename('fullpath'));
guiFolder = fullfile(root,'LaptopCaptureGUI');
if ~isfolder(guiFolder)
    error('LaptopCaptureGUI folder was not found: %s',guiFolder);
end
addpath(genpath(guiFolder));
if nargin < 1 || isempty(source)
    source = 'external';
end
source = validatestring(source,{'external','phone'},mfilename,'source');
PlacidoLaptopCaptureApp(source);
end
