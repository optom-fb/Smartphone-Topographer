function [theta_out, r_out, pp, info] = fitPeriodicSplineRobust(theta, r, varargin)
%FITPERIODICSPLINEROBUST  Robust cubic spline for one Placido ring.
%
%  Given scattered (theta, r) measurements for a single detected ring,
%  produces a smooth function r_hat(theta) — one radius per angle.
%
%  For CLOSED rings (no large angular gap) a PERIODIC cubic B-spline is
%  fitted — the curve wraps continuously from 2π back to 0.
%
%  For NON-CLOSED rings (gap > MaxGap) and FallbackToArc = true, an ARC
%  cubic B-spline is fitted instead: it runs from one end of the data arc
%  to the other and returns NaN for angles inside the gap.  This avoids
%  the periodic spline's habit of fabricating a smooth bridge across empty
%  space.  Set FallbackToArc = false to disable and always use the periodic
%  spline (useful for debugging or when you want to see the extrapolation).
%
%  Does NOT require the MATLAB Spline Toolbox.
%
%  -------------------------------------------------------------------------
%  SYNTAX
%    [theta_out, r_out]           = fitPeriodicSplineRobust(theta, r)
%    [theta_out, r_out, pp, info] = fitPeriodicSplineRobust(theta, r, Name, Value, ...)
%
%  REQUIRED INPUTS
%    theta    N×1  Angles in radians — any wrap, need not be sorted.
%    r        N×1  Radial distances (pixels or any unit).
%
%  NAME-VALUE OPTIONS
%    'QueryAngles'   M×1 output angles [rad].
%                   Default: 360 uniformly spaced angles in [0, 2π).
%    'NumKnots'      Positive integer ≥ 8.  Number of B-spline knots.
%                   Default: 36  (one knot every 10°).
%                   For arc splines, this is scaled proportionally to arc length.
%    'Lambda'        Smoothing: 'auto' (GCV, default) or a positive scalar.
%    'Method'        'irls'   — iteratively reweighted least squares.
%                   'ransac' — random starts feeding into IRLS refinement.
%                   Default: 'irls'.
%    'RobustIter'    IRLS iterations (both methods).  Default: 5.
%    'TuningConst'   Bisquare tuning constant.  Default: 4.685.
%    'NumBins'       Pre-binning bins.  Default: 180 (2° bins).  Set 0 to skip.
%    'MinCoverage'   Warn if total arc coverage < this many degrees.  Default: 90.
%    'MaxGap'        Declare ring non-closed if any single gap exceeds this
%                   many degrees.  Default: 90.
%    'FallbackToArc' If true (default) and ring is non-closed, fit a
%                   non-periodic arc spline instead of the periodic one.
%                   pp.eval returns NaN for angles inside the gap.
%                   If false, always use the periodic spline.
%    'NumRANSAC'     Random starts for 'ransac' method.  Default: 50.
%    'SampleFrac'    Fraction of bins used per random start.  Default: 0.5.
%    'InlierTol'     RANSAC inlier radius: 'auto' (3σ from initial WLS)
%                   or a positive scalar.  Default: 'auto'.
%    'Verbose'       Print per-iteration diagnostics.  Default: false.
%
%  OUTPUTS
%    theta_out   M×1  Query angles [rad] (always the full 360° grid or QueryAngles).
%    r_out       M×1  Fitted radial values at theta_out.
%                   NaN where angles fall inside the gap (arc spline only).
%    pp          Struct:
%                  .eval(t)      — evaluates fit at any angles (NaN in gap for arc)
%                  .coeff        — B-spline coefficients
%                  .K, .h, .lambda
%                  .is_arc       — true when arc spline was used
%                  .arc_start    — (arc only) arc start angle [rad]
%                  .arc_length   — (arc only) arc length [rad]
%    info        Struct:
%                  .spline_type  — 'periodic' or 'arc'
%                  .coverage_deg — total angular coverage of raw data
%                  .max_gap_deg  — largest single angular gap in binned data
%                  .is_closed    — true if max_gap_deg < MaxGap
%                  .rms_resid    — RMS residual on raw (in-arc) points
%                  .outlier_frac — fraction of raw points flagged as outliers
%                  .outlier_mask — N×1 logical (sorted order of raw input)
%                  .residuals    — N×1 residuals (sorted; NaN for gap points)
%                  .lambda       — regularisation parameter used
%                  .bin_t, .bin_r, .bin_w — binned data used for fitting
%                  .ransac_inlier_frac — (ransac only) consensus set fraction
%
%  -------------------------------------------------------------------------
%  EXAMPLE — arc spline on partial ring
%    idx = data.RingNumber == 5;
%    [tq, rq, pp, info] = fitPeriodicSplineRobust(data.T(idx), data.R(idx), ...
%        'MaxGap', 60, 'FallbackToArc', true);
%    fprintf('Spline type: %s  |  Gap: %.0f°\n', info.spline_type, info.max_gap_deg);
%    polarplot(tq(~isnan(rq)), rq(~isnan(rq)));   % plot only the valid arc
%    r_at_nasal = pp.eval(0);        % NaN if 0° is inside the gap
%
%  -------------------------------------------------------------------------
%  EXAMPLE — periodic spline on closed ring
%    [tq, rq, pp, info] = fitPeriodicSplineRobust(data.T(idx), data.R(idx));
%    r_at_45deg = pp.eval(deg2rad(45));   % always a real value
%
%  SEE ALSO  fitAllPlacidoRings, demo_periodic_spline

%% =========================================================================
%  Input parsing
%% =========================================================================
pr = inputParser();
addRequired(pr, 'theta',  @(x) isnumeric(x) && isvector(x) && ~isempty(x));
addRequired(pr, 'r',      @(x) isnumeric(x) && isvector(x) && ~isempty(x));
addParameter(pr, 'QueryAngles',   [],       @isnumeric);
addParameter(pr, 'NumKnots',      36,       @(x) isnumeric(x) && isscalar(x) && x >= 8);
addParameter(pr, 'Lambda',        'auto');
addParameter(pr, 'Method',        'irls',   @(x) ismember(lower(x), {'irls','ransac'}));
addParameter(pr, 'RobustIter',    5,        @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(pr, 'TuningConst',   4.685,    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(pr, 'NumBins',       180,      @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(pr, 'MinCoverage',   90,       @(x) isnumeric(x) && isscalar(x));
addParameter(pr, 'MaxGap',        90,       @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(pr, 'FallbackToArc', true,     @(x) islogical(x) || isnumeric(x));
addParameter(pr, 'NumRANSAC',     50,       @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(pr, 'SampleFrac',    0.5,      @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
addParameter(pr, 'InlierTol',     'auto');
addParameter(pr, 'Verbose',       false,    @(x) islogical(x) || isnumeric(x));
parse(pr, theta, r, varargin{:});
opt = pr.Results;
opt.Method = lower(opt.Method);

theta = double(theta(:));
r     = double(r(:));
assert(numel(theta) == numel(r), ...
    'fitPeriodicSplineRobust: theta and r must be the same length.');

%% Default query grid
if isempty(opt.QueryAngles)
    theta_out = (0 : 2*pi/360 : 2*pi*(1 - 1/360)).';
else
    theta_out = double(opt.QueryAngles(:));
end

%% =========================================================================
%  Step 1: Wrap to [0, 2π) and sort
%% =========================================================================
theta = mod(theta, 2*pi);
[theta_s, sidx] = sort(theta);
r_s = r(sidx);

%% =========================================================================
%  Step 2: Pre-bin and measure coverage / gaps
%% =========================================================================
if opt.NumBins > 0
    [bin_t, bin_r, bin_w] = localBinMedian(theta_s, r_s, opt.NumBins);
else
    bin_t = theta_s;
    bin_r = r_s;
    bin_w = ones(size(r_s));
end

[cov_deg, max_gap_deg] = localAngStats(bin_t);
info.coverage_deg = cov_deg;
info.max_gap_deg  = max_gap_deg;
info.is_closed    = max_gap_deg < opt.MaxGap;
info.bin_t = bin_t;
info.bin_r = bin_r;
info.bin_w = bin_w;
info.ransac_inlier_frac = NaN;

if cov_deg < opt.MinCoverage
    warning('fitPeriodicSplineRobust:lowCoverage', ...
        'Coverage %.1f° < MinCoverage %.0f°.', cov_deg, opt.MinCoverage);
end
if ~info.is_closed
    if opt.FallbackToArc
        if opt.Verbose
            fprintf('[PeriodicSpline] Gap %.1f° > MaxGap %.0f° — switching to arc spline.\n', ...
                max_gap_deg, opt.MaxGap);
        end
    else
        warning('fitPeriodicSplineRobust:largeGap', ...
            'Gap %.1f° > MaxGap %.0f° — ring non-closed. Periodic fit extrapolates across gap.', ...
            max_gap_deg, opt.MaxGap);
    end
end
if opt.Verbose
    fprintf('[PeriodicSpline] N=%d pts  coverage=%.1f°  max_gap=%.1f°  closed=%d\n', ...
        numel(theta), cov_deg, max_gap_deg, info.is_closed);
end

%% =========================================================================
%  Branch: arc spline vs periodic spline
%% =========================================================================
if ~info.is_closed && opt.FallbackToArc
    % -----------------------------------------------------------------------
    %  ARC SPLINE PATH
    %  Fits a non-periodic cubic B-spline along the data arc.
    %  pp.eval returns NaN for angles inside the gap.
    % -----------------------------------------------------------------------
    info.spline_type = 'arc';

    % --- Find arc endpoints ------------------------------------------------
    [arc_start, arc_length] = localFindArc(bin_t, max_gap_deg);
    info.arc_start      = arc_start;
    info.arc_length_deg = rad2deg(arc_length);
    if opt.Verbose
        fprintf('  Arc: start=%.1f°  length=%.1f°\n', ...
            rad2deg(arc_start), rad2deg(arc_length));
    end

    % --- Remap angles → arc parameter τ ∈ [0, arc_length] -----------------
    tau_bin = mod(bin_t  - arc_start, 2*pi);
    tau_raw = mod(theta_s - arc_start, 2*pi);
    tau_out = mod(theta_out - arc_start, 2*pi);

    % Points that actually fall on the arc (all bins should; raw may straddle)
    in_arc_bin = tau_bin <= arc_length + 1e-9;
    in_arc_raw = tau_raw <= arc_length + 1e-9;
    in_arc_out = tau_out <= arc_length + 1e-9;

    % Fit only on arc-side bins (should be all of them after gap detection)
    tau_fit = tau_bin(in_arc_bin);
    r_fit   = bin_r(in_arc_bin);
    w_fit   = bin_w(in_arc_bin);

    % --- Scale NumKnots to arc length -------------------------------------
    K_arc = max(8, round(opt.NumKnots * arc_length / (2*pi)));
    h_arc = arc_length / max(K_arc - 1, 1);

    % --- Build arc B-spline basis and penalty matrix ----------------------
    B_fit  = localArcBasis(tau_fit, K_arc, arc_length);
    B_raw  = localArcBasis(tau_raw, K_arc, arc_length);
    Omega  = localBuildOmegaArc(K_arc, arc_length);

    N_bin = numel(tau_fit);
    if N_bin < K_arc / 2
        warning('fitPeriodicSplineRobust:sparseArcData', ...
            'Only %d arc bins filled; consider reducing NumKnots (%d).', N_bin, K_arc);
    end

    % --- Select λ ---------------------------------------------------------
    lambda = localSelectLambda(B_fit, r_fit, w_fit, Omega, opt.Lambda, opt.Verbose);
    info.lambda = lambda;
    if opt.Verbose, fprintf('  Lambda = %.4g\n', lambda); end

    % --- Fit (IRLS or RANSAC) ---------------------------------------------
    switch opt.Method
        case 'irls'
            coeff = localFitIRLS(B_fit, r_fit, w_fit, Omega, lambda, ...
                                 opt.RobustIter, opt.TuningConst, opt.Verbose);
        case 'ransac'
            [coeff, ransac_frac] = localFitRANSAC( ...
                B_fit, r_fit, w_fit, Omega, lambda, ...
                opt.NumRANSAC, opt.SampleFrac, opt.InlierTol, ...
                opt.RobustIter, opt.TuningConst, opt.Verbose);
            info.ransac_inlier_frac = ransac_frac;
    end

    % --- Evaluate at query grid (NaN in gap) ------------------------------
    r_out = nan(size(theta_out));
    if any(in_arc_out)
        B_q = localArcBasis(tau_out(in_arc_out), K_arc, arc_length);
        r_out(in_arc_out) = B_q * coeff;
    end

    % --- Package pp -------------------------------------------------------
    arc_start_cap  = arc_start;
    arc_length_cap = arc_length;
    K_cap          = K_arc;
    pp.coeff      = coeff;
    pp.K          = K_arc;
    pp.h          = h_arc;
    pp.lambda     = lambda;
    pp.is_arc     = true;
    pp.arc_start  = arc_start;
    pp.arc_length = arc_length;
    pp.eval       = @(t) localEvalArcSpline(t, arc_start_cap, arc_length_cap, K_cap, coeff);

    % --- Diagnostics on raw points ----------------------------------------
    r_pred_raw      = nan(size(r_s));
    r_pred_raw(in_arc_raw) = B_raw(in_arc_raw, :) * coeff;
    resid_raw       = r_s - r_pred_raw;

    arc_resid       = resid_raw(in_arc_raw);
    sigma_raw       = max(eps, median(abs(arc_resid)) / 0.6745);
    info.residuals  = resid_raw;
    info.rms_resid  = sqrt(mean(arc_resid.^2));
    info.outlier_mask = abs(resid_raw) > opt.TuningConst * sigma_raw;
    info.outlier_mask(~in_arc_raw) = false;  % gap points: not classified
    info.outlier_frac = mean(info.outlier_mask(in_arc_raw));

    if opt.Verbose
        fprintf('  RMS=%.3f px  outliers=%.1f%%  arc_length=%.1f°\n', ...
            info.rms_resid, 100*info.outlier_frac, rad2deg(arc_length));
    end

else
    % -----------------------------------------------------------------------
    %  PERIODIC SPLINE PATH
    % -----------------------------------------------------------------------
    info.spline_type = 'periodic';

    K = opt.NumKnots;
    h = 2*pi / K;

    B_bin = localBsplineBasis(bin_t,   K);
    B_out = localBsplineBasis(theta_out, K);
    B_raw = localBsplineBasis(theta_s,  K);

    Omega = localBuildOmega(K, h);

    N_bin = numel(bin_t);
    if N_bin < K / 2
        warning('fitPeriodicSplineRobust:sparseData', ...
            'Only %d bins filled; consider reducing NumKnots (%d).', N_bin, K);
    end

    % --- Select λ ---------------------------------------------------------
    lambda = localSelectLambda(B_bin, bin_r, bin_w, Omega, opt.Lambda, opt.Verbose);
    info.lambda = lambda;
    if opt.Verbose, fprintf('  Lambda = %.4g\n', lambda); end

    % --- Fit --------------------------------------------------------------
    switch opt.Method
        case 'irls'
            coeff = localFitIRLS(B_bin, bin_r, bin_w, Omega, lambda, ...
                                 opt.RobustIter, opt.TuningConst, opt.Verbose);
            info.ransac_inlier_frac = NaN;
        case 'ransac'
            [coeff, ransac_frac] = localFitRANSAC( ...
                B_bin, bin_r, bin_w, Omega, lambda, ...
                opt.NumRANSAC, opt.SampleFrac, opt.InlierTol, ...
                opt.RobustIter, opt.TuningConst, opt.Verbose);
            info.ransac_inlier_frac = ransac_frac;
    end

    % --- Evaluate at output grid ------------------------------------------
    r_out = B_out * coeff;

    % --- Package pp -------------------------------------------------------
    K_cap = K;
    pp.coeff  = coeff;
    pp.K      = K;
    pp.h      = h;
    pp.lambda = lambda;
    pp.is_arc = false;
    pp.eval   = @(t) localBsplineBasis(mod(double(t(:)), 2*pi), K_cap) * coeff;

    % --- Diagnostics on raw points ----------------------------------------
    r_pred_raw      = B_raw * coeff;
    resid_raw       = r_s - r_pred_raw;
    sigma_raw       = max(eps, median(abs(resid_raw)) / 0.6745);
    info.residuals  = resid_raw;
    info.rms_resid  = sqrt(mean(resid_raw.^2));
    info.outlier_mask = abs(resid_raw) > opt.TuningConst * sigma_raw;
    info.outlier_frac = mean(info.outlier_mask);

    if opt.Verbose
        fprintf('  RMS=%.3f px  outliers=%.1f%%  closed=%d  max_gap=%.1f°\n', ...
            info.rms_resid, 100*info.outlier_frac, info.is_closed, max_gap_deg);
    end
end

end  % ---- end main function ----


%% =========================================================================
%  FITTING ENGINES  (shared by both spline types)
%% =========================================================================

function coeff = localFitIRLS(B, r, w, Omega, lambda, nIter, tc, verbose)
%LOCALFITIRLS  Iteratively reweighted least squares with bisquare weights.
w_irls = w;
K      = size(B, 2);
coeff  = zeros(K, 1);

for iter = 0:nIter
    BtW   = B.' .* w_irls.';
    coeff = (BtW * B + lambda * Omega) \ (BtW * r);

    if iter < nIter
        resid  = r - B * coeff;
        sigma  = max(1e-9, median(abs(resid)) / 0.6745);
        u      = resid / (tc * sigma);
        bsq    = ((1 - u.^2).^2) .* (abs(u) < 1);
        w_irls = w .* bsq;
        if verbose
            fprintf('  IRLS iter %d: sigma=%.3f  outlier_bins=%d/%d\n', ...
                iter+1, sigma, sum(bsq < 0.5), numel(r));
        end
    end
end
end


function [coeff, inlier_frac] = localFitRANSAC(B, r, w, Omega, lambda, ...
    nTrials, sampleFrac, inlierTol, nIRLS, tc, verbose)
%LOCALFITRANSAC  Random-start IRLS (stochastic IRLS / RS-IRLS).
N_bin  = numel(r);
n_samp = max(size(B,2), round(sampleFrac * N_bin));
n_samp = min(n_samp, N_bin);

if ischar(inlierTol) && strcmp(inlierTol, 'auto')
    BtW_all  = B.' .* w.';
    c_init   = (BtW_all * B + lambda * Omega) \ (BtW_all * r);
    resid0   = r - B * c_init;
    sigma0   = max(1e-9, median(abs(resid0)) / 0.6745);
    inlierTol = 3 * sigma0;
    if verbose
        fprintf('  RANSAC: auto InlierTol = %.2f (3 × %.2f)\n', inlierTol, sigma0);
    end
end

best_weight  = -Inf;
best_coeff   = zeros(size(B, 2), 1);
best_inliers = true(N_bin, 1);

for trial = 1:nTrials
    idx   = randperm(N_bin, n_samp);
    B_sub = B(idx, :);
    r_sub = r(idx);
    w_sub = w(idx);

    BtW_sub = B_sub.' .* w_sub.';
    try
        c_try = (BtW_sub * B_sub + lambda * Omega) \ (BtW_sub * r_sub);
    catch
        continue;
    end

    resid_all   = r - B * c_try;
    inlier_mask = abs(resid_all) <= inlierTol;
    inlier_wt   = sum(w(inlier_mask));

    if inlier_wt > best_weight
        best_weight  = inlier_wt;
        best_coeff   = c_try;
        best_inliers = inlier_mask;
    end
end

inlier_frac = sum(best_inliers) / N_bin;
if verbose
    fprintf('  RANSAC: inlier_bins=%d/%d (%.0f%%)  tol=%.2f\n', ...
        sum(best_inliers), N_bin, 100*inlier_frac, inlierTol);
end

w_init = w .* double(best_inliers);
if sum(w_init) < eps, w_init = w; end

coeff = localFitIRLS(B, r, w_init, Omega, lambda, nIRLS, tc, verbose);
end


%% =========================================================================
%  PERIODIC SPLINE — KERNEL AND BASIS
%% =========================================================================

function B = localBsplineBasis(theta, K)
%LOCALBSPLINEBASIS  N×K periodic cubic B-spline design matrix.
%  Knots at t_k = 2πk/K.  Partition of unity: sum(B,2) == 1 everywhere.
h = 2*pi / K;
N = numel(theta);
B = zeros(N, K);
for k = 0:(K-1)
    d = mod(theta - k*h + pi, 2*pi) - pi;   % signed periodic distance
    B(:, k+1) = localCubicKernel(d / h);
end
end


function y = localCubicKernel(u)
%LOCALCUBICKERNEL  Cubic B-spline kernel, support (-2,2).
au = abs(u);
y  = zeros(size(u));
m1 = au < 1;
y(m1) = 2/3 - au(m1).^2 + 0.5*au(m1).^3;
m2 = (au >= 1) & (au < 2);
y(m2) = (2 - au(m2)).^3 / 6;
end


function d2y = localCubicKernel2ndDeriv(u)
%LOCALCUBICKERNEL2NDDERIV  d²B/du².
au  = abs(u);
d2y = zeros(size(u));
d2y(au < 1)             = -2 + 3*au(au < 1);
d2y((au>=1) & (au<2))  =  2 - au((au>=1) & (au<2));
end


function Omega = localBuildOmega(K, h)
%LOCALBUILDOMENGA  K×K penalty matrix Ω_{jk} = ∫B_j''(θ) B_k''(θ)dθ (periodic).
Nq = max(2000, 100*K);
tq = linspace(0, 2*pi, Nq+1); tq = tq(1:end-1).';
D2 = zeros(Nq, K);
for k = 0:(K-1)
    d = mod(tq - k*h + pi, 2*pi) - pi;
    D2(:, k+1) = localCubicKernel2ndDeriv(d/h) / h^2;
end
Omega = D2.' * D2 * (2*pi/Nq);
end


%% =========================================================================
%  ARC SPLINE — NON-PERIODIC KERNEL AND BASIS
%% =========================================================================

function B = localArcBasis(tau, K, arc_length)
%LOCALARCBASIS  N×K non-periodic cubic B-spline basis on [0, arc_length].
%
%  K knots equally spaced in [0, arc_length].  Same cubic kernel as the
%  periodic case but WITHOUT angular wrapping — ordinary distance u=(τ-t_k)/h.
%
%  Rows are normalised to sum to 1 so boundary behaviour is sensible:
%  at τ=0 only the leftmost 1–2 basis functions contribute, and without
%  normalisation the row sum is < 1, causing spurious low-radius predictions.
%  With normalisation the remaining basis functions are rescaled to share the
%  full weight, which (together with the smoothing penalty) gives clean fits
%  right to the arc endpoints.
h = arc_length / max(K - 1, 1);
N = numel(tau);
B = zeros(N, K);
for k = 0:(K-1)
    u = (tau - k*h) / h;
    B(:, k+1) = localCubicKernel(u);
end
% Partition-of-unity normalisation
row_sum = sum(B, 2);
row_sum(row_sum < eps) = 1;
B = B ./ row_sum;
end


function Omega = localBuildOmegaArc(K, arc_length)
%LOCALBUILDOMEGATANGLE  K×K penalty matrix for arc B-spline on [0, arc_length].
%  Uses finite-difference approximation of d²B/dτ² to stay consistent with
%  the normalised localArcBasis (analytical second derivative of the normalised
%  basis requires the quotient rule and is more complex than it's worth).
Nq   = max(2000, 100*K);
tq   = linspace(0, arc_length, Nq).';
dh   = arc_length * 1e-5;

B0   = localArcBasis(tq,          K, arc_length);
Bp   = localArcBasis(min(tq + dh, arc_length), K, arc_length);
Bm   = localArcBasis(max(tq - dh, 0),          K, arc_length);
D2   = (Bp - 2*B0 + Bm) / dh^2;

Omega = D2.' * D2 * (arc_length / Nq);
end


function [arc_start, arc_length] = localFindArc(bin_t, max_gap_deg)
%LOCALFINDARC  Arc start angle and arc length in radians from binned data.
%  arc_start: first angle just after the largest gap.
%  arc_length: 2π minus the largest gap — total angular extent of data.
if numel(bin_t) < 2
    arc_start = 0; arc_length = 0; return;
end
gaps    = [diff(bin_t); 2*pi - bin_t(end) + bin_t(1)];
[~, gi] = max(gaps);           % index of largest gap
if gi < numel(bin_t)
    arc_start = bin_t(gi + 1); % first angle after gap
else
    arc_start = bin_t(1);      % gap straddles wrap — data starts at bin_t(1)
end
arc_length = 2*pi - deg2rad(max_gap_deg);
end


function r = localEvalArcSpline(t, arc_start, arc_length, K, coeff)
%LOCALEVALARCSPLINE  Evaluate arc spline at arbitrary angles [rad].
%  Returns NaN for angles that fall inside the gap (tau > arc_length).
t   = mod(double(t(:)), 2*pi);
tau = mod(t - arc_start, 2*pi);
r   = nan(size(tau));
in_arc = tau <= arc_length + 1e-9;
if any(in_arc)
    B = localArcBasis(tau(in_arc), K, arc_length);
    r(in_arc) = B * coeff;
end
end


%% =========================================================================
%  PRE-PROCESSING HELPERS
%% =========================================================================

function [bin_t, bin_r, bin_w] = localBinMedian(theta, r, nBins)
%LOCALBINMEDIAN  Median radius and count per angular bin.
edges = linspace(0, 2*pi, nBins+1);
[~, ~, idx] = histcounts(theta, edges);
bin_t = zeros(0,1); bin_r = zeros(0,1); bin_w = zeros(0,1);
for k = 1:nBins
    mask = (idx == k);
    if any(mask)
        bin_t(end+1,1) = median(theta(mask));  %#ok<AGROW>
        bin_r(end+1,1) = median(r(mask));       %#ok<AGROW>
        bin_w(end+1,1) = sum(mask);             %#ok<AGROW>
    end
end
end


function [cov_deg, max_gap_deg] = localAngStats(theta)
%LOCALANGSTATS  Total coverage and largest single gap, both in degrees.
if numel(theta) < 2
    cov_deg = 0; max_gap_deg = 360; return;
end
gaps        = [diff(theta); 2*pi - theta(end) + theta(1)];
max_gap_deg = rad2deg(max(gaps));
cov_deg     = 360 - max_gap_deg;
end


function lambda = localSelectLambda(B, r, w, Omega, lambda_in, verbose)
%LOCALSELECTLAMBDA  GCV-based λ selection, or passthrough for numeric input.
if isnumeric(lambda_in)
    lambda = max(0, lambda_in); return;
end

K      = size(B, 2);
N      = numel(r);
BtWB   = B.' * (w .* B);
BtWr   = B.' * (w .* r);
lscale = max(trace(BtWB),eps) / max(trace(Omega),eps);
lambdas = lscale * logspace(-6, 3, 50);
gcv     = inf(1, numel(lambdas));

for i = 1:numel(lambdas)
    A = BtWB + lambdas(i) * Omega;
    try
        sol    = A \ [BtWB, BtWr];
        df_eff = trace(sol(:,1:K));
        rss    = sum(w .* (r - B*sol(:,end)).^2);
        den    = (1 - df_eff/N)^2;
        if den > 1e-6, gcv(i) = (rss/N) / den; end
    catch; end
end

[~, best] = min(gcv);
lambda = lambdas(best);
if verbose
    fprintf('  GCV: lambda=%.4g (index %d/%d)\n', lambda, best, numel(lambdas));
end
end
