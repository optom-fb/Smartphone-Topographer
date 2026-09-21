# Smartphone Topographer

Smartphone Topographer is a MATLAB research project for acquiring Placido
images and analysing them using two image-processing pathways:

- Placido mire detection
- Classical SmartKC mire detection

Both methods process the same image so their detected mires and calculated
image descriptors can be reviewed and compared.

## 1. Laptop acquisition GUI

Open MATLAB, set this project as the **Current Folder**, and run:

```matlab
run_LaptopCaptureGUI
```

Use the controls in the GUI to select an available acquisition source,
including a connected external camera or the CameraRecorder phone-app
pathway. Use the GUI to preview and acquire the Placido image, then save or
transfer the image into the project's `Data` folder.

The acquisition GUI and image-processing pipeline are run separately.

## 2. Image-processing pipeline

Open `run_ImagePipeline.m` and edit the settings under **USER SETTINGS**:

```matlab
INPUT_IMAGE_NAME = 'trial1.jpg';
FIRST_MIRE = 1;
LAST_MIRE = 15;
```

`INPUT_IMAGE_NAME` must match an image in the `Data` folder. Set it to an
empty value to select an image using the file picker:

```matlab
INPUT_IMAGE_NAME = '';
```

`FIRST_MIRE` and `LAST_MIRE` define the mire range included in the final
comparison. They do not restrict the initial detection of all available
mires.

Run the pipeline using:

```matlab
run_ImagePipeline
```

The pipeline processes the image using the Placido and classical SmartKC
methods, identifies complete mires for each method, and uses the common
complete mire IDs within the selected range for the final comparison.

## Results

Each run creates a timestamped folder inside `Output` containing:

- `Placido_Output` - Placido processing results
- `SmartKC_Output` - classical SmartKC processing results
- `Analysis` - final tables, figures, and comparison results

To reopen the most recent saved results without repeating the analysis, run:

```matlab
VIEW_LATEST_RESULTS
```

> **Research use only.** The supplied measurements are uncalibrated image
> descriptors and are not intended for clinical diagnosis.
