function testPhoneIntegration()
% Hardware-free regression tests. Transport calls are simulated in memory.
plan = placidoGuidedPlan();
assert(isequal(plan.PlannedTimeSeconds, [3;8;8.5;9;9.5;10;10.5;11;11.5;12;12.5;13]));
assert(isequal(plan.ArduinoCommand, {'A';'O';'A';'O';'A';'O';'A';'O';'A';'O';'A';'O'}));
[phoneFolder, name] = placidoCaptureLocation('D:\MATLAB\placido', 'phone', 'Test', 'eye');
externalFolder = placidoCaptureLocation('D:\MATLAB\placido', 'external', 'Test', 'eye');
assert(strcmp(phoneFolder, fullfile('D:\MATLAB\placido','Data','GUI Data','Smart_Phone','Test')));
assert(strcmp(externalFolder, fullfile('D:\MATLAB\placido','Data','GUI Data','EXT_Camera','Test')));
assert(strcmp(name, 'eye'));
assertThrows(@() placidoCaptureLocation('D:\MATLAB\placido', 'phone', '../escape', 'eye'), 'Placido:Folder');
assertThrows(@() placidoCaptureLocation('D:\MATLAB\placido', 'phone', 'C:\escape', 'eye'), 'Placido:Folder');
tempFolder = tempname;
mkdir(tempFolder);
cleanup = onCleanup(@() rmdir(tempFolder, 's'));
fixture = fullfile(tempFolder, 'fixture.bin');
fid = fopen(fixture, 'w'); fprintf(fid, 'abc'); fclose(fid);
expectedHash = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
assert(strcmp(PlacidoPhoneClient.fileHash(fixture), expectedHash));
recording = false;
failStart = false;
failStop = false;
malformedStatus = false;
corruptTransfer = false;
deviceCount = 1;
httpCommands = {};
transport = struct('Adb', @fakeAdb, 'Http', @fakeHttp);
client = PlacidoPhoneClient('mock-adb', transport);
info = client.connect();
assert(~info.is_recording && strcmp(info.mode, 'NORMAL'));
assert(~any(startsWith(httpCommands, 'START')));
client.startRecording('test_run');
assert(recording && client.OwnsRecording);
client.stopRecording();
assert(~recording && ~client.OwnsRecording);
files = client.fetchRecording('test_run', fullfile(tempFolder, 'transfer'));
assert(isfile(files.VideoFile) && isfile(files.PhoneTimingFile));
assert(strcmp(files.VideoSHA256, expectedHash));
assertThrows(@() client.fetchRecording('test_run', fullfile(tempFolder, 'transfer')), 'Placido:Exists');
corruptTransfer = true;
assertThrows(@() client.fetchRecording('test_run', fullfile(tempFolder, 'corrupt')), 'Placido:Integrity');
corruptTransfer = false;
failStart = true;
assertThrows(@() client.startRecording('test_run'), 'Placido:Communication');
assert(client.OwnsRecording && recording); % START reached phone, HTTP reply lost.
failStart = false;
failStop = true;
assertThrows(@() client.stopRecording(), 'Placido:Communication');
assert(client.OwnsRecording); % Failed STOP must not discard ownership.
failStop = false;
client.stopRecording();
recording = true;
assertThrows(@() client.startRecording('test_run'), 'Placido:State');
assert(~client.OwnsRecording); % Existing user recording must not be claimed.
recording = false;
malformedStatus = true;
assertThrows(@() client.status(), 'Placido:Status');
malformedStatus = false;
assertThrows(@() client.startRecording('bad;name'), 'Placido:Filename');
client.disconnect();
deviceCount = 2;
assertThrows(@() client.connect(), 'Placido:Device');
assert(any(~[client.CommandLog.Succeeded]));
fprintf('PHONE_INTEGRATION_TESTS_PASSED: schedule, hash, status, START/STOP, lost responses, ownership, transfer, overwrite, corruption, device ambiguity.\n');

    function reply = fakeHttp(command)
        httpCommands{end+1} = command;
        if strcmp(command, 'STATUS')
            if malformedStatus
                reply = '{"mode":"NORMAL"}';
            else
                reply = jsonencode(struct('mode', 'NORMAL', 'is_recording', recording));
            end
        elseif startsWith(command, 'START:')
            recording = true;
            if failStart, error('Mock:Network', 'Lost START response'); end
            reply = 'OK: START';
        elseif strcmp(command, 'STOP')
            if failStop, error('Mock:Network', 'Lost STOP request'); end
            recording = false;
            reply = 'OK: STOP';
        else
            error('Mock:Unexpected', 'Unexpected HTTP command.');
        end
    end

    function output = fakeAdb(args, ~)
        if strcmp(args{1}, 'devices')
            output = sprintf(['List of devices attached\n' ...
                'mock1\tdevice product:crownltexx model:SM_N960F transport_id:1\n']);
            if deviceCount == 2
                output = [output sprintf('mock2\tdevice product:test model:second transport_id:2\n')];
            end
        elseif any(strcmp(args, 'forward'))
            output = '18081';
        elseif any(strcmp(args, 'pull'))
            if corruptTransfer
                fid = fopen(args{end}, 'w'); fprintf(fid, 'corrupt'); fclose(fid);
            else
                copyfile(fixture, args{end});
            end
            output = 'copied';
        elseif startsWith(args{end}, 'find ')
            if contains(args{end}, '.mp4')
                output = '/sdcard/Movies/placido_data/test_run-2026-09-16.mp4';
            else
                output = '/sdcard/Documents/placido_data/test_run-2026-09-16.csv';
            end
        elseif startsWith(args{end}, 'sha256sum ')
            output = [expectedHash '  file'];
        else
            error('Mock:Unexpected', 'Unexpected ADB command.');
        end
    end
end

function assertThrows(action, identifier)
try
    action();
catch ME
    assert(strcmp(ME.identifier, identifier), 'Expected %s, got %s: %s', identifier, ME.identifier, ME.message);
    return
end
error('Test:NoError', 'Expected %s.', identifier);
end
