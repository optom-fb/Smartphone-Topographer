function [ringTable, ppArray, infoArray] = fitAllPlacidoRings(data, varargin)
%FITALLPLACIDORINGS  Fit a robust spline to every ring in a Placido table.
%
%  Applies fitPeriodicSplineRobust to each unique ring number in the
%  detection results table.
%
%  For CLOSED rings, a periodic cubic B-spline is fitted.
%  For NON-CLOSED rings with FallbackToArc = true (the default), an arc
%  cubic B-spline is fitted instead — it covers only the data arc and
%  returns NaN for angles inside the gap.  This is honest: the periodic
%  spline would silently fabricate a smooth bridge across empty space.
%
%  -------------------------------------------------------------------------
%  SYNTAX
%    [ringTable, ppArray, infoArray] = fitAllPlacidoRings(data)
%    [ringTable, ppArray, infoArray] = fitAllPlacidoRings(data, Name, Value, ...)
%
%  REQUIRED INPUT
%    data     Table from the Placido detection pipeline, containing columns:
%               RingNumber — integer ring label (1 = innermost)
%               T          — angle in radians
%               R          — radial distance in pixels
%             Any extra columns are ignored.
%
%  NAME-VALUE OPTIONS
%  ---- fitAllPlacidoRings-specific ----------------------------------------
%    'SkipBelowCoverage'  Omit rings whose arc coverage is below this many
%                         degrees.  Default: 0 (keep all).
%    'RejectNonClosed'    If true, omit rings where info.is_closed is false
%                         and FallbackToArc is false.  When FallbackToArc is
%                         true (default), non-closed rings are fitted as arcs
%                         and are never rejected on closure grounds alone.
%                         Default: false.
%
%  ---- passed through to fitPeriodicSplineRobust --------------------------
%    'QueryAngles'   M×1 output angles [rad]. Default: 360 uniform in [0,2π).
%    'NumKnots'      Default: 36.
%    'Lambda'        Default: 'auto' (GCV).
%    'Method'        'irls' (default) or 'ransac'.
%    'RobustIter'    Default: 5.
%    'TuningConst'   Default: 4.685.
%    'NumBins'       Default: 180.
%    'MinCoverage'   Warn if coverage < this.  Default: 90.
%    'MaxGap'        Declare non-closed if gap > this [°].  Default: 90.
%    'FallbackToArc' Use arc spline for non-closed rings.  Default: true.
%    'NumRANSAC'     Default: 50.
%    'SampleFrac'    Default: 0.5.
%    'InlierTol'     Default: 'auto'.
%    'Verbose'       Default: false.
%
%  OUTPUTS
%    ringTable   Table with columns:
%                  RingNumber  — ring index
%                  Theta       — query angles [rad]  (M values per ring)
%                  R_fit       — fitted radii [px]  (NaN in gap for arc rings)
%                  Coverage    — angular coverage [°]
%                  SplineType  — 'periodic' or 'arc'
%                  IsClosed    — true if ring has no large gap
%                  MaxGap      — largest single angular gap [°]
%                  RMS_resid   — RMS fit residual on raw in-arc points [px]
%                  OutlierFrac — fraction of raw points flagged as outliers
%                  Lambda      — regularisation parameter chosen
%
%    ppArray     Cell array of pp structs (one per ring, in RingNumber order).
%                pp.eval(t) gives fitted radius at arbitrary angles.
%                For arc rings, pp.eval returns NaN inside the gap.
%
%    infoArray   Cell array of info structs (one per ring).
%
%  -------------------------------------------------------------------------
%  EXAMPLE
%    data = readtable('FA_OD_results.csv');
%    [tbl, pps, infos] = fitAllPlacidoRings(data, ...
%        'MaxGap', 60, 'FallbackToArc', true, 'Method', 'ransac');
%
%    % Show which rings got arc fits
%    arc_rings = tbl(strcmp(tbl.SplineType,'arc'), :);
%    fprintf('%d rings needed arc splines.\n', numel(unique(arc_rings.RingNumber)));
%
%    % Plot all rings — NaN values break the line cleanly in the gap
%    figure; ax = polaraxes; hold(ax,'on');
%    rings = unique(tbl.RingNumber);
%    for i = 1:numel(rings)
%        k = rings(i);
%        m = tbl.RingNumber == k;
%        polarplot(ax, tbl.Theta(m), tbl.R_fit(m));
%    end
%
%    % Probe ring 5 at nasal meridian (0°)
%    r_nasal = pps{5}.eval(0);   % NaN if 0° is in ring 5's gap

%% =========================================================================
%  Parse inputs
%% =========================================================================
pr = inputParser();
addRequired(pr, 'data', @istable);
% fitAllPlacidoRings-specific
addParameter(pr, 'SkipBelowCoverage', 0,     @isnumeric);
addParameter(pr, 'RejectNonClosed',   false,  @(x) islogical(x)||isnumeric(x));
% pass-throughs
addParameter(pr, 'QueryAngles',   [],       @isnumeric);
addParameter(pr, 'NumKnots',      36,       @isnumeric);
addParameter(pr, 'Lambda',        'auto');
addParameter(pr, 'Method',        'irls',   @ischar);
addParameter(pr, 'RobustIter',    5,        @isnumeric);
addParameter(pr, 'TuningConst',   4.685,    @isnumeric);
addParameter(pr, 'NumBins',       180,      @isnumeric);
addParameter(pr, 'MinCoverage',   90,       @isnumeric);
addParameter(pr, 'MaxGap',        90,       @isnumeric);
addParameter(pr, 'FallbackToArc', true,     @(x) islogical(x)||isnumeric(x));
addParameter(pr, 'NumRANSAC',     50,       @isnumeric);
addParameter(pr, 'SampleFrac',    0.5,      @isnumeric);
addParameter(pr, 'InlierTol',     'auto');
addParameter(pr, 'Verbose',       false,    @(x) islogical(x)||isnumeric(x));
parse(pr, data, varargin{:});
opt = pr.Results;

% Validate required columns
for c = {'RingNumber', 'T', 'R'}
    if ~ismember(c{1}, data.Properties.VariableNames)
        error('fitAllPlacidoRings: input table must contain column "%s".', c{1});
    end
end

% Default query grid
if isempty(opt.QueryAngles)
    theta_q = (0 : 2*pi/360 : 2*pi*(1 - 1/360)).';
else
    theta_q = opt.QueryAngles(:);
end
M = numel(theta_q);

% Build pass-through option list
fit_opts = { ...
    'QueryAngles',   theta_q, ...
    'NumKnots',      opt.NumKnots, ...
    'Lambda',        opt.Lambda, ...
    'Method',        opt.Method, ...
    'RobustIter',    opt.RobustIter, ...
    'TuningConst',   opt.TuningConst, ...
    'NumBins',       opt.NumBins, ...
    'MinCoverage',   opt.MinCoverage, ...
    'MaxGap',        opt.MaxGap, ...
    'FallbackToArc', opt.FallbackToArc, ...
    'NumRANSAC',     opt.NumRANSAC, ...
    'SampleFrac',    opt.SampleFrac, ...
    'InlierTol',     opt.InlierTol, ...
    'Verbose',       opt.Verbose};

%% =========================================================================
%  Fit each ring
%% =========================================================================
ring_ids = sort(unique(data.RingNumber));
nRings   = numel(ring_ids);

ppArray   = cell(nRings, 1);
infoArray = cell(nRings, 1);

% Pre-allocate table accumulators
acc_rnum   = zeros(nRings * M, 1);
acc_theta  = zeros(nRings * M, 1);
acc_rfit   = nan(nRings * M, 1);
acc_cov    = zeros(nRings * M, 1);
acc_stype  = repmat({'periodic'}, nRings * M, 1);
acc_closed = true(nRings * M, 1);
acc_maxgap = zeros(nRings * M, 1);
acc_rms    = zeros(nRings * M, 1);
acc_outfr  = zeros(nRings * M, 1);
acc_lam    = zeros(nRings * M, 1);

n_written  = 0;
n_skipped  = 0;

for i = 1:nRings
    k   = ring_ids(i);
    idx = data.RingNumber == k;
    t_k = data.T(idx);
    r_k = data.R(idx);

    % --- Minimum data check -----------------------------------------------
    if numel(t_k) < 5
        if opt.Verbose
            fprintf('[fitAllPlacidoRings] Ring %d: skipped (only %d points).\n', k, numel(t_k));
        end
        n_skipped = n_skipped + 1;
        ppArray{i}   = [];
        infoArray{i} = struct('coverage_deg', 0, 'max_gap_deg', 360, ...
                              'is_closed', false, 'spline_type', 'none', ...
                              'rms_resid', NaN, 'outlier_frac', NaN, 'lambda', NaN);
        continue;
    end

    % --- Fit --------------------------------------------------------------
    try
        [~, r_fit_k, pp_k, info_k] = fitPeriodicSplineRobust(t_k, r_k, fit_opts{:});
    catch ME
        fprintf('[fitAllPlacidoRings] Ring %d: fit failed — %s\n', k, ME.message);
        n_skipped = n_skipped + 1;
        ppArray{i}   = [];
        infoArray{i} = struct('coverage_deg', 0, 'max_gap_deg', 360, ...
                              'is_closed', false, 'spline_type', 'error', ...
                              'rms_resid', NaN, 'outlier_frac', NaN, 'lambda', NaN);
        continue;
    end

    % --- Skip by coverage threshold --------------------------------------
    if info_k.coverage_deg < opt.SkipBelowCoverage
        if opt.Verbose
            fprintf('[fitAllPlacidoRings] Ring %d: skipped (coverage %.1f° < %.0f°).\n', ...
                k, info_k.coverage_deg, opt.SkipBelowCoverage);
        end
        n_skipped = n_skipped + 1;
        ppArray{i}   = [];
        infoArray{i} = info_k;
        continue;
    end

    % --- Reject non-closed (only meaningful when FallbackToArc = false) --
    if opt.RejectNonClosed && ~opt.FallbackToArc && ~info_k.is_closed
        if opt.Verbose
            fprintf('[fitAllPlacidoRings] Ring %d: rejected (non-closed, gap=%.1f°).\n', ...
                k, info_k.max_gap_deg);
        end
        n_skipped = n_skipped + 1;
        ppArray{i}   = [];
        infoArray{i} = info_k;
        continue;
    end

    % --- Store ring -------------------------------------------------------
    ppArray{i}   = pp_k;
    infoArray{i} = info_k;

    rows = n_written + (1:M);
    acc_rnum(rows)   = k;
    acc_theta(rows)  = theta_q;
    acc_rfit(rows)   = r_fit_k;
    acc_cov(rows)    = info_k.coverage_deg;
    acc_maxgap(rows) = info_k.max_gap_deg;
    acc_closed(rows) = info_k.is_closed;
    acc_stype(rows)  = {info_k.spline_type};
    acc_rms(rows)    = info_k.rms_resid;
    acc_outfr(rows)  = info_k.outlier_frac;
    acc_lam(rows)    = info_k.lambda;
    n_written = n_written + M;

    if opt.Verbose
        fprintf('[fitAllPlacidoRings] Ring %d [%s]: coverage=%.1f°  gap=%.1f°  RMS=%.2f px  out=%.1f%%\n', ...
            k, info_k.spline_type, info_k.coverage_deg, info_k.max_gap_deg, ...
            info_k.rms_resid, 100*info_k.outlier_frac);
    end
end

% --- Build output table ---------------------------------------------------
rows_used = 1:n_written;
ringTable = table( ...
    acc_rnum(rows_used), ...
    acc_theta(rows_used), ...
    acc_rfit(rows_used), ...
    acc_cov(rows_used), ...
    acc_stype(rows_used), ...
    acc_closed(rows_used), ...
    acc_maxgap(rows_used), ...
    acc_rms(rows_used), ...
    acc_outfr(rows_used), ...
    acc_lam(rows_used), ...
    'VariableNames', {'RingNumber','Theta','R_fit','Coverage', ...
                      'SplineType','IsClosed','MaxGap', ...
                      'RMS_resid','OutlierFrac','Lambda'});

if opt.Verbose || n_skipped > 0
    fprintf('[fitAllPlacidoRings] Done: %d rings fitted, %d skipped.\n', ...
        nRings - n_skipped, n_skipped);
end

end
