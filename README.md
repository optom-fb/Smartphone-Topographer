# Smartphone Topographer

Smartphone Topographer is a MATLAB research project for analysing reflected
Placido mires and testing a laptop-based image-acquisition interface. The
analysis runs two methods on the same source image:

- the developed Placido mire-detection pathway; and
- the Baseline (SmartKC) mire-detection pathway.

The two methods detect and classify mires independently. Their common
complete mire IDs are then used to compare image-domain geometric
descriptors. The acquisition GUI is a separate development component and is
not required to run the supplied trial images.

## Requirements

The analysis was developed and tested in MATLAB R2025b. MATLAB R2022b or
later is recommended, together with:

- Image Processing Toolbox;
- Signal Processing Toolbox; and
- Statistics and Machine Learning Toolbox.

External-camera acquisition additionally requires Image Acquisition Toolbox
and the MATLAB Support Package for OS Generic Video Interface. Smartphone
acquisition requires the CameraRecorder Android app and Android Debug Bridge
(ADB) USB access. The GUI can be opened for review without the acquisition
hardware, although capture controls require the corresponding devices.

After downloading or cloning the repository, open its top-level folder in
MATLAB and set it as the **Current Folder**.

## 1. Run the image-processing pipeline

### Supplied trial images

The `Data` folder contains five example images:

- `trial.jpg` — a permitted real-eye example used by the default run;
- `test1.png`;
- `test2.png`;
- `test3.png`; and
- `test4.png`.

These images allow the complete analysis to be run without acquisition
hardware. The four `test*.png` files are grayscale mire test patterns.
These images demonstrate software operation; they are not calibration
standards or labelled clinical ground truth.

### Select the image and mire range

Open `run_ImagePipeline.m` and edit the three values under **USER SETTINGS**:

```matlab
INPUT_IMAGE_NAME = 'trial.jpg';
FIRST_MIRE = 1;
LAST_MIRE = 15;
```

`INPUT_IMAGE_NAME` must match an image stored directly in `Data`. Change it
to `test1.png`, `test2.png`, `test3.png`, or `test4.png` to analyse a
different supplied image.

To select an image interactively, including an image saved by the acquisition
GUI, use an empty image name:

```matlab
INPUT_IMAGE_NAME = '';
```

`FIRST_MIRE` and `LAST_MIRE` define the inclusive range considered in the
final comparison. They do not restrict the initial detection of all available
mires.

### Start the analysis

Run the file from the MATLAB Editor or enter:

```matlab
run_ImagePipeline
```

The pipeline will:

1. process the same image with the developed Placido and Baseline (SmartKC)
   pathways;
2. detect all available mire candidates with each method;
3. classify complete and incomplete mires independently;
4. select the mire IDs that are complete in both methods and fall within the
   requested range; and
5. calculate covariance eigen ratio, cross-mire centre dispersion,
   ellipse-based radial irregularity, and principal image-axis orientation.

The full-screen MATLAB viewer contains seven tabs: all detected mires,
complete mires, and covariance ellipses for each method, followed by the
common-complete-mire comparison.

### Find the saved results

Each run creates `Output/<image>_<timestamp>/` with three folders:

- `Placido_Output` contains the write-up-aligned Placido processing stages;
- `SmartKC_Output` contains the write-up-aligned Baseline (SmartKC) stages;
  and
- `Analysis` contains the figures, CSV tables, summaries, and saved MATLAB
  results used in the final comparison.

To reopen the most recent saved results without repeating the processing,
run:

```matlab
VIEW_LATEST_RESULTS
```

## 2. Open the laptop acquisition GUI

The acquisition GUI can operate with an external USB camera or the
CameraRecorder smartphone pathway. It acquires images and videos but does not
automatically start the image-processing pipeline.

Launch it from the project root:

```matlab
run_LaptopCaptureGUI
```

Use the **Acquisition source** menu at the top of the control panel to switch
between the two camera pathways. The optional command
`run_LaptopCaptureGUI('phone')` opens the same GUI with smartphone mode
selected initially.

### External USB camera mode

1. Select **External USB camera (IR)**, the camera, and the capture format.
2. Enter an optional output subfolder and filename beginning.
3. Connect the Arduino if the external white Placido illumination is being
   used.
4. Select **Start camera + Arduino** to begin the live alignment preview.
5. Use the iris-centre guide for positioning, then save a PNG snapshot or run
   the guided 13-second video sequence when permitted by the study protocol.
6. Select **Stop preview** when acquisition is complete.

External-camera files are saved below `Data/GUI Data/EXT_Camera` in uniquely
named run folders.

### Smartphone CameraRecorder mode

1. Open CameraRecorder in **NORMAL** mode on the unlocked Android phone and
   connect it to the laptop by USB.
2. Select **Smartphone CameraRecorder (USB)** in the acquisition-source menu.
3. Select **Connect smartphone (status only)**. The phone preview remains on
   the phone; the laptop panel reports connection and transfer status.
4. Connect the Arduino if the guided illumination sequence is required.
5. Start the guided recording. When recording finishes, the GUI transfers the
   video and timing files while retaining the originals on the phone.

Smartphone files are saved below `Data/GUI Data/Smart_Phone`. See
[`MobileApp/README.md`](MobileApp/README.md) for the phone component,
communication method, and current limitations.

### Analyse an acquired image

The acquisition and analysis stages are intentionally separate. After
reviewing a GUI capture, either copy the chosen still image into `Data` and
set `INPUT_IMAGE_NAME`, or set `INPUT_IMAGE_NAME = ''` and browse to the
saved image. Then run `run_ImagePipeline` normally.

## Project folders

| Folder | Contents |
|---|---|
| `Data` | Supplied trial images and locally acquired data |
| `AnalysisPipeline` | Developed Placido and Baseline (SmartKC) processing code |
| `LaptopCaptureGUI` | Laptop acquisition interface and support files |
| `MobileApp` | CameraRecorder documentation |
| `Output` | Timestamped pipeline results |

Third-party attribution and licence information are recorded in
[`AnalysisPipeline/THIRD_PARTY_NOTICES.md`](AnalysisPipeline/THIRD_PARTY_NOTICES.md).

> **Research use only.** The supplied measurements are uncalibrated
> image-domain descriptors and are not intended for clinical diagnosis.
