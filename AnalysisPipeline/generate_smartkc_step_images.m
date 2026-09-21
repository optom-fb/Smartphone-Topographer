function result = generate_smartkc_step_images(inputImage,ringRange,outputRoot,selectedSteps)
%GENERATE_SMARTKC_STEP_IMAGES Export selected dependency-linked SmartKC images.
base = fileparts(mfilename('fullpath'));
projectRoot = base;
assert(isfolder(projectRoot),'SmartKC project files are missing from AnalysisPipeline.');
addpath(projectRoot); addpath(fullfile(projectRoot,'config'));
addpath(genpath(fullfile(projectRoot,'functions')));
if nargin<1 || isempty(inputImage)
    [f,p]=uigetfile({'*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp','Images'});
    if isequal(f,0), error('No input image selected.'); end
    inputImage=fullfile(p,f);
end
assert(isfile(inputImage),'Input image does not exist: %s',inputImage);
if nargin<2 || isempty(ringRange), ringRange=[1 20]; end
validateattributes(ringRange,{'numeric'},{'vector','numel',2,'integer','positive'});
ringRange=ringRange(:).'; assert(ringRange(2)>=ringRange(1),'Invalid ring range.');
if nargin<3 || isempty(outputRoot), outputRoot=fullfile(base,'outputs','smartkc_steps'); end
if nargin<4 || isempty(selectedSteps), selectedSteps=[1:7 20:28]; end
validateattributes(selectedSteps,{'numeric'},{'vector','integer','>=',1,'<=',28});
if any(~ismember(selectedSteps,[1:7 20:28]))
    error('SmartKC selectedSteps must use image stages 1:7 or quality/analysis stages 20:28.');
end
if ~isfolder(outputRoot), mkdir(outputRoot); end
[~,stem]=fileparts(inputImage); runFolder=fullfile(outputRoot, ...
    sprintf('%s_%s',regexprep(stem,'[^A-Za-z0-9_-]','_'),datestr(now,'yyyymmdd_HHMMSS'))); %#ok<TNOW1,DATST>
mkdir(runFolder);

cfg=smartKCConstants(projectRoot);
pre=preprocessPlacidoImage(char(inputImage),cfg);
[sourceOriented,~]=readImageWithExifOrientation(char(inputImage));
seg=segmentMiresClassical(pre,cfg,"smartkc");
[candidates,polar]=extractMireCandidates(pre,seg,cfg);
matrices=mirePointsToMatrices(candidates,polar.AnglesDeg,cfg.placido.MaximumMires);
eigen=calculateMireEigenRatio(matrices,pre,cfg,"smartkc");
metrics=eigen.Metrics;
allShapes=calculateComparisonShapes(candidates,pre,cfg,metrics);
allMetrics=applyHealthExEllipseIrregularity(metrics,allShapes);
metrics=metrics(metrics.MireIndex>=ringRange(1) & metrics.MireIndex<=ringRange(2),:);
if isempty(metrics), error('No localized SmartKC physical mires exist in range %d:%d.',ringRange); end
shapes=calculateComparisonShapes(candidates,pre,cfg,metrics);
metrics=applyHealthExEllipseIrregularity(metrics,shapes);

slugs=cell(1,28);
slugs(1:7)={'source','centred_crop','flat_field_normalized','dog_response', ...
    'segmentation_mask','radial_peak_localization','selected_mires'};
slugs{20}='mire_completeness_quality_gate';
slugs(21:25)={'eigen_ratio','centre_instability','irregularity', ...
    'principal_image_axis','combined_per_mire_summary'};
slugs(26:28)={'representative_mire_ellipse_flat_steep', ...
    'all_mire_ellipses_individual_flat_steep','all_mire_ellipses_mean_flat_steep'};
files=strings(numel(selectedSteps),1);
fullFrameFiles=strings(0,1);
for q=1:numel(selectedSteps)
    step=selectedSteps(q); path=fullfile(runFolder,sprintf('step_%02d_%s.png',step,slugs{step}));
    renderStep(step,pre,seg,candidates,polar,metrics,shapes,ringRange,cfg,path); files(q)=string(path);
    reportWriteupStep('SmartKC',step);
    if ismember(step,2:7)
        fullPath=fullfile(runFolder,sprintf('step_%02d_%s_full_frame.png',step,slugs{step}));
        renderSmartKCFullFrameStep(step,sourceOriented,pre,seg,candidates,ringRange,fullPath);
        fullFrameFiles(end+1,1)=string(fullPath); %#ok<AGROW>
    end
end
result=struct('InputImage',string(inputImage),'RingRange',ringRange, ...
    'SelectedSteps',selectedSteps,'OutputFolder',string(runFolder), ...
    'OutputFiles',files,'FullFrameOutputFiles',fullFrameFiles);
result.AllMetrics=allMetrics;
result.AllShapes=allShapes;
% Preserve the exact display conversion used by this run. The SmartKC
% analysis remains in nominal sensor-plane millimetres, while the paired
% report can convert its geometry back to source-image pixels.
result.SourceImageSizePx=pre.SourceOriginalSize;
result.ProcessingSensorSizeMm=pre.ProcessingSensorSizeMm;
result.SourcePixelsPerMm=[pre.SourceOriginalSize(2)/pre.ProcessingSensorSizeMm(1), ...
    pre.SourceOriginalSize(1)/pre.ProcessingSensorSizeMm(2)];
end

function renderStep(step,pre,seg,candidates,polar,m,shapes,range,cfg,path)
switch step
    case 1
        [orientedSource,~]=readImageWithExifOrientation(char(pre.SourcePath));
        writeImage(orientedSource,path);
    case 2
        f=imageFigure(pre.RGB); hold on; plot(pre.CenterPx(1),pre.CenterPx(2),'y+','MarkerSize',18,'LineWidth',2); saveFig(f,path);
    case 3, writeImage(pre.NormalizedGray,path);
    case 4, writeImage(seg.Response,path);
    case 5, writeImage(seg.Mask,path);
    case 6
        f=figure('Visible','off','Color','w','Position',[100 100 1300 850]);
        subplot(1,2,1); imagesc(polar.AnglesDeg,polar.RadiiPx,polar.Profiles); axis xy tight; xlabel('Angle (deg)'); ylabel('Radius (px)'); title('Radial response profiles'); colormap(turbo);
        subplot(1,2,2); imshow(pre.RGB); hold on; active=candidates(candidates.IsValid,:); scatter(active.X,active.Y,5,active.MireIndex,'filled'); title('Localized subpixel radial peaks'); saveFig(f,path);
    case 7
        f=imageFigure(pre.RGB); active=candidates(candidates.IsValid & candidates.MireIndex>=range(1) & candidates.MireIndex<=range(2),:); scatter(active.X,active.Y,7,active.MireIndex,'filled'); colormap(turbo(max(2,diff(range)+1))); colorbar; saveFig(f,path);
    case 20
        renderMireCompleteness(m,path);
    case 21
        renderEigenComparison(m,shapes,path);
    case {22,23}
        renderMetricStep(step,m,shapes,pre,cfg,path);
    case 24
        renderAxisComparison(m,shapes,path);
    case 25
        renderSummary(m,shapes,path);
    case 26
        renderSmartKCEllipseViews(m,shapes,pre,cfg,path,"single");
    case 27
        renderSmartKCEllipseViews(m,shapes,pre,cfg,path,"individual");
    case 28
        renderSmartKCEllipseViews(m,shapes,pre,cfg,path,"mean");
end
end

function renderMireCompleteness(m,path)
% Explicitly expose the quality gate used before descriptor summaries.
f=figure('Visible','off','Color','w','Position',[50 50 1750 900]);
layout=tiledlayout(f,1,2,'Padding','compact','TileSpacing','compact');
complete=logical(m.IsIncludedInPrimary); colours=repmat([.86 .28 .22],height(m),1);
colours(complete,:)=repmat([.18 .70 .38],sum(complete),1);
ax1=nexttile(layout); styleDark(ax1); hold(ax1,'on');
b=bar(ax1,m.MireIndex,100*m.CoverageFraction,.72,'FaceColor','flat'); b.CData=colours;
yline(ax1,87.5,'--k','87.5% minimum','LabelHorizontalAlignment','left');
ylim(ax1,[0 105]); xticks(ax1,m.MireIndex); xlabel(ax1,'Physical mire index'); ylabel(ax1,'Angular coverage (%)');
title(ax1,'Coverage quality gate','Color','k');
ax2=nexttile(layout); styleDark(ax2); hold(ax2,'on');
b=bar(ax2,m.MireIndex,m.MaximumGapDeg,.72,'FaceColor','flat'); b.CData=colours;
yline(ax2,45,'--k','45 deg maximum','LabelHorizontalAlignment','left');
xticks(ax2,m.MireIndex); xlabel(ax2,'Physical mire index'); ylabel(ax2,'Maximum angular gap (degrees)');
title(ax2,'Green = complete primary; red = incomplete diagnostic','Color','k');
for k=1:height(m)
    status='I'; if complete(k), status='C'; end
    text(ax2,m.MireIndex(k),m.MaximumGapDeg(k),['  ' status], ...
        'Color','k','FontWeight','bold','VerticalAlignment','bottom');
end
saveFig(f,path);
end

function renderSmartKCEllipseViews(m,shapes,pre,cfg,path,mode)
f=figure('Visible','off','Color','w','Position',[50 50 1300 1000]);
ax=axes(f); styleDark(ax); hold(ax,'on'); colours=lines(max(1,numel(shapes))); t=linspace(0,2*pi,720);
indices=1:numel(shapes); if mode=="single", indices=1; end
sensorSize=getProcessingSensorSizeMm(pre,cfg);
pitch=[sensorSize(1)/pre.OriginalSize(2),sensorSize(2)/pre.OriginalSize(1)];
pixelPitch=mean(pitch)*pre.InputResizeScale;
maxLength=0;
for k=indices
    s=shapes(k); plotX=s.X/pixelPitch; plotY=s.Y/pixelPitch;
    plotCentre=s.Centroid/pixelPitch; plotExtents=s.Extents/pixelPitch;
    scatter(ax,plotX,plotY,4,[.68 .68 .68],'filled','MarkerFaceAlpha',.22,'HandleVisibility','off');
    if any(~isfinite(s.Extents)) || any(~isfinite(s.Centroid)), continue; end
    e=plotCentre.'+s.Eigenvectors*[plotExtents(1)*cos(t);plotExtents(2)*sin(t)];
    plot(ax,e(1,:),e(2,:),'--','Color',colours(k,:),'LineWidth',2.8, ...
        'DisplayName',sprintf('Mire %d covariance ellipse',s.MireIndex));
    maxLength=max(maxLength,plotExtents(1));
    if mode~="mean"
        drawSmartKCAxisPair(ax,plotCentre,m.CovarianceMajorAxisDegCCW(k),plotExtents(1),colours(k,:),mode=="single");
    end
end
if mode=="mean"
    [meanFlat,~]=axial(m.CovarianceMajorAxisDegCCW); centres=vertcat(shapes.Centroid)/pixelPitch;
    centre=mean(centres(all(isfinite(centres),2),:),1,'omitnan');
    drawSmartKCAxisPair(ax,centre,meanFlat,maxLength,[.05 .35 .80],true);
    title(ax,sprintf('All fitted physical-mire ellipses; mean flat %.2f deg and steep %.2f deg',meanFlat,mod(meanFlat+90,180)),'Color','k');
elseif mode=="single"
    title(ax,sprintf('Representative physical mire %d: fitted ellipse with flat and steep axes',shapes(indices).MireIndex),'Color','k');
else
    title(ax,'All selected physical mires: covariance ellipses with individual flat and steep axes','Color','k');
end
axis(ax,'equal'); grid(ax,'on');
xlabel(ax,'Tracking X (source-image pixels)');
ylabel(ax,'Tracking Y (source-image pixels)');
lgd=legend(ax,'TextColor','k','Location','bestoutside');
set(lgd,'Color','w','EdgeColor',[.35 .35 .35]);
saveFig(f,path);
end

function drawSmartKCAxisPair(ax,centre,flatDeg,lengthValue,colour,showLegend)
flat=[cosd(flatDeg) sind(flatDeg)]; steep=[cosd(flatDeg+90) sind(flatDeg+90)];
flatName='Flat axis'; steepName='Steep axis'; if ~showLegend, flatName=''; steepName=''; end
h1=plot(ax,centre(1)+[-lengthValue lengthValue]*flat(1),centre(2)+[-lengthValue lengthValue]*flat(2),'--','Color',colour,'LineWidth',1.5,'DisplayName',flatName);
h2=plot(ax,centre(1)+[-lengthValue lengthValue]*steep(1),centre(2)+[-lengthValue lengthValue]*steep(2),':','Color',[.18 .18 .18],'LineWidth',1.7,'DisplayName',steepName);
if ~showLegend, set([h1 h2],'HandleVisibility','off'); end
if showLegend
    text(ax,centre(1)+.72*lengthValue*flat(1),centre(2)+.72*lengthValue*flat(2), ...
        sprintf(' Flat %.2f deg',mod(flatDeg,180)),'Color',colour,'FontWeight','bold','BackgroundColor','w');
    text(ax,centre(1)+.72*lengthValue*steep(1),centre(2)+.72*lengthValue*steep(2), ...
        sprintf(' Steep %.2f deg',mod(flatDeg+90,180)),'Color',[.12 .12 .12],'FontWeight','bold','BackgroundColor','w');
end
end

function renderSmartKCFullFrameStep(step,source,pre,seg,candidates,range,path)
% Map crop-coordinate SmartKC evidence back to the oriented source frame.
if ismatrix(source), source=repmat(source,1,1,3); else, source=source(:,:,1:3); end
source=im2single(source); rect=sourceCropRectangle(pre,size(source));
switch step
    case 2
        f=imageFigure(source); rectangle('Position',rect,'EdgeColor','c','LineWidth',2);
        plot(pre.CenterSourcePx(1),pre.CenterSourcePx(2),'y+', ...
            'MarkerSize',18,'LineWidth',2); saveFig(f,path);
    case 3
        mapped=embedCropImage(source,pre.NormalizedGray,rect,false); writeImage(mapped,path);
    case 4
        mapped=embedCropImage(source,seg.Response,rect,false); writeImage(mapped,path);
    case 5
        mapped=embedCropImage(source,seg.Mask,rect,true); writeImage(mapped,path);
    case 6
        f=imageFigure(source); active=candidates(candidates.IsValid,:);
        [x,y]=candidateSourceCoordinates(active,pre);
        scatter(x,y,5,active.MireIndex,'filled'); colormap(turbo(24)); saveFig(f,path);
    case 7
        f=imageFigure(source);
        active=candidates(candidates.IsValid & candidates.MireIndex>=range(1) & ...
            candidates.MireIndex<=range(2),:);
        [x,y]=candidateSourceCoordinates(active,pre);
        scatter(x,y,7,active.MireIndex,'filled');
        colormap(turbo(max(2,diff(range)+1))); colorbar; saveFig(f,path);
end
end

function rect=sourceCropRectangle(pre,sourceSize)
r=pre.CropRectangleSourcePx; x=max(1,round(r(1))); y=max(1,round(r(2)));
w=min(sourceSize(2)-x+1,max(1,round(r(3))));
h=min(sourceSize(1)-y+1,max(1,round(r(4)))); rect=[x y w h];
end

function output=embedCropImage(source,crop,rect,isMask)
output=source; x=rect(1); y=rect(2); w=rect(3); h=rect(4);
method='bilinear'; if isMask, method='nearest'; end
resized=imresize(single(crop),[h w],method);
if isMask
    region=output(y:y+h-1,x:x+w-1,:); mask=resized>.5;
    red=ones(h,w,'single'); zero=zeros(h,w,'single'); overlay=cat(3,red,zero,zero);
    alpha=.72*single(mask); region=region.*(1-alpha)+overlay.*alpha;
else
    region=repmat(mat2gray(resized),1,1,3);
end
output(y:y+h-1,x:x+w-1,:)=region;
end

function [x,y]=candidateSourceCoordinates(points,pre)
processingX=points.X+pre.CropRectangleFullPx(1)-1;
processingY=points.Y+pre.CropRectangleFullPx(2)-1;
x=(processingX-.5)/pre.InputResizeScale+.5;
y=(processingY-.5)/pre.InputResizeScale+.5;
end

function renderMetricStep(step,m,shapes,pre,cfg,path)
r=m.MireIndex;
switch step
    case 22
        % Express SmartKC centroids in source-image-equivalent pixels so this
        % figure is directly comparable with the Placido Step 22 output.
        sensorSize=getProcessingSensorSizeMm(pre,cfg);
        pitch=[sensorSize(1)/pre.OriginalSize(2),sensorSize(2)/pre.OriginalSize(1)];
        centres=vertcat(shapes.Centroid);
        centres(:,1)=centres(:,1)/pitch(1)/pre.InputResizeScale;
        centres(:,2)=centres(:,2)/pitch(2)/pre.InputResizeScale;
        valid=all(isfinite(centres),2);
        primary=logical(m.IsIncludedInPrimary) & valid;
        referenceRows=primary;
        if ~any(referenceRows), referenceRows=valid; end
        ref=mean(centres(referenceRows,:),1,'omitnan');
        deviations=hypot(centres(:,1)-ref(1),centres(:,2)-ref(2));
        spread=hypot(std(centres(referenceRows,1),'omitnan'), ...
            std(centres(referenceRows,2),'omitnan'));

        f=figure('Visible','off','Color','w','Position',[100 100 1450 760]);
        layout=tiledlayout(f,1,2,'Padding','compact','TileSpacing','compact');
        ax1=nexttile(layout); styleDark(ax1); hold(ax1,'on');
        colours=lines(max(1,height(m)));
        for k=1:height(m)
            if ~valid(k), continue; end
            plot(ax1,[ref(1) centres(k,1)],[ref(2) centres(k,2)],':', ...
                'Color',colours(k,:),'HandleVisibility','off');
            scatter(ax1,centres(k,1),centres(k,2),55,colours(k,:),'filled', ...
                'DisplayName',sprintf('Mire %d',r(k)));
            text(ax1,centres(k,1),centres(k,2),sprintf('  M%d',r(k)), ...
                'Color',colours(k,:),'FontWeight','bold','FontSize',9);
        end
        plot(ax1,ref(1),ref(2),'k+','MarkerSize',16,'LineWidth',2, ...
            'HandleVisibility','off');
        axis(ax1,'equal'); grid(ax1,'on');
        xlabel(ax1,'Mire-centre X (source-image pixels)');
        ylabel(ax1,'Mire-centre Y (source-image pixels)');
        title(ax1,'Per-mire centroids and selected-range mean','Color','k');

        ax2=nexttile(layout); styleDark(ax2); hold(ax2,'on');
        plot(ax2,r,deviations,'o-','Color',[.12 .63 .38], ...
            'MarkerFaceColor',[.12 .63 .38],'LineWidth',1.7);
        yline(ax2,mean(deviations(referenceRows),'omitnan'),'--k', ...
            sprintf('Mean %.3f',mean(deviations(referenceRows),'omitnan')));
        xticks(ax2,r); grid(ax2,'on'); xlabel(ax2,'Physical mire index');
        ylabel(ax2,'Distance from mean centre (source-image pixels)');
        title(ax2,sprintf('Single-frame cross-mire centre spread = %.3f pixels',spread),'Color','k');
        saveFig(f,path);
    case 23
        f=figure('Visible','off','Color','w','Position',[100 100 1100 720]);
        ax=axes(f); styleDark(ax); hold(ax,'on');
        y=m.Irregularity_percent;
        primary=logical(m.IsIncludedInPrimary) & isfinite(y);
        diagnostic=~logical(m.IsIncludedInPrimary) & isfinite(y);
        if any(primary)
            plot(ax,r(primary),y(primary),'o-','Color',[.18 .78 .46], ...
                'MarkerFaceColor',[.18 .78 .46],'LineWidth',1.7, ...
                'DisplayName','Complete-primary');
            primaryMean=mean(y(primary),'omitnan');
            yline(ax,primaryMean,'--','Color',[.82 .84 .88],'LineWidth',1.1, ...
                'Label',sprintf('primary mean %.3g',primaryMean), ...
                'LabelHorizontalAlignment','left','HandleVisibility','off');
        end
        if any(diagnostic)
            plot(ax,r(diagnostic),y(diagnostic),'x:','Color',[1 .62 .16], ...
                'MarkerSize',8,'LineWidth',1.3,'DisplayName','Incomplete diagnostic');
        end
        xticks(ax,r); grid(ax,'on'); xlabel(ax,'Physical mire index');
        ylabel(ax,'Ellipse-RMSE irregularity (%)');
        title(ax,'Per-mire ellipse-RMSE irregularity','Color','k');
        if any(primary) || any(diagnostic)
            legend(ax,'Location','best','Color','w','TextColor','k');
        end
        saveFig(f,path);
end
end

function metrics=applyHealthExEllipseIrregularity(metrics,shapes)
% Replace the exploratory harmonic-SD irregularity with the unified
% explicit-ellipse RMSE definition.
ellipseRMSE=nan(height(metrics),1);
metrics.Irregularity_percent(:)=NaN;
for k=1:height(metrics)
    if ~metrics.IsIncludedInPrimary(k)
        continue;
    end
    [ellipseRMSE(k),metrics.Irregularity_percent(k)] = ...
        calculateHealthExEllipseIrregularity(shapes(k).X,shapes(k).Y);
end
metrics.EllipseRMSEmm=ellipseRMSE;
end

function [rmseValue,irregularityPct]=calculateHealthExEllipseIrregularity(x,y)
rmseValue=NaN; irregularityPct=NaN;
if numel(x)<5 || exist('fit_ellipse','file')~=2 || ...
        exist('get_optometric_axes','file')~=2
    return;
end
try
    warningState=warning;
    warning('off','all');
    params=fit_ellipse(x(:),y(:));
    warning(warningState);
    if isempty(params), return; end
    opto=get_optometric_axes(params);
    radius=hypot(x(:),y(:)); theta=atan2(y(:),x(:));
    a=opto.major_radius; b=opto.minor_radius;
    phi=deg2rad(opto.major_axis_deg);
    ideal=(a*b)./sqrt((b*cos(theta-phi)).^2+(a*sin(theta-phi)).^2);
    residual=radius-ideal;
    rmseValue=sqrt(mean(residual.^2));
    irregularityPct=100*rmseValue/max(mean(radius),eps);
catch
    warning(warningState);
    rmseValue=NaN; irregularityPct=NaN;
end
end

function renderSummary(m,shapes,path)
n=height(m); f=figure('Visible','off','Color','w','Position',[50 50 1900 max(900,500+38*n)]);
ax1=axes(f,'Position',[.05 .12 .40 .76]); styleDark(ax1); hold(ax1,'on');
plotHarmonicGeometry(ax1,shapes); title(ax1,'SmartKC second-harmonic curves and axes','Color','k');
ax2=axes(f,'Position',[.48 .08 .50 .82],'Color','w'); axis(ax2,[0 1 0 1]); axis(ax2,'off');
cx=m.CenterXmm; cy=m.CenterYmm; ref=[mean(cx,'omitnan') mean(cy,'omitnan')]; dc=hypot(cx-ref(1),cy-ref(2));
head=sprintf('%-5s %7s %8s %8s %8s %9s %8s','Mire','ER','CtrXmm','CtrYmm','dCtrmm','Irreg%%','Axis');
out=strings(n+6,1); out(1)="SMARTKC PER-PHYSICAL-MIRE QUANTITATIVE OUTPUT"; out(2)=head; out(3)=repmat('-',1,strlength(head));
for k=1:n, out(k+3)=sprintf('%-5d %7.4f %8.4f %8.4f %8.4f %9.3f %8.2f',m.MireIndex(k),m.EigenRatio(k),cx(k),cy(k),dc(k),m.Irregularity_percent(k),m.CovarianceMajorAxisDegCCW(k)); end
[am,asd]=axial(m.CovarianceMajorAxisDegCCW); out(n+4)=repmat('-',1,strlength(head)); out(n+5)=sprintf('MEAN  %7.4f %8.4f %8.4f %8.4f %9.3f %8.2f',mean(m.EigenRatio,'omitnan'),mean(cx,'omitnan'),mean(cy,'omitnan'),mean(dc,'omitnan'),mean(m.Irregularity_percent,'omitnan'),am); out(n+6)=sprintf('SD    %7.4f %8.4f %8.4f %8.4f %9.3f %8.2f | centre instability %.4f mm',std(m.EigenRatio,'omitnan'),std(cx,'omitnan'),std(cy,'omitnan'),std(dc,'omitnan'),std(m.Irregularity_percent,'omitnan'),asd,hypot(std(cx,'omitnan'),std(cy,'omitnan')));
text(ax2,.02,.97,strjoin(out,newline),'Color','k','FontName','Consolas','FontSize',max(6.5,min(10.5,12-.18*n)),'VerticalAlignment','top','Interpreter','none'); saveFig(f,path);
end

function shapes=calculateComparisonShapes(candidates,pre,cfg,metrics)
sensorSize=getProcessingSensorSizeMm(pre,cfg);
pitch=[sensorSize(1)/pre.OriginalSize(2),sensorSize(2)/pre.OriginalSize(1)];
template=struct('MireIndex',0,'X',[],'Y',[],'Centroid',[NaN NaN], ...
    'Eigenvectors',nan(2),'Extents',[NaN NaN],'HarmonicCoefficients',nan(3,1));
shapes=repmat(template,height(metrics),1);
for k=1:height(metrics)
    ring=metrics.MireIndex(k); rows=candidates.IsValid & candidates.MireIndex==ring;
    x=(candidates.X(rows)-pre.CenterPx(1))*pitch(1);
    y=-(candidates.Y(rows)-pre.CenterPx(2))*pitch(2);
    shapes(k).MireIndex=ring; shapes(k).X=x; shapes(k).Y=y;
    if numel(x)<3, continue; end
    ctr=[mean(x) mean(y)]; shapes(k).Centroid=ctr;
    [v,d]=eig(cov([x-ctr(1),y-ctr(2)]),'vector');
    [d,order]=sort(real(d),'descend'); v=real(v(:,order));
    shapes(k).Eigenvectors=v; shapes(k).Extents=sqrt(2*max(d(:).',0));
    phi=atan2(y-ctr(2),x-ctr(1)); rho=hypot(x-ctr(1),y-ctr(2));
    shapes(k).HarmonicCoefficients=[ones(size(phi)),cos(2*phi),sin(2*phi)]\rho;
end
end

function renderEigenComparison(m,shapes,path)
f=figure('Visible','off','Color','w','Position',[50 50 1700 900]);
ax1=axes(f,'Position',[.06 .12 .42 .76]); styleDark(ax1); hold(ax1,'on'); colours=lines(height(m)); t=linspace(0,2*pi,500);
for k=1:numel(shapes)
    s=shapes(k); scatter(ax1,s.X,s.Y,5,colours(k,:),'filled','MarkerFaceAlpha',.25,'HandleVisibility','off');
    if any(~isfinite(s.Extents)), continue; end
    e=s.Centroid.'+s.Eigenvectors*[s.Extents(1)*cos(t);s.Extents(2)*sin(t)];
    plot(ax1,e(1,:),e(2,:),'Color',colours(k,:),'LineWidth',1.4,'DisplayName',sprintf('Mire %d',s.MireIndex));
end
axis(ax1,'equal'); xlabel(ax1,'Sensor X (mm)'); ylabel(ax1,'Sensor Y (mm)'); title(ax1,'SmartKC physical-mire centrelines and covariance ellipses','Color','k');
ax2=axes(f,'Position',[.55 .14 .40 .70]); styleDark(ax2); bar(ax2,m.MireIndex,m.EigenRatio,'FaceColor',[.18 .58 .78]); yline(ax2,mean(m.EigenRatio,'omitnan'),'--k',sprintf('Mean %.4f',mean(m.EigenRatio,'omitnan'))); xlabel(ax2,'Physical mire index'); ylabel(ax2,'Eigen ratio'); ylim(ax2,[0 1.05]); title(ax2,'sqrt(lambda minor / lambda major)','Color','k'); saveFig(f,path);
end

function renderAxisComparison(m,shapes,path)
f=figure('Visible','off','Color','w','Position',[50 50 1700 900]);
ax1=axes(f,'Position',[.06 .12 .42 .76]); styleDark(ax1); hold(ax1,'on'); plotHarmonicGeometry(ax1,shapes); title(ax1,'SmartKC fitted harmonic curves and axes','Color','k');
ax2=axes(f,'Position',[.55 .14 .40 .70]); styleDark(ax2); hold(ax2,'on');
plot(ax2,m.MireIndex,m.MajorRadiusAxisDegCCW,'o','LineWidth',1.5,'MarkerFaceColor',[.12 .72 .93],'DisplayName','Harmonic axis');
plot(ax2,m.MireIndex,m.CovarianceMajorAxisDegCCW,'s','LineWidth',1.4,'MarkerFaceColor',[1 .62 .16],'DisplayName','Covariance axis');
ylim(ax2,[0 180]); yticks(ax2,0:30:180); xlabel(ax2,'Physical mire index'); ylabel(ax2,'Axis (deg CCW)'); title(ax2,'Per-physical-mire image axes','Color','k'); legend(ax2,'Color','w','TextColor','k','Location','best'); saveFig(f,path);
end

function plotHarmonicGeometry(ax,shapes)
colours=lines(numel(shapes)); t=linspace(0,2*pi,720).';
for k=1:numel(shapes)
    s=shapes(k); c=s.HarmonicCoefficients; if any(~isfinite(c)), continue; end
    rho=[ones(size(t)),cos(2*t),sin(2*t)]*c; ctr=s.Centroid;
    plot(ax,ctr(1)+rho.*cos(t),ctr(2)+rho.*sin(t),'Color',colours(k,:),'LineWidth',1.25,'DisplayName',sprintf('Mire %d',s.MireIndex));
    a=mod(.5*atan2d(c(3),c(2)),180); L=max(rho); d=[cosd(a) sind(a)];
    plot(ax,ctr(1)+[-L L]*d(1),ctr(2)+[-L L]*d(2),'--','Color',colours(k,:),'HandleVisibility','off');
end
axis(ax,'equal'); xlabel(ax,'Sensor X (mm)'); ylabel(ax,'Sensor Y (mm)');
end

function styleDark(ax)
set(ax,'Color','w','XColor','k','YColor','k','GridColor',[.72 .72 .72]); grid(ax,'on');
end

function [mu,sd]=axial(a)
a=a(isfinite(a)); if isempty(a), mu=NaN; sd=NaN; return; end
c=mean(cosd(2*a)); s=mean(sind(2*a)); mu=mod(.5*atan2d(s,c),180); R=max(eps,min(1,hypot(c,s))); sd=.5*rad2deg(sqrt(max(0,-2*log(R))));
end
function f=imageFigure(im), f=figure('Visible','off','Color','w','Position',[100 100 1000 850]); imshow(im); hold on; end
function writeImage(im,path), imwrite(im,path); end
function saveFig(f,path), exportgraphics(f,path,'Resolution',180); close(f); end
