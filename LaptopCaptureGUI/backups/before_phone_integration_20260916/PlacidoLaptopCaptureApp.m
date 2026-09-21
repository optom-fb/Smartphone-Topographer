function PlacidoLaptopCaptureApp
% PlacidoLaptopCaptureApp  Preview and save snapshots from a USB camera.
%
% This laptop capture system previews/saves camera images and provides manual,
% safety-first control of the separate Arduino-driven white Placido LEDs. It
% does not control the camera's built-in IR LEDs. It can also save one guided
% pilot video to disk using a conservative IR-only / rings-on / block-switching
% sequence.
%
% Run this file from MATLAB while the external camera is connected:
%   PlacidoLaptopCaptureApp
%
% Saved PNG files go below Data/Images. The default folder is
% Data/Images/Test/Camera, which keeps captured test images separate from the
% example images already used by the analysis workflow.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
imageRoot = fullfile(projectRoot, 'Data', 'Images');
videoRoot = fullfile(projectRoot, 'Data', 'Videos');

if exist('videoinput', 'file') ~= 2
    error(['The Image Acquisition Toolbox Support Package for OS Generic ' ...
        'Video Interface is required before this app can use a USB camera.']);
end

state = struct();
state.ProjectRoot = projectRoot;
state.ImageRoot = imageRoot;
state.VideoRoot = videoRoot;
state.Video = [];
state.PreviewImage = [];
state.AlignmentIrisGuide = [];
state.AlignmentCrosshairHorizontal = [];
state.AlignmentCrosshairVertical = [];
state.VideoResolution = [];
state.ShowAlignmentGuide = true;
state.IrisGuideDiameterPixels = 360;
state.DeviceInfo = struct([]);
state.Arduino = [];
state.IsGuidedRecording = false;
% Keep full-frame acquisition as the safe default. FrameGrabInterval controls
% triggered data logging, not the rate shown by MATLAB's preview window.
state.PreviewFrameGrabInterval = 1;
% Rendering a full 1920-by-1080 RGB image in a uiaxes is substantially more
% expensive than acquiring or writing it. Limit graphics updates, especially
% during disk recording, but always keep every acquired camera frame for AVI.
state.LivePreviewDisplayPeriodSeconds = 1 / 15;
state.RecordingPreviewDisplayPeriodSeconds = 1 / 8;
state.PreviewDisplayClock = [];
state.LastPreviewDisplayTimeSeconds = -Inf;
state.GuidedIrOnlySeconds = 3;
state.GuidedSolidPlacidoSeconds = 5;
state.GuidedBlinkHalfBlockSeconds = 0.5;
state.GuidedBlinkBlockCount = 5;
state.GuidedSequenceSeconds = state.GuidedIrOnlySeconds + ...
    state.GuidedSolidPlacidoSeconds + ...
    2 * state.GuidedBlinkHalfBlockSeconds * state.GuidedBlinkBlockCount;
state.RecordingClock = [];
state.RecordingEvents = struct('Event', {}, 'PlannedTimeSeconds', {}, ...
    'ActualTimeSeconds', {}, 'ArduinoCommand', {}, 'WallClockTime', {});
state.RecordingStartTime = [];

appFigure = uifigure( ...
    'Name', 'Placido Laptop Camera - Preview and Snapshots', ...
    'Position', [100 60 1450 900], ...
    'Color', [0.97 0.97 0.97], ...
    'CloseRequestFcn', @onCloseRequest);
% Start maximised so the camera controls are not cut off on the laptop screen.
appFigure.WindowState = 'maximized';

mainLayout = uigridlayout(appFigure, [1 2]);
mainLayout.ColumnWidth = {'1x', 365};
mainLayout.RowHeight = {'1x'};
mainLayout.Padding = [14 14 14 14];
mainLayout.ColumnSpacing = 14;

previewPanel = uipanel(mainLayout, 'Title', 'Live camera preview');
previewPanel.FontWeight = 'bold';
previewAxes = uiaxes(previewPanel);
previewAxes.Units = 'normalized';
previewAxes.Position = [0.015 0.015 0.97 0.96];
previewAxes.XTick = [];
previewAxes.YTick = [];
previewAxes.Box = 'on';
title(previewAxes, 'Press "Start camera + Arduino" to begin alignment');

controlPanel = uipanel(mainLayout, 'Title', 'Camera controls');
controlPanel.FontWeight = 'bold';
controlLayout = uigridlayout(controlPanel, [30 1]);
controlLayout.RowHeight = {22, 28, 22, 28, 24, 22, 32, 8, 22, 28, ...
    22, 28, 8, 32, 32, 32, 32, 32, 32, 10, 22, 28, 30, 30, 30, ...
    30, 'fit', 48, 'fit', '1x'};
controlLayout.Padding = [13 13 13 13];
controlLayout.RowSpacing = 4;

cameraLabel = uilabel(controlLayout, 'Text', 'Camera');
cameraLabel.FontWeight = 'bold';
cameraDropDown = uidropdown(controlLayout, ...
    'Items', {'Checking camera list...'}, ...
    'Enable', 'off', ...
    'ValueChangedFcn', @onCameraChanged);

formatLabel = uilabel(controlLayout, 'Text', 'Capture format');
formatLabel.FontWeight = 'bold';
formatDropDown = uidropdown(controlLayout, ...
    'Items', {'Waiting for camera selection...'}, ...
    'Enable', 'off');

alignmentGuideCheckBox = uicheckbox(controlLayout, ...
    'Text', 'Show iris-centre alignment guide', ...
    'Value', true, ...
    'ValueChangedFcn', @onAlignmentGuideVisibilityChanged);
alignmentGuideCheckBox.FontWeight = 'bold';
alignmentGuideCheckBox.Tooltip = ['A visual positioning aid only. It does not ' ...
    'measure the pupil or prevent recording.'];

irisGuideSizeLabel = uilabel(controlLayout, ...
    'Text', 'Approximate iris-guide diameter: 360 px');

irisGuideSizeSlider = uislider(controlLayout, ...
    'Limits', [220 600], ...
    'Value', state.IrisGuideDiameterPixels, ...
    'MajorTicks', [220 300 380 460 540 600], ...
    'ValueChangingFcn', @onIrisGuideSizeChanging, ...
    'ValueChangedFcn', @onIrisGuideSizeChanged);
irisGuideSizeSlider.Tooltip = ['Adjust this yellow circle to roughly match the ' ...
    'visible iris while the eye is centred.'];

spacer1 = uilabel(controlLayout, 'Text', ''); %#ok<NASGU>

folderLabel = uilabel(controlLayout, ...
    'Text', 'Image folder below Data/Images');
folderLabel.FontWeight = 'bold';
folderField = uieditfield(controlLayout, 'text', 'Value', 'Test/Camera');
folderField.Tooltip = 'Example: Test/Camera or SPDA/KCN';

nameLabel = uilabel(controlLayout, 'Text', 'Filename beginning');
nameLabel.FontWeight = 'bold';
nameField = uieditfield(controlLayout, 'text', 'Value', 'eye');
nameField.Tooltip = 'A date-and-time suffix is added automatically.';

spacer2 = uilabel(controlLayout, 'Text', ''); %#ok<NASGU>

startButton = uibutton(controlLayout, 'push', ...
    'Text', 'Start camera + Arduino', ...
    'ButtonPushedFcn', @onStartSystem, ...
    'Enable', 'off');
startButton.FontWeight = 'bold';
startButton.Tooltip = ['Starts the selected camera preview, then connects to ' ...
    'the selected Arduino and turns the white Placido light ON for alignment.'];

stopButton = uibutton(controlLayout, 'push', ...
    'Text', 'Stop preview', ...
    'ButtonPushedFcn', @onStopPreview, ...
    'Enable', 'off');

snapshotButton = uibutton(controlLayout, 'push', ...
    'Text', 'Save PNG snapshot', ...
    'ButtonPushedFcn', @onSaveSnapshot, ...
    'Enable', 'off');
snapshotButton.FontWeight = 'bold';

recordVideoButton = uibutton(controlLayout, 'push', ...
    'Text', 'Record guided 13 s video', ...
    'ButtonPushedFcn', @onRecordGuidedVideo, ...
    'Enable', 'off');
recordVideoButton.FontWeight = 'bold';
recordVideoButton.Tooltip = ['Turns the alignment light OFF, then records 3 s ' ...
    'IR-only, 5 s solid Placido, and five 0.5 s OFF/ON blocks.'];

showSettingsButton = uibutton(controlLayout, 'push', ...
    'Text', 'Show camera settings', ...
    'ButtonPushedFcn', @onShowCameraSettings, ...
    'Enable', 'off');

refreshButton = uibutton(controlLayout, 'push', ...
    'Text', 'Refresh camera list', ...
    'ButtonPushedFcn', @onRefreshCameraList);

spacer3 = uilabel(controlLayout, 'Text', ''); %#ok<NASGU>

arduinoLabel = uilabel(controlLayout, ...
    'Text', 'Arduino port (white Placido LEDs)');
arduinoLabel.FontWeight = 'bold';
arduinoPortDropDown = uidropdown(controlLayout, ...
    'Items', {'Checking serial ports...'}, ...
    'Enable', 'off');
arduinoPortDropDown.Tooltip = ['The Arduino is usually the USB serial port, ' ...
    'not a Bluetooth COM port.'];

refreshArduinoButton = uibutton(controlLayout, 'push', ...
    'Text', 'Refresh Arduino ports', ...
    'ButtonPushedFcn', @onRefreshArduinoPorts);

connectArduinoButton = uibutton(controlLayout, 'push', ...
    'Text', 'Connect Arduino', ...
    'ButtonPushedFcn', @onConnectArduino, ...
    'Enable', 'off');

lightOnButton = uibutton(controlLayout, 'push', ...
    'Text', 'White Placido light ON (15 s)', ...
    'ButtonPushedFcn', @onLightOn, ...
    'Enable', 'off');
lightOnButton.FontWeight = 'bold';

lightOffButton = uibutton(controlLayout, 'push', ...
    'Text', 'White Placido light OFF', ...
    'ButtonPushedFcn', @onLightOff, ...
    'Enable', 'off');
lightOffButton.FontWeight = 'bold';

arduinoStatusLabel = uilabel(controlLayout, ...
    'Text', 'Checking for an available Arduino serial port...', ...
    'WordWrap', 'on', ...
    'VerticalAlignment', 'top', ...
    'FontColor', [0.15 0.15 0.15]);

uilabel(controlLayout, ...
    'Text', ['Safety: this controls only the external white Placido LEDs. ' ...
    'It cannot switch the camera''s built-in IR LEDs. The light is sent OFF ' ...
    'when this app closes.'], ...
    'WordWrap', 'on', ...
    'VerticalAlignment', 'top', ...
    'FontAngle', 'italic', ...
    'FontColor', [0.45 0.12 0.05]);

statusLabel = uilabel(controlLayout, ...
    'Text', 'Checking for Windows video cameras...', ...
    'WordWrap', 'on', ...
    'VerticalAlignment', 'top', ...
    'FontColor', [0.15 0.15 0.15]);

uilabel(controlLayout, ...
    'Text', ['Pilot-video stage: use the guided recording only under your ' ...
    'approved laboratory protocol. It is not yet a validated measurement.'], ...
    'WordWrap', 'on', ...
    'VerticalAlignment', 'bottom', ...
    'FontAngle', 'italic', ...
    'FontColor', [0.35 0.20 0.05]);

% Display the controls before Windows performs its sometimes slow UVC-device
% enumeration. The controls remain disabled until a camera list is available.
drawnow;
refreshCameraList();
refreshArduinoPorts();

    function refreshArduinoPorts()
        if hasActiveArduino()
            return
        end

        try
            ports = string(serialportlist("available"));
        catch ME
            arduinoPortDropDown.Items = {'Could not list serial ports'};
            arduinoPortDropDown.Enable = 'off';
            connectArduinoButton.Enable = 'off';
            refreshArduinoButton.Enable = 'on';
            setArduinoStatus(sprintf('Could not list serial ports: %s', ME.message), 'error');
            return
        end

        if isempty(ports)
            arduinoPortDropDown.Items = {'No available serial port found'};
            arduinoPortDropDown.Enable = 'off';
            connectArduinoButton.Enable = 'off';
            refreshArduinoButton.Enable = 'on';
            setArduinoStatus('No available Arduino serial port found. Check the USB cable and close other serial apps.', 'error');
            return
        end

        arduinoPortDropDown.Items = cellstr(ports);
        arduinoPortDropDown.Value = arduinoPortDropDown.Items{1};
        expectedPort = "COM7";
        if any(ports == expectedPort)
            arduinoPortDropDown.Value = char(expectedPort);
        end
        arduinoPortDropDown.Enable = 'on';
        refreshArduinoButton.Enable = 'on';
        connectArduinoButton.Enable = 'on';
        lightOnButton.Enable = 'off';
        lightOffButton.Enable = 'off';
        setArduinoStatus(['Select the Arduino USB serial port and connect. ' ...
            'For this laptop, COM7 is the currently detected USB serial device.'], 'normal');
    end

    function onRefreshArduinoPorts(~, ~)
        if hasActiveArduino()
            uialert(appFigure, ...
                'Disconnect the Arduino before refreshing the port list.', ...
                'Arduino is connected');
            return
        end

        arduinoPortDropDown.Enable = 'off';
        connectArduinoButton.Enable = 'off';
        refreshArduinoButton.Enable = 'off';
        setArduinoStatus('Refreshing available serial ports...', 'normal');
        drawnow;
        refreshArduinoPorts();
    end

    function onConnectArduino(~, ~)
        if hasActiveArduino()
            releaseArduino();
            refreshArduinoPorts();
            setArduinoStatus('Arduino disconnected. White Placido light was sent OFF.', 'normal');
            return
        end

        selectedPort = string(arduinoPortDropDown.Value);
        if strlength(selectedPort) == 0 || startsWith(selectedPort, "No ") || ...
                startsWith(selectedPort, "Could not")
            uialert(appFigure, 'Choose an available serial port first.', 'Arduino port needed');
            return
        end

        connectArduinoButton.Enable = 'off';
        refreshArduinoButton.Enable = 'off';
        arduinoPortDropDown.Enable = 'off';
        setArduinoStatus(sprintf('Connecting to Arduino on %s at 9600 baud...', selectedPort), 'normal');
        drawnow;

        try
            % Opening a USB Arduino can reset it. The current firmware starts
            % in OFF state; after the reset delay we send a second explicit OFF.
            state.Arduino = serialport(selectedPort, 9600, 'Timeout', 1);
            pause(2.2);
            sendArduinoCode('O', 'OFF (connection safety)');

            connectArduinoButton.Text = 'Disconnect Arduino';
            connectArduinoButton.Enable = 'on';
            lightOnButton.Enable = 'on';
            lightOffButton.Enable = 'on';
            updateGuidedVideoButton();
            setArduinoStatus(sprintf(['Arduino connected on %s. The white Placido light is OFF. ' ...
                'Use ON only when you are ready to observe the setup.'], selectedPort), 'success');
        catch ME
            releaseArduino();
            arduinoPortDropDown.Enable = 'on';
            refreshArduinoButton.Enable = 'on';
            connectArduinoButton.Text = 'Connect Arduino';
            connectArduinoButton.Enable = 'on';
            setArduinoStatus(sprintf('Could not connect to %s: %s', selectedPort, ME.message), 'error');
            uialert(appFigure, ME.message, 'Could not connect to Arduino');
        end
    end

    function onLightOn(~, ~)
        try
            sendArduinoCode('A', 'ON');
            setArduinoStatus('White Placido light is ON. Use OFF before changing the physical setup.', 'success');
        catch ME
            setArduinoStatus(sprintf('Could not turn the white Placido light on: %s', ME.message), 'error');
            uialert(appFigure, ME.message, 'Arduino command failed');
        end
    end

    function onLightOff(~, ~)
        try
            sendArduinoCode('O', 'OFF');
            setArduinoStatus('White Placido light is OFF.', 'normal');
        catch ME
            setArduinoStatus(sprintf('Could not turn the white Placido light off: %s', ME.message), 'error');
            uialert(appFigure, ME.message, 'Arduino command failed');
        end
    end

    function sendArduinoCode(code, ~)
        if ~hasActiveArduino()
            error('Arduino is not connected. Connect it before sending a light command.');
        end
        write(state.Arduino, char(code), 'char');
    end

    function tf = hasActiveArduino()
        tf = ~isempty(state.Arduino) && isvalid(state.Arduino);
    end

    function releaseArduino()
        if ~hasActiveArduino()
            state.Arduino = [];
            return
        end

        try
            % Safety first: never deliberately leave the external light on
            % when MATLAB releases the serial connection.
            write(state.Arduino, 'O', 'char');
            pause(0.05);
        catch
            % Continue cleanup if the cable was disconnected unexpectedly.
        end

        try
            delete(state.Arduino);
        catch
        end
        state.Arduino = [];
        connectArduinoButton.Text = 'Connect Arduino';
        lightOnButton.Enable = 'off';
        lightOffButton.Enable = 'off';
        recordVideoButton.Enable = 'off';
    end

    function setArduinoStatus(message, kind)
        arduinoStatusLabel.Text = message;
        switch kind
            case 'success'
                arduinoStatusLabel.FontColor = [0.00 0.45 0.13];
            case 'error'
                arduinoStatusLabel.FontColor = [0.75 0.05 0.05];
            otherwise
                arduinoStatusLabel.FontColor = [0.15 0.15 0.15];
        end
    end

    function refreshCameraList()
        try
            cameraInfo = imaqhwinfo('winvideo');
            state.DeviceInfo = cameraInfo.DeviceInfo;
        catch ME
            setStatus(sprintf('Could not list Windows cameras: %s', ME.message), 'error');
            cameraDropDown.Items = {'Camera list unavailable'};
            formatDropDown.Items = {'Camera list unavailable'};
            startButton.Enable = 'off';
            return
        end

        if isempty(state.DeviceInfo)
            setStatus('No Windows video camera was found. Check the USB connection.', 'error');
            cameraDropDown.Items = {'No camera found'};
            formatDropDown.Items = {'No camera found'};
            startButton.Enable = 'off';
            return
        end

        deviceIDs = [state.DeviceInfo.DeviceID];
        deviceItems = cell(1, numel(deviceIDs));
        for deviceNumber = 1:numel(deviceIDs)
            deviceItems{deviceNumber} = sprintf('Device %d - %s', ...
                deviceIDs(deviceNumber), state.DeviceInfo(deviceNumber).DeviceName);
        end
        cameraDropDown.Items = deviceItems;
        cameraDropDown.ItemsData = deviceIDs;
        cameraDropDown.Value = deviceIDs(1);
        updateFormatsForSelectedCamera();
        cameraDropDown.Enable = 'on';
        formatDropDown.Enable = 'on';
        startButton.Enable = 'on';
        setStatus(['Camera found. Choose a format, then start the preview. ' ...
            'The first UVC connection can take 5-15 seconds.'], 'normal');
    end

    function onCameraChanged(~, ~)
        if hasActiveVideo()
            uialert(appFigure, ...
                'Stop the current preview before changing the camera.', ...
                'Camera is in use');
            return
        end
        updateFormatsForSelectedCamera();
    end

    function onRefreshCameraList(~, ~)
        if hasActiveVideo()
            uialert(appFigure, ...
                'Stop the current preview before refreshing the camera list.', ...
                'Camera is in use');
            return
        end

        cameraDropDown.Enable = 'off';
        formatDropDown.Enable = 'off';
        startButton.Enable = 'off';
        refreshButton.Enable = 'off';
        setStatus('Resetting MATLAB camera discovery and refreshing the Windows camera list...', 'normal');
        drawnow;

        try
            % imaqhwinfo caches the adapter's device list. Resetting while
            % preview is stopped forces MATLAB to reload the Windows UVC list.
            imaqreset;
            state.Video = [];
            state.PreviewImage = [];
            state.AlignmentIrisGuide = [];
            state.AlignmentCrosshairHorizontal = [];
            state.AlignmentCrosshairVertical = [];
            state.VideoResolution = [];
            pause(0.5);
            refreshCameraList();
        catch ME
            setStatus(sprintf('Could not refresh the camera list: %s', ME.message), 'error');
            cameraDropDown.Items = {'Camera refresh failed'};
            formatDropDown.Items = {'Camera refresh failed'};
            startButton.Enable = 'off';
        end
        refreshButton.Enable = 'on';
    end

    function updateFormatsForSelectedCamera()
        deviceIndex = getSelectedDeviceIndex();
        formats = string(state.DeviceInfo(deviceIndex).SupportedFormats);
        formatDropDown.Items = formats;

        preferredFormat = "MJPG_1920x1080";
        if any(formats == preferredFormat)
            formatDropDown.Value = preferredFormat;
        else
            formatDropDown.Value = formats(1);
        end
    end

    function onStartPreview(~, ~)
        if hasActiveVideo()
            return
        end

        setStatus(['Connecting to the selected camera. Windows may take ' ...
            '5-15 seconds to start the first 1080p UVC stream...'], 'normal');
        appFigure.Pointer = 'watch';
        drawnow;

        try
            deviceID = cameraDropDown.Value;
            videoFormat = char(formatDropDown.Value);
            state.Video = videoinput('winvideo', deviceID, videoFormat);
            state.Video.ReturnedColorSpace = 'rgb';
            % FrameGrabInterval only applies when triggered logging begins.
            % Keep the default of one so every source frame is available to a
            % future disk recording; MATLAB's preview window manages its own
            % display-frame skipping when necessary.
            state.Video.FrameGrabInterval = state.PreviewFrameGrabInterval;
            state.VideoResolution = state.Video.VideoResolution;

            cla(previewAxes);
            previewAxes.Visible = 'on';
            previewAxes.XTick = [];
            previewAxes.YTick = [];
            previewAxes.YDir = 'reverse';
            title(previewAxes, sprintf('%s  |  %s  |  yellow iris guide + green centre crosshair', ...
                state.DeviceInfo(getSelectedDeviceIndex()).DeviceName, videoFormat));

            % Put MATLAB's preview directly in this app so the alignment guide
            % is fixed to image pixels rather than to the laptop screen size.
            % The raw camera stream is not resized or modified before saving.
            imageHeight = state.VideoResolution(2);
            imageWidth = state.VideoResolution(1);
            imageBands = state.Video.NumberOfBands;
            blankFrame = zeros(imageHeight, imageWidth, imageBands, 'uint8');
            state.PreviewImage = image(previewAxes, blankFrame);
            state.PreviewImage.XData = [1 imageWidth];
            state.PreviewImage.YData = [1 imageHeight];
            configurePreviewAxes(imageWidth, imageHeight);
            createAlignmentGuide();
            resetPreviewDisplayClock();
            % A custom callback keeps MATLAB's preview CData, coordinate
            % limits, and the image-coordinate overlay synchronised. Without
            % it, some UVC drivers reset XData/YData and show a small image in
            % one corner of the otherwise full-size viewer.
            setappdata(state.PreviewImage, 'UpdatePreviewWindowFcn', @onPreviewFrame);
            preview(state.Video, state.PreviewImage);

            startButton.Enable = 'off';
            stopButton.Enable = 'on';
            snapshotButton.Enable = 'on';
            updateGuidedVideoButton();
            showSettingsButton.Enable = 'on';
            refreshButton.Enable = 'off';
            cameraDropDown.Enable = 'off';
            formatDropDown.Enable = 'off';
            setStatus(['Live preview is ready. Align the iris to the yellow ' ...
                'circle and the pupil towards the green crosshair before recording.'], 'normal');
        catch ME
            releaseCamera();
            setStatus(sprintf('Could not start preview: %s', ME.message), 'error');
            uialert(appFigure, ME.message, 'Could not start camera');
        end

        appFigure.Pointer = 'arrow';
    end

    function onStartSystem(~, ~)
        % Normal workflow: one button starts the camera and connects the
        % Arduino. The separate Arduino button remains available only for a
        % later reconnect or a manual safety/light check.
        if ~hasActiveVideo()
            onStartPreview([], []);
        end
        if ~hasActiveVideo()
            return
        end

        if ~hasActiveArduino()
            refreshArduinoPorts();
            selectedArduinoPort = string(arduinoPortDropDown.Value);
            % COM7 is the known Arduino port on this laptop. Do not silently
            % open an arbitrary Bluetooth/serial device if COM7 is absent.
            if strcmpi(arduinoPortDropDown.Enable, 'on') && selectedArduinoPort == "COM7"
                onConnectArduino([], []);
            else
                setStatus(['Camera preview is running, but the Arduino was not ' ...
                    'connected. Check that it appears as COM7, then use the ' ...
                    'manual Arduino controls if its port has changed.'], 'error');
            end
        end

        if hasActiveVideo() && hasActiveArduino()
            try
                sendArduinoCode('A', 'alignment light ON');
                setArduinoStatus(['White Placido light is ON for mire focus and ' ...
                    'alignment. It has a 15-second independent safety cutoff.'], 'success');
                setStatus(['White Placido light is ON. Centre the iris, focus the ' ...
                    'mires, then select Record guided 13 s video.'], 'success');
            catch ME
                setStatus(sprintf(['Camera preview is ready, but the alignment ' ...
                    'light could not be turned on: %s'], ME.message), 'error');
                uialert(appFigure, ME.message, 'Arduino command failed');
            end
        end
    end

    function onAlignmentGuideVisibilityChanged(~, ~)
        state.ShowAlignmentGuide = alignmentGuideCheckBox.Value;
        updateAlignmentGuide();
    end

    function onIrisGuideSizeChanging(~, event)
        updateIrisGuideSize(event.Value);
    end

    function onIrisGuideSizeChanged(~, event)
        updateIrisGuideSize(event.Value);
    end

    function updateIrisGuideSize(diameterPixels)
        state.IrisGuideDiameterPixels = round(diameterPixels);
        irisGuideSizeLabel.Text = sprintf('Approximate iris-guide diameter: %d px', ...
            state.IrisGuideDiameterPixels);
        updateAlignmentGuide();
    end

    function createAlignmentGuide()
        if isempty(state.VideoResolution) || numel(state.VideoResolution) ~= 2
            return
        end

        imageWidth = state.VideoResolution(1);
        imageHeight = state.VideoResolution(2);
        centreX = (imageWidth + 1) / 2;
        centreY = (imageHeight + 1) / 2;
        radius = state.IrisGuideDiameterPixels / 2;
        crosshairHalfLength = max(28, round(radius * 0.22));

        hold(previewAxes, 'on');
        state.AlignmentIrisGuide = rectangle(previewAxes, ...
            'Position', [centreX - radius, centreY - radius, 2 * radius, 2 * radius], ...
            'Curvature', [1 1], ...
            'EdgeColor', [1.00 0.84 0.00], ...
            'LineWidth', 1.8, ...
            'HitTest', 'off');
        state.AlignmentCrosshairHorizontal = line(previewAxes, ...
            [centreX - crosshairHalfLength, centreX + crosshairHalfLength], ...
            [centreY, centreY], ...
            'Color', [0.10 0.95 0.25], 'LineWidth', 1.8, 'HitTest', 'off');
        state.AlignmentCrosshairVertical = line(previewAxes, ...
            [centreX, centreX], ...
            [centreY - crosshairHalfLength, centreY + crosshairHalfLength], ...
            'Color', [0.10 0.95 0.25], 'LineWidth', 1.8, 'HitTest', 'off');
        hold(previewAxes, 'off');
        updateAlignmentGuide();
    end

    function updateAlignmentGuide()
        if isempty(state.AlignmentIrisGuide) || ...
                isempty(state.AlignmentCrosshairHorizontal) || ...
                isempty(state.AlignmentCrosshairVertical) || ...
                ~isgraphics(state.AlignmentIrisGuide) || ...
                ~isgraphics(state.AlignmentCrosshairHorizontal) || ...
                ~isgraphics(state.AlignmentCrosshairVertical) || ...
                isempty(state.VideoResolution)
            return
        end

        imageWidth = state.VideoResolution(1);
        imageHeight = state.VideoResolution(2);
        centreX = (imageWidth + 1) / 2;
        centreY = (imageHeight + 1) / 2;
        radius = state.IrisGuideDiameterPixels / 2;
        crosshairHalfLength = max(28, round(radius * 0.22));
        if state.ShowAlignmentGuide
            visibleState = 'on';
        else
            visibleState = 'off';
        end

        state.AlignmentIrisGuide.Position = [centreX - radius, centreY - radius, ...
            2 * radius, 2 * radius];
        state.AlignmentCrosshairHorizontal.XData = ...
            [centreX - crosshairHalfLength, centreX + crosshairHalfLength];
        state.AlignmentCrosshairHorizontal.YData = [centreY, centreY];
        state.AlignmentCrosshairVertical.XData = [centreX, centreX];
        state.AlignmentCrosshairVertical.YData = ...
            [centreY - crosshairHalfLength, centreY + crosshairHalfLength];
        state.AlignmentIrisGuide.Visible = visibleState;
        state.AlignmentCrosshairHorizontal.Visible = visibleState;
        state.AlignmentCrosshairVertical.Visible = visibleState;
    end

    function configurePreviewAxes(imageWidth, imageHeight)
        previewAxes.XLim = [0.5 imageWidth + 0.5];
        previewAxes.YLim = [0.5 imageHeight + 0.5];
        previewAxes.XLimMode = 'manual';
        previewAxes.YLimMode = 'manual';
        previewAxes.DataAspectRatio = [1 1 1];
        previewAxes.DataAspectRatioMode = 'manual';
        previewAxes.PlotBoxAspectRatioMode = 'auto';
        previewAxes.Color = [0 0 0];
    end

    function onPreviewFrame(~, event, imageHandle)
        % The preview callback must set CData itself when it is registered.
        % It also prevents the adaptor from shrinking the display coordinates.
        if ~isgraphics(imageHandle)
            return
        end

        frameData = event.Data;
        imageHeight = size(frameData, 1);
        imageWidth = size(frameData, 2);
        resolutionChanged = isempty(state.VideoResolution) || ...
            ~isequal(state.VideoResolution, [imageWidth imageHeight]);

        % Keep the live view responsive while a 1080p AVI is being written.
        % This affects only graphics refreshes: the camera still acquires, and
        % DiskLogger still writes, every source frame (FrameGrabInterval = 1).
        if isempty(state.PreviewDisplayClock)
            resetPreviewDisplayClock();
        end
        if state.IsGuidedRecording
            displayPeriodSeconds = state.RecordingPreviewDisplayPeriodSeconds;
        else
            displayPeriodSeconds = state.LivePreviewDisplayPeriodSeconds;
        end
        currentDisplayTime = toc(state.PreviewDisplayClock);
        if ~resolutionChanged && ...
                currentDisplayTime - state.LastPreviewDisplayTimeSeconds < displayPeriodSeconds
            return
        end

        imageHandle.CData = frameData;
        imageHandle.XData = [1 imageWidth];
        imageHandle.YData = [1 imageHeight];
        state.LastPreviewDisplayTimeSeconds = currentDisplayTime;

        if resolutionChanged
            state.VideoResolution = [imageWidth imageHeight];
            configurePreviewAxes(imageWidth, imageHeight);
            updateAlignmentGuide();
        end
    end

    function resetPreviewDisplayClock()
        state.PreviewDisplayClock = tic;
        state.LastPreviewDisplayTimeSeconds = -Inf;
    end

    function onShowCameraSettings(~, ~)
        if ~hasActiveVideo()
            uialert(appFigure, 'Start the live preview before viewing camera settings.', ...
                'Preview is not running');
            return
        end

        try
            cameraSource = getselectedsource(state.Video);
            settings = get(cameraSource);
            propertyNames = fieldnames(settings);
            settingValues = cell(numel(propertyNames), 1);

            for propertyIndex = 1:numel(propertyNames)
                settingValues{propertyIndex} = formatSettingValue( ...
                    settings.(propertyNames{propertyIndex}));
            end

            settingsTableData = [propertyNames, settingValues];
            settingsFigure = uifigure( ...
                'Name', 'Camera settings - read only', ...
                'Position', [220 180 720 560]);
            settingsLayout = uigridlayout(settingsFigure, [2 1]);
            settingsLayout.RowHeight = {42, '1x'};
            settingsLayout.Padding = [12 12 12 12];

            uilabel(settingsLayout, ...
                'Text', ['These are the settings reported by the USB camera driver. ' ...
                'This window does not change any setting.'], ...
                'WordWrap', 'on', ...
                'VerticalAlignment', 'center');
            uitable(settingsLayout, ...
                'Data', settingsTableData, ...
                'ColumnName', {'Setting', 'Current value'}, ...
                'ColumnWidth', {260, 400}, ...
                'RowName', []);
        catch ME
            setStatus(sprintf('Could not read camera settings: %s', ME.message), 'error');
            uialert(appFigure, ME.message, 'Could not read camera settings');
        end
    end

    function onStopPreview(~, ~)
        releaseCamera();
        startButton.Enable = 'on';
        stopButton.Enable = 'off';
        snapshotButton.Enable = 'off';
        recordVideoButton.Enable = 'off';
        showSettingsButton.Enable = 'off';
        refreshButton.Enable = 'on';
        cameraDropDown.Enable = 'on';
        formatDropDown.Enable = 'on';
        cla(previewAxes);
        previewAxes.Visible = 'on';
        previewAxes.XTick = [];
        previewAxes.YTick = [];
        title(previewAxes, 'Preview stopped');
        setStatus('Preview stopped. The camera has been released.', 'normal');
    end

    function onSaveSnapshot(~, ~)
        if ~hasActiveVideo()
            uialert(appFigure, 'Start the live preview before saving a snapshot.', ...
                'Preview is not running');
            return
        end

        try
            [saveFolder, baseName] = getSaveLocation();
            if ~isfolder(saveFolder)
                mkdir(saveFolder);
            end

            setStatus('Capturing and saving PNG snapshot...', 'normal');
            drawnow;
            frame = getsnapshot(state.Video);
            timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
            outputFile = fullfile(saveFolder, sprintf('%s_%s.png', baseName, timestamp));
            imwrite(frame, outputFile);

            relativeFile = erase(string(outputFile), string(state.ProjectRoot) + filesep);
            setStatus(sprintf('Saved: %s', relativeFile), 'success');
        catch ME
            setStatus(sprintf('Could not save snapshot: %s', ME.message), 'error');
            uialert(appFigure, ME.message, 'Snapshot was not saved');
        end
    end

    function onRecordGuidedVideo(~, ~)
        if state.IsGuidedRecording
            return
        end
        if ~hasActiveVideo()
            uialert(appFigure, 'Start the live preview before recording a video.', ...
                'Preview is not running');
            return
        end
        if ~hasActiveArduino()
            uialert(appFigure, ['Connect the Arduino before recording. The guided ' ...
                'sequence must be able to turn the white Placido light OFF.'], ...
                'Arduino is not connected');
            return
        end

        try
            [saveFolder, baseName] = getVideoSaveLocation();
            if ~isfolder(saveFolder)
                mkdir(saveFolder);
            end
            timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
            videoFile = fullfile(saveFolder, sprintf('%s_%s.avi', baseName, timestamp));
            metadataFile = fullfile(saveFolder, ...
                sprintf('%s_%s_timing.csv', baseName, timestamp));

            state.IsGuidedRecording = true;
            setGuidedRecordingControls(true);
            setStatus(sprintf(['Turning the alignment light OFF, then preparing a ' ...
                '%.0f-second video: %.0f s IR only, %.0f s solid Placido, then ' ...
                '%d 0.5 s OFF/ON blocks...'], state.GuidedSequenceSeconds, ...
                state.GuidedIrOnlySeconds, state.GuidedSolidPlacidoSeconds, ...
                state.GuidedBlinkBlockCount), 'normal');
            drawnow;

            % Keep the in-app preview active during disk logging. MATLAB can
            % skip *display* frames when needed, while the disk logger still
            % receives every acquired frame. This gives the operator a live
            % positioning view instead of a frozen window during the sequence.
            if ~strcmpi(state.Video.Previewing, 'on')
                resumeInAppPreview();
            end

            triggerconfig(state.Video, 'immediate');
            state.Video.FramesPerTrigger = Inf;
            state.Video.TriggerRepeat = 0;
            state.Video.FrameGrabInterval = 1;
            state.Video.LoggingMode = 'disk';
            state.Video.DiskLogger = VideoWriter(videoFile, 'Motion JPEG AVI');
            state.RecordingEvents = struct('Event', {}, 'PlannedTimeSeconds', {}, ...
                'ActualTimeSeconds', {}, 'ArduinoCommand', {}, 'WallClockTime', {});

            % The white alignment light is deliberately switched off before
            % starting the AVI so the entire recorded IR-only segment begins
            % with the external Placido illumination absent.
            sendArduinoCode('O', 'pre-recording alignment light OFF');
            pause(0.15);

            setStatus(['Recording now. The in-app preview stays live; it may ' ...
                'skip display frames while the full video is written to disk.'], 'normal');
            drawnow;
            start(state.Video);
            state.RecordingStartTime = datetime('now', ...
                'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
            state.RecordingClock = tic;
            recordGuidedStateEvent('record_start_ir_only', 0.0, 'O_pre_record');

            solidStart = state.GuidedIrOnlySeconds;
            blinkStart = solidStart + state.GuidedSolidPlacidoSeconds;
            waitForRecordingTime(solidStart);
            recordGuidedLightEvent('solid_placido_on', solidStart, 'A');

            waitForRecordingTime(blinkStart);
            fullBlinkBlockSeconds = 2 * state.GuidedBlinkHalfBlockSeconds;
            for blockNumber = 1:state.GuidedBlinkBlockCount
                blockStart = blinkStart + (blockNumber - 1) * fullBlinkBlockSeconds;
                waitForRecordingTime(blockStart);
                recordGuidedLightEvent(sprintf('block_%d_placido_off', blockNumber), ...
                    blockStart, 'O');
                waitForRecordingTime(blockStart + state.GuidedBlinkHalfBlockSeconds);
                recordGuidedLightEvent(sprintf('block_%d_placido_on', blockNumber), ...
                    blockStart + state.GuidedBlinkHalfBlockSeconds, 'A');
                waitForRecordingTime(blockStart + fullBlinkBlockSeconds);
            end

            waitForRecordingTime(state.GuidedSequenceSeconds);
            recordGuidedLightEvent('record_end_placido_off', ...
                state.GuidedSequenceSeconds, 'O');
            [framesAcquired, framesWritten] = stopDiskRecording();
            writeGuidedVideoMetadata(metadataFile, videoFile, framesAcquired, framesWritten);
            restartPreviewAfterRecording();
            state.IsGuidedRecording = false;
            setGuidedRecordingControls(false);

            relativeFile = erase(string(videoFile), string(state.ProjectRoot) + filesep);
            setStatus(sprintf(['Saved guided video: %s (%d frames; %d written). ' ...
                'The white Placido light is OFF.'], relativeFile, ...
                framesAcquired, framesWritten), 'success');
        catch ME
            % The firmware timeout is an additional safety layer, but always
            % attempt an explicit OFF command before cleaning up MATLAB state.
            try
                sendArduinoCode('O', 'recording error safety OFF');
            catch
            end
            try
                stopDiskRecording();
            catch
            end
            try
                restartPreviewAfterRecording();
            catch
            end
            state.IsGuidedRecording = false;
            setGuidedRecordingControls(false);
            setStatus(sprintf('Guided video was not completed: %s', ME.message), 'error');
            uialert(appFigure, ME.message, 'Guided video failed');
        end
    end

    function recordGuidedLightEvent(eventName, plannedTimeSeconds, code)
        sendArduinoCode(code, eventName);
        recordGuidedStateEvent(eventName, plannedTimeSeconds, code);
    end

    function recordGuidedStateEvent(eventName, plannedTimeSeconds, commandDescription)
        eventIndex = numel(state.RecordingEvents) + 1;
        state.RecordingEvents(eventIndex) = struct( ...
            'Event', char(eventName), ...
            'PlannedTimeSeconds', plannedTimeSeconds, ...
            'ActualTimeSeconds', toc(state.RecordingClock), ...
            'ArduinoCommand', char(commandDescription), ...
            'WallClockTime', char(datetime('now', ...
                'Format', 'yyyy-MM-dd HH:mm:ss.SSS')));
    end

    function waitForRecordingTime(targetTimeSeconds)
        remainingSeconds = targetTimeSeconds - toc(state.RecordingClock);
        if remainingSeconds > 0
            pause(remainingSeconds);
        end
    end

    function [framesAcquired, framesWritten] = stopDiskRecording()
        framesAcquired = 0;
        framesWritten = 0;
        if ~hasActiveVideo()
            return
        end

        if isrunning(state.Video)
            stop(state.Video);
        end
        framesAcquired = state.Video.FramesAcquired;
        framesWritten = state.Video.DiskLoggerFrameCount;

        % Disk writing can finish slightly after the camera stream stops. Do
        % not release the DiskLogger until it has caught up or 30 seconds pass.
        flushClock = tic;
        while framesWritten < framesAcquired && toc(flushClock) < 30
            pause(0.1);
            drawnow;
            framesWritten = state.Video.DiskLoggerFrameCount;
        end

        if framesWritten < framesAcquired
            error(['The camera acquired %d frames but only %d were written to disk. ' ...
                'Do not use this recording; check disk speed and free space.'], ...
                framesAcquired, framesWritten);
        end

        state.Video.DiskLogger = [];
        state.Video.LoggingMode = 'memory';
        state.Video.FramesPerTrigger = 10;
        state.Video.FrameGrabInterval = state.PreviewFrameGrabInterval;
    end

    function restartPreviewAfterRecording()
        if ~hasActiveVideo()
            return
        end
        if ~strcmpi(state.Video.Previewing, 'on')
            resumeInAppPreview();
        end
    end

    function resumeInAppPreview()
        if ~hasActiveVideo()
            return
        end
        if isempty(state.PreviewImage) || ~isgraphics(state.PreviewImage)
            error(['The in-app preview image is no longer available. Stop the ' ...
                'camera and start it again before recording.']);
        end
        setappdata(state.PreviewImage, 'UpdatePreviewWindowFcn', @onPreviewFrame);
        resetPreviewDisplayClock();
        preview(state.Video, state.PreviewImage);
    end

    function writeGuidedVideoMetadata(metadataFile, videoFile, framesAcquired, framesWritten)
        eventTable = struct2table(state.RecordingEvents);
        eventCount = height(eventTable);
        eventTable.RecordingStartTime = repmat( ...
            string(state.RecordingStartTime), eventCount, 1);
        eventTable.VideoFile = repmat(string(videoFile), eventCount, 1);
        eventTable.FramesAcquired = repmat(framesAcquired, eventCount, 1);
        eventTable.FramesWritten = repmat(framesWritten, eventCount, 1);
        writetable(eventTable, metadataFile);
    end

    function setGuidedRecordingControls(isRecording)
        if isRecording
            startButton.Enable = 'off';
            stopButton.Enable = 'off';
            snapshotButton.Enable = 'off';
            recordVideoButton.Enable = 'off';
            showSettingsButton.Enable = 'off';
            refreshButton.Enable = 'off';
            cameraDropDown.Enable = 'off';
            formatDropDown.Enable = 'off';
            folderField.Enable = 'off';
            nameField.Enable = 'off';
            arduinoPortDropDown.Enable = 'off';
            refreshArduinoButton.Enable = 'off';
            connectArduinoButton.Enable = 'off';
            lightOnButton.Enable = 'off';
            lightOffButton.Enable = 'off';
            return
        end

        folderField.Enable = 'on';
        nameField.Enable = 'on';
        if hasActiveVideo()
            startButton.Enable = 'off';
            stopButton.Enable = 'on';
            snapshotButton.Enable = 'on';
            showSettingsButton.Enable = 'on';
            refreshButton.Enable = 'off';
            cameraDropDown.Enable = 'off';
            formatDropDown.Enable = 'off';
        else
            startButton.Enable = 'on';
            stopButton.Enable = 'off';
            snapshotButton.Enable = 'off';
            showSettingsButton.Enable = 'off';
            refreshButton.Enable = 'on';
            cameraDropDown.Enable = 'on';
            formatDropDown.Enable = 'on';
        end

        if hasActiveArduino()
            arduinoPortDropDown.Enable = 'off';
            refreshArduinoButton.Enable = 'off';
            connectArduinoButton.Text = 'Disconnect Arduino';
            connectArduinoButton.Enable = 'on';
            lightOnButton.Enable = 'on';
            lightOffButton.Enable = 'on';
        else
            refreshArduinoPorts();
        end
        updateGuidedVideoButton();
    end

    function updateGuidedVideoButton()
        if state.IsGuidedRecording || ~hasActiveVideo() || ~hasActiveArduino()
            recordVideoButton.Enable = 'off';
        else
            recordVideoButton.Enable = 'on';
        end
    end

    function [saveFolder, baseName] = getVideoSaveLocation()
        [imageSaveFolder, baseName] = getSaveLocation();
        relativeFolder = erase(string(imageSaveFolder), string(state.ImageRoot));
        relativeFolder = strip(relativeFolder, 'left', filesep);
        saveFolder = fullfile(state.VideoRoot, char(relativeFolder));
    end

    function [saveFolder, baseName] = getSaveLocation()
        relativeFolder = strtrim(string(folderField.Value));
        if strlength(relativeFolder) == 0
            error('Enter an image folder, for example Test/Camera.');
        end

        relativeFolder = replace(relativeFolder, '/', filesep);
        if contains(relativeFolder, '..') || startsWith(relativeFolder, filesep) || ...
                contains(relativeFolder, ':')
            error('The image folder must be a relative folder below Data/Images.');
        end

        saveFolder = fullfile(state.ImageRoot, char(relativeFolder));
        rawBaseName = strtrim(string(nameField.Value));
        baseName = regexprep(rawBaseName, '[<>:"/\\|?*]', '_');
        baseName = regexprep(baseName, '\s+', '_');
        if strlength(baseName) == 0
            error('Enter a filename beginning, for example eye or participant01.');
        end
        baseName = char(baseName);
    end

    function deviceIndex = getSelectedDeviceIndex()
        selectedID = cameraDropDown.Value;
        deviceIndex = find([state.DeviceInfo.DeviceID] == selectedID, 1, 'first');
        if isempty(deviceIndex)
            error('The selected camera is no longer available. Restart the app.');
        end
    end

    function tf = hasActiveVideo()
        tf = ~isempty(state.Video) && isvalid(state.Video);
    end

    function releaseCamera()
        if ~hasActiveVideo()
            state.Video = [];
            state.PreviewImage = [];
            state.AlignmentIrisGuide = [];
            state.AlignmentCrosshairHorizontal = [];
            state.AlignmentCrosshairVertical = [];
            state.VideoResolution = [];
            state.PreviewDisplayClock = [];
            state.LastPreviewDisplayTimeSeconds = -Inf;
            return
        end

        try
            if strcmpi(state.Video.Previewing, 'on')
                stoppreview(state.Video);
            end
        catch
            % Continue cleanup even if the Windows driver has already stopped.
        end

        try
            if isrunning(state.Video)
                stop(state.Video);
            end
        catch
        end

        try
            delete(state.Video);
        catch
        end

        state.Video = [];
        state.PreviewImage = [];
        state.AlignmentIrisGuide = [];
        state.AlignmentCrosshairHorizontal = [];
        state.AlignmentCrosshairVertical = [];
        state.VideoResolution = [];
        state.PreviewDisplayClock = [];
        state.LastPreviewDisplayTimeSeconds = -Inf;
    end

    function onCloseRequest(~, ~)
        releaseCamera();
        releaseArduino();
        delete(appFigure);
    end

    function setStatus(message, kind)
        statusLabel.Text = message;
        switch kind
            case 'success'
                statusLabel.FontColor = [0.00 0.45 0.13];
            case 'error'
                statusLabel.FontColor = [0.75 0.05 0.05];
            otherwise
                statusLabel.FontColor = [0.15 0.15 0.15];
        end
    end

    function textValue = formatSettingValue(value)
        if ischar(value) || (isstring(value) && isscalar(value))
            textValue = char(string(value));
        elseif isnumeric(value) || islogical(value)
            if isscalar(value)
                textValue = num2str(value);
            else
                textValue = mat2str(value);
            end
        elseif iscell(value)
            textValue = sprintf('{%d values}', numel(value));
        else
            textValue = sprintf('<%s>', class(value));
        end
    end
end
