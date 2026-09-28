function VIEW_LATEST_RESULTS
% Open the most recent saved numerical reports without rerunning detection.
root=fileparts(mfilename('fullpath'));
runs=dir(fullfile(root,'Output','*','Analysis','paired_results.mat'));
assert(~isempty(runs),'No saved paired results were found.');
[~,idx]=max([runs.datenum]);
data=load(fullfile(runs(idx).folder,runs(idx).name));
assert(isfield(data.placido,'AllMetrics'), ...
    'This older run lacks numerical reports. Run run_ImagePipeline once.');
addpath(fullfile(root,'AnalysisPipeline'));
if isfield(data,'mireRange')
    mireRange=data.mireRange;
else
    mireRange=data.ringRange; % compatibility with earlier saved runs
end
presentPairedResults(data.placido,data.smartkc,mireRange,runs(idx).folder);
end
