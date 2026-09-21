# MATLAB SmartKC and SmartKC++ research pipeline

This project processes smartphone Placido-reflection images through paired
MATLAB implementations of the SmartKC and SmartKC++ methods. It keeps the
step-by-step, reviewable folder flow used in the neighbouring `placido`
project, while leaving that project unchanged.

> **Research status:** the supplied camera/Placido values are public Microsoft
> reference values, not a calibration of this phone and attachment. Real-image
> curvature, power, and SimK outputs are therefore **uncalibrated research
> outputs**. They are not diagnoses and must not be used for clinical decisions.

## What is implemented

| Branch | Mire segmentation | Mire localization | Reconstruction |
|---|---|---|---|
| SmartKC baseline | Classical band-pass/adaptive segmentation | Radial ordering | Circular completion of each retained mire, then contiguous Arc-Step |
| SmartKC++ | Parity-validated conversion of the published U-Net, or an explicitly labelled robust classical fallback | Radial candidates plus graph connected-component correction | Arc-Step from the last available inner mire, then 2-D Zernike surface fitting |

The baseline is a method-faithful MATLAB translation of the [2021 SmartKC
release](https://github.com/microsoft/SmartKC-A-Smartphone-based-Corneal-Topographer/tree/d2bbe99db897034c6db881d635508d289fbb6b3d),
not a claim of bit-for-bit numerical equivalence with Python. The SmartKC++
branch follows the changes described in the [WACV 2025
paper](https://openaccess.thecvf.com/content/WACV2025/html/Ganatra_SmartKC_Improving_Performance_of_Smartphone-Based_Corneal_Topographers_WACV_2025_paper.html).

### Important U-Net status

The conversion tooling pins Microsoft's updated checkpoint at commit
`d9191fac74b0f4902cfe044f8686416b8b14fc1a`, verifies its SHA-256, builds the
native MATLAB network, and requires parity with a deterministic official
PyTorch fixture. Install the Git-ignored local model once with:

```matlab
addpath(fullfile(pwd, 'scripts'))
setup_smartkcpp_unet()
```

On the first computer, pass a Python 3 executable if the local conversion
environment does not exist. Normal Step-02 inference is Python-free after
setup. See [`models/README.md`](models/README.md) for Windows/macOS details.

If `models/smartkcpp_mire_unet.mat` is absent, invalid, or fails provenance
checks, SmartKC++ uses a robust classical mask and records:

```text
MethodRequested = smartkcpp-unet
MethodActual    = robust-classical-fallback
UsedFallback    = true
```

This makes the fallback auditable; its output must not be described as the
published U-Net result. Conversion parity establishes software equivalence for
the pinned fixture, not segmentation accuracy or clinical validity on this
phone. See the [workflow and methods guide](docs/WORKFLOW_AND_METHODS_GUIDE.md#step-02---paired-mire-segmentation).

## Quick start

Keep the MATLAB Current Folder at this project root.

The core project is path-portable across Windows, macOS, and Linux. It uses
`fullfile`, `filesep`, and project-relative discovery rather than drive-letter
paths. After cloning or switching computers, run the platform preflight before
processing data:

```matlab
run(fullfile('scripts', 'check_platform_compatibility.m'))
```

Use the `develop` branch for ongoing research changes. Treat `main` as the
stable reviewed branch and merge only after a validation milestone.

### Capture GUI

Run `RUN_CAPTURE_GUI.m` to open the project-local capture application. It can
preview and save lossless PNG frames from an external camera exposed through
a MATLAB Image Acquisition adaptor, record a guided 13-second external-camera
video with synchronized Arduino light commands, or import a transferred
smartphone image. Captures and matching audit CSV files are saved below
`Data/Captured/<PseudoId>/<YYYYMMDD>` and are intentionally Git-ignored.

The GUI includes a visual centring guide, immediate non-clinical focus and
saturation checks, optional Arduino light ON/OFF controls, and a button that
runs the saved image through S00--S07. The alignment guide and rapid checks do
not calibrate the device or validate a capture clinically. See the
[capture guide](CaptureGUI/README.md) before collecting data.

### One-image master runner

Open `RUN_IMAGE_MASTER.m`. For an image stored inside this project, build its
path from the script's `projectRoot` rather than pasting a Windows drive path:

```matlab
imagePath = fullfile(projectRoot, 'Data', 'your-folder', 'Image01.jpg');
```

For an image anywhere else, set `imagePath = ""` and use the file picker. This
is the recommended cross-platform choice when moving between computers. Then
click **Run**. The script runs
the complete paired pipeline, writes `Data/Output/<CaseId>`, and opens one
window with eight tabs: S00 input, S01 preprocessing, S02 segmentation, S03
mire labels, S04 SmartKC maps, S05 SmartKC++ maps, S06 final review, and the
optional S07 mire eigen-ratio diagnostic. Paths are handled with MATLAB
utilities, so the same script works on Windows, macOS, and Linux.

S01 also shows the optional Placido-style pupil review: the detected Placido
centre is red and the pupil-like circle is yellow. Its CSV distances are
camera-sensor-plane millimetres, not anatomical pupil millimetres. Because a
ring-on image can hide the true pupil boundary, this result is review-only and
never changes centring, segmentation, Arc-Step reconstruction, or maps.

S07 contains four inner review tabs matching the established Placido analysis
flow: complete-ring axes and tables; distortion, irregularity, harmonic RMS,
and eigen-ratio plots; incomplete-ring diagnostics; and the full quality gate.
S07 now focuses on the preferred SmartKC++ branch. Its displayed and exported
segmentation method states whether the official U-Net or the auditable
classical fallback actually supplied the mire edges.

The master runner keeps a diagnostic result even when input QC fails, but it
raises a warning and leaves the S01 evidence visible. Use the paused numbered
workflow when QC rejection must stop a formal batch.

### Recommended numbered workflow

Open `scripts/run_steps_with_review.m` and click **Run**. It executes Steps
00--07 in order and pauses after each stage for review. The stable numbered
flow enforces the Step-01 focus/saturation quality gate before segmentation.

The individual scripts and their outputs are listed in
[`scripts/README.md`](scripts/README.md).

### Interactive mire formation viewer

Run `OPEN_MIRE_CSV_VIEWER.m` to open the dependency-free local browser tool.
Load an `S03_skc_mires.csv` or `S03_skcpp_mires.csv` to see how its sampled
points form each Placido ring, filter rings, colour by mire/radius/score/width,
and inspect millimetre values by hovering or clicking. No file is uploaded.

New pipeline audit bundles also include
`S03_mire_viewer_metadata.json`. Load that file together with `S01_crop.png`
to place the millimetre mire samples over the processed image. The companion
pixel metadata is used only for display alignment; the scientific CSV remains
in camera-sensor-plane millimetres. See the
[viewer guide](tools/mire-csv-viewer/README.md).

The same tool includes a **Sphere image formation** mode for the completed
42--46 D validation series. It uses the tracked exact reflection truth and
rendered PNGs to show the Placido source ring, spherical corneal reflection,
camera ray, progressively formed mire points, and hover values.
An S03 CSV from one of those five fixtures can be transferred from the detected
viewer into a selected known-power comparison. Exact points and detected points
are overlaid, with raw and display-aligned per-ring radial differences kept
separate.

### One-call expert API

```matlab
imagePath = fullfile(pwd, 'Data', 'eye_20260814_104114_378.png');
result = runSmartKCPipeline(imagePath);
```

Omitting the output argument writes an audit bundle to
`Data/Output/<CaseId>`. To run without writing outputs:

```matlab
result = runSmartKCPipeline(imagePath, [], '');
```

The one-call API exposes `result.Preprocessing.Quality` but intentionally
remains callable for diagnostic work even when Step-01 QC would reject the
image. Use the numbered workflow for normal batch research processing.

The one image currently supplied under `Data` is useful for a **smoke test of
code flow only**. One image, with no annotation, calibration object, repeated
capture, or reference-topographer result, is not a validation dataset.

In the current smoke run, centring/segmentation/localization complete, but both
reconstructions are deliberately blocked because the public reference camera
profile maps no valid points inside the 4 mm fitting radius. The generated
review and summary are written locally under `Data/Output/<CaseId>` and are
intentionally not committed. This is a calibration failure, not a corneal
finding.

## Synthetic engineering dataset

Run:

```matlab
run(fullfile('scripts', 'generate_synthetic_dataset.m'))
run(fullfile('scripts', 'validate_synthetic_dataset.m'))
run(fullfile('scripts', 'evaluate_synthetic_segmentation.m'))
run(fullfile('scripts', 'generate_sphere_series.m'))
run(fullfile('scripts', 'validate_sphere_series.m'))
run(fullfile('scripts', 'run_sphere_accuracy_experiment.m'))
```

This creates ten deterministic cases: a 43 D sphere; low (1.0 D) and moderate
(2.5 D) WTR, ATR, and oblique regular astigmatism; and early, moderate, and
severe keratoconus-like surfaces under `Data/Synthetic`. All ten default images
now contain deliberately complete rings with zero synthetic glare and only
light noise/blur, so surface-shape testing is not confounded by missing arcs.
Broken arcs remain available as an explicit scenario override for separate
robustness tests. The severity labels
are engineering scenario names, not clinical diagnoses. The forward
model solves the Arc-Step reflection relation independently within each
meridian; it does not model full 3-D skew rays from azimuthal gradients in a
decentred cone. Read the [synthetic dataset
guide](docs/SYNTHETIC_DATASET_GUIDE.md) before interpreting results.

When `RUN_IMAGE_MASTER.m` receives one of the tracked synthetic PNGs, it now
recognizes the paired truth MAT automatically. It applies the matched effective
sensor scale and synthetic centre search and selects the robust-classical
SmartKC++ regression, which detects the complete rendered rings more reliably
than the real-image-trained U-Net. Real images continue to request the official
U-Net normally; the actual method remains visible in S02, S06, and S07.
The Command Window reports elapsed time for every major processing stage, and
the completed case folder includes `S00_stage_timings.csv` for performance
diagnosis without changing the numerical workflow.

The generated [manifest](Data/Synthetic/manifest.csv) is included. The
end-to-end validation summary is generated locally at
`Data/Output/Synthetic/S06_validation_summary.csv`. Normal and regular-astigmatism
cases serve as numerical regressions; cone-case base powers are nominal
references rather than post-cone ground-truth SimK.

The separate `Data/Synthetic/SphereSeries` fixture contains true 42--46 D
spheres. Its validation CSV distinguishes exact generator truth (0 D power
error and 0 D cylinder) from image-pipeline reconstruction error. Change the
`spherePowersD` vector at the top of `scripts/generate_sphere_series.m` to
create another requested series.

`run_sphere_accuracy_experiment.m` separates four error sources for the
requested spheres: exact continuous mire coordinates, an ideal noise-free 2x
render, the standard synthetic PNG, and a 0.5x render. Its local CSV under
`Data/Output/SphereAccuracyExperiment` shows whether error originates before
or after rasterization and image localization.

Before changing mire localization, run
`scripts/evaluate_sphere_localization_baseline.m`. It compares every labelled
SmartKC++ sphere point with the same exact physical mire and separates total
radial error from centre-compensated edge error. Detailed point, per-mire,
per-sphere, and K-relationship CSVs are written locally beneath
`Data/Output/SphereLocalizationBaseline`.

Each case includes an exact binary mire mask and a `uint8` physical mire-label
map. The evaluation script writes three-way SmartKC, robust-fallback, and
official-U-Net mask/localization metrics to
`Data/Output/Synthetic/S02_segmentation_metrics.csv`.

An experimental three-sample quadratic radial-peak refinement is available
through `cfg.localization.SubpixelMethod = "quadratic"`. It is deliberately
disabled by default. Run `scripts/compare_sphere_subpixel_localization.m` for
the 42--46 D sphere comparison and
`scripts/compare_synthetic_subpixel_regression.m` for the broader ten-case
gate. The corrected matched-3-mm-truth gate passes the sphere, all six regular-
astigmatism cases, and the observable early-cone stress case. Moderate and
severe cone mire-1 identity comparisons are explicitly not applicable because
the rendered first mire has no candidate coverage. Quadratic localization
remains opt-in pending device-anchored and real-image validation.

For regular astigmatism, run `scripts/run_exact_toric_experiment.m` before
interpreting a nominal K discrepancy as reconstruction error. It bypasses the
image stages and separately reports nominal apical powers, matched 3 mm
truth-surface SimK, and exact-mire Arc-Step/Zernike/SimK results.

## Folder guide

- `config` - the single settings registry, `smartKCConstants.m`.
- `CaptureGUI` - external-camera capture and smartphone-image import.
- `scripts` - auditable Steps 00--07, guided runner, tests, and simulation tools.
- `functions` - reusable preprocessing, detection, reconstruction, quality,
  simulation, I/O, utility, and visualisation functions.
- `tests` - MATLAB unit and integration tests.
- `Data` - source images plus generated `Derived`, `Output`, and `Synthetic`
  subfolders.
- `models` - Git-ignored converted U-Net and pinned upstream checkpoint cache.
- `tools/mire-csv-viewer` - local interactive CSV and image-overlay viewer.
  Its validated-sphere mode also shows the assumed camera projection centre,
  sensor plane, and truth/reconstructed/error axial or tangential power maps.
  Its real-eye observed-ray mode shows measured sensor points and assumed
  camera-ray directions while explicitly withholding an uncalibrated corneal
  reflection or power solution.
- `docs` - methods, constants, calibration, validation, development, and
  synthetic-data guides.

The concise [calibration requirements checklist](docs/CALIBRATION_REQUIREMENTS_CHECKLIST.md)
lists every measurement and record still needed for a device-specific profile.
The longer [calibration guide](docs/CALIBRATION_GUIDE.md) explains how to obtain
and verify them.

The anonymized source filename stem becomes a lower-case `CaseId` of at most
32 characters. For example, `C001.jpg` becomes `c001`. Duplicate or unsafe
CaseIDs are rejected before processing so outputs cannot be silently
overwritten.

Generated stage files go under `Data/Derived/<CaseId>` and final review bundles
under `Data/Output/<CaseId>`. Filenames use a fixed step prefix, such as
`S01_preprocess.mat`, `S01_pupil.csv`, `S03_skcpp_mires.csv`, and
`S06_review.png`.

`Data/Derived` and `Data/Output` are machine-local and Git-ignored because their
manifests can contain absolute paths. Regenerate them after changing operating
system, computer, or clone location; do not reuse a manifest generated at a
different absolute path. Source images and `Data/Synthetic` remain portable
tracked inputs.

## Requirements

Development and verification use MATLAB R2025b. The pipeline uses Image
Processing Toolbox, Deep Learning Toolbox, and signal/statistical
image-analysis functions. PyTorch is needed only in the isolated one-time
conversion environment, not for normal MATLAB inference. Run all available
tests with:

```matlab
run(fullfile('scripts', 'run_all_tests.m'))
```

## Documentation

- [Workflow and methods](docs/WORKFLOW_AND_METHODS_GUIDE.md)
- [Constants guide](docs/CONSTANTS_GUIDE.md)
- [Calibration guide](docs/CALIBRATION_GUIDE.md)
- [Synthetic dataset guide](docs/SYNTHETIC_DATASET_GUIDE.md)
- [Validation plan](docs/VALIDATION_PLAN.md)
- [Development plan and change log](docs/DEVELOPMENT_PLAN.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

The official upstream implementation is the [Microsoft SmartKC
repository](https://github.com/microsoft/SmartKC-A-Smartphone-based-Corneal-Topographer).
Its own disclaimer also limits the system to research and development use.
