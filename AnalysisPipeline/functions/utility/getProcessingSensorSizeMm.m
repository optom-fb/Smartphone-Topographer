function sensorSizeMm = getProcessingSensorSizeMm(pre, cfg)
%GETPROCESSINGSENSORSIZEMM Return sensor axes aligned to processed pixels.

if isfield(pre, 'ProcessingSensorSizeMm')
    sensorSizeMm = double(pre.ProcessingSensorSizeMm(:).');
else
    sensorSizeMm = double(cfg.camera.SensorSizeMm(:).');
end
end
