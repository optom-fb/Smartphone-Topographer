function presentPairedResults(p,s,range,folder)
% Tables and native MATLAB plots; no inferred clinical axes or dimensions.
m=p.AllMetrics;
centres=vertcat(m.TrackingCentroid);
P=table([m.Ring]',[m.IsCompletePrimary]',centres(:,1),centres(:,2), ...
    [m.EigenRatio]',[m.IrregularityPct]',[m.ImageAxisDeg]', ...
    [m.MajorExtentPx]',[m.MinorExtentPx]', ...
    'VariableNames',{'Mire','Complete','CenterX','CenterY','EigenRatio', ...
    'EllipseIrregularityPct','MajorAxisDeg','MajorExtent','MinorExtent'});
M=s.AllMetrics;
[smartShapes,smartPixelGeometry]=smartKCSourcePixelGeometry(s,M);
S=table(M.MireIndex,M.IsIncludedInPrimary,smartPixelGeometry.CenterX, ...
    smartPixelGeometry.CenterY,smartPixelGeometry.EigenRatio, ...
    M.Irregularity_percent,smartPixelGeometry.MajorAxisDeg, ...
    smartPixelGeometry.MajorExtent,smartPixelGeometry.MinorExtent, ...
    'VariableNames',P.Properties.VariableNames);
% Retain the original SmartKC reference-geometry values in the detailed
% CSV. They are not used for the paired display because they are not a
% calibration of the phone that acquired the image.
S.CenterXNominalMm=M.CenterXmm;
S.CenterYNominalMm=M.CenterYmm;
S.MajorExtentNominalMm=M.MajorExtentMm;
S.MinorExtentNominalMm=M.MinorExtentMm;
S.MajorAxisDegNominalMm=M.CovarianceMajorAxisDegCCW;
S.EigenRatioNominalMm=M.EigenRatio;
P.MaximumGapDeg=[m.MaximumGapDeg]';
P.CoverageDeg=[m.CoverageDeg]';
S.MaximumGapDeg=M.MaximumGapDeg;
S.CoverageDeg=M.ObservedAngleEquivalentDeg;
tables={P,S}; names={'Placido','SmartKC'};
units={'source pixels','source pixels'};
commonComplete=intersect(P.Mire(P.Complete),S.Mire(S.Complete));
commonSelected=commonComplete(commonComplete>=range(1) & commonComplete<=range(2));
fprintf('Final analysis uses common complete mire IDs in range %d:%d: %s\n', ...
    range(1),range(2),mat2str(commonSelected'));
comparisonSelection=table(commonComplete, ...
    ismember(commonComplete,commonSelected), ...
    'VariableNames',{'CommonCompleteMire','IncludedInSelectedRange'});
writetable(comparisonSelection,fullfile(folder,'common_complete_mires.csv'));
themeBg=get(groot,'defaultFigureColor'); themeAxes=get(groot,'defaultAxesColor');
themeText=get(groot,'defaultAxesXColor');
old=findall(groot,'Type','figure','Tag','PairedMireReport');
delete(old);
f=figure('Name','Smartphone Topographer - mire review','Tag','PairedMireReport', ...
    'NumberTitle','off','Visible','on','Color',themeBg,'Position',[60 60 1400 900]);
tabs=uitabgroup(f);
pairedAxes=gobjects(2,1);
pairedTables=cell(2,1);
for method=1:2
    T=tables{method}; T.MinorAxisDeg=mod(T.MajorAxisDeg+90,180);
    T.Selected=T.Mire>=range(1) & T.Mire<=range(2);
    T.SpatialUnit=repmat(string(units{method}),height(T),1);
    writetable(T,fullfile(folder,[names{method} '_all_detected_mires.csv']));
    writetable(T(T.Complete,:),fullfile(folder,[names{method} '_complete_mires.csv']));
    writetable(T(T.Selected,:),fullfile(folder,[names{method} '_selected_mires.csv']));
    for view=1:2
        if view==1
            rows=true(height(T),1); label='All detected mires'; suffix='all_detected';
        else
            rows=T.Complete; label='Complete mires only'; suffix='complete_only';
        end
        V=T(rows,:); primary=V(V.Complete,:);
        fprintf('%s | %s: %d detected, %d complete included in summary\n', ...
            names{method},label,height(V),height(primary));
        meanAxis=mod(atan2d(mean(sind(2*primary.MajorAxisDeg),'omitnan'), ...
            mean(cosd(2*primary.MajorAxisDeg),'omitnan'))/2,180);
        summary=table(height(primary),mean(primary.EigenRatio,'omitnan'), ...
            mean(primary.EllipseIrregularityPct,'omitnan'), ...
            hypot(std(primary.CenterX),std(primary.CenterY)), ...
            'VariableNames',{'CompleteCount','MeanEigenRatio','MeanEllipseIrregularityPct','CentreSpread'});
        summary.MeanMajorAxisDeg=meanAxis;
        summary.SpatialUnit=string(units{method});
        writetable(summary,fullfile(folder,[names{method} '_' suffix '_summary.csv']));
        tab=uitab(tabs,'Title',[names{method} ' - ' label],'BackgroundColor',themeBg);
        if view==1
            axesPosition=[.08 .10 .78 .78];
        else
            axesPosition=[.08 .43 .78 .49];
        end
        ax=axes(tab,'Position',axesPosition,'Color',themeAxes,'XColor',themeText,'YColor',themeText);
        hold(ax,'on'); colors=lines(max(height(T),1));
        for k=find(rows)'
            style=':'; if T.Complete(k), style='-'; end
            if method==1
                pts=p.AllPoints(p.AllPoints.RingNumber==T.Mire(k),:);
                x=pts.R.*cos(pts.T); y=-pts.R.*sin(pts.T);
                x=x(:); y=y(:);
                angle=mod(atan2(y,x),2*pi);
                [~,order]=sort(angle); x=x(order); y=y(order);
                if ~T.Complete(k)
                    sortedAngles=angle(order);
                    gaps=find(diff(sortedAngles)>pi/4);
                    for gap=flip(gaps(:)')
                        x=[x(1:gap);NaN;x(gap+1:end)];
                        y=[y(1:gap);NaN;y(gap+1:end)];
                    end
                end
                if T.Complete(k), x=[x(:);x(1)]; y=[y(:);y(1)]; end
                plot(ax,x,y,style,'Color',colors(k,:),'LineWidth',1.5, ...
                    'DisplayName',sprintf('Mire %d',T.Mire(k)));
            else
                shape=smartShapes(k);
                x=shape.X(:); y=shape.Y(:);
                % Show the actual localized SmartKC mire centreline. The
                % covariance ellipse is reserved for its dedicated tab.
                angle=mod(atan2(y,x),2*pi);
                [sortedAngles,order]=sort(angle); x=x(order); y=y(order);
                if ~T.Complete(k)
                    gaps=find(diff(sortedAngles)>pi/4);
                    for gap=flip(gaps(:)')
                        x=[x(1:gap);NaN;x(gap+1:end)];
                        y=[y(1:gap);NaN;y(gap+1:end)];
                    end
                elseif ~isempty(x)
                    x=[x;x(1)]; y=[y;y(1)]; %#ok<AGROW>
                end
                plot(ax,x,y,style,'Color',colors(k,:),'LineWidth',1.25, ...
                    'Marker','.','MarkerSize',5, ...
                    'DisplayName',sprintf('Mire %d',T.Mire(k)));
            end
            if view==2
                a=T.MajorAxisDeg(k); span=T.MajorExtent(k);
                plot(ax,T.CenterX(k)+[-1 1]*span*cosd(a), ...
                    T.CenterY(k)+[-1 1]*span*sind(a),'-','Color',colors(k,:), ...
                    'HandleVisibility','off');
                plot(ax,T.CenterX(k)+[-1 1]*T.MinorExtent(k)*cosd(a+90), ...
                    T.CenterY(k)+[-1 1]*T.MinorExtent(k)*sind(a+90),':', ...
                    'Color',colors(k,:),'HandleVisibility','off');
            end
        end
        axis(ax,'equal'); fitAxesToData(ax,.07); grid(ax,'on');
        xlabel(ax,['X (' units{method} ')'],'Color',themeText); ylabel(ax,['Y (' units{method} ')'],'Color',themeText);
        title(ax,sprintf('%s: %s | complete %d | solid=complete, dotted=diagnostic', ...
            names{method},label,height(primary)),'Color',themeText,'Interpreter','none');
        legend(ax,'Location','eastoutside','TextColor',themeText,'Color',themeBg);
        if view==2
            displayTable=V(:,{'Mire','Complete','CenterX','CenterY','EigenRatio', ...
                'EllipseIrregularityPct','MajorAxisDeg','MinorAxisDeg'});
            uitable(tab,'Data',table2cell(displayTable), ...
                'ColumnName',displayTable.Properties.VariableNames, ...
                'Units','normalized','Position',[.04 .04 .92 .29], ...
                'ForegroundColor',themeText,'BackgroundColor',[themeBg; themeBg*.94]);
        end
        drawnow;
        exportgraphics(ax,fullfile(folder,[names{method} '_' suffix '.png']),'BackgroundColor',themeBg);
    end
end
% Paired numerical comparison uses the same mire IDs that are complete in
% both methods and fall within the user's adjustable comparison range.
for method=1:2
    T=tables{method}; T.MinorAxisDeg=mod(T.MajorAxisDeg+90,180);
    commonTable=T(ismember(T.Mire,commonSelected),:);
    commonTable.SpatialUnit=repmat(string(units{method}),height(commonTable),1);
    writetable(commonTable,fullfile(folder,[names{method} '_common_complete_selected.csv']));
    count=height(commonTable);
    centreSpread=NaN;
    if count>1, centreSpread=hypot(std(commonTable.CenterX),std(commonTable.CenterY)); end
    summary=table(count,mean(commonTable.EigenRatio,'omitnan'), ...
        mean(commonTable.EllipseIrregularityPct,'omitnan'),centreSpread, ...
        'VariableNames',{'CommonCompleteCount','MeanEigenRatio','MeanEllipseIrregularityPct','CentreSpread'});
    if count>0
        meanFlat=mod(atan2d(mean(sind(2*commonTable.MajorAxisDeg),'omitnan'), ...
            mean(cosd(2*commonTable.MajorAxisDeg),'omitnan'))/2,180);
    else
        meanFlat=NaN;
    end
    summary.MeanFlatAxisDeg=meanFlat;
    summary.MeanSteepAxisDeg=mod(meanFlat+90,180);
    summary.SpatialUnit=string(units{method});
    writetable(summary,fullfile(folder,[names{method} '_paired_summary.csv']));
end
for method=1:2
    ellipseTab=uitab(tabs,'Title',[names{method} ' covariance ellipses'],'BackgroundColor',themeBg);
    ax=axes(ellipseTab,'Position',[.08 .43 .78 .49], ...
        'Color',themeAxes,'XColor',themeText,'YColor',themeText); hold(ax,'on');
    T=tables{method}; T.MinorAxisDeg=mod(T.MajorAxisDeg+90,180);
    rows=ismember(T.Mire,commonSelected);
    colours=lines(max(height(T),1)); theta=linspace(0,2*pi,360);
    for k=find(rows)'
        if method==1
            if isfield(p,'DetectedPoints')
                points=p.DetectedPoints;
            else
                points=p.AllPoints;
            end
            pts=points(points.RingNumber==T.Mire(k),:);
            scatter(ax,pts.R.*cos(pts.T),-pts.R.*sin(pts.T),5, ...
                colours(k,:),'filled','HandleVisibility','off');
        else
            shape=smartShapes(k);
            scatter(ax,shape.X,shape.Y,5,colours(k,:), ...
                'filled','HandleVisibility','off');
        end
        a=T.MajorAxisDeg(k); major=T.MajorExtent(k); minor=T.MinorExtent(k);
        ex=T.CenterX(k)+major*cos(theta)*cosd(a)-minor*sin(theta)*sind(a);
        ey=T.CenterY(k)+major*cos(theta)*sind(a)+minor*sin(theta)*cosd(a);
        plot(ax,ex,ey,':','Color',colours(k,:),'LineWidth',1.8, ...
            'DisplayName',sprintf('Mire %d',T.Mire(k)));
    end
    commonTable=T(rows,:);
    if isempty(commonTable)
        meanFlat=NaN; meanSteep=NaN; centre=[NaN NaN]; scale=NaN;
    else
        meanFlat=mod(atan2d(mean(sind(2*commonTable.MajorAxisDeg),'omitnan'), ...
            mean(cosd(2*commonTable.MajorAxisDeg),'omitnan'))/2,180);
        meanSteep=mod(meanFlat+90,180);
        centre=[mean(commonTable.CenterX,'omitnan'),mean(commonTable.CenterY,'omitnan')];
        scale=max(commonTable.MajorExtent,[],'omitnan')*1.35;
    end
    if all(isfinite([meanFlat meanSteep centre scale]))
        plot(ax,centre(1)+[-1 1]*scale*cosd(meanFlat), ...
            centre(2)+[-1 1]*scale*sind(meanFlat),'--','Color',[.15 .55 1], ...
            'LineWidth',2.1,'DisplayName',sprintf('Mean flat %.2f deg',meanFlat));
        plot(ax,centre(1)+[-1 1]*scale*cosd(meanSteep), ...
            centre(2)+[-1 1]*scale*sind(meanSteep),':','Color',[1 .55 .15], ...
            'LineWidth',2.1,'DisplayName',sprintf('Mean steep %.2f deg',meanSteep));
        text(ax,centre(1)+scale*cosd(meanFlat),centre(2)+scale*sind(meanFlat), ...
            sprintf(' Flat %.2f deg',meanFlat),'Color',[.15 .55 1]);
        text(ax,centre(1)+scale*cosd(meanSteep),centre(2)+scale*sind(meanSteep), ...
            sprintf(' Steep %.2f deg',meanSteep),'Color',[1 .55 .15]);
    end
    axis(ax,'equal'); fitAxesToData(ax,.07); grid(ax,'on'); xlabel(ax,['X (' units{method} ')'],'Color',themeText);
    ylabel(ax,['Y (' units{method} ')'],'Color',themeText);
    title(ax,sprintf('%s common complete mires (%s)', ...
        names{method},mat2str(commonSelected')), ...
        'Color',themeText);
    if isempty(commonSelected)
        text(ax,.5,.5,'No common complete mires in the selected range','Units','normalized', ...
            'HorizontalAlignment','center','Color',themeText);
    end
    legend(ax,'Location','eastoutside','TextColor',themeText,'Color',themeBg);
    V=T(rows,:);
    uitable(ellipseTab,'Data',table2cell(V(:,{'Mire','Complete','CenterX','CenterY', ...
        'EigenRatio','EllipseIrregularityPct','MajorAxisDeg','MinorAxisDeg'})), ...
        'ColumnName',{'Mire','Complete','CenterX','CenterY','EigenRatio', ...
        'EllipseIrregularityPct','MajorAxisDeg','MinorAxisDeg'},'Units','normalized', ...
        'Position',[.04 .04 .92 .29],'ForegroundColor',themeText, ...
        'BackgroundColor',[themeBg; themeBg*.94]);
    pairedAxes(method)=ax;
    pairedTables{method}=V(:,{'Mire','Complete','CenterX','CenterY', ...
        'EigenRatio','EllipseIrregularityPct','MajorAxisDeg','MinorAxisDeg'});
    if method==1 && ~isfield(p,'DetectedPoints')
        subtitle(ax,'Older saved run: points are spline samples, not raw detections','Color',themeText);
    else
        subtitle(ax,'Detected points with dotted covariance ellipse','Color',themeText);
    end
end
synchroniseSquareAxes(pairedAxes,.07);
for method=1:2
    exportgraphics(pairedAxes(method),fullfile(folder, ...
        [names{method} '_common_mire_ellipse_overlay.png']),'BackgroundColor',themeBg);
end
comparison=uitab(tabs,'Title','Complete-mire comparison','BackgroundColor',themeBg);
for method=1:2
    ax=copyobj(pairedAxes(method),comparison);
    set(ax,'Position',[.06+.49*(method-1) .43 .40 .47]);
    V=pairedTables{method};
    uitable(comparison,'Data',table2cell(V),'ColumnName',V.Properties.VariableNames, ...
        'Units','normalized','Position',[.02+.50*(method-1) .06 .46 .27], ...
        'ForegroundColor',themeText,'BackgroundColor',[themeBg; themeBg*.94]);
end
uicontrol(comparison,'Style','text','Units','normalized','Position',[.04 .94 .92 .045], ...
    'String',sprintf('Common complete mire IDs in selected range %d:%d: %s', ...
    range(1),range(2),mat2str(commonSelected')), ...
    'BackgroundColor',themeBg,'ForegroundColor',themeText,'FontSize',11);
desiredTitles={...
    'Placido - All detected mires', ...
    'Placido - Complete mires only', ...
    'Placido covariance ellipses', ...
    'SmartKC - All detected mires', ...
    'SmartKC - Complete mires only', ...
    'SmartKC covariance ellipses', ...
    'Complete-mire comparison'};
ordered=gobjects(1,numel(desiredTitles));
for q=1:numel(desiredTitles)
    ordered(q)=findobj(tabs,'Type','uitab','Title',desiredTitles{q});
end
tabs.Children=ordered;
tabs.SelectedTab=ordered(1);
drawnow;
savefig(f,fullfile(folder,'Paired_mire_review.fig'));
end

function [displayShapes,geometry]=smartKCSourcePixelGeometry(result,metrics)
% Convert SmartKC's nominal sensor-plane geometry back to source pixels for
% a like-for-like display with the Placido pathway. This does not alter the
% stored SmartKC analysis or its nominal-mm diagnostic columns.
pixelsPerMm=smartKCPixelsPerMm(result);
sourceShapes=result.AllShapes;
shapeRings=[sourceShapes.MireIndex];
n=height(metrics);
displayShapes=repmat(sourceShapes(1),n,1);
centerX=nan(n,1); centerY=nan(n,1); major=nan(n,1); minor=nan(n,1);
axisDeg=nan(n,1); eigenRatio=nan(n,1);
for row=1:n
    sourceIndex=find(shapeRings==metrics.MireIndex(row),1);
    if isempty(sourceIndex), continue; end
    shape=sourceShapes(sourceIndex);
    shape.X=shape.X*pixelsPerMm(1);
    shape.Y=shape.Y*pixelsPerMm(2);
    valid=isfinite(shape.X) & isfinite(shape.Y);
    if nnz(valid)>=3
        centre=[mean(shape.X(valid)) mean(shape.Y(valid))];
        covariance=cov([shape.X(valid)-centre(1),shape.Y(valid)-centre(2)]);
        [vectors,values]=eig(covariance,'vector');
        [values,order]=sort(real(values),'descend');
        vectors=real(vectors(:,order));
        extents=sqrt(2*max(values(:).',0));
        shape.Centroid=centre;
        shape.Eigenvectors=vectors;
        shape.Extents=extents;
        centerX(row)=centre(1); centerY(row)=centre(2);
        major(row)=extents(1); minor(row)=extents(2);
        axisDeg(row)=mod(atan2d(vectors(2,1),vectors(1,1)),180);
        eigenRatio(row)=minor(row)/major(row);
    end
    displayShapes(row)=shape;
end
geometry=table(centerX,centerY,eigenRatio,axisDeg,major,minor, ...
    'VariableNames',{'CenterX','CenterY','EigenRatio','MajorAxisDeg', ...
    'MajorExtent','MinorExtent'});
end

function pixelsPerMm=smartKCPixelsPerMm(result)
if isfield(result,'SourcePixelsPerMm') && numel(result.SourcePixelsPerMm)==2
    pixelsPerMm=double(result.SourcePixelsPerMm(:).');
    return
end
% Compatibility for saved results created before conversion metadata was
% embedded. Reconstruct the same public-reference scaling from the source
% image and its EXIF orientation.
assert(isfield(result,'InputImage') && isfile(result.InputImage), ...
    'Cannot convert this older SmartKC result to source pixels: source image is unavailable.');
warningState=warning;
restoreWarnings=onCleanup(@() warning(warningState));
warning('off','all');
information=imfinfo(char(result.InputImage));
orientation=1;
if isfield(information(1),'Orientation') && isnumeric(information(1).Orientation) && ...
        isscalar(information(1).Orientation)
    orientation=double(information(1).Orientation);
elseif isfield(information(1),'DigitalCamera') && isstruct(information(1).DigitalCamera) && ...
        isfield(information(1).DigitalCamera,'Orientation') && ...
        isnumeric(information(1).DigitalCamera.Orientation) && ...
        isscalar(information(1).DigitalCamera.Orientation)
    orientation=double(information(1).DigitalCamera.Orientation);
elseif isfield(information(1),'UnknownTags') && ~isempty(information(1).UnknownTags)
    tags=information(1).UnknownTags;
    tagIndex=find([tags.ID]==274,1);
    if ~isempty(tagIndex) && isnumeric(tags(tagIndex).Value) && ...
            ~isempty(tags(tagIndex).Value)
        orientation=double(tags(tagIndex).Value(1));
    end
end
if ~ismember(orientation,1:8), orientation=1; end
sourceSize=[information(1).Height information(1).Width];
sensorSize=[6.4 4.8];
if ismember(orientation,5:8)
    sourceSize=sourceSize([2 1]);
    sensorSize=sensorSize([2 1]);
end
pixelsPerMm=[sourceSize(2)/sensorSize(1),sourceSize(1)/sensorSize(2)];
end

function fitAxesToData(ax,marginFraction)
objects=findobj(ax,'-property','XData','-property','YData');
x=[]; y=[];
for k=1:numel(objects)
    x=[x; double(objects(k).XData(:))]; %#ok<AGROW>
    y=[y; double(objects(k).YData(:))]; %#ok<AGROW>
end
valid=isfinite(x) & isfinite(y); x=x(valid); y=y(valid);
if isempty(x), return; end
xLimits=[min(x) max(x)]; yLimits=[min(y) max(y)];
xSpan=diff(xLimits); ySpan=diff(yLimits);
if xSpan<=0, xSpan=max(1,abs(xLimits(1))); end
if ySpan<=0, ySpan=max(1,abs(yLimits(1))); end
xlim(ax,xLimits+[-1 1]*marginFraction*xSpan);
ylim(ax,yLimits+[-1 1]*marginFraction*ySpan);
end

function synchroniseSquareAxes(axesHandles,marginFraction)
largestMagnitude=0;
for axisIndex=1:numel(axesHandles)
    objects=findobj(axesHandles(axisIndex),'-property','XData','-property','YData');
    for objectIndex=1:numel(objects)
        values=[double(objects(objectIndex).XData(:)); ...
            double(objects(objectIndex).YData(:))];
        values=values(isfinite(values));
        if ~isempty(values)
            largestMagnitude=max(largestMagnitude,max(abs(values)));
        end
    end
end
if largestMagnitude<=0 || ~isfinite(largestMagnitude), return; end
limit=largestMagnitude*(1+marginFraction);
for axisIndex=1:numel(axesHandles)
    xlim(axesHandles(axisIndex),[-limit limit]);
    ylim(axesHandles(axisIndex),[-limit limit]);
end
end
