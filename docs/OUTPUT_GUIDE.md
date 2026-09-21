# Image analysis outputs

Paired comparison and ellipse overlays use mire IDs that pass the completeness
gate in both methods. `FIRST_MIRE` and `LAST_MIRE` limit only the final
comparison and quantitative summaries; they do not alter either detector.
For example, if Placido mires 2–8 and SmartKC mires 1–7 are complete, the
common complete set is 2–7. `common_complete_mires.csv` records the common set
and which entries fall inside the selected comparison range.

New runs preserve raw Placido centreline points for the dotted covariance
ellipse overlays. Older saved runs without these points are explicitly labelled
as displaying spline samples. Detection completeness and successful explicit
ellipse fitting are separate checks; an undefined ellipse metric is NaN.

Run `run_ImagePipeline` for the configured image and inclusive mire range.
Run `VIEW_LATEST_RESULTS` to reopen the latest saved numerical reports without
repeating detection. Report windows follow the active MATLAB theme.

Each run contains Placido_Output, SmartKC_Output, and Analysis. Method folders
contain figures numbered by manuscript phase and step. Analysis contains CSV
tables, summary CSVs, native MATLAB FIG reports, plot PNGs, and paired_results.mat.
Intermediate rendering files are temporary and are not retained in Output.

The viewer has seven tabs: Placido all detected, Placido complete only,
Placido covariance ellipses, SmartKC all detected, SmartKC complete only,
SmartKC covariance ellipses, and a side-by-side complete-mire comparison.
The all-detected and complete-only views plot the detected mire centrelines.
Placido obtains its centreline from the midpoint of paired inner and outer
white-band boundaries. SmartKC obtains its centreline from ordered localized
radial-response points. Smooth covariance ellipses appear only as dotted
overlays in the dedicated covariance and comparison views.
The complete-only, covariance, and comparison tabs include numerical tables.
The editable selected range remains available in the selected-mire CSV exports.
It restricts the common-complete comparison and summaries but does not restrict
detection or the complete-only tabs. The two all-detected tabs omit on-screen
tables to give the mire review more space; their full numerical tables remain
in the CSV exports. The two common-mire covariance views and the comparison tab
use the same square X/Y limits.
Solid traces
pass that method's completeness gate; dotted traces are diagnostic. Summary
CSV rows use complete mires only. No complete mires means a zero count and
undefined summary values, not a fallback to incomplete mires. CSV tables
retain the completeness decision, observed coverage and maximum angular gap.

All detected means all mire candidates returned within the configured search
field, not every physical mire visible anywhere in the photograph. Placido uses a
fixed 700-pixel requested search radius (subject to its detector bounds),
independent of FIRST_MIRE and LAST_MIRE. This replaces the earlier 420-pixel
radius used for mires 1–6 and can change detection results. Classical SmartKC
uses its existing crop and default maximum of 22 mire indices, raised if the
requested upper index is greater. Neither method guarantees absolute physical
mire identity when an inner band is missing.

The paired viewer and its primary tables express both methods in hub-relative
source-image pixels, x right and y up. This permits a like-for-like image-shape
comparison. SmartKC's original nominal sensor-plane millimetre values remain
in its detailed CSV columns for traceability and are explicitly uncalibrated;
they are not calibrated corneal dimensions. Axis angles are degrees and describe
covariance image axes. Ellipse irregularity preserves the existing explicit-
ellipse residual formula.

The manuscript Phase 1 historical Placido steps remain illustrations of the
development branch. They are not dependencies of the dedicated hub detector.
SmartKC Phase 1 Step 07 now uses the completeness-gate figure rather than
labelling the selected-mire image as proof of completeness.
