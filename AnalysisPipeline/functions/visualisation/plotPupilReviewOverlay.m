function plotPupilReviewOverlay(axisHandle, image, pre, coordinateMode)
%PLOTPUPILREVIEWOVERLAY Show Placido centre and pupil candidate separately.

arguments
    axisHandle
    image
    pre struct
    coordinateMode (1,1) string {mustBeMember(coordinateMode, ...
        ["full", "crop"])}
end

imshow(image, 'Parent', axisHandle);
hold(axisHandle, 'on');
if coordinateMode == "full"
    if isfield(pre, 'InputResizeScale')
        scale = pre.InputResizeScale;
    else
        scale = 1;
    end
    placidoCenter = (pre.CenterFullPx-0.5)/scale+0.5;
    pupilCenter = (pre.Pupil.CenterFullPx-0.5)/scale+0.5;
    pupilRadius = pre.Pupil.RadiusPx/scale;
else
    placidoCenter = pre.CenterPx;
    pupilCenter = pre.Pupil.CenterPx;
    pupilRadius = pre.Pupil.RadiusPx;
end
plot(axisHandle, placidoCenter(1), placidoCenter(2), 'r+', ...
    'MarkerSize', 18, 'LineWidth', 2);
if pre.Pupil.IsValid
    viscircles(axisHandle, pupilCenter, pupilRadius, ...
        'Color', 'y', 'LineWidth', 1.8);
    plot(axisHandle, pupilCenter(1), pupilCenter(2), 'y+', ...
        'MarkerSize', 15, 'LineWidth', 2);
end
hold(axisHandle, 'off');
end
