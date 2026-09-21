function [mirePoints, pairSummary] = pairPlacidoBoundaryTracks(boundaryPoints)
%PAIRPLACIDOBOUNDARYTRACKS Convert inner/outer edge tracks to mire centrelines.
% Boundary points must contain RingNumber, Label, T and R. Odd Label values
% identify the negative-gradient mask and even values the positive-gradient
% mask, matching step01_detect_placido_rings.m. Radially adjacent tracks are
% paired only when their polarities differ. One midpoint radius is emitted
% per common integer-degree angular bin.

required = {'RingNumber','Label','T','R'};
assert(all(ismember(required,boundaryPoints.Properties.VariableNames)), ...
    'Boundary table must contain RingNumber, Label, T and R.');
trackIds = unique(boundaryPoints.RingNumber).';
n = numel(trackIds); meanRadius = nan(n,1); polarity = nan(n,1);
for k = 1:n
    rows = boundaryPoints.RingNumber == trackIds(k);
    meanRadius(k) = median(boundaryPoints.R(rows),'omitnan');
    polarity(k) = mode(mod(boundaryPoints.Label(rows),2));
end
[meanRadius,order] = sort(meanRadius);
trackIds = trackIds(order); polarity = polarity(order);

MireIndex=zeros(0,1); InnerBoundaryTrack=zeros(0,1); OuterBoundaryTrack=zeros(0,1);
InnerMeanRadiusPx=zeros(0,1); OuterMeanRadiusPx=zeros(0,1); MeanWidthPx=zeros(0,1);
CommonAngleCount=zeros(0,1); CoverageDeg=zeros(0,1); mirePoints=table();
k=1; mire=0;
while k<n
    if polarity(k)==polarity(k+1), k=k+1; continue; end
    innerTrack=trackIds(k); outerTrack=trackIds(k+1);
    a=boundaryPoints.RingNumber==innerTrack; b=boundaryPoints.RingNumber==outerTrack;
    rInner=angularMedian(boundaryPoints.T(a),boundaryPoints.R(a));
    rOuter=angularMedian(boundaryPoints.T(b),boundaryPoints.R(b));
    common=isfinite(rInner)&isfinite(rOuter)&rOuter>rInner;
    if sum(common)>=30
        mire=mire+1; T=deg2rad(find(common)-1); R=.5*(rInner(common)+rOuter(common));
        T_deg=rad2deg(T); X=R.*cos(T); Y=R.*sin(T); Label=repmat(mire,numel(T),1);
        RingNumber=Label; InnerTrack=repmat(innerTrack,numel(T),1);
        OuterTrack=repmat(outerTrack,numel(T),1); WidthPx=rOuter(common)-rInner(common);
        mirePoints=[mirePoints;table(Label,X,Y,T,R,RingNumber,T_deg, ...
            InnerTrack,OuterTrack,WidthPx)]; %#ok<AGROW>
        MireIndex(end+1,1)=mire; InnerBoundaryTrack(end+1,1)=innerTrack; %#ok<AGROW>
        OuterBoundaryTrack(end+1,1)=outerTrack; %#ok<AGROW>
        InnerMeanRadiusPx(end+1,1)=meanRadius(k); %#ok<AGROW>
        OuterMeanRadiusPx(end+1,1)=meanRadius(k+1); %#ok<AGROW>
        MeanWidthPx(end+1,1)=mean(WidthPx,'omitnan'); %#ok<AGROW>
        CommonAngleCount(end+1,1)=sum(common); CoverageDeg(end+1,1)=sum(common); %#ok<AGROW>
    end
    k=k+2;
end
pairSummary=table(MireIndex,InnerBoundaryTrack,OuterBoundaryTrack, ...
    InnerMeanRadiusPx,OuterMeanRadiusPx,MeanWidthPx,CommonAngleCount,CoverageDeg);
if ~isempty(mirePoints), mirePoints=sortrows(mirePoints,{'RingNumber','T'}); end
end

function profile=angularMedian(theta,radius)
bin=mod(round(rad2deg(theta)),360)+1;
profile=accumarray(bin(:),radius(:),[360 1],@median,NaN);
end
