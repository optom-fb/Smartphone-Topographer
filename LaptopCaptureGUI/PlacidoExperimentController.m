classdef PlacidoExperimentController < matlab.apps.AppBase
    % PlacidoExperimentController  Simple controller for the CameraRecorder app.
    %
    % Sends the CameraRecorder command set (START, START:<prefix>, STOP,
    % NORMAL, SLOW) over either WiFi (HTTP GET) or classic Bluetooth (SPP).
    %
    % Usage:
    %   PlacidoExperimentController

    properties (Access = public)
        UIFigure            matlab.ui.Figure
        MainGrid            matlab.ui.container.GridLayout

        ModeDropDown        matlab.ui.control.DropDown

        % WiFi / HTTP panel
        WiFiPanel           matlab.ui.container.Panel
        IPField             matlab.ui.control.EditField
        PortField           matlab.ui.control.EditField
        URLTemplateField    matlab.ui.control.EditField

        % Bluetooth panel
        BTPanel             matlab.ui.container.Panel
        DeviceDropDown      matlab.ui.control.DropDown
        RefreshButton       matlab.ui.control.Button
        ConnectBTButton     matlab.ui.control.Button
        BTStatusLamp        matlab.ui.control.Lamp

        % Command controls
        PrefixField         matlab.ui.control.EditField
        StartButton         matlab.ui.control.Button
        StopButton          matlab.ui.control.Button
        ModeButtonGroup     matlab.ui.container.ButtonGroup
        NormalRadio         matlab.ui.control.RadioButton
        SlowRadio           matlab.ui.control.RadioButton
        SlowerRadio         matlab.ui.control.RadioButton
        ExposureSwitch      matlab.ui.control.Switch
        ExposureSlider      matlab.ui.control.Slider
        RecLamp             matlab.ui.control.Lamp

        % LSL event logging panel
        LslPanel            matlab.ui.container.Panel
        DataDirField        matlab.ui.control.EditField
        PythonField         matlab.ui.control.EditField
        ArduinoPortField    matlab.ui.control.EditField
        LslLamp             matlab.ui.control.Lamp
        LslToggleButton     matlab.ui.control.Button

        % Log
        LogArea             matlab.ui.control.TextArea
    end

    properties (Access = private)
        BTObj = []              % connected bluetooth() object, or [] if disconnected
        LslPid = []             % PID of the running lsl_recorder.py process, or [] if not running
        ArduinoServerPid = []     % PID of ArduinoController.py, but ONLY if this app spawned it -- stays
                                 % empty if an instance was already running, so we never kill one we didn't start
        RecordingState = 'IDLE'  % 'IDLE' -> 'ACQUIRING' -> 'RUNNING' -> 'IDLE'
    end

    properties (Access = private, Constant)
        ArduinoServerPort = 8095  % must match ArduinoController.py's own default
        LockFileName = '.instance.lock'  % single-instance guard; see acquireSingleInstanceLock
        SettingsFileName = '.settings.json'  % persisted field values; see loadDataDirSetting
        DefaultDataDir = 'D:\PLACIDO'
    end

    methods (Access = private)

        function log(app, msg)
            ts = datestr(now, 'HH:MM:SS'); %#ok<TNOW1,DATST>
            newLine = sprintf('[%s] %s', ts, msg);
            existing = app.LogArea.Value;
            if ischar(existing)
                existing = {existing};
            end
            app.LogArea.Value = [existing; {newLine}];
            try
                scroll(app.LogArea, 'bottom');
            catch
            end
            drawnow limitrate;
        end

        function ok = sendCommand(app, cmd)
            ok = true;
            try
                if strcmp(app.ModeDropDown.Value, 'WiFi (HTTP)')
                    app.sendHttp(cmd);
                else
                    app.sendBluetooth(cmd);
                end
            catch ME
                ok = false;
                app.log(sprintf('ERROR sending "%s": %s', cmd, ME.message));
            end
        end

        function sendHttp(app, cmd)
            ip = strtrim(app.IPField.Value);
            port = strtrim(app.PortField.Value);
            if isempty(ip)
                error('Enter the CameraRecorder device IP address first.');
            end

            url = app.URLTemplateField.Value;
            url = strrep(url, '{ip}', ip);
            url = strrep(url, '{port}', port);
            url = strrep(url, '{cmd}', cmd);

            app.log(sprintf('HTTP -> %s', url));

            req = matlab.net.http.RequestMessage('GET');
            uri = matlab.net.URI(url);
            opts = matlab.net.http.HTTPOptions('ConnectTimeout', 3);
            resp = send(req, uri, opts);

            app.log(sprintf('HTTP <- %d %s', double(resp.StatusCode), char(resp.StatusCode)));
        end

        function sendBluetooth(app, cmd)
            if isempty(app.BTObj)
                error('Not connected to a Bluetooth device.');
            end
            app.log(sprintf('BT -> %s', cmd));
            writeline(app.BTObj, cmd);
        end

        function sendArduinoCommand(app, cmd)
            % Best-effort notification to ArduinoController.py -- never
            % blocks/breaks the recording flow if it isn't reachable.
            url = sprintf('http://127.0.0.1:%d/?cmd=%s', app.ArduinoServerPort, cmd);
            try
                req = matlab.net.http.RequestMessage('GET');
                uri = matlab.net.URI(url);
                opts = matlab.net.http.HTTPOptions('ConnectTimeout', 1);
                send(req, uri, opts);
                app.log(sprintf('Arduino -> %s', cmd));
            catch ME
                app.log(sprintf('Arduino notify failed ("%s"): %s', cmd, ME.message));
            end
        end

        function setBTConnectedUI(app, connected)
            if connected
                app.BTStatusLamp.Color = [0.20 0.75 0.20];
                app.ConnectBTButton.Text = 'Disconnect';
            else
                app.BTStatusLamp.Color = [0.75 0.20 0.20];
                app.ConnectBTButton.Text = 'Connect';
            end
        end

        function setRecLampUI(app, recording)
            % Best-effort indicator: reflects the last command this GUI
            % sent successfully, not a live status pushed from the phone.
            if recording
                app.RecLamp.Color = [0.85 0.10 0.10];
            else
                app.RecLamp.Color = [0.55 0.55 0.55];
            end
        end

        function setLslLampUI(app, running)
            if running
                app.LslLamp.Color = [0.20 0.75 0.20];
                app.LslToggleButton.Text = 'Stop Logger';
            else
                app.LslLamp.Color = [0.75 0.20 0.20];
                app.LslToggleButton.Text = 'Start Logger';
            end
        end

        function startLslLogger(app)
            if ~isempty(app.LslPid)
                return
            end

            dataDir = strtrim(app.DataDirField.Value);
            if isempty(dataDir)
                error('Enter a DATA directory first.');
            end
            if ~exist(dataDir, 'dir')
                mkdir(dataDir);
            end

            scriptPath = fullfile(fileparts(mfilename('fullpath')), 'lsl_recorder.py');
            if ~isfile(scriptPath)
                error('lsl_recorder.py not found next to PlacidoExperimentController.m');
            end

            pythonExe = strtrim(app.PythonField.Value);
            logPath = fullfile(dataDir, 'lsl_recorder.log');

            % Regenerate lsl_api.cfg next to lsl_recorder.py on every start.
            % If the phone's IP is filled in, list it as a KnownPeer so LSL
            % queries it by direct unicast -- university networks routinely
            % block the multicast discovery LSL relies on by default. The
            % recorder is spawned with this folder as its working directory
            % so liblsl actually finds the file.
            scriptDir = fileparts(scriptPath);
            phoneIp = strtrim(app.IPField.Value);
            fid = fopen(fullfile(scriptDir, 'lsl_api.cfg'), 'w');
            if fid ~= -1
                fprintf(fid, '; Auto-generated by PlacidoExperimentController at logger start.\n');
                if ~isempty(phoneIp)
                    fprintf(fid, '[lab]\n');
                    fprintf(fid, 'KnownPeers = {%s}\n', phoneIp);
                    app.log(sprintf('LSL: using KnownPeers = {%s} for unicast discovery.', phoneIp));
                else
                    app.log('LSL: no phone IP set -- multicast discovery only.');
                end
                fclose(fid);
            end

            pidPath = fullfile(dataDir, 'lsl_recorder.pid');

            if ispc
                errLogPath = fullfile(dataDir, 'lsl_recorder_err.log');
                % Passing this as a -Command "..." string breaks once any
                % path has a space (this repo lives under "ABI eye lab"):
                % MATLAB's system() relays the whole line through cmd.exe,
                % and cmd.exe's own double-quote parsing collides with the
                % quoting Start-Process -ArgumentList needs to keep spaced
                % paths as single arguments. Writing a real .ps1 file and
                % running it via -File sidesteps that relay entirely --
                % PowerShell parses the file's own content directly, with
                % no cmd.exe re-quoting in between.
                ps1Path = fullfile(dataDir, 'lsl_recorder_launch.ps1');
                ps1fid = fopen(ps1Path, 'w');
                if ps1fid == -1
                    error('Failed to write launch script %s', ps1Path);
                end
                fprintf(ps1fid, ['$p = Start-Process -FilePath "%s" ' ...
                    '-ArgumentList @(''"%s"'',''--data-dir'',''"%s"'') ' ...
                    '-WorkingDirectory "%s" ' ...
                    '-RedirectStandardOutput "%s" -RedirectStandardError "%s" ' ...
                    '-WindowStyle Hidden -PassThru\n'], ...
                    app.windowlessPythonExe(pythonExe), scriptPath, dataDir, scriptDir, logPath, errLogPath);
                fprintf(ps1fid, 'Set-Content -Path "%s" -Value $p.Id -NoNewline\n', pidPath);
                fclose(ps1fid);

                % `powershell -WindowStyle Hidden` alone doesn't reliably
                % suppress the *initial* console flash -- the console window
                % is created by the OS as part of process startup, before
                % PowerShell's own code runs and can act on the flag.
                % Routing through WScript.Shell.Run with window style 0
                % instead is the standard bulletproof fix: that hidden style
                % is enforced by the shell itself, not the target program's
                % cooperation. wscript.exe also has no console of its own
                % (it's a GUI-subsystem executable), so it can't flash
                % either. Downside: Run() doesn't expose the child's stdout,
                % so the PID can't be captured via `system()`'s output
                % anymore -- the .ps1 script above writes it to pidPath
                % instead, read back below once this synchronous call
                % returns (the 3rd Run() argument, True, waits for it).
                psCmd = sprintf('powershell -NoProfile -ExecutionPolicy Bypass -File "%s"', ps1Path);
                vbsPath = fullfile(dataDir, 'lsl_recorder_launch.vbs');
                vbsFid = fopen(vbsPath, 'w');
                if vbsFid == -1
                    error('Failed to write launch script %s', vbsPath);
                end
                fprintf(vbsFid, 'Set objShell = CreateObject("WScript.Shell")\n');
                fprintf(vbsFid, 'objShell.Run "%s", 0, True\n', strrep(psCmd, '"', '""'));
                fclose(vbsFid);
                cmd = sprintf('wscript //B "%s"', vbsPath);
            else
                cmd = sprintf('cd "%s" && nohup %s "%s" --data-dir "%s" > "%s" 2>&1 & echo $!', ...
                    scriptDir, pythonExe, scriptPath, dataDir, logPath);
            end

            [status, out] = system(cmd);
            if ispc
                pid = NaN;
                if isfile(pidPath)
                    pid = str2double(strtrim(fileread(pidPath)));
                end
            else
                pid = str2double(strtrim(out));
            end
            if status ~= 0 || isnan(pid)
                error('Failed to launch lsl_recorder.py (see %s)', logPath);
            end

            app.LslPid = pid;
            app.setLslLampUI(true);
            app.log(sprintf('LSL logger started (pid %d), writing to %s', pid, dataDir));
        end

        function stopLslLogger(app)
            if isempty(app.LslPid)
                return
            end
            try
                if ispc
                    system(sprintf('taskkill /PID %d /F', app.LslPid));
                else
                    system(sprintf('kill %d', app.LslPid));
                end
            catch
            end
            app.LslPid = [];
            app.setLslLampUI(false);
            app.log('LSL logger stopped.');
        end

        function onPhoneIpChanged(app)
            % The LSL logger bakes the phone IP into lsl_api.cfg at start,
            % so a change to the field only takes effect after a restart.
            if ~isempty(app.LslPid)
                app.log('Phone IP changed -- restarting LSL logger.');
                app.stopLslLogger();
                try
                    app.startLslLogger();
                catch ME
                    app.log(sprintf('LSL logger restart failed: %s', ME.message));
                end
            end
        end

        function alive = isArduinoServerAlive(~, port)
            alive = false;
            try
                url = sprintf('http://127.0.0.1:%d/', port);
                req = matlab.net.http.RequestMessage('GET');
                uri = matlab.net.URI(url);
                opts = matlab.net.http.HTTPOptions('ConnectTimeout', 1);
                send(req, uri, opts);
                alive = true;
            catch
                alive = false;
            end
        end

        function exe = defaultPythonExe(~)
            % Prefer the venv next to this script over whatever 'python' is
            % on PATH -- the Anaconda base python has a broken LSL data path
            % on this machine (streams resolve but no data arrives).
            here = fileparts(mfilename('fullpath'));
            if ispc
                candidate = fullfile(here, '.venv', 'Scripts', 'python.exe');
                fallback = 'python';
            else
                candidate = fullfile(here, '.venv', 'bin', 'python3');
                fallback = 'python3';
            end
            if isfile(candidate)
                exe = candidate;
            else
                exe = fallback;
            end
        end

        function exe = windowlessPythonExe(~, pythonExe)
            % python.exe is a console-subsystem executable -- launching it
            % via Start-Process, even with no visible window requested,
            % still allocates a real console window that stays open for
            % the process's whole (long-running) lifetime. That's the
            % "big window that stays open", not anything about the
            % PowerShell wrapper. pythonw.exe is the windowless variant
            % every CPython install ships alongside python.exe: it never
            % allocates a console at all, while a script's own GUI (e.g.
            % ArduinoController.py's Tkinter window) still displays
            % normally. Falls back to pythonExe unchanged if no sibling
            % pythonw.exe is found (e.g. a non-standard interpreter).
            exe = pythonExe;
            if ~ispc
                return
            end
            [dir, name, ~] = fileparts(pythonExe);
            if ~strcmpi(name, 'python')
                return
            end
            candidate = fullfile(dir, 'pythonw.exe');
            if isfile(candidate)
                exe = candidate;
            end
        end

        function ensureArduinoServerRunning(app)
            % Independent process (see ARDUINO_LIGHT_CONTROL_TODO.md) --
            % this only spawns it if nothing is already listening, and
            % only ever kills the instance it spawned itself (tracked via
            % ArduinoServerPid), never one that was already running.
            port = app.ArduinoServerPort;
            if app.isArduinoServerAlive(port)
                app.log(sprintf('Arduino control server already running on port %d.', port));
                return
            end

            scriptPath = fullfile(fileparts(mfilename('fullpath')), 'ArduinoController.py');
            if ~isfile(scriptPath)
                error('ArduinoController.py not found next to PlacidoExperimentController.m');
            end

            if ispc
                % Use the GUI's Python field (defaults to the local venv) so
                % both scripts run on the same working interpreter.
                pythonExe = strtrim(app.PythonField.Value);
                if isempty(pythonExe)
                    pythonExe = app.defaultPythonExe();
                end
            elseif isfile('/usr/local/bin/python3')
                % Prefer python.org's installer Python if present -- Apple's
                % bundled /usr/bin/python3 ships Tcl/Tk 8.5, which is known
                % to render blank / burn CPU for Tkinter GUIs on modern
                % macOS. python.org's build typically has a working Tk 8.6+.
                pythonExe = '/usr/local/bin/python3';
            else
                pythonExe = 'python3';
            end
            logDir = tempdir;
            logPath = fullfile(logDir, 'ArduinoController.log');

            serialPort = strtrim(app.ArduinoPortField.Value);
            if isempty(serialPort)
                serialPort = 'auto';
            end

            pidPath = fullfile(logDir, 'ArduinoController.pid');

            if ispc
                errLogPath = fullfile(logDir, 'ArduinoController_err.log');
                % See matching comment in startLslLogger: write a real .ps1
                % file and run it via -File, rather than relaying a
                % -Command "..." string through cmd.exe -- the extra
                % cmd.exe layer mangles quoting once any path (this repo
                % lives under "ABI eye lab") contains a space. Note: no
                % -WindowStyle Hidden on this inner Start-Process call --
                % windowlessPythonExe (below) already keeps python.exe from
                % allocating a console at all, and ArduinoController.py's
                % Tkinter window is meant to be visible regardless.
                ps1Path = fullfile(logDir, 'ArduinoController_launch.ps1');
                ps1fid = fopen(ps1Path, 'w');
                if ps1fid == -1
                    error('Failed to write launch script %s', ps1Path);
                end
                fprintf(ps1fid, ['$p = Start-Process -FilePath "%s" ' ...
                    '-ArgumentList @(''"%s"'',''--port'',''%d'',''--serial-port'',''%s'') ' ...
                    '-RedirectStandardOutput "%s" -RedirectStandardError "%s" -PassThru\n'], ...
                    app.windowlessPythonExe(pythonExe), scriptPath, port, serialPort, logPath, errLogPath);
                fprintf(ps1fid, 'Set-Content -Path "%s" -Value $p.Id -NoNewline\n', pidPath);
                fclose(ps1fid);

                % See matching comment in startLslLogger: `powershell
                % -WindowStyle Hidden` doesn't reliably suppress the
                % *initial* console flash, since the console is created by
                % the OS before PowerShell's own code can act on the flag.
                % WScript.Shell.Run with window style 0 is the bulletproof
                % fix -- enforced by the shell itself, and wscript.exe has
                % no console of its own to flash in the first place. This
                % only hides *this* intermediate powershell.exe hop; the
                % Start-Process call above still launches
                % ArduinoController.py with a normal (visible) window.
                psCmd = sprintf('powershell -NoProfile -ExecutionPolicy Bypass -File "%s"', ps1Path);
                vbsPath = fullfile(logDir, 'ArduinoController_launch.vbs');
                vbsFid = fopen(vbsPath, 'w');
                if vbsFid == -1
                    error('Failed to write launch script %s', vbsPath);
                end
                fprintf(vbsFid, 'Set objShell = CreateObject("WScript.Shell")\n');
                fprintf(vbsFid, 'objShell.Run "%s", 0, True\n', strrep(psCmd, '"', '""'));
                fclose(vbsFid);
                cmd = sprintf('wscript //B "%s"', vbsPath);
            else
                cmd = sprintf('nohup %s "%s" --port %d --serial-port %s > "%s" 2>&1 & echo $!', ...
                    pythonExe, scriptPath, port, serialPort, logPath);
            end

            [status, out] = system(cmd);
            if ispc
                pid = NaN;
                if isfile(pidPath)
                    pid = str2double(strtrim(fileread(pidPath)));
                end
            else
                pid = str2double(strtrim(out));
            end
            if status ~= 0 || isnan(pid)
                error('Failed to launch ArduinoController.py (see %s)', logPath);
            end

            app.ArduinoServerPid = pid;
            app.log(sprintf('Arduino control server started (pid %d) on port %d.', pid, port));
        end

        function stopArduinoServerIfOwned(app)
            if isempty(app.ArduinoServerPid)
                return
            end
            try
                if ispc
                    system(sprintf('taskkill /PID %d /F', app.ArduinoServerPid));
                else
                    system(sprintf('kill %d', app.ArduinoServerPid));
                end
            catch
            end
            app.ArduinoServerPid = [];
            app.log('Arduino control server stopped (was spawned by this app).');
        end

        function acquireSingleInstanceLock(app)
            % Refuses to start if another instance's lock file points at a
            % still-alive MATLAB process. A lock left behind by a MATLAB
            % crash (not a clean delete(app)) is harmless -- its PID won't
            % be alive, so it's treated as stale and overwritten below.
            lockPath = fullfile(fileparts(mfilename('fullpath')), app.LockFileName);
            if isfile(lockPath)
                existingPid = str2double(strtrim(fileread(lockPath)));
                if ~isnan(existingPid) && app.isMatlabProcessAlive(existingPid)
                    msg = sprintf(['Another Placido Experiment Controller is already running ' ...
                        '(MATLAB PID %d). Close it before opening a new one -- running two at ' ...
                        'once double-spawns lsl_recorder.py/ArduinoController.py.'], existingPid);
                    errordlg(msg, 'Already Running', 'modal');
                    error('PlacidoExperimentController:AlreadyRunning', '%s', msg);
                end
            end
            fid = fopen(lockPath, 'w');
            if fid ~= -1
                fprintf(fid, '%d', feature('getpid'));
                fclose(fid);
            end
        end

        function releaseSingleInstanceLock(app)
            % Only clears the lock if it still names this instance's own
            % PID -- if a stale lock from a crashed instance already got
            % overwritten by a newer one, this instance must not delete it.
            lockPath = fullfile(fileparts(mfilename('fullpath')), app.LockFileName);
            if ~isfile(lockPath)
                return
            end
            try
                existingPid = str2double(strtrim(fileread(lockPath)));
                if existingPid == feature('getpid')
                    delete(lockPath);
                end
            catch
            end
        end

        function alive = isMatlabProcessAlive(~, pid)
            alive = false;
            try
                if ispc
                    [status, out] = system(sprintf('tasklist /FI "PID eq %d" /FI "IMAGENAME eq MATLAB.exe" /NH', pid));
                    alive = (status == 0) && contains(out, 'MATLAB.exe');
                else
                    status = system(sprintf('kill -0 %d', pid));
                    alive = (status == 0);
                end
            catch
                alive = false;
            end
        end

        function dataDir = loadDataDirSetting(app)
            % Persists across sessions, unlike a plain hardcoded default --
            % settingsPath is read here (before createComponents assigns
            % it to DataDirField.Value) and written back by
            % saveDataDirSetting whenever the field changes.
            dataDir = app.DefaultDataDir;
            settingsPath = fullfile(fileparts(mfilename('fullpath')), app.SettingsFileName);
            if isfile(settingsPath)
                try
                    settings = jsondecode(fileread(settingsPath));
                    if isfield(settings, 'dataDir') && ~isempty(settings.dataDir)
                        dataDir = settings.dataDir;
                    end
                catch
                end
            end
        end

        function saveDataDirSetting(app)
            settingsPath = fullfile(fileparts(mfilename('fullpath')), app.SettingsFileName);
            settings = struct();
            if isfile(settingsPath)
                try
                    settings = jsondecode(fileread(settingsPath));
                catch
                    settings = struct();
                end
            end
            settings.dataDir = strtrim(app.DataDirField.Value);
            try
                fid = fopen(settingsPath, 'w');
                if fid ~= -1
                    fprintf(fid, '%s', jsonencode(settings));
                    fclose(fid);
                end
            catch
            end
        end

    end

    methods (Access = private)

        function onModeChanged(app, ~)
            isWifi = strcmp(app.ModeDropDown.Value, 'WiFi (HTTP)');
            app.WiFiPanel.Visible = isWifi;
            app.BTPanel.Visible = ~isWifi;
        end

        function onRefreshDevices(app, ~)
            try
                app.log('Scanning for Bluetooth devices...');
                devices = bluetoothlist('Timeout', 5);
                if isempty(devices)
                    app.DeviceDropDown.Items = {'(no devices found)'};
                    app.log('Bluetooth scan: no devices found.');
                else
                    app.DeviceDropDown.Items = cellstr(devices.Name);
                    app.log(sprintf('Bluetooth scan found %d device(s).', height(devices)));
                end
            catch ME
                app.log(sprintf('ERROR scanning Bluetooth: %s', ME.message));
            end
        end

        function onConnectBT(app, ~)
            if ~isempty(app.BTObj)
                try
                    delete(app.BTObj);
                catch
                end
                app.BTObj = [];
                app.setBTConnectedUI(false);
                app.log('Bluetooth disconnected.');
                return;
            end

            name = app.DeviceDropDown.Value;
            if isempty(name) || strcmp(name, '(no devices found)')
                app.log('ERROR: select a scanned device first.');
                return;
            end

            try
                app.log(sprintf('Connecting to Bluetooth device "%s"...', name));
                app.BTObj = bluetooth(name);
                configureTerminator(app.BTObj, 'CR/LF');
                app.setBTConnectedUI(true);
                app.log('Bluetooth connected.');
            catch ME
                app.BTObj = [];
                app.setBTConnectedUI(false);
                app.log(sprintf('ERROR connecting: %s', ME.message));
            end
        end

        function onStartToggle(app, ~)
            % Same control for START/ACQUIRE/RUNNING, advanced by button
            % press or spacebar each time: IDLE -> "ACQUIRE" (sends
            % START) -> "RUNNING" (local only, no command) -> back to
            % IDLE/"START" (sends STOP, via doStop -- also reachable
            % directly from the dedicated STOP button or Esc key). Each
            % press also notifies ArduinoController with the matching
            % word (START/ACQUIRE/RUNNING/STOP).
            switch app.RecordingState
                case 'IDLE'
                    % Re-send the GUI's current mode/exposure right before
                    % recording starts -- there's no readback from the
                    % phone to truly verify a match, but this eliminates
                    % drift from an earlier radio/slider change that got
                    % missed (dropped packet, phone not listening yet,
                    % etc.), so what's about to be captured matches what
                    % the GUI displays at this exact moment.
                    app.syncPhoneSettings();
                    prefix = strtrim(app.PrefixField.Value);
                    if isempty(prefix)
                        cmd = 'START';
                    else
                        cmd = sprintf('START:%s', prefix);
                    end
                    if app.sendCommand(cmd)
                        app.RecordingState = 'ACQUIRING';
                        app.StartButton.Text = 'ACQUIRE';
                        app.setRecLampUI(true);
                        app.setExposureLocked(true);
                        app.sendArduinoCommand('START');
                    end
                case 'ACQUIRING'
                    app.RecordingState = 'RUNNING';
                    app.StartButton.Text = 'RUNNING';
                    app.sendArduinoCommand('ACQUIRE');
                case 'RUNNING'
                    app.sendArduinoCommand('RUNNING');
                    app.doStop();
            end
        end

        function doStop(app)
            if app.sendCommand('STOP')
                app.RecordingState = 'IDLE';
                app.StartButton.Text = 'START';
                app.setRecLampUI(false);
                app.setExposureLocked(false);
                app.sendArduinoCommand('STOP');
            end
        end

        function onKeyPress(app, evt)
            switch evt.Key
                case 'space'
                    app.onStartToggle(evt);
                case 'escape'
                    app.doStop();
            end
        end

        function onCaptureModeChanged(app, evt)
            % Radio group for the phone's capture-rate mode -- NORMAL
            % (30fps), SLOW (120fps), SLOWER (240fps, disabled for now).
            % The phone's command string for 240fps is "SLOWER" (see
            % MainActivity.handleCommand), not "FAST".
            switch evt.NewValue
                case app.NormalRadio
                    app.sendCommand('NORMAL');
                case app.SlowRadio
                    app.sendCommand('SLOW');
                case app.SlowerRadio
                    app.sendCommand('SLOWER');
            end
        end

        function onExposureSwitchChanged(app, ~)
            % Not yet implemented on the phone side -- see README.md's
            % "Manual exposure control" section for the command convention
            % (EXPOSURE:<1-10> / AE_AUTO) this is designed against.
            if strcmp(app.ExposureSwitch.Value, 'Manual')
                app.ExposureSlider.Enable = 'on';
                app.sendCommand(sprintf('EXPOSURE:%d', round(app.ExposureSlider.Value)));
            else
                app.ExposureSlider.Enable = 'off';
                app.sendCommand('AE_AUTO');
            end
        end

        function onExposureSliderChanged(app, ~)
            if strcmp(app.ExposureSwitch.Value, 'Manual')
                app.sendCommand(sprintf('EXPOSURE:%d', round(app.ExposureSlider.Value)));
            end
        end

        function syncPhoneSettings(app)
            % Re-sends the GUI's current mode + exposure state. Called
            % right before every recording starts (see onStartToggle) --
            % all sendCommand calls are already best-effort/non-throwing,
            % same as everywhere else they're used.
            switch app.ModeButtonGroup.SelectedObject
                case app.NormalRadio
                    app.sendCommand('NORMAL');
                case app.SlowRadio
                    app.sendCommand('SLOW');
                case app.SlowerRadio
                    app.sendCommand('SLOWER');
            end
            if strcmp(app.ExposureSwitch.Value, 'Manual')
                app.sendCommand(sprintf('EXPOSURE:%d', round(app.ExposureSlider.Value)));
            else
                app.sendCommand('AE_AUTO');
            end
        end

        function setExposureLocked(app, locked)
            % Prevents exposure changes mid-recording -- the value that
            % actually applies for a capture is whatever syncPhoneSettings
            % pushed right before START, and there's no mechanism to
            % re-apply a mid-capture change on the phone anyway. Unlocking
            % on stop respects whichever Auto/Manual state was already
            % selected: the switch always re-enables, but the slider only
            % re-enables if still in Manual (matching
            % onExposureSwitchChanged's normal enable logic), so the
            % setting carries over unchanged into the next capture unless
            % the operator deliberately touches it.
            if locked
                app.ExposureSwitch.Enable = 'off';
                app.ExposureSlider.Enable = 'off';
            else
                app.ExposureSwitch.Enable = 'on';
                if strcmp(app.ExposureSwitch.Value, 'Manual')
                    app.ExposureSlider.Enable = 'on';
                end
            end
        end

        function onToggleLsl(app, ~)
            try
                if isempty(app.LslPid)
                    app.startLslLogger();
                else
                    app.stopLslLogger();
                end
            catch ME
                app.log(sprintf('ERROR: %s', ME.message));
            end
        end

    end

    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Name', 'Placido Experiment Controller', ...
                'Position', [100 100 460 790]);
            app.UIFigure.KeyPressFcn = @(src, evt) app.onKeyPress(evt);
            app.UIFigure.CloseRequestFcn = @(src, evt) delete(app);

            app.MainGrid = uigridlayout(app.UIFigure);
            app.MainGrid.ColumnWidth = {'1x'};
            app.MainGrid.RowHeight = {30, 40, 150, 40, 84, 70, 30, 130, 'fit', '1x'};
            app.MainGrid.RowSpacing = 8;
            app.MainGrid.Padding = [12 12 12 12];

            % --- Title ---
            title = uilabel(app.MainGrid);
            title.Text = 'Placido Experiment Controller';
            title.FontSize = 16;
            title.FontWeight = 'bold';
            title.Layout.Row = 1;
            title.Layout.Column = 1;

            % --- Mode selector ---
            modeGrid = uigridlayout(app.MainGrid);
            modeGrid.Layout.Row = 2;
            modeGrid.Layout.Column = 1;
            modeGrid.ColumnWidth = {100, '1x'};
            modeGrid.RowHeight = {'1x'};
            modeGrid.Padding = [0 0 0 0];

            modeLabel = uilabel(modeGrid);
            modeLabel.Text = 'Connection:';
            modeLabel.Layout.Row = 1;
            modeLabel.Layout.Column = 1;

            app.ModeDropDown = uidropdown(modeGrid);
            app.ModeDropDown.Items = {'WiFi (HTTP)', 'Bluetooth'};
            app.ModeDropDown.Value = 'WiFi (HTTP)';
            app.ModeDropDown.Layout.Row = 1;
            app.ModeDropDown.Layout.Column = 2;
            app.ModeDropDown.ValueChangedFcn = @(src, evt) app.onModeChanged(evt);

            % --- WiFi / HTTP panel ---
            app.WiFiPanel = uipanel(app.MainGrid);
            app.WiFiPanel.Title = 'WiFi (HTTP)';
            app.WiFiPanel.Layout.Row = 3;
            app.WiFiPanel.Layout.Column = 1;

            wifiGrid = uigridlayout(app.WiFiPanel);
            wifiGrid.ColumnWidth = {90, '1x'};
            wifiGrid.RowHeight = {30, 30, 30};

            ipLabel = uilabel(wifiGrid);
            ipLabel.Text = 'IP address:';
            ipLabel.Layout.Row = 1;
            ipLabel.Layout.Column = 1;

            app.IPField = uieditfield(wifiGrid, 'text');
            app.IPField.Value = '192.168.0.106';
            app.IPField.ValueChangedFcn = @(~,~) app.onPhoneIpChanged();
            app.IPField.Layout.Row = 1;
            app.IPField.Layout.Column = 2;

            portLabel = uilabel(wifiGrid);
            portLabel.Text = 'Port:';
            portLabel.Layout.Row = 2;
            portLabel.Layout.Column = 1;

            app.PortField = uieditfield(wifiGrid, 'text');
            app.PortField.Value = '8080';
            app.PortField.Layout.Row = 2;
            app.PortField.Layout.Column = 2;

            urlLabel = uilabel(wifiGrid);
            urlLabel.Text = 'URL format:';
            urlLabel.Layout.Row = 3;
            urlLabel.Layout.Column = 1;

            app.URLTemplateField = uieditfield(wifiGrid, 'text');
            app.URLTemplateField.Value = 'http://{ip}:{port}/?cmd={cmd}';
            app.URLTemplateField.Layout.Row = 3;
            app.URLTemplateField.Layout.Column = 2;

            % --- Bluetooth panel ---
            app.BTPanel = uipanel(app.MainGrid);
            app.BTPanel.Title = 'Bluetooth';
            app.BTPanel.Layout.Row = 3;
            app.BTPanel.Layout.Column = 1;
            app.BTPanel.Visible = 'off';

            btGrid = uigridlayout(app.BTPanel);
            btGrid.ColumnWidth = {'1x', 100};
            btGrid.RowHeight = {30, 30, 30};

            app.DeviceDropDown = uidropdown(btGrid);
            app.DeviceDropDown.Items = {'(scan for devices)'};
            app.DeviceDropDown.Layout.Row = 1;
            app.DeviceDropDown.Layout.Column = 1;

            app.RefreshButton = uibutton(btGrid, 'push');
            app.RefreshButton.Text = 'Scan';
            app.RefreshButton.Layout.Row = 1;
            app.RefreshButton.Layout.Column = 2;
            app.RefreshButton.ButtonPushedFcn = @(src, evt) app.onRefreshDevices(evt);

            app.ConnectBTButton = uibutton(btGrid, 'push');
            app.ConnectBTButton.Text = 'Connect';
            app.ConnectBTButton.Layout.Row = 2;
            app.ConnectBTButton.Layout.Column = 1;
            app.ConnectBTButton.ButtonPushedFcn = @(src, evt) app.onConnectBT(evt);

            app.BTStatusLamp = uilamp(btGrid);
            app.BTStatusLamp.Color = [0.75 0.20 0.20];
            app.BTStatusLamp.Layout.Row = 2;
            app.BTStatusLamp.Layout.Column = 2;

            % --- Prefix field ---
            prefixGrid = uigridlayout(app.MainGrid);
            prefixGrid.Layout.Row = 4;
            prefixGrid.Layout.Column = 1;
            prefixGrid.ColumnWidth = {100, '1x'};
            prefixGrid.RowHeight = {'1x'};
            prefixGrid.Padding = [0 0 0 0];

            prefixLabel = uilabel(prefixGrid);
            prefixLabel.Text = 'START prefix:';
            prefixLabel.Layout.Row = 1;
            prefixLabel.Layout.Column = 1;

            app.PrefixField = uieditfield(prefixGrid, 'text');
            app.PrefixField.Value = '';
            app.PrefixField.Placeholder = 'optional, e.g. MyRun';
            app.PrefixField.Layout.Row = 1;
            app.PrefixField.Layout.Column = 2;

            % --- Command buttons ---
            cmdGrid = uigridlayout(app.MainGrid);
            cmdGrid.Layout.Row = 5;
            cmdGrid.Layout.Column = 1;
            cmdGrid.ColumnWidth = {'1x', '1x', '1x', '1x'};
            cmdGrid.RowHeight = {'1x', '1x'};
            cmdGrid.Padding = [0 0 0 0];

            app.StartButton = uibutton(cmdGrid, 'push');
            app.StartButton.Text = 'START';
            app.StartButton.BackgroundColor = [0.25 0.65 0.35];
            app.StartButton.FontColor = [1 1 1];
            app.StartButton.Layout.Row = 1;
            app.StartButton.Layout.Column = [1 2];
            app.StartButton.ButtonPushedFcn = @(src, evt) app.onStartToggle(evt);

            app.StopButton = uibutton(cmdGrid, 'push');
            app.StopButton.Text = 'STOP';
            app.StopButton.BackgroundColor = [0.75 0.25 0.25];
            app.StopButton.FontColor = [1 1 1];
            app.StopButton.Layout.Row = 1;
            app.StopButton.Layout.Column = [3 4];
            app.StopButton.ButtonPushedFcn = @(src, evt) app.doStop();

            % Capture-rate mode -- mutually exclusive, mirrors the phone's
            % actual capture state (only one rate can be active at once).
            % uiradiobutton requires its Parent to BE a ButtonGroup
            % directly (unlike most components, it can't sit inside a
            % GridLayout nested in one), so these three are positioned
            % with pixel Position rather than Layout.Row/Column.
            app.ModeButtonGroup = uibuttongroup(cmdGrid);
            app.ModeButtonGroup.BorderType = 'none';
            app.ModeButtonGroup.Layout.Row = 2;
            app.ModeButtonGroup.Layout.Column = [1 4];
            app.ModeButtonGroup.SelectionChangedFcn = @(src, evt) app.onCaptureModeChanged(evt);

            app.NormalRadio = uiradiobutton(app.ModeButtonGroup);
            app.NormalRadio.Text = 'NORMAL (30fps)';
            app.NormalRadio.Position = [5 5 140 22];
            app.NormalRadio.Value = true;

            app.SlowRadio = uiradiobutton(app.ModeButtonGroup);
            app.SlowRadio.Text = 'SLOW (120fps)';
            app.SlowRadio.Position = [150 5 140 22];

            app.SlowerRadio = uiradiobutton(app.ModeButtonGroup);
            app.SlowerRadio.Text = 'SLOWER (240fps)';
            app.SlowerRadio.Tooltip = 'Disabled for now.';
            app.SlowerRadio.Enable = 'off';
            app.SlowerRadio.Position = [295 5 140 22];

            % --- Exposure ---
            % Not yet implemented on the phone side -- see the "Manual
            % exposure control" section in README.md for the EXPOSURE:<n>
            % / AE_AUTO command convention this sends, which the
            % CameraRecorder Android app (a separate codebase) needs to
            % handle for this to actually do anything on the phone.
            exposureGrid = uigridlayout(app.MainGrid);
            exposureGrid.Layout.Row = 6;
            exposureGrid.Layout.Column = 1;
            exposureGrid.ColumnWidth = {70, 100, '1x'};
            exposureGrid.RowHeight = {22, '1x'};
            exposureGrid.Padding = [0 0 0 0];

            exposureLabel = uilabel(exposureGrid);
            exposureLabel.Text = 'Exposure:';
            exposureLabel.Layout.Row = 1;
            exposureLabel.Layout.Column = 1;

            app.ExposureSwitch = uiswitch(exposureGrid, 'slider');
            app.ExposureSwitch.Items = {'Auto', 'Manual'};
            app.ExposureSwitch.Value = 'Auto';
            app.ExposureSwitch.Layout.Row = 1;
            app.ExposureSwitch.Layout.Column = 2;
            app.ExposureSwitch.ValueChangedFcn = @(src, evt) app.onExposureSwitchChanged(evt);

            app.ExposureSlider = uislider(exposureGrid);
            app.ExposureSlider.Limits = [1 10];
            app.ExposureSlider.MajorTicks = 1:10;
            app.ExposureSlider.MinorTicks = [];
            app.ExposureSlider.Value = 5;
            app.ExposureSlider.Enable = 'off';
            app.ExposureSlider.Tooltip = 'Coarse 1-10 exposure level -- exact meaning is up to the phone app.';
            app.ExposureSlider.Layout.Row = 2;
            app.ExposureSlider.Layout.Column = [1 3];
            app.ExposureSlider.ValueChangedFcn = @(src, evt) app.onExposureSliderChanged(evt);

            % --- Recording status ---
            recGrid = uigridlayout(app.MainGrid);
            recGrid.Layout.Row = 7;
            recGrid.Layout.Column = 1;
            recGrid.ColumnWidth = {100, 30, '1x'};
            recGrid.RowHeight = {'1x'};
            recGrid.Padding = [0 0 0 0];

            recLabel = uilabel(recGrid);
            recLabel.Text = 'Recording:';
            recLabel.Layout.Row = 1;
            recLabel.Layout.Column = 1;

            app.RecLamp = uilamp(recGrid);
            app.RecLamp.Color = [0.55 0.55 0.55];
            app.RecLamp.Layout.Row = 1;
            app.RecLamp.Layout.Column = 2;

            % --- LSL event logging panel ---
            app.LslPanel = uipanel(app.MainGrid);
            app.LslPanel.Title = 'LSL Event Logging';
            app.LslPanel.Layout.Row = 8;
            app.LslPanel.Layout.Column = 1;

            lslGrid = uigridlayout(app.LslPanel);
            lslGrid.ColumnWidth = {70, '1x', 90};
            lslGrid.RowHeight = {26, 26, 26, 26};

            dataDirLabel = uilabel(lslGrid);
            dataDirLabel.Text = 'DATA dir:';
            dataDirLabel.Layout.Row = 1;
            dataDirLabel.Layout.Column = 1;

            app.DataDirField = uieditfield(lslGrid, 'text');
            app.DataDirField.Value = app.loadDataDirSetting();
            app.DataDirField.Layout.Row = 1;
            app.DataDirField.Layout.Column = [2 3];
            app.DataDirField.ValueChangedFcn = @(src, evt) app.saveDataDirSetting();

            pythonLabel = uilabel(lslGrid);
            pythonLabel.Text = 'Python:';
            pythonLabel.Layout.Row = 2;
            pythonLabel.Layout.Column = 1;

            app.PythonField = uieditfield(lslGrid, 'text');
            app.PythonField.Value = app.defaultPythonExe();
            app.PythonField.Layout.Row = 2;
            app.PythonField.Layout.Column = [2 3];

            arduinoPortLabel = uilabel(lslGrid);
            arduinoPortLabel.Text = 'Arduino port:';
            arduinoPortLabel.Layout.Row = 3;
            arduinoPortLabel.Layout.Column = 1;

            app.ArduinoPortField = uieditfield(lslGrid, 'text');
            app.ArduinoPortField.Value = 'auto';
            app.ArduinoPortField.Tooltip = 'Serial port for the Arduino UNO (e.g. COM6), or ''auto'' to detect it.';
            app.ArduinoPortField.Layout.Row = 3;
            app.ArduinoPortField.Layout.Column = [2 3];

            app.LslLamp = uilamp(lslGrid);
            app.LslLamp.Color = [0.75 0.20 0.20];
            app.LslLamp.Layout.Row = 4;
            app.LslLamp.Layout.Column = 1;

            app.LslToggleButton = uibutton(lslGrid, 'push');
            app.LslToggleButton.Text = 'Start Logger';
            app.LslToggleButton.Layout.Row = 4;
            app.LslToggleButton.Layout.Column = 3;
            app.LslToggleButton.ButtonPushedFcn = @(src, evt) app.onToggleLsl(evt);

            % --- Log label ---
            logLabel = uilabel(app.MainGrid);
            logLabel.Text = 'Log:';
            logLabel.Layout.Row = 9;
            logLabel.Layout.Column = 1;

            % --- Log area ---
            app.LogArea = uitextarea(app.MainGrid);
            app.LogArea.Layout.Row = 10;
            app.LogArea.Layout.Column = 1;
            app.LogArea.Editable = 'off';
            app.LogArea.Value = {''};
        end

    end

    methods (Access = public)

        function app = PlacidoExperimentController
            % Only one instance may run at a time -- two GUIs each spawn
            % their own lsl_recorder.py/ArduinoController.py, which is how
            % duplicate orphaned processes piled up before this check
            % existed. Aborts construction entirely (before any UI or
            % process spawning) if another instance is already alive.
            app.acquireSingleInstanceLock();

            createComponents(app);
            app.log('Placido Experiment Controller ready.');
            % Sync the phone to the GUI's default mode/exposure state right
            % away -- otherwise the phone stays in whatever it was last
            % left in, out of sync with what the GUI displays, until the
            % operator happens to touch a control (and again right before
            % each recording, via syncPhoneSettings in onStartToggle).
            app.syncPhoneSettings();
            try
                app.startLslLogger();
            catch ME
                app.log(sprintf('LSL logger not started: %s', ME.message));
            end
            try
                app.ensureArduinoServerRunning();
            catch ME
                app.log(sprintf('Arduino control server not started: %s', ME.message));
            end
        end

        function delete(app)
            if ~isempty(app.BTObj)
                try
                    delete(app.BTObj);
                catch
                end
            end
            app.stopLslLogger();
            app.stopArduinoServerIfOwned();
            app.releaseSingleInstanceLock();
            if isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end

    end
end
