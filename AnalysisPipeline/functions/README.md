# Active functions

The scripts and `runSmartKCPipeline.m` add these folders to the MATLAB path
automatically.

- `preprocessing` - decode an image, estimate the Placido centre, produce the
  review-only pupil circle, crop, flat-field normalize, and calculate input QC.
- `detection` - classical and validated U-Net segmentation, radial candidate
  extraction, SmartKC++ graph relabelling, and mire-by-angle matrices.
- `geometry` - convert measured Placido boundaries into reflective midpoints.
- `reconstruction` - SmartKC circular completion, paired Arc-Step variants,
  robust 2-D Zernike fitting, and curvature-map generation.
- `quality` - SimK-style research metrics, auditable coverage/convergence
  gates, and the optional mire eigen-ratio image-shape diagnostic.
- `simulation` - deterministic forward rendering, exact raster mask/label
  truth, dataset generation, and segmentation/localization metrics.
- `io` - input discovery, provenance manifests, and final audit bundles.
- `visualisation` - paired review figures and the S00--S07 tabbed viewer.
- `utility` - project initialization and folder helpers.
- `capture` - camera discovery, safe naming, capture metadata, and immediate
  non-clinical image-quality checks used by the independent capture GUI, plus
  guided-video pupil/ring candidate-frame extraction.

## Main data contracts

`preprocessPlacidoImage` returns a `pre` structure containing the original and
cropped coordinates, normalized image, detected centre, QC values, and source
provenance. Its `Pupil` field is a separate cautious review result and never
replaces the centre used by reconstruction. `pupilForCsv` exports its spatial
values only as explicitly named camera-sensor-plane millimetres; internal pixel
coordinates remain in the MAT structure.

Segmentation functions return a structure with `Mask`, `Response`,
`MethodRequested`, `MethodActual`, `ModelFile`, `ModelValidated`, and
`UsedFallback`. The U-Net path additionally preserves its zero-based 19-class
label map, pinned commit/hash, crop rectangle, and model-format version.
Preserve those fields so a classical fallback can never be mistaken for
validated U-Net inference.

`extractMireCandidates` returns one table row per radial peak. Important fields
include `AngleIndex`, `ProvisionalMire`, `MireIndex`, `RadiusPx`, `Score`,
`ComponentId`, `IsValid`, and `RejectionReason`. `correctMireLabelsGraph`
updates the SmartKC++ identity and audit fields; it does not alter the SmartKC
baseline table.

Those `Px` fields are internal image-processing coordinates retained in MAT
files. `mirePointsForCsv` converts exported spatial columns to explicitly named
camera-sensor-plane millimetres (`SensorXmm`, `SensorYmm`, `SensorRadiusMm`,
and `SensorWidthMm`) and records the coordinate frame and calibration status.
It names the image-ray angle (`ImageRayAngleDegCW`) separately from the
physical sensor-plane angle (`SensorAngleDegCCW`).
Sensor-plane millimetres are not corneal-surface millimetres.

`deriveCaseId` converts the short anonymized source stem into a safe,
cross-platform CaseID and rejects reserved or overlong names. `smartKCPaths`
is the single naming registry for all `S00`--`S07` manifests and per-case
artifacts. Output-producing code should not construct these names independently.

`calculateMireEigenRatio` runs after localization for the configured S07 branch,
which defaults to SmartKC++ only. Its spatial
columns are camera-sensor-plane millimetres and its minor/major covariance
ratio is dimensionless. Only traces passing the configured coverage, maximum-
gap, and point-count gate enter the primary mean. Incomplete traces are retained
as diagnostic rows and must not be interpreted as corneal power or a validated
keratoconus index.

`populateEigenRatioReview` presents the complete Placido-style review as four
inner S07 tabs: axes/tables, four complete-ring metrics, incomplete diagnostics,
and the quality gate. Each view states the actual SmartKC++ segmentation method
so the official U-Net and fallback cannot be confused.

`arcStepReconstruct` accepts only `"smartkc"` or `"smartkcpp"` and returns
the reconstructed point table plus per-meridian status. `fitZernikeSurface`
then produces sag, tangential-power, and axial-power grids. Both branches use
the same surface fitter so the comparison isolates the upstream method changes.

## U-Net model contract

`segmentMiresSmartKCPlus` looks for
`models/smartkcpp_mire_unet.mat`. The MAT file must contain a native `dlnetwork`
and metadata produced by `scripts/setup_smartkcpp_unet.m`. The loader requires
the pinned Microsoft commit/checkpoint SHA-256 and successful official-PyTorch
parity. Arbitrary `DAGNetwork`, `SeriesNetwork`, or `dlnetwork` variables are
not accepted as the published SmartKC++ model.

`predictSmartKCPPUNet` reproduces the official 500-to-512 Pillow resize,
ImageNet normalization, 19-class argmax, and nearest-neighbour restoration.
`buildSmartKCPPUNet` maps the converted PyTorch tensors into the native MATLAB
graph. Conversion and parity helpers live under `tools/smartkcpp_unet`.

## Adding functions

Keep reusable code in the folder that describes its responsibility, retain
physical units in names (`Mm`, `Px`, `D`, `Deg`), and return status/provenance
rather than hiding a fallback. Add or update tests and record method-affecting
changes in `../docs/DEVELOPMENT_PLAN.md`.
