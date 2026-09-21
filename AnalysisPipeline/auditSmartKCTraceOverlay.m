function auditSmartKCTraceOverlay(data,folder)
% Inspect saved SmartKC points on their processing image, without changing them.
base=fileparts(mfilename('fullpath'));
cfg=smartKCConstants(base);
pre=preprocessPlacidoImage(data.imagePath,cfg);
sensor=getProcessingSensorSizeMm(pre,cfg);
pitch=[sensor(1)/pre.OriginalSize(2),sensor(2)/pre.OriginalSize(1)];
f=figure('Visible','off','Color','w'); cleanup=onCleanup(@() close(f));
ax=axes(f); imshow(pre.NormalizedGray,'Parent',ax); hold(ax,'on');
colors=lines(numel(data.smartkc.AllShapes));
for k=1:numel(data.smartkc.AllShapes)
    shape=data.smartkc.AllShapes(k);
    x=shape.X/pitch(1)+pre.CenterPx(1);
    y=-shape.Y/pitch(2)+pre.CenterPx(2);
    scatter(ax,x,y,4,colors(k,:),'filled');
end
title(ax,'SmartKC radial candidates on normalized crop (no smoothing)','Color','k');
exportgraphics(ax,fullfile(folder,'SmartKC_candidate_overlay_audit.png'),'BackgroundColor','white');
end
