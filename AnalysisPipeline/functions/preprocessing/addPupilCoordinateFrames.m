function pupil = addPupilCoordinateFrames(pupil, cropOriginPx, ...
        originalSize, placidoCenterFullPx, cfg)
%ADDPUPILCOORDINATEFRAMES Add crop and sensor-plane coordinates.
%   Pixel values remain internal. Exported spatial values describe the
%   camera sensor plane and are not anatomical pupil dimensions.

pitchXmm = cfg.camera.SensorSizeMm(1)/originalSize(2);
pitchYmm = cfg.camera.SensorSizeMm(2)/originalSize(1);
if pupil.IsValid
    pupil.CenterPx = pupil.CenterFullPx-[cropOriginPx(1)-1, cropOriginPx(2)-1];
    deltaPx = pupil.CenterFullPx-placidoCenterFullPx;
    pupil.CenterRelativeToPlacidoSensorMm = ...
        [deltaPx(1)*pitchXmm, -deltaPx(2)*pitchYmm];
    pupil.OffsetMagnitudeSensorMm = ...
        norm(pupil.CenterRelativeToPlacidoSensorMm);
    pupil.DiameterXSensorMm = pupil.DiameterPx*pitchXmm;
    pupil.DiameterYSensorMm = pupil.DiameterPx*pitchYmm;
    pupil.EquivalentDiameterSensorMm = sqrt( ...
        pupil.DiameterXSensorMm*pupil.DiameterYSensorMm);
    pupil.DetectionStatus = "VALID_REVIEW_ONLY";
else
    pupil.CenterPx = [NaN, NaN];
    pupil.CenterRelativeToPlacidoSensorMm = [NaN, NaN];
    pupil.OffsetMagnitudeSensorMm = NaN;
    pupil.DiameterXSensorMm = NaN;
    pupil.DiameterYSensorMm = NaN;
    pupil.EquivalentDiameterSensorMm = NaN;
    if ~isfield(pupil, 'DetectionStatus')
        pupil.DetectionStatus = "NOT_ACCEPTED";
    end
end
pupil.SpatialUnit = "mm";
pupil.CoordinateFrame = ...
    "camera-sensor-plane; origin=detected-Placido-centre; x=right; y=superior";
end
