function cameras = discoverSmartKCCameras()
%DISCOVERSMARTKCCAMERAS List cameras exposed by installed MATLAB adaptors.

cameras = table('Size', [0 5], ...
    'VariableTypes', {'string', 'cell', 'string', 'cell', 'string'}, ...
    'VariableNames', {'Adaptor', 'DeviceID', 'DeviceName', ...
    'SupportedFormats', 'DisplayName'});

if exist('imaqhwinfo', 'file') ~= 2
    return
end

rootInfo = imaqhwinfo();
adaptors = string(rootInfo.InstalledAdaptors);
for adaptorIndex = 1:numel(adaptors)
    adaptor = adaptors(adaptorIndex);
    try
        adaptorInfo = imaqhwinfo(char(adaptor));
    catch
        continue
    end
    devices = adaptorInfo.DeviceInfo;
    for deviceIndex = 1:numel(devices)
        device = devices(deviceIndex);
        formats = cellstr(string(device.SupportedFormats));
        displayName = sprintf('%s | %s | device %s', adaptor, ...
            string(device.DeviceName), string(device.DeviceID));
        newRow = table(adaptor, {device.DeviceID}, string(device.DeviceName), ...
            {formats}, string(displayName), 'VariableNames', ...
            cameras.Properties.VariableNames);
        cameras = [cameras; newRow]; %#ok<AGROW>
    end
end
end
