function PlacidoLaptopCaptureApp(initialSource)
% PlacidoLaptopCaptureApp  External USB or CameraRecorder phone acquisition.
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
% All new captures go below Data/GUI Data/Smart_Phone or EXT_Camera.
% The default optional subfolder is Test; every recording has a unique run
% folder containing its video and associated acquisition records.

if nargin == 0, initialSource = 'external'; end
initialSource = validatestring(initialSource, {'external', 'phone'});
projectRoot = fileparts(fileparts(mfilename('fullpath')));
imageRoot = fullfile(projectRoot, 'Data', 'GUI Data');
videoRoot = imageRoot;

state = struct();
state.Phone = [];
state.PhoneConnected = false;
state.PhonePreviewMessage = [];
state.CancelRequested = false;
state.CloseRequested = false;
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
state.ExternalPreviewPaused = false;
state.PreviewTitleBeforeRecording = '';
% Keep full-frame acquisition as the safe default. FrameGrabInterval controls
% triggered data logging, not the rate shown by MATLAB's preview window.
state.PreviewFrameGrabInterval = 1;
% Rendering a full 1920-by-1080 RGB image in a uiaxes is substantially more
% expensive than acquiring or writing it. Limit graphics updates, especially
% during disk recording, but always keep every acquired camera frame for AVI.
state.LivePreviewDisplayPeriodSeconds = 1 / 15;
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
    'Tag', 'PlacidoLaptopCapture', ...
    'Name', 'Placido Acquisition - External USB or Smartphone', ...
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
previewPanel.AutoResizeChildren = 'off';
previewPanel.SizeChangedFcn = @onPreviewPanelSizeChanged;
previewAxes = uiaxes(previewPanel);
previewAxes.Units = 'normalized';
previewAxes.Position = [0.015 0.015 0.97 0.96];
previewAxes.XTick = [];
previewAxes.YTick = [];
previewAxes.Box = 'on';
title(previewAxes, 'Press "Start camera + Arduino" to begin alignment');

controlPanel = uipanel(mainLayout, 'Title', 'Camera controls');
controlPanel.FontWeight = 'bold';
controlLayout = uigridlayout(controlPanel, [32 1]);
controlLayout.Scrollable = 'on';
controlLayout.RowHeight = {22, 28, 22, 28, 22, 28, 24, 22, 32, 8, 22, 28, ...
    22, 28, 8, 32, 32, 32, 32, 32, 32, 10, 22, 28, 30, 30, 30, ...
    30, 'fit', 48, 'fit', '1x'};
controlLayout.Padding = [13 13 13 13];
controlLayout.RowSpacing = 4;

uilabel(controlLayout, 'Text', 'Acquisition source', 'FontWeight', 'bold');
sourceDropDown = uidropdown(controlLayout, ...
    'Tag', 'AcquisitionSource', ...
    'Items', {'External USB camera (IR)', 'Smartphone CameraRecorder (USB)'}, ...
    'ItemsData', {'external', 'phone'}, 'Value', initialSource, ...
    'ValueChangedFcn', @onSourceChanged);

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
    'Text', 'Output below GUI Data/EXT_Camera');
folderLabel.FontWeight = 'bold';
folderField = uieditfield(controlLayout, 'text', 'Value', 'Test');
folderField.Tooltip = 'Optional subfolder below the selected camera folder, e.g. Test or SPDA/KCN.';

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
if isPhoneSelected()
    onSourceChanged([], []);
else
    refreshCameraList();
end
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
            resetPreviewAxesGeometry();
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
        if isPhoneSelected()
            connectPhone();
            return
        end
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

    function resetPreviewAxesGeometry()
        % CLA can restore the default pixel-sized UIAxes rectangle in some
        % MATLAB releases. Reapply the panel-filling normalized position.
        previewAxes.Units = 'normalized';
        previewAxes.Position = [0.015 0.015 0.97 0.96];
    end

    function onPreviewFrame(~, event, imageHandle)
        % The preview callback must set CData itself when it is registered.
        % It also prevents the adaptor from shrinking the display coordinates.
        if ~isgraphics(imageHandle) || state.ExternalPreviewPaused
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
        displayPeriodSeconds = state.LivePreviewDisplayPeriodSeconds;
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
        if isPhoneSelected()
            try
                info = state.Phone.status();
                uialert(appFigure, jsonencode(info, 'PrettyPrint', true), ...
                    'Phone settings (read only)', 'Icon', 'info');
            catch ME
                uialert(appFigure, ME.message, 'Phone status unavailable');
            end
            return
        end
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
        if state.IsGuidedRecording
            state.CancelRequested = true;
            return
        end
        if isPhoneSelected()
            try
                if ~isempty(state.Phone), state.Phone.disconnect(); end
                state.PhoneConnected = false;
                configurePhoneControls();
                setStatus('Laptop disconnected. CameraRecorder preview remains on the phone.', 'normal');
            catch ME
                uialert(appFigure, ME.message, 'Phone disconnect failed');
            end
            return
        end
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
        resetPreviewAxesGeometry();
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
            saveFolder = fullfile(saveFolder, sprintf('%s_snapshot_%s', baseName, timestamp));
            if isfolder(saveFolder), error('Placido:Exists', 'Capture folder already exists.'); end
            mkdir(saveFolder);
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
        if isPhoneSelected()
            recordPhoneVideo();
            return
        end
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

        videoFile = '';
        framesAcquired = NaN;
        framesWritten = NaN;
        state.RecordingEvents = struct('Event', {}, 'PlannedTimeSeconds', {}, ...
            'ActualTimeSeconds', {}, 'ArduinoCommand', {}, 'WallClockTime', {});
        state.RecordingStartTime = [];
        try
            [saveFolder, baseName] = getVideoSaveLocation();
            if ~isfolder(saveFolder)
                mkdir(saveFolder);
            end
            timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
            saveFolder = fullfile(saveFolder, sprintf('%s_ext_%s', baseName, timestamp));
            if isfolder(saveFolder), error('Placido:Exists', 'Capture folder already exists.'); end
            mkdir(saveFolder);
            videoFile = fullfile(saveFolder, sprintf('%s_%s.avi', baseName, timestamp));
            metadataFile = fullfile(saveFolder, ...
                sprintf('%s_%s_timing.csv', baseName, timestamp));

            state.IsGuidedRecording = true;
            state.CancelRequested = false;
            setGuidedRecordingControls(true);
            setStatus(sprintf(['Turning the alignment light OFF, then preparing a ' ...
                '%.0f-second video: %.0f s IR only, %.0f s solid Placido, then ' ...
                '%d 0.5 s OFF/ON blocks...'], state.GuidedSequenceSeconds, ...
                state.GuidedIrOnlySeconds, state.GuidedSolidPlacidoSeconds, ...
                state.GuidedBlinkBlockCount), 'normal');
            drawnow;

            % Pause graphics before timed acquisition; retain the last
            % alignment image and acquire native frames directly to disk.
            state.PreviewTitleBeforeRecording = previewAxes.Title.String;
            state.ExternalPreviewPaused = true;
            if strcmpi(state.Video.Previewing, 'on')
                stoppreview(state.Video);
            end
            title(previewAxes, 'Preview paused during recording - last alignment frame');

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

            setStatus(['Recording now. Preview is paused; native-resolution ' ...
                'video is written to disk.'], 'normal');
            drawnow;
            start(state.Video);
            state.RecordingStartTime = datetime('now', ...
                'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
            state.RecordingClock = tic;
            recordGuidedStateEvent('record_start_ir_only', 0.0, 'O_pre_record');

            runGuidedPlan();
            [framesAcquired, framesWritten] = stopDiskRecording();
            writeGuidedVideoMetadata(metadataFile, videoFile, framesAcquired, framesWritten);
            writeExternalSession(videoFile, true, '', framesAcquired, framesWritten);
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
            warning('Placido:ExternalIncomplete', '%s', ME.message);
            try
                sendArduinoCode('O', 'recording error safety OFF');
            catch
            end
            try
                [framesAcquired, framesWritten] = stopDiskRecording();
            catch
            end
            try
                if ~isempty(videoFile)
                    if ~isempty(state.RecordingEvents)
                        [runFolder, runName] = fileparts(videoFile);
                        writeGuidedVideoMetadata(fullfile(runFolder, ...
                            [runName '_partial_timing.csv']), videoFile, framesAcquired, framesWritten);
                    end
                    writeExternalSession(videoFile, false, ME.message, framesAcquired, framesWritten);
                end
            catch logError
                warning('Placido:FailureLog', '%s', logError.message);
            end
            try
                restartPreviewAfterRecording();
            catch
            end
            state.IsGuidedRecording = false;
            setGuidedRecordingControls(false);
            setStatus(sprintf('Guided video was not completed: %s', ME.message), 'error');
            if ~state.CloseRequested
                uialert(appFigure, ME.message, 'Guided video failed');
            end
        end
        if state.CloseRequested, onCloseRequest([], []); end
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
        while toc(state.RecordingClock) < targetTimeSeconds
            if state.CancelRequested
                error('Placido:Cancelled', 'Recording cancelled by operator.');
            end
            pause(min(0.02, max(0, targetTimeSeconds - toc(state.RecordingClock))));
        end
        if state.CancelRequested, error('Placido:Cancelled', 'Recording cancelled by operator.'); end
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
        state.ExternalPreviewPaused = false;
        if isgraphics(previewAxes) && ~isempty(state.PreviewTitleBeforeRecording)
            title(previewAxes, state.PreviewTitleBeforeRecording);
        end
        state.PreviewTitleBeforeRecording = '';
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

    function writeExternalSession(videoFile, completed, failure, acquired, written)
        manifest = struct('CameraBackend', 'External_USB', 'Completed', completed, ...
            'Failure', failure, 'CreatedUTC', PlacidoPhoneClient.utcNow(), ...
            'VideoFile', videoFile, 'FramesAcquired', acquired, 'FramesWritten', written, ...
            'NominalProtocolSeconds', state.GuidedSequenceSeconds, ...
            'PhysicalIlluminationValidated', false, 'VideoTimeAlignmentValidated', false, ...
            'TimingOrigin', 'Host clock established after MATLAB camera start returned', ...
            'CameraDevice', state.DeviceInfo(getSelectedDeviceIndex()).DeviceName, ...
            'CaptureFormat', char(formatDropDown.Value), 'AVIPlaybackFrameRate', 30, ...
            'ArduinoPort', char(state.Arduino.Port), 'ArduinoBaudRate', state.Arduino.BaudRate, ...
            'PreviewDuringRecording', 'Paused; last alignment frame displayed', ...
            'GUI_SHA256', PlacidoPhoneClient.fileHash([mfilename('fullpath') '.m']), ...
            'CaptureLocation_SHA256', PlacidoPhoneClient.fileHash(which('placidoCaptureLocation')), ...
            'ProtocolPlan_SHA256', PlacidoPhoneClient.fileHash(which('placidoGuidedPlan')));
        if isfile(videoFile), manifest.VideoSHA256 = PlacidoPhoneClient.fileHash(videoFile); end
        % Avoid driver property queries in end/error cleanup: a stalled driver
        % must not prevent the GUI from releasing the serial connection.
        manifest.DriverSettingsStatus = ...
            'Not collected automatically. Inspect read-only settings before recording.';
        encodedManifest = jsonencode(manifest, 'PrettyPrint', true);
        fid = fopen(fullfile(fileparts(videoFile), 'external_session.json'), 'w');
        if fid < 0, error('Placido:Manifest', 'Cannot write external session manifest.'); end
        fileCleanup = onCleanup(@() fclose(fid));
        fprintf(fid, '%s\n', encodedManifest);
        clear fileCleanup
    end

    function setGuidedRecordingControls(isRecording)
        if isRecording, sourceDropDown.Enable = 'off'; else, sourceDropDown.Enable = 'on'; end
        if isRecording
            startButton.Enable = 'off';
            stopButton.Enable = 'on';
            stopButton.Text = 'Cancel recording / LEDs OFF';
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
        stopButton.Text = 'Stop preview';
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
        if isPhoneSelected(), configurePhoneControls(); end
    end

    function updateGuidedVideoButton()
        cameraReady = hasActiveVideo() || (isPhoneSelected() && state.PhoneConnected);
        if isPhoneSelected() && ~isempty(state.Phone) && state.Phone.OwnsRecording
            cameraReady = false;
        end
        if state.IsGuidedRecording || ~cameraReady || ~hasActiveArduino()
            recordVideoButton.Enable = 'off';
        else
            recordVideoButton.Enable = 'on';
        end
    end

    function [saveFolder, baseName] = getVideoSaveLocation()
        [saveFolder, baseName] = getSaveLocation();
    end

    function [saveFolder, baseName] = getSaveLocation()
        backend = 'external';
        if isPhoneSelected(), backend = 'phone'; end
        [saveFolder, baseName] = placidoCaptureLocation(state.ProjectRoot, ...
            backend, folderField.Value, nameField.Value);
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
        if state.IsGuidedRecording
            state.CancelRequested = true;
            state.CloseRequested = true;
            % Interrupt the protocol first; its catch block saves partial logs.
            try
                sendArduinoCode('O', 'close requested');
            catch
            end
            return
        end
        releaseCamera();
        releaseArduino();
        try
            if ~isempty(state.Phone), state.Phone.disconnect(); end
        catch ME
            state.CloseRequested = false;
            if state.Phone.OwnsRecording
                uialert(appFigure, ['Could not confirm phone STOP. ' ...
                    'Check CameraRecorder and stop recording manually if needed. ' ME.message], ...
                    'Phone requires attention');
                return
            end
            warning('Placido:Disconnect', 'Could not remove phone USB mapping: %s', ME.message);
        end
        delete(appFigure);
    end

    function tf = isPhoneSelected()
        tf = strcmp(sourceDropDown.Value, 'phone');
    end

    function onSourceChanged(~, ~)
        releaseCamera();
        clearPhonePreviewMessage();
        % Release illumination when changing acquisition hardware.
        releaseArduino();
        try
            if ~isempty(state.Phone), state.Phone.disconnect(); end
            state.PhoneConnected = false;
        catch ME
            sourceDropDown.Value = 'phone';
            uialert(appFigure, ME.message, 'Stop the phone before switching cameras');
            return
        end
        alignmentGuideCheckBox.Enable = 'on';
        irisGuideSizeSlider.Enable = 'on';
        stopButton.Text = 'Stop preview';
        startButton.Text = 'Start camera + Arduino';
        startButton.Tooltip = 'Start external camera and Arduino alignment illumination.';
        cla(previewAxes);
        resetPreviewAxesGeometry();
        if isPhoneSelected()
            configurePhoneControls();
            previewAxes.Visible = 'off';
            state.PhonePreviewMessage = uilabel(previewPanel, ...
                'Text', sprintf(['Smartphone CameraRecorder\n\nPhone preview remains on the phone screen.\n' ...
                'A saved frame will appear here after recording and verified transfer.']), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
                'WordWrap', 'on', 'FontSize', 16, 'FontWeight', 'bold');
            onPreviewPanelSizeChanged();
            folderLabel.Text = 'Output below GUI Data/Smart_Phone';
            setStatus(['Open CameraRecorder in NORMAL mode on the unlocked phone. ' ...
                'Connect by USB, then select Connect smartphone.'], 'normal');
        else
            previewAxes.Visible = 'on';
            folderLabel.Text = 'Output below GUI Data/EXT_Camera';
            setGuidedRecordingControls(false);
            refreshCameraList();
            title(previewAxes, 'Start external camera preview');
        end
    end

    function configurePhoneControls()
        if ~isPhoneSelected() || state.IsGuidedRecording, return; end
        cameraDropDown.ItemsData = [];
        cameraDropDown.Items = {'CameraRecorder via USB debugging'};
        cameraDropDown.Enable = 'off';
        formatDropDown.Items = {'NORMAL - resolution reported after capture'};
        formatDropDown.Enable = 'off';
        refreshButton.Enable = 'off';
        alignmentGuideCheckBox.Enable = 'off';
        irisGuideSizeSlider.Enable = 'off';
        snapshotButton.Enable = 'off';
        startButton.Text = 'Connect smartphone (status only)';
        startButton.Tooltip = 'Check the running phone app. Does not start recording or switch LEDs.';
        stopButton.Text = 'Disconnect smartphone';
        startButton.Enable = 'on';
        stopButton.Enable = 'off';
        showSettingsButton.Enable = 'off';
        if state.PhoneConnected
            startButton.Enable = 'off';
            stopButton.Enable = 'on';
            showSettingsButton.Enable = 'on';
        end
        recordVideoButton.Tooltip = ['13 s nominal illumination protocol after phone recording ' ...
            'is confirmed. White OFF does not guarantee IR. Phone video includes startup/stop latency.'];
        updateGuidedVideoButton();
    end

    function clearPhonePreviewMessage()
        if ~isempty(state.PhonePreviewMessage) && isgraphics(state.PhonePreviewMessage)
            delete(state.PhonePreviewMessage);
        end
        state.PhonePreviewMessage = [];
    end

    function onPreviewPanelSizeChanged(varargin)
        if isempty(state.PhonePreviewMessage) || ~isgraphics(state.PhonePreviewMessage)
            return
        end
        panelSize = previewPanel.Position(3:4);
        state.PhonePreviewMessage.Position = [round(0.08 * panelSize(1)), ...
            round(0.37 * panelSize(2)), round(0.84 * panelSize(1)), ...
            round(0.24 * panelSize(2))];
    end

    function connectPhone()
        try
            setStatus('Checking CameraRecorder over USB...', 'normal');
            drawnow;
            if isempty(state.Phone), state.Phone = PlacidoPhoneClient(); end
            info = state.Phone.connect();
            state.PhoneConnected = true;
            configurePhoneControls();
            setStatus(sprintf(['Phone connected (%s). Align using the PHONE screen. ' ...
                'Connect the Arduino separately before the guided sequence.'], info.mode), 'success');
        catch ME
            state.PhoneConnected = false;
            configurePhoneControls();
            setStatus(ME.message, 'error');
            uialert(appFigure, ME.message, 'Phone connection failed');
        end
    end

    function runGuidedPlan()
        plan = placidoGuidedPlan(state.GuidedIrOnlySeconds, ...
            state.GuidedSolidPlacidoSeconds, state.GuidedBlinkHalfBlockSeconds, ...
            state.GuidedBlinkBlockCount);
        for eventIndex = 1:height(plan)
            if isPhoneSelected()
                info = state.Phone.status();
                if ~info.is_recording
                    error('Placido:Stopped', 'Phone stopped recording before protocol completion.');
                end
            end
            waitForRecordingTime(plan.PlannedTimeSeconds(eventIndex));
            % Abort instead of compressing missed illumination blocks into a burst.
            if toc(state.RecordingClock) - plan.PlannedTimeSeconds(eventIndex) > 0.25
                error('Placido:Late', 'Host command is over 250 ms late; protocol aborted.');
            end
            recordGuidedLightEvent(plan.Event{eventIndex}, ...
                plan.PlannedTimeSeconds(eventIndex), plan.ArduinoCommand{eventIndex});
        end
    end

    function recordPhoneVideo()
        if state.IsGuidedRecording, return; end
        if ~state.PhoneConnected || ~hasActiveArduino()
            uialert(appFigure, 'Connect both smartphone and Arduino before the guided protocol.', ...
                'Connections required');
            return
        end
        runFolder = '';
        logStart = numel(state.Phone.CommandLog) + 1;
        manifest = struct('CameraBackend', 'CameraRecorder_USB', 'Completed', false, ...
            'ProtocolCompleted', false, 'PhysicalIlluminationValidated', false, ...
            'VideoTimeAlignmentValidated', false, 'NominalProtocolSeconds', 13, ...
            'TimingOrigin', 'Host receipt of first STATUS reporting recording=true', ...
            'PhoneIRIllumination', 'Not established or controlled by this GUI', ...
            'Failure', '');
        state.RecordingEvents = struct('Event', {}, 'PlannedTimeSeconds', {}, ...
            'ActualTimeSeconds', {}, 'ArduinoCommand', {}, 'WallClockTime', {});
        try
            [saveFolder, baseName] = getVideoSaveLocation();
            safeName = regexprep(baseName, '[^A-Za-z0-9_-]', '_');
            prefix = sprintf('%s_phone_%s', safeName, ...
                char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS')));
            runFolder = fullfile(saveFolder, prefix);
            if isfolder(runFolder), error('Placido:Exists', 'Run folder already exists.'); end
            mkdir(runFolder);
            manifest.PhoneFilenamePrefix = prefix;
            manifest.CreatedUTC = PlacidoPhoneClient.utcNow();
            manifest.SoftwareSHA256 = struct( ...
                'GUI', PlacidoPhoneClient.fileHash([mfilename('fullpath') '.m']), ...
                'PhoneClient', PlacidoPhoneClient.fileHash(which('PlacidoPhoneClient')), ...
                'CaptureLocation', PlacidoPhoneClient.fileHash(which('placidoCaptureLocation')), ...
                'ProtocolPlan', PlacidoPhoneClient.fileHash(which('placidoGuidedPlan')));
            manifest.SettingsBefore = state.Phone.status();
            manifest.ArduinoPort = char(state.Arduino.Port);
            manifest.ArduinoBaudRate = state.Arduino.BaudRate;
            state.IsGuidedRecording = true;
            state.CancelRequested = false;
            setGuidedRecordingControls(true);
            setStatus('Preparing phone recording; white illumination sent OFF.', 'normal');
            sendArduinoCode('O', 'pre-recording OFF');
            manifest.PreRecordOffUTC = PlacidoPhoneClient.utcNow();
            pause(0.15);
            if state.CancelRequested, error('Placido:Cancelled', 'Cancelled before phone START.'); end
            state.Phone.startRecording(prefix);
            state.RecordingClock = tic;
            state.RecordingStartTime = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
            manifest.ProtocolOriginUTC = PlacidoPhoneClient.utcNow();
            recordGuidedStateEvent('protocol_start_white_off', 0, 'O_pre_record');
            setStatus('Recording on phone. Use the phone screen for alignment.', 'normal');
            runGuidedPlan();
            manifest.ProtocolCompleted = true;
            state.Phone.stopRecording();
            manifest.StopConfirmedUTC = PlacidoPhoneClient.utcNow();
            setStatus('Phone stopped. Copying video and phone timing CSV; originals retained...', 'normal');
            files = state.Phone.fetchRecording(prefix, runFolder);
            manifest.Files = files;
            video = VideoReader(files.VideoFile);
            manifest.VideoWidth = video.Width;
            manifest.VideoHeight = video.Height;
            manifest.VideoFrameRate = video.FrameRate;
            manifest.VideoDurationSeconds = video.Duration;
            decoded = 0;
            firstFrame = [];
            while hasFrame(video)
                frame = readFrame(video);
                decoded = decoded + 1;
                if decoded == 1, firstFrame = frame; end
            end
            if decoded == 0, error('Placido:EmptyVideo', 'Transferred MP4 contains no readable frames.'); end
            manifest.DecodedVideoFrames = decoded;
            phoneTiming = readtable(files.PhoneTimingFile, 'NumHeaderLines', 1);
            expected = {'lsl_timestamp', 'frame_number', 'sensor_timestamp_ns', 'is_recording'};
            if ~all(ismember(expected, phoneTiming.Properties.VariableNames)) || height(phoneTiming) == 0
                error('Placido:Timing', 'Phone timing CSV is empty or has unexpected columns.');
            end
            manifest.PhoneTimingSamples = height(phoneTiming);
            manifest.TimingCaveat = ['Phone analysis samples are not verified encoded-frame timestamps. ' ...
                'Do not use host protocol seconds as MP4 frame times.'];
            manifest.Completed = true;
            clearPhonePreviewMessage();
            previewAxes.Visible = 'on';
            image(previewAxes, firstFrame);
            axis(previewAxes, 'image');
            previewAxes.XTick = []; previewAxes.YTick = [];
            title(previewAxes, 'First saved phone frame - NOT a live preview');
        catch ME
            manifest.Failure = ME.message;
            try
                sendArduinoCode('O', 'phone error safety OFF');
            catch
            end
            try
                state.Phone.stopRecording();
            catch stopError
                manifest.StopFailure = stopError.message;
            end
        end
        % Persist command evidence and incomplete-run status even after a failure.
        try
            if ~isempty(runFolder) && isfolder(runFolder)
                if ~isempty(state.RecordingEvents)
                    events = struct2table(state.RecordingEvents);
                    events.RecordingStartTime = repmat(string(state.RecordingStartTime), height(events), 1);
                    writetable(events, fullfile(runFolder, 'phone_host_protocol.csv'));
                end
                commands = state.Phone.CommandLog(logStart:end);
                if ~isempty(commands)
                    writetable(struct2table(commands), fullfile(runFolder, 'phone_commands.csv'));
                end
                fid = fopen(fullfile(runFolder, 'phone_session.json'), 'w');
                if fid < 0, error('Placido:Manifest', 'Cannot write session manifest.'); end
                fileCleanup = onCleanup(@() fclose(fid));
                fprintf(fid, '%s\n', jsonencode(manifest, 'PrettyPrint', true));
                clear fileCleanup
            end
        catch logError
            manifest.Completed = false;
            manifest.Failure = [manifest.Failure ' Metadata save failed: ' logError.message];
        end
        state.IsGuidedRecording = false;
        setGuidedRecordingControls(false);
        if manifest.Completed
            setStatus(sprintf('Saved phone MP4 and logs: %s. White OFF command sent.', runFolder), 'success');
        else
            setStatus(['Phone acquisition incomplete: ' manifest.Failure], 'error');
            if ~state.CloseRequested
                uialert(appFigure, [manifest.Failure ' Phone originals are retained. ' ...
                    'Check the phone recording state before disconnecting.'], 'Phone acquisition incomplete');
            end
        end
        if state.CloseRequested, onCloseRequest([], []); end
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
