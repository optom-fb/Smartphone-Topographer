classdef PlacidoPhoneClient < handle
    % USB transport for CameraRecorder. Never launches or installs the app.
    % HTTP OK is only receipt; START/STOP require a separate STATUS check.
    properties (SetAccess = private)
        AdbPath
        Serial = ''
        Port = ''
        OwnsRecording = false
        CommandLog = struct('Command', {}, 'SentUTC', {}, 'ReturnedUTC', {}, ...
            'ElapsedSeconds', {}, 'Response', {}, 'Succeeded', {})
    end
    properties (Access = private)
        Transport = struct()
    end
    methods
        function obj = PlacidoPhoneClient(adbPath, transport)
            % Optional injected transport is for hardware-free regression tests.
            if nargin > 1, obj.Transport = transport; end
            if nargin == 0
                adbPath = fullfile(getenv('LOCALAPPDATA'), 'Android', 'Sdk', ...
                    'platform-tools', 'adb.exe');
            end
            if ~isfile(adbPath) && ~isfield(obj.Transport, 'Adb')
                error('Placido:ADB', 'ADB not found: %s. Install SDK Platform-Tools.', adbPath);
            end
            obj.AdbPath = char(adbPath);
        end

        function info = connect(obj)
            obj.disconnect();
            % Windows ADB may take about 30 s on its first device command.
            listing = obj.runAdb({'devices'}, 45);
            % `adb devices -l` may append product/model/transport fields.
            devices = regexp(listing, '(?m)^([^\s]+)\s+device(?:\s|$)', 'tokens');
            if numel(devices) ~= 1
                error('Placido:Device', ['Connect exactly one authorised Android device. ' ...
                    'Unlock it and accept the USB debugging prompt.']);
            end
            obj.Serial = devices{1}{1};
            try
                obj.Port = strtrim(obj.runAdb({'-s', obj.Serial, 'forward', ...
                    'tcp:0', 'tcp:8080'}, 45));
                if isempty(regexp(obj.Port, '^\d+$', 'once'))
                    error('Placido:Port', 'ADB did not return a valid local port.');
                end
                info = obj.status();
                if info.is_recording
                    error('Placido:Busy', 'Phone is already recording. Stop it on the phone first.');
                end
                if ~strcmp(info.mode, 'NORMAL')
                    error('Placido:Mode', 'Select NORMAL mode on the phone before connecting.');
                end
            catch ME
                obj.disconnect();
                rethrow(ME);
            end
        end

        function info = status(obj)
            info = jsondecode(obj.request('STATUS'));
            if ~isstruct(info) || ~isfield(info, 'is_recording') || ...
                    ~islogical(info.is_recording) || ~isscalar(info.is_recording) || ...
                    ~isfield(info, 'mode')
                error('Placido:Status', 'CameraRecorder returned an unsupported STATUS response.');
            end
        end

        function info = startRecording(obj, prefix)
            if isempty(regexp(prefix, '^[A-Za-z0-9_-]+$', 'once'))
                error('Placido:Filename', 'Phone filename prefix must use letters, digits, _ or -.');
            end
            info = obj.status();
            if info.is_recording || ~strcmp(info.mode, 'NORMAL')
                error('Placido:State', 'Phone must be idle and in NORMAL mode.');
            end
            % Retain ownership even if the response is lost after START was sent.
            obj.OwnsRecording = true;
            obj.request(['START:' char(prefix)]);
            info = obj.waitForState(true, 8);
        end

        function stopRecording(obj)
            if ~obj.OwnsRecording
                return
            end
            obj.request('STOP');
            obj.waitForState(false, 8);
            obj.OwnsRecording = false;
        end

        function result = fetchRecording(obj, prefix, destination)
            if obj.OwnsRecording
                error('Placido:Running', 'Confirm STOP before transferring files.');
            end
            if isempty(regexp(prefix, '^[A-Za-z0-9_-]+$', 'once'))
                error('Placido:Filename', 'Unsafe file prefix.');
            end
            if ~isfolder(destination), mkdir(destination); end
            roots = {'/sdcard/Movies/placido_data', '/sdcard/Documents/placido_data'};
            extensions = {'.mp4', '.csv'};
            result = struct();
            for k = 1:2
                searchClock = tic;
                remote = '';
                while toc(searchClock) < 20
                    listing = obj.runAdb({'-s', obj.Serial, 'shell', ...
                        sprintf('find %s -maxdepth 1 -type f -name "%s-*%s"', ...
                        roots{k}, prefix, extensions{k})}, 45);
                    paths = splitlines(strtrim(string(listing)));
                    paths(paths == "") = [];
                    if numel(paths) > 1
                        error('Placido:Ambiguous', 'Multiple phone files match this run. Originals retained.');
                    elseif isscalar(paths)
                        remote = char(paths(1));
                        break
                    end
                    pause(0.25);
                end
                pattern = ['^' regexptranslate('escape', [roots{k} '/' prefix '-']) ...
                    '[A-Za-z0-9_-]+' regexptranslate('escape', extensions{k}) '$'];
                if isempty(regexp(remote, pattern, 'once'))
                    error('Placido:MissingFile', 'Expected %s file not found; retain/recover phone originals.', extensions{k});
                end
                [~, stem, ext] = fileparts(remote);
                local = fullfile(destination, [stem ext]);
                if isfile(local) || isfile([local '.partial'])
                    error('Placido:Exists', 'Refusing to overwrite %s.', local);
                end
                % Require stable content and then compare SHA-256 across USB.
                digest = obj.remoteHash(remote);
                stable = false;
                for attempt = 1:10
                    pause(0.5);
                    current = obj.remoteHash(remote);
                    if strcmp(current, digest), stable = true; break; end
                    digest = current;
                end
                if ~stable, error('Placido:Finalize', 'Phone file is still changing.'); end
                obj.runAdb({'-s', obj.Serial, 'pull', remote, [local '.partial']}, 120);
                if ~strcmp(digest, PlacidoPhoneClient.fileHash([local '.partial'])) || ...
                        ~strcmp(digest, obj.remoteHash(remote))
                    error('Placido:Integrity', 'Transfer hash mismatch. Partial copy and phone original retained.');
                end
                movefile([local '.partial'], local);
                if k == 1
                    result.VideoFile = local;
                    result.VideoSHA256 = digest;
                else
                    result.PhoneTimingFile = local;
                    result.PhoneTimingSHA256 = digest;
                end
            end
        end

        function disconnect(obj)
            % Do not silently discard recording ownership after a failed STOP.
            if obj.OwnsRecording, obj.stopRecording(); end
            if ~isempty(obj.Port) && ~isempty(obj.Serial)
                obj.runAdb({'-s', obj.Serial, 'forward', '--remove', ['tcp:' obj.Port]}, 45);
            end
            obj.Port = '';
            obj.Serial = '';
        end
    end
    methods (Access = private)
        function info = waitForState(obj, expected, timeout)
            clock = tic;
            while toc(clock) < timeout
                info = obj.status();
                if info.is_recording == expected, return; end
                pause(0.1);
            end
            error('Placido:Timeout', 'Phone did not confirm recording state %d.', expected);
        end

        function response = request(obj, command)
            if isempty(obj.Port), error('Placido:Disconnected', 'Connect the phone first.'); end
            sent = PlacidoPhoneClient.utcNow();
            clock = tic;
            success = false;
            try
                if isfield(obj.Transport, 'Http')
                    response = obj.Transport.Http(command);
                else
                    response = webread(['http://127.0.0.1:' obj.Port '/'], 'cmd', command, ...
                        weboptions('Timeout', 2, 'ContentType', 'text'));
                end
                success = true;
            catch ME
                response = ME.message;
            end
            obj.CommandLog(end+1) = struct('Command', command, 'SentUTC', sent, ...
                'ReturnedUTC', PlacidoPhoneClient.utcNow(), 'ElapsedSeconds', toc(clock), ...
                'Response', response, 'Succeeded', success);
            if ~success, error('Placido:Communication', '%s', response); end
        end

        function digest = remoteHash(obj, remote)
            output = obj.runAdb({'-s', obj.Serial, 'shell', ['sha256sum ' remote]}, 45);
            digest = regexp(output, '^[a-fA-F0-9]{64}', 'match', 'once');
            if isempty(digest), error('Placido:Hash', 'Cannot verify phone file SHA-256.'); end
            digest = lower(digest);
        end

        function output = runAdb(obj, args, timeout)
            % Argument vector, not a host shell command. Bound every subprocess.
            if isfield(obj.Transport, 'Adb')
                output = obj.Transport.Adb(args, timeout);
                return
            end
            argv = java.util.ArrayList();
            argv.add(java.lang.String(obj.AdbPath));
            for k = 1:numel(args), argv.add(java.lang.String(args{k})); end
            builder = java.lang.ProcessBuilder(argv);
            builder.redirectErrorStream(true);
            logFile = [tempname '.txt'];
            cleanFile = onCleanup(@() PlacidoPhoneClient.removeTemp(logFile));
            builder.redirectOutput(java.io.File(logFile));
            process = builder.start();
            cleanProcess = onCleanup(@() process.destroy());
            clock = tic;
            while process.isAlive()
                if toc(clock) > timeout
                    process.destroyForcibly();
                    error('Placido:ADBTimeout', 'ADB timed out after %g seconds.', timeout);
                end
                pause(0.05);
            end
            output = fileread(logFile);
            if process.exitValue() ~= 0, error('Placido:ADB', '%s', strtrim(output)); end
        end
    end
    methods (Static)
        function value = utcNow()
            value = char(datetime('now', 'TimeZone', 'UTC', ...
                'Format', "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
        end
        function digest = fileHash(path)
            fid = fopen(path, 'rb');
            if fid < 0, error('Placido:File', 'Cannot read %s.', path); end
            cleanup = onCleanup(@() fclose(fid));
            md = java.security.MessageDigest.getInstance('SHA-256');
            while ~feof(fid)
                bytes = fread(fid, 1024*1024, '*uint8');
                md.update(typecast(bytes, 'int8'));
            end
            digest = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2).', 1, []));
        end
    end
    methods (Static, Access = private)
        function removeTemp(path)
            if isfile(path), delete(path); end
        end
    end
end
